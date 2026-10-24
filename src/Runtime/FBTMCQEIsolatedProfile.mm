#import "FBTMCQEIsolatedProfile.h"
#import "FBTMobileConfigFetchDiagnostics.h"
#import "FBTMobileConfigResponseCapture.h"
#import "FBTMCNativeSessionProbes.h"
#import "FBTDataSlotRebinding.h"
#import "../FBTDefaults.h"
#include "FBTMCQEFullMetadataCore.hpp"
#import <QuartzCore/QuartzCore.h>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#if FBT_ENABLE_QE_ISOLATED_PROFILE

// This is not the old QE observer. It owns exactly one UUID-verified data
// slot, cannot coexist with the prior native fetcher probe, and has no global
// NSError/NSURLSession/Tigon callback/refreshNames/swizzle hooks.
using FBTQECompletion = std::function<void(bool, const std::string &)>;
using FBTQENativeFetcher = void (*)(const void *, const std::string &,
    const std::string &, const fbt_qe_isolated::Pairs &, FBTQECompletion,
    const std::string &, uint64_t);
static FBTQENativeFetcher sOriginal;
static bool sInstalled = false;
static NSString *sFailure = @"not_attempted";
static std::mutex sInstallMutex;
static fbt_qe_isolated::OneShot sOneShot;

static NSString *FBTQESafeProtocolOptions(const fbt_qe_isolated::Pairs &pairs) {
    // Only nine fixed protocol keys; never log queries, IDs, tokens or arbitrary
    // headers. A duplicate/unexpected value is represented by a constant label.
    NSMutableDictionary *summary = [NSMutableDictionary dictionary];
    for (const auto &field : fbt_qe_isolated::kFields) {
        std::size_t count = 0;
        NSString *label = @"missing";
        for (const auto &pair : pairs) {
            if (pair.first != field.name) continue;
            ++count;
            if (pair.second == "true" || pair.second == "1") label = @"true";
            else if (pair.second == "false" || pair.second == "0") label = @"false";
            else label = @"invalid";
        }
        if (count > 1) label = @"duplicate";
        summary[[NSString stringWithUTF8String:field.name]] = label;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:summary
        options:NSJSONWritingSortedKeys error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

static void FBTQERecordAsync(NSString *event, NSDictionary *details) {
    // No synchronous diagnostics serialization on the Tigon fetcher's stack.
    dispatch_async(dispatch_get_main_queue(), ^{
        FBTMobileConfigFetchDiagnosticsRecord(event, details);
    });
}

static void FBTQEIsolatedFetch(const void *fetcher, const std::string &method,
    const std::string &purpose, const fbt_qe_isolated::Pairs &params,
    FBTQECompletion callback, const std::string &routingHint, uint64_t target) {
    FBTQENativeFetcher original = sOriginal;
    if (!original) return; // A verified slot can never be installed without original.
    // Keep ordinary and value-sync fetches on a fast, identity-preserving path.
    if (method != "POST" || purpose != "mobileconfig_qe_info" ||
        !sOneShot.consume(method, purpose, CACurrentMediaTime())) {
        original(fetcher, method, purpose, params, std::move(callback), routingHint, target);
        return;
    }

    // Re-check the capture setting, and fail closed if the old probe somehow
    // became active after the profile was manually armed.
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled] ||
        FBTQEInvasiveHooksAllowed() || FBTMCNativeProbeAnyEnabled()) {
        FBTQERecordAsync(@"qe_isolated_profile_request", @{
            @"experiment_profile": @"QE_full_metadata_isolated",
            @"experiment_state": @"original_request",
            @"qe_isolated_reason": @"capture_disabled_or_probe_conflict",
            @"hook_installed": @YES
        });
        original(fetcher, method, purpose, params, std::move(callback), routingHint, target);
        return;
    }

    auto outgoing = std::make_shared<fbt_qe_isolated::Pairs>(params);
    NSString *before = FBTQESafeProtocolOptions(params);
    const auto changed = fbt_qe_isolated::apply(*outgoing);
    NSString *after = FBTQESafeProtocolOptions(*outgoing);
    FBTQERecordAsync(@"qe_isolated_profile_request", @{
        @"experiment_profile": @"QE_full_metadata_isolated",
        @"experiment_state": changed.applied ? @"profile_applied" : @"original_request",
        @"qe_isolated_reason": [NSString stringWithUTF8String:changed.reason],
        @"qe_isolated_applied": @(changed.applied),
        @"qe_isolated_changed": @(changed.changed),
        @"qe_isolated_before": before,
        @"qe_isolated_after": after,
        @"hook_installed": @YES,
        @"request_method": @"POST",
        @"capture_reason": @"mobileconfig_qe_info"
    });

    if (!changed.applied) {
        original(fetcher, method, purpose, params, std::move(callback), routingHint, target);
        return;
    }

    // A minimal completion passthrough is necessary to keep the modified pairs
    // alive in case the private fetcher holds their reference asynchronously.
    // It NEVER inspects/modifies the native response or success value.
    auto originalCompletion = std::make_shared<FBTQECompletion>(std::move(callback));
    FBTQECompletion passthrough = [outgoing, originalCompletion]
        (bool success, const std::string &bytes) {
        FBTQERecordAsync(@"qe_isolated_profile_completion", @{
            @"experiment_profile": @"QE_full_metadata_isolated",
            @"native_transport_success": @(success),
            @"response_bytes": @(bytes.size())
        });
        if (originalCompletion && *originalCompletion)
            (*originalCompletion)(success, bytes);
    };
    original(fetcher, method, purpose, *outgoing, std::move(passthrough), routingHint, target);
}

