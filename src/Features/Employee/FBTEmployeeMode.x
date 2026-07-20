#import "FBTPrefix.h"
#import "FacebookHeaders.h"
#import "FBTDefaults.h"
#import <objc/runtime.h>
#import <string.h>

// Known identity/gating hooks verified in Facebook, FBSharedFramework,
// FBSharedDynamicFramework and FBRarelyUsedFramework. These are deliberately
// separate from the arbitrary runtime sweep: each selector and ABI was mapped
// before being included here.

static inline BOOL FBTEmployeeIdentityOn(void) {
    return [FBTDefaults boolForKey:FBTKeyEmployeeEnabled];
}

static inline BOOL FBTTestUserOn(void) {
    return FBTEmployeeIdentityOn() || [FBTDefaults boolForKey:FBTKeyTestUserEnabled];
}

static inline BOOL FBTKnownDogfoodOn(void) {
    return FBTEmployeeIdentityOn() || [FBTDefaults boolForKey:FBTKeyKnownDogfoodEnabled];
}

%group FBTEmployee

%hook FBUserPreferences
- (BOOL)isEmployee {
    return FBTEmployeeIdentityOn() ? YES : %orig;
}
- (void)setEmployee:(BOOL)value {
    %orig(FBTEmployeeIdentityOn() ? YES : value);
}
%end

%hook FBBugReportConfiguration
- (BOOL)isEmployee {
    return FBTEmployeeIdentityOn() ? YES : %orig;
}
- (void)setIsEmployee:(BOOL)value {
    %orig(FBTEmployeeIdentityOn() ? YES : value);
}
- (void)setEnableInternalSettingsOption:(BOOL)value {
    %orig(FBTEmployeeIdentityOn() ? YES : value);
}
- (void)setEnableInternalToolsSubmenu:(BOOL)value {
    %orig(FBTEmployeeIdentityOn() ? YES : value);
}
- (void)setForceShowingInternalTools:(BOOL)value {
    %orig(FBTEmployeeIdentityOn() ? YES : value);
}
- (void)setShowTriageToDogfoodingAssistantSession:(BOOL)value {
    %orig(FBTKnownDogfoodOn() ? YES : value);
}
- (void)setDisableEmployeeProductionReports:(BOOL)value {
    %orig(FBTEmployeeIdentityOn() ? NO : value);
}
%end

%hook FBProductTagCreationLogger
- (BOOL)isEmployee {
    return FBTEmployeeIdentityOn() ? YES : %orig;
}
%end

%hook FBSnacksThreadOwnerMessengerContact
- (BOOL)isEmployee {
    return FBTEmployeeIdentityOn() ? YES : %orig;
}
%end

%hook FBLoggedOutImageNetworkerConfiguration
- (BOOL)isViewerEmployee {
    return FBTEmployeeIdentityOn() ? YES : %orig;
}
%end

%hook FBSessionImageNetworkerConfiguration
- (BOOL)isViewerEmployee {
    return FBTEmployeeIdentityOn() ? YES : %orig;
}
%end

%hook FBRichPushNotificationTypeTraits
+ (BOOL)_isEmployeeOrTestUser:(id)arg1 {
    return FBTTestUserOn() ? YES : %orig;
}
%end

%hook FBWKWebView
- (void)setIsEmployee:(BOOL)value {
    %orig(FBTEmployeeIdentityOn() ? YES : value);
}
%end

%hook FBWKWebViewDelegateAdaptor
- (void)setIsEmployee:(BOOL)value {
    %orig(FBTEmployeeIdentityOn() ? YES : value);
}
%end

%hook RCDMobileConfigParams
- (BOOL)isEmployee {
    return FBTEmployeeIdentityOn() ? YES : %orig;
}
- (id)initWithClassesString:(id)classesString
     trackNSObjectBaseClass:(BOOL)trackNSObjectBaseClass
        isEventBasedTrigger:(BOOL)isEventBasedTrigger
                maxCycleLen:(long long)maxCycleLen
 ignoreAppleClassesWithPrefix:(id)ignoreAppleClassesWithPrefix
             peopleSampling:(long long)peopleSampling
                  isEmployee:(BOOL)isEmployee
         isEnabledProduction:(BOOL)isEnabledProduction
  shouldUseSwiftABITraversal:(BOOL)shouldUseSwiftABITraversal {
    return %orig(classesString,
                 trackNSObjectBaseClass,
                 isEventBasedTrigger,
                 maxCycleLen,
                 ignoreAppleClassesWithPrefix,
                 peopleSampling,
                 FBTEmployeeIdentityOn() ? YES : isEmployee,
                 isEnabledProduction,
                 shouldUseSwiftABITraversal);
}
%end

