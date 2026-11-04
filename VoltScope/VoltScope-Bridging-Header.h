#ifndef VOLTSCOPE_BRIDGING_HEADER_H
#define VOLTSCOPE_BRIDGING_HEADER_H

// Returns a malloc-owned UTF-8 property-list XML document, or NULL if the
// private IORegistry service is not accessible to the running application.
char *VSReadBatteryPropertiesPlist(void);
void VSFreeBatteryPropertiesPlist(char *value);

#endif