static BOOL FBTQESafeInstall(NSString **reason) {
    std::lock_guard<std::mutex> guard(sInstallMutex);
    if (sInstalled) {
        if (reason) *reason = @"slot_verified_already_installed";
        return YES;
    }
    // The old fetcher and Tigon probes are mutually exclusive with this
    // experiment, including their installed-but-currently-disarmed wrappers.
    if (FBTMCNativeProbeAnyEnabled() ||
        [FBTMobileConfigFetcherCaptureStatus()[@"native_mc_fetcher_installed"] boolValue] ||
        [FBTMobileConfigTigonCaptureStatus()[@"simple_callback_hooks_installed"] boolValue]) {
        sFailure = @"native_probe_conflict";
        if (reason) *reason = sFailure;
        return NO;
    }
    // Verified against the original Facebook 583.0.0 FBSharedFramework Mach-O:
    // uuid 4c4c44fe-5555-3144-a1c2-6ccae4ed2597; slot 0x8161f88
    // points to target 0xa17f70. The verified rebinder rejects mismatches.
    static const unsigned char uuid[16] = {
        0x4c,0x4c,0x44,0xfe,0x55,0x55,0x31,0x44,
        0xa1,0xc2,0x6c,0xca,0xe4,0xed,0x25,0x97
    };
    NSString *failure = nil;
    sInstalled = FBTRebindVerifiedImageConstSlot("FBSharedFramework",
        0x8161f88ULL, uuid, 0xa17f70ULL, (void *)FBTQEIsolatedFetch,
        (void **)&sOriginal, &failure);
    sFailure = sInstalled ? @"none" : (failure ?: @"slot_validation_failed");
    if (reason) *reason = sInstalled ? @"slot_verified_installed" : sFailure;
    return sInstalled;
}
#endif // FBT_ENABLE_QE_ISOLATED_PROFILE

BOOL FBTMCQEIsolatedProfileAvailable(void) {
#if FBT_ENABLE_QE_ISOLATED_PROFILE
    return !FBTQEInvasiveHooksAllowed();
#else
    return NO;
#endif
}
BOOL FBTMCQEIsolatedProfileInstalled(void) {
#if FBT_ENABLE_QE_ISOLATED_PROFILE
    return sInstalled;
#else
    return NO;
#endif
}
BOOL FBTMCQEIsolatedProfileArm(NSString **reason) {
#if FBT_ENABLE_QE_ISOLATED_PROFILE
    if (FBTQEInvasiveHooksAllowed() ||
        ![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
        if (reason) *reason = @"diagnostics_off_or_invasive_mode_enabled";
        return NO;
    }
    NSString *message = nil;
    if (!FBTQESafeInstall(&message)) {
        if (reason) *reason = message;
        return NO;
    }
    sOneShot.arm(CACurrentMediaTime());
    FBTQERecordAsync(@"qe_isolated_profile_armed", @{
        @"experiment_profile": @"QE_full_metadata_isolated",
        @"experiment_state": @"armed_next_QE_only",
        @"capture_window_seconds": @120,
        @"hook_installed": @YES
    });
    if (reason) *reason = @"armed_one_POST_120s";
    return YES;
#else
    if (reason) *reason = @"requires_explicit_QE_isolated_build";
    return NO;
#endif
}
void FBTMCQEIsolatedProfileCancel(void) {
#if FBT_ENABLE_QE_ISOLATED_PROFILE
    sOneShot.cancel();
#endif
}
NSDictionary *FBTMCQEIsolatedProfileStatus(void) {
#if FBT_ENABLE_QE_ISOLATED_PROFILE
    return @{
        @"compiled": @YES,
        @"installed": @(sInstalled),
        @"armed": @(sOneShot.pending(CACurrentMediaTime())),
        @"last_install_state": sFailure ?: @"not_attempted",
        @"mode": @"isolated_one_slot_only",
        @"global_invasive_hooks": @(FBTQEInvasiveHooksAllowed())
    };
#else
    return @{@"compiled": @NO, @"installed": @NO, @"armed": @NO,
             @"last_install_state": @"not_compiled",
             @"mode": @"release_read_only",
             @"global_invasive_hooks": @(FBTQEInvasiveHooksAllowed())};
#endif
}
