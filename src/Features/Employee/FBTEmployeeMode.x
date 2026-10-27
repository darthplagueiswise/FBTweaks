#import "FBTPrefix.h"
#import "FacebookHeaders.h"
#import "FBTDefaults.h"
#import <objc/runtime.h>
#import <string.h>
#import "../../Runtime/FBTEmployeeDiagnostics.h"

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
    BOOL forceEmployee = FBTEmployeeIdentityOn();
    if (!forceEmployee && !FBTEmployeeDiagnosticsShouldObserve()) return %orig;

    BOOL original;
    if (forceEmployee) {
        // Use this account's native setter, rather than guessing a defaults suite.
        // Serialize the read/write decision so concurrent readers do not all write.
        @synchronized (self) {
            original = %orig;
            static __thread BOOL persistingEmployee = NO;
            if (!original && !persistingEmployee) {
                persistingEmployee = YES;
                @try {
                    [self setEmployee:YES];
                } @finally {
                    // A native setter/observer may reenter the getter or throw.
                    persistingEmployee = NO;
                }
            }
        }
    } else {
        original = %orig;
    }
    BOOL effective = forceEmployee ? YES : original;
    FBTEmployeeObserveBool(@"FBUserPreferences.isEmployee", original, effective, __builtin_return_address(0));
    return effective;
}
- (void)setEmployee:(BOOL)value {
    BOOL effective = FBTEmployeeIdentityOn() ? YES : value;
    FBTEmployeeObserveBool(@"FBUserPreferences.setEmployee.input", value, effective, __builtin_return_address(0));
    %orig(effective);
}
%end

%hook FBBugReportConfiguration
- (BOOL)isEmployee {
    BOOL original = %orig;
    BOOL effective = FBTEmployeeIdentityOn() ? YES : original;
    FBTEmployeeObserveBool(@"FBBugReportConfiguration.isEmployee", original, effective, __builtin_return_address(0));
    return effective;
}
- (void)setIsEmployee:(BOOL)value {
    %orig(FBTEmployeeIdentityOn() ? YES : value);
}
// Internal Settings is gated through FBShouldEnableInternalSettings.
// The removed setters do not exist on FBBugReportConfiguration in build 583.
%end

%hook FBProductTagCreationLogger
- (BOOL)isEmployee {
    BOOL original = %orig;
    BOOL effective = FBTEmployeeIdentityOn() ? YES : original;
    FBTEmployeeObserveBool(@"FBProductTagCreationLogger.isEmployee", original, effective, __builtin_return_address(0));
    return effective;
}
%end

%hook FBSnacksThreadOwnerMessengerContact
- (BOOL)isEmployee {
    BOOL original = %orig;
    BOOL effective = FBTEmployeeIdentityOn() ? YES : original;
    FBTEmployeeObserveBool(@"FBSnacksThreadOwnerMessengerContact.isEmployee", original, effective, __builtin_return_address(0));
    return effective;
}
%end

%hook FBLoggedOutImageNetworkerConfiguration
- (BOOL)isViewerEmployee {
    BOOL original = %orig;
    BOOL effective = FBTEmployeeIdentityOn() ? YES : original;
    FBTEmployeeObserveBool(@"FBLoggedOutImageNetworkerConfiguration.isViewerEmployee", original, effective, __builtin_return_address(0));
    return effective;
}
%end

