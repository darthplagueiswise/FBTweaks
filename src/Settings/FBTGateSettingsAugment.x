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

static BOOL FBTItemsContainKey(NSArray<NSDictionary *> *items, NSString *key) {
    for (NSDictionary *item in items) {
        if ([item[@"key"] isEqualToString:key]) return YES;
    }
    return NO;
}

static BOOL FBTItemsContainAction(NSArray<NSDictionary *> *items, NSString *action) {
    for (NSDictionary *item in items) {
        if ([item[@"action"] isEqualToString:action]) return YES;
    }
    return NO;
}

static NSArray<NSDictionary *> *FBTReplaceEmployeeMasterDescription(NSArray<NSDictionary *> *items) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *item in items) {
        if ([item[@"key"] isEqualToString:FBTKeyEmployeeEnabled]) {
            NSMutableDictionary *updated = [item mutableCopy];
            updated[@"subtitle"] = @"Identidade e propagação no executable/Shared/Dynamic/RN, Internal Settings, FFDB local e dogfood conhecido. Imports C exigem reabrir o app para desligar completamente.";
            updated[@"restart"] = @YES;
            [result addObject:updated];
        } else {
            [result addObject:item];
        }
    }
    return result;
}

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

    if ([key isEqualToString:FBTKeyEmployeeSweepEnabled] && !enabled) {
        FBTRuntimeBoolClearSweep(@"employee");
    } else if ([key isEqualToString:FBTKeyDogfoodSweepEnabled] && !enabled) {
        FBTRuntimeBoolClearSweep(@"dogfood");
    } else if ([key isEqualToString:FBTKeyInternalDebugSweepEnabled] && !enabled) {
        FBTRuntimeBoolClearSweep(@"internaldebug");
    }
}

%group FBTGateSettingsAugment

%hook FBTSettingsViewController

- (void)rebuildSections {
    %orig;

    NSArray<NSArray<NSDictionary *> *> *base = self.sections;
    if (![base isKindOfClass:[NSArray class]] || base.count < 5) return;

    NSMutableArray<NSMutableArray<NSDictionary *> *> *sections = [NSMutableArray arrayWithCapacity:base.count];
    for (NSArray *section in base) {
        [sections addObject:[section mutableCopy]];
    }

    NSMutableArray<NSDictionary *> *known = sections[1];
    NSArray *updatedKnown = FBTReplaceEmployeeMasterDescription(known);
    known = [updatedKnown mutableCopy];

    NSUInteger insertion = MIN((NSUInteger)1, known.count);
    NSArray<NSDictionary *> *familyRows = @[
        @{ @"kind": @"switch",
           @"title": @"Test user / internal test user",
           @"subtitle": @"Employee-or-test-user, IdentitySwitcher, tagging e acesso local a Internal Settings. Não fabrica identidade do backend.",
           @"key": FBTKeyTestUserEnabled,
           @"restart": @YES },
        @{ @"kind": @"switch",
           @"title": @"Dogfood conhecido",
           @"subtitle": @"AC dogfooding, Dogfooding Assistant, ads dogfood view e RageShake tardio. Descritores DATA continuam no MobileConfig.",
           @"key": FBTKeyKnownDogfoodEnabled },
        @{ @"kind": @"switch",
           @"title": @"React Native Internal Settings",
           @"subtitle": @"RCT DevMenu/DevSettings, disponibilidade de debug, shake, hotkeys, menu items e DevLoadingView. Profiler, hot reload e perf monitor continuam controlados pelo usuário.",
           @"key": FBTKeyReactNativeInternalEnabled,
           @"restart": @YES },
        @{ @"kind": @"switch",
           @"title": @"OS beta predicate",
           @"subtitle": @"fishhook em METAOSBuildIsBeta (BOOL(void)). Não altera recibo TestFlight nem o isInternalBuild Swift stripped.",
           @"key": FBTKeyBetaBuildEnabled,
           @"restart": @YES },
    ];

    for (NSDictionary *row in [familyRows reverseObjectEnumerator]) {
        NSString *key = row[@"key"];
        if (!FBTItemsContainKey(known, key)) {
            [known insertObject:row atIndex:insertion];
        }
    }
    sections[1] = known;

    NSMutableArray<NSDictionary *> *runtime = sections[2];
    if (!FBTItemsContainKey(runtime, FBTKeyMobileConfigNativeUIWarmupEnabled)) {
        NSUInteger index = MIN((NSUInteger)1, runtime.count);
        [runtime insertObject:@{
            @"kind": @"switch",
            @"title": @"Aquecer MobileConfig nativo",
            @"subtitle": @"Instala readers/context antes da seleção, faz um retry tipado e mantém fallback local se o QE server continuar indisponível.",
            @"key": FBTKeyMobileConfigNativeUIWarmupEnabled,
        } atIndex:index];
    }

    NSMutableArray<NSDictionary *> *actions = sections[4];
    if (!FBTItemsContainAction(actions, @"rn_internal")) {
        NSUInteger index = MIN((NSUInteger)1, actions.count);
        [actions insertObject:@{
            @"kind": @"action",
            @"title": @"Abrir React Native Internal Settings",
            @"subtitle": @"Abre a rota nativa fb://rninternalsettings confirmada no RN framework.",
            @"action": @"rn_internal",
        } atIndex:index];
    }

    self.sections = sections;
}

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
