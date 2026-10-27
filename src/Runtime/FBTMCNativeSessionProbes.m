#import "FBTMCNativeSessionProbes.h"
#import "../FBTDefaults.h"
#import "FBTMobileConfigResponseCapture.h"
#import "FBTMobileConfigFetchDiagnostics.h"
#import "FBTNativeTrace.h"
#include <stdatomic.h>

NSString * const FBTMCNativeProbeTigonKey = @"fbt_mc_native_tigon_probe_session";
NSString * const FBTMCNativeProbeFetcherKey = @"fbt_mc_native_fetcher_probe_session";
static atomic_bool sTigonEnabled = ATOMIC_VAR_INIT(false);
static atomic_bool sFetcherEnabled = ATOMIC_VAR_INIT(false);

BOOL FBTMCNativeProbeIsKey(NSString *key) {
    return [key isEqualToString:FBTMCNativeProbeTigonKey] ||
        [key isEqualToString:FBTMCNativeProbeFetcherKey];
}
BOOL FBTMCNativeProbeIsEnabled(NSString *key) {
    if ([key isEqualToString:FBTMCNativeProbeTigonKey])
        return atomic_load_explicit(&sTigonEnabled, memory_order_acquire);
    if ([key isEqualToString:FBTMCNativeProbeFetcherKey])
        return atomic_load_explicit(&sFetcherEnabled, memory_order_acquire);
    return NO;
}
BOOL FBTMCNativeProbeAnyEnabled(void) {
    return atomic_load_explicit(&sTigonEnabled, memory_order_acquire) ||
        atomic_load_explicit(&sFetcherEnabled, memory_order_acquire);
}
void FBTMCNativeProbeDisableAll(void) {
    atomic_store_explicit(&sTigonEnabled, false, memory_order_release);
    atomic_store_explicit(&sFetcherEnabled, false, memory_order_release);
}

NSDictionary *FBTMCNativeProbeStatus(void) {
    return @{
        @"tigon_session_enabled": @(FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey)),
        @"fetcher_session_enabled": @(FBTMCNativeProbeIsEnabled(FBTMCNativeProbeFetcherKey)),
        @"tigon_simple_callbacks": FBTMobileConfigTigonCaptureStatus()[@"simple_callback_hooks_installed"] ?: @NO,
        @"fetcher_async_callback": FBTMobileConfigFetcherCaptureStatus()[@"native_mc_fetcher_installed"] ?: @NO,
        @"tigon_dynamic_symbol_count": FBTMobileConfigTigonCaptureStatus()[@"simple_symbol_resolved_callbacks"] ?: @0,
        @"tigon_method_entry_hook_count": FBTMobileConfigTigonCaptureStatus()[@"simple_exported_function_hooks"] ?: @0,
        @"tigon_hook_kind": FBTMobileConfigTigonCaptureStatus()[@"simple_hook_kind"] ?: @"not_attempted",
        @"tigon_resolution": FBTMobileConfigTigonCaptureStatus()[@"simple_callback_failure"] ?: @"not_attempted",
        @"fetcher_resolution": FBTMobileConfigFetcherCaptureStatus()[@"native_mc_fetcher_failure"] ?: @"unknown",
        @"nonpersistent": @YES
    };
}

BOOL FBTMCNativeProbeSetEnabled(NSString *key, BOOL enabled, NSString **reason) {
    if (!FBTMCNativeProbeIsKey(key)) {
        if (reason) *reason = @"Tipo de probe desconhecido.";
        return NO;
    }
    atomic_bool *enabledFlag = [key isEqualToString:FBTMCNativeProbeTigonKey]
        ? &sTigonEnabled : &sFetcherEnabled;
    if (!enabled) {
        atomic_store_explicit(enabledFlag, false, memory_order_release);
        if (reason) *reason = @"Desarmado nesta sessão. Reiniciar restaura o estado sem hooks.";
        return YES;
    }
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
        if (reason) *reason = @"Ative primeiro Log QE-info (seguro).";
        return NO;
    }
    // Installers resolve live C++ symbols/RTTI and verify vtable pointers,
    // with exact-UUID fallback. No global NSURLSession hook or __TEXT writes.
    atomic_store_explicit(enabledFlag, true, memory_order_release);
    BOOL installed = NO;
    NSString *failure = nil;
    if ([key isEqualToString:FBTMCNativeProbeTigonKey]) {
        FBTMobileConfigResponseCaptureInstallTigon();
        NSDictionary *state = FBTMobileConfigTigonCaptureStatus();
        installed = [state[@"simple_callback_hooks_installed"] boolValue];
        failure = state[@"simple_callback_failure"];
    } else {
        FBTMobileConfigFetcherCaptureInstall();
        NSDictionary *state = FBTMobileConfigFetcherCaptureStatus();
        installed = [state[@"native_mc_fetcher_installed"] boolValue];
        failure = state[@"native_mc_fetcher_failure"];
    }
    if (!installed) atomic_store_explicit(enabledFlag, false, memory_order_release);
    // This explicit opt-in must arm the sanitized in-memory collector too.
    // Failed hook validation never turns a previously OFF collector ON.
    if (installed) FBTNativeTraceSetSessionCaptureEnabled(YES);
    if (reason) *reason = installed ?
        @"Probe de sessão instalado após validação da imagem, slot e símbolos/RTTI ou UUID conhecido." :
        [NSString stringWithFormat:@"Hook não instalado: %@", failure ?: @"UUID, slot ou ABI incompatível."];
    FBTMobileConfigFetchDiagnosticsRecord(@"mc_native_probe_toggle", @{
        @"hook_installed": @(installed),
        @"message": installed ? @"manual_opt_in_session" : (failure ?: @"validation_failed"),
        @"capture_surface": [key isEqualToString:FBTMCNativeProbeTigonKey]
            ? @"TigonSimpleCallbacks" : @"FBMobileConfigTigonFetcher.asyncFetch"
    });
    return installed;
}
