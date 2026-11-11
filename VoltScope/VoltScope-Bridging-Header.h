#ifndef VOLTSCOPE_BRIDGING_HEADER_H
#define VOLTSCOPE_BRIDGING_HEADER_H

#import <Foundation/Foundation.h>

// Returns a malloc-owned UTF-8 property-list XML document, or NULL if the
// private IORegistry service is not accessible to the running application.
char *VSReadBatteryPropertiesPlist(void);
void VSFreeBatteryPropertiesPlist(char *value);

// Read-only PowerLog capability probe. On iOS 27 it may obtain a temporary
// sandbox extension using the App Group signed into the installed app.
// The system database is never modified.
NSString *VSRecoverPowerLogCache(void);
NSDictionary<NSString *, NSString *> *VSProbePowerLog(void);

#endif
