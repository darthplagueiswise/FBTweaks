#import "FBTMCNativeSessionProbes.h"
#import "../FBTDefaults.h"
#import "FBTMobileConfigResponseCapture.h"
#import "FBTMobileConfigFetchDiagnostics.h"
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
NSDictionary *FBTMCNativeProbeStatus(void) {
    return @{
        @"tigon_session_enabled": @(FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey)),
        @"fetcher_session_enabled": @(FBTMCNativeProbeIsEnabled(FBTMCNativeProbeFetcherKey)),
        @"tigon_simple_callbacks": FBTMobileConfigTigonCaptureStatus()[@"simple_callback_hooks_installed"] ?: @NO,
        @"fetcher_async_callback": FBTMobileConfigFetcherCaptureStatus()[@"native_mc_fetcher_installed"] ?: @NO,
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
    // Installers are independently protected by exact UUID + pointer + data
    // section checks; no global NSURLSession hook, no Frida, no __TEXT writes.
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
    if (reason) *reason = installed ?
        @"Probe armado apenas nesta sessão. Hook nativo verificado no UUID e no slot; veja o diagnóstico após reproduzir o fetch." :
        [NSString stringWithFormat:@"Hook não instalado: %@", failure ?: @"UUID, slot ou ABI incompatível."];
    FBTMobileConfigFetchDiagnosticsRecord(@"mc_native_probe_toggle", @{
        @"hook_installed": @(installed),
        @"message": installed ? @"manual_opt_in_session" : (failure ?: @"validation_failed"),
        @"capture_surface": [key isEqualToString:FBTMCNativeProbeTigonKey]
            ? @"TigonSimpleCallbacks" : @"FBMobileConfigTigonFetcher.asyncFetch"
    });
    return installed;
}
