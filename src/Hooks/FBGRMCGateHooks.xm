// FBGRMCGateHooks.xm — MobileConfig getBool interceptor.
// Runtime-only install, no constructor, no global scan, no logging/NSString in hot path.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRLog.h"

typedef BOOL (*GetBoolIMP)(id, SEL, mc_bool_param_t, id);
typedef BOOL (*GetBoolWDIMP)(id, SEL, mc_bool_param_t, id, BOOL);
typedef void (*SetScrollIMP)(id, SEL, BOOL);

typedef struct { Class cls; GetBoolIMP boolImp; GetBoolWDIMP boolWDImp; } FBGRMCOrig;
static FBGRMCOrig gOrigs[32]; static int gOrigCount = 0; static SetScrollIMP orig_setScrollable = NULL; static BOOL gInstalled = NO;

static GetBoolIMP FBGROrigBool(Class cls) { for (int i=0;i<gOrigCount;i++) if (gOrigs[i].cls==cls) return gOrigs[i].boolImp; return NULL; }
static GetBoolWDIMP FBGROrigBoolWD(Class cls) { for (int i=0;i<gOrigCount;i++) if (gOrigs[i].cls==cls) return gOrigs[i].boolWDImp; return NULL; }
static void FBGRRemember(Class cls, IMP a, IMP b) { for (int i=0;i<gOrigCount;i++) if (gOrigs[i].cls==cls) { if(a) gOrigs[i].boolImp=(GetBoolIMP)a; if(b) gOrigs[i].boolWDImp=(GetBoolWDIMP)b; return; } if (gOrigCount<32) gOrigs[gOrigCount++]=(FBGRMCOrig){cls,(GetBoolIMP)a,(GetBoolWDIMP)b}; }

static inline BOOL FBGRShouldOverride(uint64_t slotId, BOOL *outValue) { if (FBGRGateIsSet(slotId)) { *outValue = FBGRGateGet(slotId); return YES; } return NO; }
static BOOL h_getBoolWithOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) { BOOL forced; if (FBGRShouldOverride(p.value, &forced)) return forced; GetBoolIMP orig=FBGROrigBool(object_getClass(self)); if (!orig) orig=FBGROrigBool([self class]); return orig ? orig(self,_cmd,p,opts) : NO; }
static BOOL h_getBoolWithOptionsDefault(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) { BOOL forced; if (FBGRShouldOverride(p.value, &forced)) return forced; GetBoolWDIMP orig=FBGROrigBoolWD(object_getClass(self)); if (!orig) orig=FBGROrigBoolWD([self class]); return orig ? orig(self,_cmd,p,opts,def) : def; }
static void h_setShouldEnableScrollableTabBar(id self, SEL _cmd, BOOL v) { BOOL forced; if (FBGRShouldOverride(1217, &forced) && forced) v = YES; if (orig_setScrollable) orig_setScrollable(self,_cmd,v); }

static void FBGRMCHookClass(Class cls) {
    if (!cls) return;
    SEL sA=sel_registerName("getBool:withOptions:"); SEL sB=sel_registerName("getBool:withOptions:withDefault:"); SEL sC=sel_registerName("setShouldEnableScrollableTabBar:");
    IMP a=NULL,b=NULL;
    if (class_getInstanceMethod(cls, sA)) MSHookMessageEx(cls, sA, (IMP)h_getBoolWithOptions, &a);
    if (class_getInstanceMethod(cls, sB)) MSHookMessageEx(cls, sB, (IMP)h_getBoolWithOptionsDefault, &b);
    if (a || b) FBGRRemember(cls,a,b);
    if (!orig_setScrollable && class_getInstanceMethod(cls, sC)) { IMP o=NULL; MSHookMessageEx(cls, sC, (IMP)h_setShouldEnableScrollableTabBar, &o); if (o) orig_setScrollable=(SetScrollIMP)o; }
}
extern "C" void FBGRMCGateHooksEnsureInstalled(void) {
    if (gInstalled) return; gInstalled = YES; FBGRGateWarmCacheFromPrefs();
    for (NSString *cn in @[@"FBMobileConfigContextManager", @"FBMobileConfigUserSessionContextManager", @"FBMobileConfigSessionlessContextManager", @"FBMobileConfigAdminIDContextManager", @"FBMobileConfigFBTAPI", @"FBMobileConfigFBTContextManager", @"FBMobileConfigAPI", @"FBMobileConfigGlobalContext", @"RCTMobileConfigNative", @"MobileConfigModule"]) FBGRMCHookClass(NSClassFromString(cn));
    FBGRLogAppend([NSString stringWithFormat:@"MCGateHooks installed classes=%d scrollable=%@", gOrigCount, orig_setScrollable?@"YES":@"NO"]);
}
extern "C" NSString *FBGRMCGateHooksDiagnostic(void) { return [NSString stringWithFormat:@"installed=%@\nclasses=%d\nscrollable=%@\noverrides=%lu", gInstalled?@"YES":@"NO", gOrigCount, orig_setScrollable?@"YES":@"NO", (unsigned long)FBGRGateAllOverrideSlotIds().count]; }
