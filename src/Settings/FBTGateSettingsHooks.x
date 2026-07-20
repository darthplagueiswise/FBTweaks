#import "FBTPrefix.h"
#import "FBTDefaults.h"
#import "Runtime/FBTRuntimeBoolBrowser.h"
#import "Features/Employee/FBTInternalImports.h"
#import "Features/ReactNative/FBTReactNativeInternal.h"

// Extends the existing UIKit settings without duplicating the controller.
// The main settings implementation remains the owner of cell rendering and
// generic persistence; this file only adds the newly mapped gate families and
// performs their explicit post-launch installers.

@interface FBTSettingsSwitch : UISwitch
@property (nonatomic, copy) NSString *prefKey;
@end

@interface FBTSettingsViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
- (void)rebuildSections;
- (void)switchChanged:(FBTSettingsSwitch *)sender;
- (void)showInfoTitle:(NSString *)title message:(NSString *)message;
@end

extern void FBTInitEmployeeGroup(void);
extern void FBTInstallKnownGateRuntimeHooks(void);

static NSArray<NSDictionary *> *FBTMappedGateRows(void) {
    return @[
        @{
            @"kind": @"switch",
            @"title": @"Internal / Test User",
            @"subtitle": @"IdentitySwitcher isInternalTestUser:, tagging e employee-or-test-user gates confirmados.",
            @"key": FBTKeyTestUserEnabled
        },
        @{
            @"kind": @"switch",
            @"title": @"Dogfood / Dogfooding",
            @"subtitle": @"Dogfooding Assistant, enableDogfoodingView e agrupamento AC dogfood confirmados.",
            @"key": FBTKeyKnownDogfoodEnabled
        },
        @{
            @"kind": @"switch",
            @"title": @"React Native Internal Settings",
            @"subtitle": @"RCTDevMenu, RCTDevSettings, dev-loading view e propagação employee para RCTCurrentViewer.",
            @"key": FBTKeyReactNativeInternalEnabled
        },
        @{
            @"kind": @"switch",
            @"title": @"Beta build channel",
            @"subtitle": @"Força o import METAOSBuildIsBeta. Não finge TestFlight receipt; desligar exige restart.",
            @"key": FBTKeyBetaBuildEnabled,
            @"restart": @YES
        },
        @{
            @"kind": @"action",
            @"title": @"Abrir React Native Internal Settings",
            @"subtitle": @"Abre a rota nativa confirmada fb://rninternalsettings.",
            @"action": @"rn_internal_settings"
        },
    ];
}

%hook FBTSettingsViewController

- (void)rebuildSections {
    %orig;

    NSMutableArray *sections = [self.sections mutableCopy] ?: [NSMutableArray array];

    // Clarify the already-existing Employee master: it now covers concrete
    // identity propagation and the native Internal Settings gate, not only a
    // handful of getters.
    if (sections.count > 1) {
        NSMutableArray *known = [sections[1] mutableCopy];
        for (NSUInteger i = 0; i < known.count; i++) {
            NSDictionary *row = [known[i] isKindOfClass:[NSDictionary class]] ? known[i] : nil;
            if ([row[@"key"] isEqualToString:FBTKeyEmployeeEnabled]) {
                NSMutableDictionary *updated = [row mutableCopy];
                updated[@"title"] = @"Employee / Internal";
                updated[@"subtitle"] = @"Identidade + propagação WebView/RN/Loom/RCD + FBBugReportConfiguration + native Internal Settings.";
                known[i] = updated;
                break;
            }
        }
        sections[1] = known;
    }

    [sections addObject:FBTMappedGateRows()];
    self.sections = sections;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == (NSInteger)self.sections.count - 1) return @"Mapped gate families";
    return %orig;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == (NSInteger)self.sections.count - 1) {
        return @"Employee/Test User/Dogfood use live Objective-C/Swift gates. RN dev-loading and METAOSBuildIsBeta are C imports: once installed, turning them off requires restarting Facebook.";
    }
    return %orig;
}

- (void)switchChanged:(FBTSettingsSwitch *)sender {
    %orig;

    NSString *key = sender.prefKey ?: @"";

    if ([key isEqualToString:FBTKeyEmployeeEnabled]) {
        if (sender.isOn) {
            FBTInitEmployeeGroup();
            FBTInitReactNativeInternalGroup();
            FBTInstallKnownGateRuntimeHooks();
            FBTInstallReactNativeAndBuildImportHooks();
            FBTInstallInternalImportHooks();
        }
        FBTInternalImportReloadPrefs();
    } else if ([key isEqualToString:FBTKeyTestUserEnabled] ||
               [key isEqualToString:FBTKeyKnownDogfoodEnabled]) {
        if (sender.isOn) FBTInitEmployeeGroup();
        FBTInstallKnownGateRuntimeHooks();
    } else if ([key isEqualToString:FBTKeyReactNativeInternalEnabled]) {
        if (sender.isOn) {
            FBTInitReactNativeInternalGroup();
            FBTInstallReactNativeAndBuildImportHooks();
        }
    } else if ([key isEqualToString:FBTKeyBetaBuildEnabled]) {
        if (sender.isOn) FBTInstallReactNativeAndBuildImportHooks();
    }

    // Sweeps are no longer one-shot. Turning a family off removes only the
    // overrides created by that sweep and preserves manual browser overrides.
    if (!sender.isOn && [key isEqualToString:FBTKeyEmployeeSweepEnabled]) {
        FBTRuntimeBoolClearSweep(@"employee");
    } else if (!sender.isOn && [key isEqualToString:FBTKeyDogfoodSweepEnabled]) {
        FBTRuntimeBoolClearSweep(@"dogfood");
    } else if (!sender.isOn && [key isEqualToString:FBTKeyInternalDebugSweepEnabled]) {
        FBTRuntimeBoolClearSweep(@"internaldebug");
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = nil;
    if (indexPath.section < (NSInteger)self.sections.count &&
        indexPath.row < (NSInteger)self.sections[indexPath.section].count) {
        item = self.sections[indexPath.section][indexPath.row];
    }

    %orig;

    if (![item[@"action"] isEqualToString:@"rn_internal_settings"]) return;

    NSURL *url = [NSURL URLWithString:@"fb://rninternalsettings"];
    if (!url) return;
    [[UIApplication sharedApplication]
        openURL:url
        options:@{}
        completionHandler:^(BOOL success) {
            if (!success) {
                [self showInfoTitle:@"React Native Internal Settings"
                            message:@"A rota fb://rninternalsettings não foi aceita nesta sessão/build."];
            }
        }];
}

%end