%hook FBLoom
- (void)userSessionDidUpdateWithValidUser:(BOOL)validUser
                              isEmployee:(BOOL)isEmployee
                       networkDispatcher:(id)networkDispatcher
                     mobileConfigManager:(id)mobileConfigManager
                              qplSession:(long long)qplSession {
    %orig(validUser,
          FBTEmployeeIdentityOn() ? YES : isEmployee,
          networkDispatcher,
          mobileConfigManager,
          qplSession);
}
%end

%hook FBBugReportInitialCoordinator
- (BOOL)triageToDogfoodingAssistantSession {
    return FBTKnownDogfoodOn() ? YES : %orig;
}
- (void)updateTriageToDogfoodingAssistantSession:(BOOL)value {
    %orig(FBTKnownDogfoodOn() ? YES : value);
}
%end

%hook FBSnacksAdsDeliveryConfig
- (BOOL)enableDogfoodingView {
    return FBTKnownDogfoodOn() ? YES : %orig;
}
%end

%end // FBTEmployee

// -------------------------------------------------------------------------
// Swift and late-loaded Objective-C classes.
// One original pointer per selector/class. The installer is retryable and is
// called again from the tab host after the main UI is live.
// -------------------------------------------------------------------------

typedef BOOL (*FBTBoolObjectFn)(id, SEL, id);
typedef BOOL (*FBTBoolVoidFn)(id, SEL);
typedef void (*FBTVoidBoolFn)(id, SEL, BOOL);

static FBTBoolObjectFn orig_isInternalTestUser = NULL;
static FBTBoolObjectFn orig_isTaggingInternalTestUserEnabled = NULL;
static FBTBoolObjectFn orig_isInGroupingByACDogfooding = NULL;
static FBTBoolVoidFn orig_MBUISimpleParticipantModel_isEmployee = NULL;
static FBTBoolVoidFn orig_RageState_triage = NULL;
static FBTBoolVoidFn orig_RageModel_triage = NULL;
static FBTVoidBoolFn orig_RageView_updatedTriage = NULL;

static BOOL fbt_isInternalTestUser(id self, SEL _cmd, id arg1) {
    return FBTTestUserOn() ? YES : (orig_isInternalTestUser ? orig_isInternalTestUser(self, _cmd, arg1) : NO);
}

static BOOL fbt_isTaggingInternalTestUserEnabled(id self, SEL _cmd, id arg1) {
    return FBTTestUserOn() ? YES : (orig_isTaggingInternalTestUserEnabled ? orig_isTaggingInternalTestUserEnabled(self, _cmd, arg1) : NO);
}

static BOOL fbt_isInGroupingByACDogfooding(id self, SEL _cmd, id arg1) {
    return FBTKnownDogfoodOn() ? YES : (orig_isInGroupingByACDogfooding ? orig_isInGroupingByACDogfooding(self, _cmd, arg1) : NO);
}

static BOOL fbt_MBUISimpleParticipantModel_isEmployee(id self, SEL _cmd) {
    return FBTEmployeeIdentityOn() ? YES : (orig_MBUISimpleParticipantModel_isEmployee ? orig_MBUISimpleParticipantModel_isEmployee(self, _cmd) : NO);
}

static BOOL fbt_RageState_triage(id self, SEL _cmd) {
    return FBTKnownDogfoodOn() ? YES : (orig_RageState_triage ? orig_RageState_triage(self, _cmd) : NO);
}

static BOOL fbt_RageModel_triage(id self, SEL _cmd) {
    return FBTKnownDogfoodOn() ? YES : (orig_RageModel_triage ? orig_RageModel_triage(self, _cmd) : NO);
}

