#import "FBTPrefix.h"
#import "FacebookHeaders.h"
#import "FBTDefaults.h"

// =====================================================================
// Modo Employee / Internal (KEYSTONE)
// Força os getters de "é funcionário/test user" a retornarem YES.
// Estes seletores foram confirmados no binário, cada um na classe abaixo.
// Sem chamadas pesadas: cada corpo lê uma pref barata e cai p/ orig.
// =====================================================================

%group FBTEmployee

%hook FBUserPreferences
- (BOOL)isEmployee {
    if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled]) return YES;
    return %orig;
}
%end

%hook FBBugReportConfiguration
- (BOOL)isEmployee {
    if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled]) return YES;
    return %orig;
}
%end

%hook FBProductTagCreationLogger
- (BOOL)isEmployee {
    if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled]) return YES;
    return %orig;
}
%end

%hook FBSnacksThreadOwnerMessengerContact
- (BOOL)isEmployee {
    if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled]) return YES;
    return %orig;
}
%end

%hook FBLoggedOutImageNetworkerConfiguration
- (BOOL)isViewerEmployee {
    if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled]) return YES;
    return %orig;
}
%end

%hook FBSessionImageNetworkerConfiguration
- (BOOL)isViewerEmployee {
    if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled]) return YES;
    return %orig;
}
%end

%hook FBRichPushNotificationTypeTraits
+ (BOOL)_isEmployeeOrTestUser:(id)arg1 {
    if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled]) return YES;
    return %orig;
}
%end

%end // FBTEmployee

// Swift: _TtC24FBIdentitySwitcherGating30FBIdentitySwitcherGatingHelper
//   - (BOOL)isInternalTestUser:(id)arg1
// Classe Swift @objc — resolvida em runtime e hookada via MSHookMessageEx.
static BOOL (*orig_isInternalTestUser)(id, SEL, id) = NULL;
static BOOL fbt_isInternalTestUser(id self, SEL _cmd, id arg1) {
    if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled]) return YES;
    return orig_isInternalTestUser ? orig_isInternalTestUser(self, _cmd, arg1) : NO;
}

static void FBTInstallSwiftEmployeeHook(void) {
    Class cls = objc_getClass("_TtC24FBIdentitySwitcherGating30FBIdentitySwitcherGatingHelper");
    if (!cls) { FBTLog(@"IdentitySwitcherGatingHelper ausente"); return; }
    SEL sel = NSSelectorFromString(@"isInternalTestUser:");
    if (!class_getInstanceMethod(cls, sel)) { FBTLog(@"isInternalTestUser: ausente"); return; }
    MSHookMessageEx(cls, sel, (IMP)fbt_isInternalTestUser, (IMP *)&orig_isInternalTestUser);
}

// Wrapper chamado pelo Tweak.x quando a pref está on.
void FBTInitEmployeeGroup(void) {
    %init(FBTEmployee);
    FBTInstallSwiftEmployeeHook();
}