%hook FBSessionImageNetworkerConfiguration
- (BOOL)isViewerEmployee {
    BOOL original = %orig;
    BOOL effective = FBTEmployeeIdentityOn() ? YES : original;
    FBTEmployeeObserveBool(@"FBSessionImageNetworkerConfiguration.isViewerEmployee", original, effective, __builtin_return_address(0));
    return effective;
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
    BOOL original = %orig;
    BOOL effective = FBTEmployeeIdentityOn() ? YES : original;
    FBTEmployeeObserveBool(@"RCDMobileConfigParams.isEmployee", original, effective, __builtin_return_address(0));
    return effective;
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
static FBTBoolVoidFn orig_FFDB_isInternLoggedIn = NULL;
static FBTBoolVoidFn orig_FBUser_isEmployee = NULL;

static BOOL fbt_FBUser_isEmployee(id self, SEL command) {
    BOOL original = orig_FBUser_isEmployee ? orig_FBUser_isEmployee(self, command) : NO;
    BOOL effective = FBTEmployeeIdentityOn() ? YES : original;
    FBTEmployeeObserveBool(@"FBUser.isEmployee", original, effective, __builtin_return_address(0));
    return effective;
}

static BOOL fbt_isInternalTestUser(id self, SEL _cmd, id arg1) {
    BOOL original = orig_isInternalTestUser ? orig_isInternalTestUser(self, _cmd, arg1) : NO;
    BOOL effective = FBTTestUserOn() ? YES : original;
    FBTEmployeeObserveBool(@"FBIdentitySwitcherGatingHelper.isInternalTestUser", original, effective, __builtin_return_address(0));
    return effective;
}

static BOOL fbt_isTaggingInternalTestUserEnabled(id self, SEL _cmd, id arg1) {
    BOOL original = orig_isTaggingInternalTestUserEnabled ? orig_isTaggingInternalTestUserEnabled(self, _cmd, arg1) : NO;
    BOOL effective = FBTTestUserOn() ? YES : original;
    FBTEmployeeObserveBool(@"FBIdentitySwitcherGatingHelper.isTaggingInternalTestUserEnabled", original, effective, __builtin_return_address(0));
    return effective;
}

static BOOL fbt_isInGroupingByACDogfooding(id self, SEL _cmd, id arg1) {
    BOOL original = orig_isInGroupingByACDogfooding ? orig_isInGroupingByACDogfooding(self, _cmd, arg1) : NO;
    BOOL effective = FBTKnownDogfoodOn() ? YES : original;
    FBTEmployeeObserveBool(@"FBIdentitySwitcherGatingHelper.isInGroupingByACDogfooding", original, effective, __builtin_return_address(0));
    return effective;
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

static BOOL fbt_FFDB_isInternLoggedIn(id self, SEL _cmd) {
    // Local FFDB UI gate only. This does not mint/replace an internal token.
    return FBTEmployeeIdentityOn() ? YES :
        (orig_FFDB_isInternLoggedIn ? orig_FFDB_isInternLoggedIn(self, _cmd) : NO);
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

static void FBTInstallBoolVoidHook(Class cls,
                                   const char *selectorName,
                                   IMP replacement,
                                   IMP *original) {
    if (!cls || !selectorName || !replacement || !original || *original) return;
    SEL sel = sel_registerName(selectorName);
    if (!FBTMethodHasEncoding(cls, sel, "B16@0:8") &&
        !FBTMethodHasEncoding(cls, sel, "c16@0:8")) {
        return;
    }
    MSHookMessageEx(cls, sel, replacement, original);
}

void FBTInstallKnownGateRuntimeHooks(void) {
    // Retryable; no selector is added. Only an existing B16/c16 getter can hook.
    FBTInstallBoolVoidHook(objc_getClass("FBUser"), "isEmployee",
        (IMP)fbt_FBUser_isEmployee, (IMP *)&orig_FBUser_isEmployee);
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

    FBTInstallBoolVoidHook(objc_getClass("MBUISimpleParticipantModel"),
                           "isEmployee",
                           (IMP)fbt_MBUISimpleParticipantModel_isEmployee,
                           (IMP *)&orig_MBUISimpleParticipantModel_isEmployee);

    FBTInstallBoolVoidHook(objc_getClass("FBClientRageShakeBugReporterIssueComponentState"),
                           "triageToDogfoodingAssistantSession",
                           (IMP)fbt_RageState_triage,
                           (IMP *)&orig_RageState_triage);

    FBTInstallBoolVoidHook(objc_getClass("FBClientRageShakeBugReporterIssueModel"),
                           "triageToDogfoodingAssistantSession",
                           (IMP)fbt_RageModel_triage,
                           (IMP *)&orig_RageModel_triage);

    Class rageView = objc_getClass("FBClientRageShakeBugReporterIssueViewController");
    SEL updateSel = sel_registerName("updatedTriageToDogfoodingAssistantSession:");
    if (rageView && !orig_RageView_updatedTriage &&
        FBTMethodHasEncoding(rageView, updateSel, "v20@0:8B16")) {
        MSHookMessageEx(rageView,
                        updateSel,
                        (IMP)fbt_RageView_updatedTriage,
                        (IMP *)&orig_RageView_updatedTriage);
    }

    FBTInstallBoolVoidHook(objc_getClass("FFDBInternalSettingsWebViewController"),
                           "isInternLoggedIn",
                           (IMP)fbt_FFDB_isInternLoggedIn,
                           (IMP *)&orig_FFDB_isInternLoggedIn);
}

void FBTInitEmployeeGroup(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        %init(FBTEmployee);
    });
    FBTInstallKnownGateRuntimeHooks();
}

