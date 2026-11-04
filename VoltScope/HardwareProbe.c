#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

// iOS does not have a public SDK contract for the AppleSmartBattery registry.
// Resolve the symbols only at runtime. Failing to open it is normal on stock
// iOS and must never prevent the rest of the app from running.
typedef uint32_t VSIOObject;
typedef VSIOObject (*VSMatchingServiceFn)(uint32_t, CFDictionaryRef);
typedef CFMutableDictionaryRef (*VSServiceMatchingFn)(const char *);
typedef int (*VSRegistryPropertiesFn)(VSIOObject, CFMutableDictionaryRef *, CFAllocatorRef, uint32_t);
typedef int (*VSReleaseFn)(VSIOObject);

char *VSReadBatteryPropertiesPlist(void) {
    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (!handle) return NULL;
    VSServiceMatchingFn matching = (VSServiceMatchingFn)dlsym(handle, "IOServiceMatching");
    VSMatchingServiceFn service = (VSMatchingServiceFn)dlsym(handle, "IOServiceGetMatchingService");
    VSRegistryPropertiesFn properties = (VSRegistryPropertiesFn)dlsym(handle, "IORegistryEntryCreateCFProperties");
    VSReleaseFn release = (VSReleaseFn)dlsym(handle, "IOObjectRelease");
    if (!matching || !service || !properties || !release) { dlclose(handle); return NULL; }

    CFMutableDictionaryRef query = matching("AppleSmartBattery");
    if (!query) { dlclose(handle); return NULL; }
    VSIOObject battery = service(0, query); // service consumes query
    if (!battery) { dlclose(handle); return NULL; }

    CFMutableDictionaryRef dictionary = NULL;
    int status = properties(battery, &dictionary, kCFAllocatorDefault, 0);
    release(battery);
    if (status != 0 || !dictionary) { dlclose(handle); return NULL; }

    CFErrorRef error = NULL;
    CFDataRef data = CFPropertyListCreateData(kCFAllocatorDefault, dictionary,
        kCFPropertyListXMLFormat_v1_0, 0, &error);
    CFRelease(dictionary);
    if (error) CFRelease(error);
    if (!data) { dlclose(handle); return NULL; }

    CFIndex length = CFDataGetLength(data);
    char *result = (char *)malloc((size_t)length + 1);
    if (result) {
        memcpy(result, CFDataGetBytePtr(data), (size_t)length);
        result[length] = '\0';
    }
    CFRelease(data);
    dlclose(handle);
    return result;
}

void VSFreeBatteryPropertiesPlist(char *value) { free(value); }
