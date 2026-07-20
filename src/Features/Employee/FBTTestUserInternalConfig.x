#import "FBTPrefix.h"
#import "FBTDefaults.h"

// Test accounts are accepted by the native Internal Settings access copy, but
// they are not employees. Keep that distinction: this group forces only the
// visibility/access configuration setters and never changes -isEmployee.

static inline BOOL FBTTestUserInternalOn(void) {
    return [FBTDefaults boolForKey:FBTKeyTestUserEnabled];
}

%group FBTTestUserInternalConfig

%hook FBBugReportConfiguration
- (void)setEnableInternalSettingsOption:(BOOL)value {
    %orig(FBTTestUserInternalOn() ? YES : value);
}
- (void)setEnableInternalToolsSubmenu:(BOOL)value {
    %orig(FBTTestUserInternalOn() ? YES : value);
}
- (void)setForceShowingInternalTools:(BOOL)value {
    %orig(FBTTestUserInternalOn() ? YES : value);
}
%end

%end

void FBTInitTestUserInternalConfigGroup(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        %init(FBTTestUserInternalConfig);
    });
}
