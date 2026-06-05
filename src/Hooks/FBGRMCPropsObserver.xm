#import <Foundation/Foundation.h>
#import "../FBGramPrefix.h"

static BOOL gEnabled = NO;
extern "C" void FBGRMCObserverSetEnabled(BOOL enabled) {
    gEnabled = enabled;
    [FBGRPrefs() setBool:enabled forKey:kFBGRMCObserverEnabled];
    [FBGRPrefs() synchronize];
}
extern "C" void FBGRMCObserverEnsureInstalled(void) { gEnabled = FBGRPref(kFBGRMCObserverEnabled); }
extern "C" void FBGRMCObserverFlush(void) {}
extern "C" NSUInteger FBGRMCObserverSlotCount(void) { return 0; }
extern "C" NSString *FBGRMCObserverDump(void) { return gEnabled ? @"Observer shell enabled. Runtime browsers are the real scanners." : @"Observer disabled. Use runtime browsers for real scanning."; }
