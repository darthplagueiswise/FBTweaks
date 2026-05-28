// FBGRMCGateHooks.xm
//
// CRASH HISTORY (com.facebook.startup.asyncpreload):
//   v0.2.4 — crash depth=2053: bypass path chamava NSStringFromClass
//            → CoreFoundation TSD init → getBool: → bypass → NSStringFromClass → loop
//   v0.2.5 — crash depth=1954: mesmo loop (guard funcionou mas bypass ainda usava CF)
//
// ROOT CAUSE: qualquer chamada CF/ObjC no bypass path (quando guard=YES) durante
//   startup pode disparar uma leitura interna de MobileConfig → nova entrada no hook
//   → bypass → CF/ObjC → loop infinito.
//
// SOLUÇÃO DUPLA:
//   1. bypass path 100% C puro — sem NSStringFromClass, sem ObjC dict, sem CF
//      Usa arrays C com comparação de ponteiro de classe (object_getClass = C inline)
//   2. Hook instalado com delay de 2s após o main runloop → startup já terminou,
//      CF/TSD/MC initialization já completos → recursão não ocorre
//      Leituras durante startup (<2s) usam valores padrão do MC (sem override).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRLog.h"

// ── Reentrancy guard (TLS) ────────────────────────────────────────────────────
static __thread BOOL gFBGRMCHookGuard = NO;

// ── C-level class/IMP table ───────────────────────────────────────────────────
// Sem ObjC: usa comparação de ponteiro de classe, não NSStringFromClass.
// object_getClass() lê o isa diretamente, zero side effects.
#define FBGR_MAX_HOOKED_CLS 10
typedef struct {
    Class cls;
    IMP   getBoolOrig;
    IMP   getBoolWDOrig;
} FBGRHookedClass;

static FBGRHookedClass gHookedClasses[FBGR_MAX_HOOKED_CLS];
static int             gHookedN = 0;

static IMP FBGRGetBoolOrig(Class cls) {
    // Pure C — safe to call when guard is active
    for (int i = 0; i < gHookedN; i++)
        if (gHookedClasses[i].cls == cls) return gHookedClasses[i].getBoolOrig;
    return NULL;
}
static IMP FBGRGetBoolWDOrig(Class cls) {
    for (int i = 0; i < gHookedN; i++)
        if (gHookedClasses[i].cls == cls) return gHookedClasses[i].getBoolWDOrig;
    return NULL;
}

// ── C-level override cache ─────────────────────────────────────────────────────
// Overrides são lidos do NSUserDefaults UMA VEZ na instalação do hook
// (e atualizados quando o usuário altera via menu).
// Zero ObjC/CF no hot path.
#define FBGR_MAX_OVERRIDES 64
typedef struct { uint64_t slotId; BOOL value; } FBGROverride;
static FBGROverride gOverrideCache[FBGR_MAX_OVERRIDES];
static int          gOverrideCacheN = 0;

static BOOL FBGRCacheLookup(uint64_t slotId, BOOL *outValue) {
    for (int i = 0; i < gOverrideCacheN; i++) {
        if (gOverrideCache[i].slotId == slotId) {
            *outValue = gOverrideCache[i].value;
            return YES;
        }
    }
    return NO;
}

static void FBGRCacheRebuild(void) {
    // Called from main thread ONLY (after hook installation).
    // Reads NSUserDefaults → safe here, startup is complete.
    @autoreleasepool {
        gOverrideCacheN = 0;
        NSArray<NSNumber *> *ids = FBGRGateAllOverrideSlotIds();
        for (NSNumber *n in ids) {
            if (gOverrideCacheN >= FBGR_MAX_OVERRIDES) break;
            uint64_t s = [n unsignedLongLongValue];
            gOverrideCache[gOverrideCacheN].slotId = s;
            gOverrideCache[gOverrideCacheN].value  = FBGRGateGet(s);
            gOverrideCacheN++;
        }
        // Also cache LiquidGlass master toggle as slotId 0
        if (FBGRPref(kFBGRLiquidGlassMaster) && gOverrideCacheN < FBGR_MAX_OVERRIDES) {
            gOverrideCache[gOverrideCacheN].slotId = 0;
            gOverrideCache[gOverrideCacheN].value  = YES;
            gOverrideCacheN++;
        }
        FBGRLogAppend([NSString stringWithFormat:@"MCGateHooks: cache rebuilt %d overrides", gOverrideCacheN]);
    }
}

// ── Trampolines ───────────────────────────────────────────────────────────────

typedef BOOL (*GetBoolIMP)(id, SEL, mc_bool_param_t, id);
typedef BOOL (*GetBoolWDIMP)(id, SEL, mc_bool_param_t, id, BOOL);
typedef void (*SetScrollIMP)(id, SEL, BOOL);
static SetScrollIMP orig_setScrollable = NULL;

