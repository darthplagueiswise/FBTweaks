#import "FBTPrefix.h"
#import "FBTDefaults.h"
#import "Runtime/FBTRuntimeBoolBrowser.h"
#import "Runtime/FBTMobileConfigDebugUIHooks.h"
#import "Features/Employee/FBTInternalImports.h"
#import "Features/ReactNative/FBTReactNativeInternal.h"

extern void FBTInitEmployeeGroup(void);
extern void FBTInstallKnownGateRuntimeHooks(void);

// Keep the gate-family UI isolated from the large base settings controller.
// This avoids replacing unrelated UI code and lets the rows track the exact
// executable/framework analysis independently.
@interface FBTSettingsViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
- (void)rebuildSections;
- (void)switchChanged:(id)sender;
@end

static void FBTInstallGateFamiliesForKey(NSString *key, BOOL enabled) {
    if ([key isEqualToString:FBTKeyEmployeeEnabled] ||
        [key isEqualToString:FBTKeyTestUserEnabled] ||
        [key isEqualToString:FBTKeyKnownDogfoodEnabled]) {
        if (enabled) FBTInitEmployeeGroup();
        FBTInstallKnownGateRuntimeHooks();
        FBTInternalImportReloadPrefs();

        if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled] ||
            [FBTDefaults boolForKey:FBTKeyTestUserEnabled]) {
            FBTInstallInternalImportHooks();
            FBTInitReactNativeInternalGroup();
            FBTInstallReactNativeAndBuildImportHooks();
        }
    }

    if (([key isEqualToString:FBTKeyReactNativeInternalEnabled] ||
         [key isEqualToString:FBTKeyBetaBuildEnabled]) && enabled) {
        FBTInitReactNativeInternalGroup();
        FBTInstallReactNativeAndBuildImportHooks();
    }

    if ([key isEqualToString:FBTKeyMobileConfigNativeUIWarmupEnabled] && enabled) {
        FBTInstallMobileConfigDebugUIBootstrap();
        FBTInstallMobileConfigDebugUIHooks();
    }

    if ([key isEqualToString:FBTKeyDogfoodSweepEnabled] && !enabled) {
        FBTRuntimeBoolClearSweep(@"dogfood");
    } else if ([key isEqualToString:FBTKeyInternalDebugSweepEnabled] && !enabled) {
        FBTRuntimeBoolClearSweep(@"internaldebug");
    }
}

%group FBTGateSettingsAugment

%hook FBTSettingsViewController

- (void)switchChanged:(id)sender {
    %orig;

    NSString *key = nil;
    BOOL enabled = NO;
    @try {
        key = [sender valueForKey:@"prefKey"];
        enabled = [sender isOn];
    } @catch (__unused NSException *exception) {
        return;
    }

    if ([key isKindOfClass:[NSString class]]) {
        FBTInstallGateFamiliesForKey(key, enabled);
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *sections = self.sections;
    NSDictionary *item = nil;
    if (indexPath.section < (NSInteger)sections.count) {
        NSArray *section = sections[indexPath.section];
        if (indexPath.row < (NSInteger)section.count) item = section[indexPath.row];
    }

    if ([item[@"action"] isEqualToString:@"rn_internal"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        FBTOpenReactNativeInternalSettings();
        return;
    }

    %orig;
}

%end
%end

%ctor {
    %init(FBTGateSettingsAugment);
}
