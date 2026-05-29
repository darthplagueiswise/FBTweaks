// FBGRMCNativeHooks.xm — fishhook on C-symbol MobileConfig getters.
//
// Why fishhook here (sideload-safe):
//   fishhook rebinds the GOT entries in the calling binary's __DATA segment
//   at runtime. It does NOT modify any binary on disk and does NOT touch the
//   FBSharedFramework code segment. So signature of the framework remains
//   intact — only the Facebook main binary's runtime resolution of imports
//   is redirected. This is exactly the same pattern we use successfully for
//   _METAIsLiquidGlassEnabled and is permitted for sideloaded builds.
//
// Target: _MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter
//   Exported by FBSharedFramework, imported by Facebook main binary
//   (confirmed via lief). It's a C function (source:
//   xplat/msys/src/MessengerCoreSync/MCDCoreDasmNativeOperationsImplementation.c).
//
// SCOPE FOR v3.1 — OBSERVABILITY ONLY:
//   We log invocations when the Observer toggle is on so we can confirm
//   whether THIS getter path is what the framework uses for the gates we
//   care about. The exact argument layout (which arg is the slotId? is it
//   the param key? a session pointer?) is not yet confirmed. Forcing the
//   return without knowing which arg carries the identity would either
//   force ALL bool reads to YES (way too broad) or none.
//
//   Once logs confirm the signature (visible in the Log view), v3.2 can
//   add slot-aware forcing here too.

#import <Foundation/Foundation.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRLog.h"
#import "fishhook.h"

// Conservative generic signature — arm64 ABI passes the first 8 ints in
// x0-x7. We declare 4 uint64 args and call orig with the same registers.
// Real function probably takes 2-3 args; the extra unused args are harmless
// (registers just go ignored by the callee). NOT dereferencing any of them.
typedef bool (*MCDGetBoolFn)(uint64_t a, uint64_t b, uint64_t c, uint64_t d);
static MCDGetBoolFn orig_MCDGetBool = NULL;
static uint64_t gMCDNativeCallCount = 0;

static bool h_MCDGetBool(uint64_t a, uint64_t b, uint64_t c, uint64_t d) {
    bool r = orig_MCDGetBool ? orig_MCDGetBool(a, b, c, d) : false;
    gMCDNativeCallCount++;
    // Log only when the Observer master toggle is on (avoid flooding).
    if (FBGRPref(kFBGRMCObserverEnabled)) {
        // First arg often the param identifier (slotId/configKey). Log all
        // four so the dev can correlate them with known params via the catalog.
        FBGRLogAppend([NSString stringWithFormat:
            @"MCDNative: a=%llx b=%llx c=%llx d=%llx → %@",
            (unsigned long long)a, (unsigned long long)b,
            (unsigned long long)c, (unsigned long long)d,
            r ? @"YES" : @"NO"]);
    }
    return r;
}

extern "C" NSString *FBGRMCNativeHooksDiagnostic(void) {
    return [NSString stringWithFormat:
        @"MCDNative hook=%@ calls=%llu",
        orig_MCDGetBool ? @"installed" : @"NOT installed",
        (unsigned long long)gMCDNativeCallCount];
}

__attribute__((constructor))
static void FBGRMCNativeHooksCtor(void) {
    // Delayed 2.5s like the other hooks so framework symbols are bound.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        struct rebinding r = {
            "MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter",
            (void *)h_MCDGetBool,
            (void **)&orig_MCDGetBool
        };
        int rc = rebind_symbols((struct rebinding[1]){ r }, 1);
        FBGRLogAppend([NSString stringWithFormat:
            @"MCNativeHooks: rebind rc=%d orig=%p", rc, orig_MCDGetBool]);
    });
}