static BOOL h_getBoolWithOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    // object_getClass: pure C, reads isa, zero side effects — safe at any depth
    IMP orig = FBGRGetBoolOrig(object_getClass(self));

    if (gFBGRMCHookGuard) {
        // PURE C PATH: no ObjC, no CF, no string, no TSD
        return orig ? ((GetBoolIMP)orig)(self, _cmd, p, opts) : NO;
    }

    BOOL forced = NO;
    if (FBGRCacheLookup(p.value, &forced)) {
        // Cache hit: set guard only to protect the log call (ObjC)
        gFBGRMCHookGuard = YES;
        FBGRLogAppend([NSString stringWithFormat:@"MC getBool slotId=%llu → %@",
                       (unsigned long long)p.value, forced ? @"YES" : @"NO"]);
        gFBGRMCHookGuard = NO;
        return forced;
    }

    return orig ? ((GetBoolIMP)orig)(self, _cmd, p, opts) : NO;
}

static BOOL h_getBoolWithOptionsDefault(id self, SEL _cmd,
                                        mc_bool_param_t p, id opts, BOOL def) {
    IMP orig = FBGRGetBoolWDOrig(object_getClass(self));

    if (gFBGRMCHookGuard)
        return orig ? ((GetBoolWDIMP)orig)(self, _cmd, p, opts, def) : def;

    BOOL forced = NO;
    if (FBGRCacheLookup(p.value, &forced)) return forced;
    return orig ? ((GetBoolWDIMP)orig)(self, _cmd, p, opts, def) : def;
}

static void h_setShouldEnableScrollableTabBar(id self, SEL _cmd, BOOL v) {
    BOOL forced = NO;
    if (!gFBGRMCHookGuard && FBGRCacheLookup(1217, &forced) && forced) v = YES;
    if (orig_setScrollable) orig_setScrollable(self, _cmd, v);
}

// ── Hook installation ─────────────────────────────────────────────────────────
static NSUInteger gHookedCount = 0;

static void FBGRMCHookClass(Class cls) {
    if (!cls || gHookedN >= FBGR_MAX_HOOKED_CLS) return;
    // Check if already hooked
    for (int i = 0; i < gHookedN; i++) if (gHookedClasses[i].cls == cls) return;

    SEL sA = sel_registerName("getBool:withOptions:");
    SEL sB = sel_registerName("getBool:withOptions:withDefault:");
    SEL sC = sel_registerName("setShouldEnableScrollableTabBar:");

    FBGRHookedClass *slot = &gHookedClasses[gHookedN];
    slot->cls = cls;
    BOOL hooked = NO;

    if (class_getInstanceMethod(cls, sA)) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sA, (IMP)h_getBoolWithOptions, &orig);
        if (orig) { slot->getBoolOrig = orig; hooked = YES; }
    }
    if (class_getInstanceMethod(cls, sB)) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sB, (IMP)h_getBoolWithOptionsDefault, &orig);
        if (orig) slot->getBoolWDOrig = orig;
    }
    if (!orig_setScrollable && class_getInstanceMethod(cls, sC)) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sC, (IMP)h_setShouldEnableScrollableTabBar, &orig);
        if (orig) orig_setScrollable = (SetScrollIMP)orig;
    }

    if (hooked) { gHookedN++; gHookedCount++; }
}

static void FBGRMCInstallHooks(void) {
    for (NSString *cn in @[
        @"FBMobileConfigContextManager",
        @"FBMobileConfigUserSessionContextManager",
        @"FBMobileConfigSessionlessContextManager",
        @"FBMobileConfigFBTAPI",
        @"FBMobileConfigFBTContextManager",
        @"FBMobileConfigAPI",
        @"FBMobileConfigGlobalContext",
    ]) {
        Class cls = NSClassFromString(cn);
        if (cls) FBGRMCHookClass(cls);
    }
    if (!orig_setScrollable) {
        SEL sC = sel_registerName("setShouldEnableScrollableTabBar:");
        unsigned int n = 0; Class *all = objc_copyClassList(&n);
        for (unsigned i = 0; i < n && !orig_setScrollable; i++)
            if (class_getInstanceMethod(all[i], sC)) FBGRMCHookClass(all[i]);
        free(all);
    }
    FBGRCacheRebuild();
    FBGRLogAppend([NSString stringWithFormat:
        @"MCGateHooks: installed on %lu classes, %d overrides cached",
        (unsigned long)gHookedCount, gOverrideCacheN]);
}

// ── Public API ────────────────────────────────────────────────────────────────
extern "C" void FBGRMCGateHooksEnsureInstalled(void) {
    // No-op here: installation is delayed to after startup (see ctor below)
}

extern "C" void FBGRMCGateCacheRefresh(void) {
    // Call after user changes settings in menu
    FBGRCacheRebuild();
}

extern "C" NSString *FBGRMCGateHooksDiagnostic(void) {
    return [NSString stringWithFormat:
        @"hookedClasses=%lu\nscrollable=%@\ncachedOverrides=%d",
        (unsigned long)gHookedCount,
        orig_setScrollable ? @"YES" : @"NO",
        gOverrideCacheN];
}

// ── Constructor: DELAYED installation ────────────────────────────────────────
// FIX: não instalar no ctor direto — startup asyncpreload ainda está
// inicializando CF/TSD/MC nesse momento → recursão infinita.
// Aguarda 2s no main queue → startup completo, safe para hooks ObjC.
__attribute__((constructor))
static void FBGRMCGateHooksCtor(void) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            FBGRMCInstallHooks();
        }
    );
}