static void fbt_RageView_updatedTriage(id self, SEL _cmd, BOOL value) {
    if (orig_RageView_updatedTriage) {
        orig_RageView_updatedTriage(self, _cmd, FBTKnownDogfoodOn() ? YES : value);
    }
}

static BOOL FBTMethodHasEncoding(Class cls, SEL sel, const char *encoding) {
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    const char *actual = method ? method_getTypeEncoding(method) : NULL;
    return actual && encoding && strcmp(actual, encoding) == 0;
}

static void FBTInstallBoolObjectHook(Class cls,
                                     const char *selectorName,
                                     IMP replacement,
                                     IMP *original) {
    if (!cls || !selectorName || !replacement || !original || *original) return;
    SEL sel = sel_registerName(selectorName);
    if (!FBTMethodHasEncoding(cls, sel, "B24@0:8@16") &&
        !FBTMethodHasEncoding(cls, sel, "c24@0:8@16")) {
        return;
    }
    MSHookMessageEx(cls, sel, replacement, original);
}

void FBTInstallKnownGateRuntimeHooks(void) {
    Class helper = objc_getClass("_TtC24FBIdentitySwitcherGating30FBIdentitySwitcherGatingHelper");
    FBTInstallBoolObjectHook(helper,
                             "isInternalTestUser:",
                             (IMP)fbt_isInternalTestUser,
                             (IMP *)&orig_isInternalTestUser);
    FBTInstallBoolObjectHook(helper,
                             "isTaggingInternalTestUserEnabled:",
                             (IMP)fbt_isTaggingInternalTestUserEnabled,
                             (IMP *)&orig_isTaggingInternalTestUserEnabled);
    FBTInstallBoolObjectHook(helper,
                             "isInGroupingByACDogfooding:",
                             (IMP)fbt_isInGroupingByACDogfooding,
                             (IMP *)&orig_isInGroupingByACDogfooding);

    Class mbui = objc_getClass("MBUISimpleParticipantModel");
    SEL employeeSel = sel_registerName("isEmployee");
    if (mbui && !orig_MBUISimpleParticipantModel_isEmployee &&
        (FBTMethodHasEncoding(mbui, employeeSel, "B16@0:8") ||
         FBTMethodHasEncoding(mbui, employeeSel, "c16@0:8"))) {
        MSHookMessageEx(mbui,
                        employeeSel,
                        (IMP)fbt_MBUISimpleParticipantModel_isEmployee,
                        (IMP *)&orig_MBUISimpleParticipantModel_isEmployee);
    }

    Class rageState = objc_getClass("FBClientRageShakeBugReporterIssueComponentState");
    SEL triageSel = sel_registerName("triageToDogfoodingAssistantSession");
    if (rageState && !orig_RageState_triage &&
        (FBTMethodHasEncoding(rageState, triageSel, "B16@0:8") ||
         FBTMethodHasEncoding(rageState, triageSel, "c16@0:8"))) {
        MSHookMessageEx(rageState,
                        triageSel,
                        (IMP)fbt_RageState_triage,
                        (IMP *)&orig_RageState_triage);
    }

    Class rageModel = objc_getClass("FBClientRageShakeBugReporterIssueModel");
    if (rageModel && !orig_RageModel_triage &&
        (FBTMethodHasEncoding(rageModel, triageSel, "B16@0:8") ||
         FBTMethodHasEncoding(rageModel, triageSel, "c16@0:8"))) {
        MSHookMessageEx(rageModel,
                        triageSel,
                        (IMP)fbt_RageModel_triage,
                        (IMP *)&orig_RageModel_triage);
    }

    Class rageView = objc_getClass("FBClientRageShakeBugReporterIssueViewController");
    SEL updateSel = sel_registerName("updatedTriageToDogfoodingAssistantSession:");
    if (rageView && !orig_RageView_updatedTriage &&
        FBTMethodHasEncoding(rageView, updateSel, "v20@0:8B16")) {
        MSHookMessageEx(rageView,
                        updateSel,
                        (IMP)fbt_RageView_updatedTriage,
                        (IMP *)&orig_RageView_updatedTriage);
    }
}

void FBTInitEmployeeGroup(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        %init(FBTEmployee);
    });
    FBTInstallKnownGateRuntimeHooks();
}
