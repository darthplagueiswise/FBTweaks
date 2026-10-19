#import "FBTEmployeeDiagnostics.h"
#import "FBTFlagCatalog.h"
#import "FBTMobileConfigValueReader.h"
#import "../FBTDefaults.h"
#include <dlfcn.h>
#include <pthread.h>
#import <objc/runtime.h>

static pthread_mutex_t sIdentityLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary *sIdentityReads;
static unsigned long long sIdentitySequence;
static __thread BOOL sIdentityInspecting;
static NSTimeInterval sTWDeadline;

void FBTEmployeeArmTWProbe(void) {
    pthread_mutex_lock(&sIdentityLock);
    sTWDeadline = [NSProcessInfo processInfo].systemUptime + 120;
    pthread_mutex_unlock(&sIdentityLock);
}
void FBTEmployeeCancelTWProbe(void) {
    pthread_mutex_lock(&sIdentityLock); sTWDeadline = 0; pthread_mutex_unlock(&sIdentityLock);
}
BOOL FBTEmployeeApplyTWProbe(uint64_t key, BOOL value) {
    if (sIdentityInspecting || FBTMobileConfigIsInspectingSystemValue() ||
        ![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return value;
    pthread_mutex_lock(&sIdentityLock);
    BOOL armed = [NSProcessInfo processInfo].systemUptime < sTWDeadline;
    pthread_mutex_unlock(&sIdentityLock);
    if (!armed) return value;
    sIdentityInspecting = YES;
    BOOL matches = NO;
    @try {
        NSDictionary *label = [FBTFlagCatalog bestMatchForMobileConfigKey:key];
        matches = [label[@"c"] isEqual:@"tw_is_employee"] && [label[@"p"] isEqual:@"enabled"];
    } @finally { sIdentityInspecting = NO; }
    return matches ? YES : value;
}

void FBTEmployeeObserveBool(NSString *source, BOOL original, BOOL effective, const void *caller) {
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled] || !source.length) return;
    // Only developer-supplied labels reach this function; no object descriptions.
    Dl_info info = {0};
    NSString *image = @"unresolved", *rva = @"unresolved";
    if (caller && dladdr(caller, &info) && info.dli_fname && info.dli_fbase) {
        image = [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent] ?: @"unresolved";
        rva = [NSString stringWithFormat:@"0x%llx", (unsigned long long)((uintptr_t)caller - (uintptr_t)info.dli_fbase)];
    }
    pthread_mutex_lock(&sIdentityLock);
    if (!sIdentityReads) sIdentityReads = [NSMutableDictionary dictionary];
    NSDictionary *previous = sIdentityReads[source];
    // Fixed cap; retain existing counters instead of silently evicting identity.
    if (previous || sIdentityReads.count < 64) {
        sIdentityReads[source] = @{@"source": source, @"count": @([previous[@"count"] unsignedLongLongValue] + 1),
            @"original_return": @(original), @"effective_return": @(effective),
            @"changed_by_this_tweak": @(original != effective), @"sequence": @(++sIdentitySequence),
            @"time_unix": @([NSDate date].timeIntervalSince1970), @"caller_image": image, @"caller_rva": rva};
    }
    pthread_mutex_unlock(&sIdentityLock);
}

void FBTEmployeeObserveMCBool(uint64_t key, BOOL original, BOOL effective, const void *caller) {
    if (sIdentityInspecting || FBTMobileConfigIsInspectingSystemValue() ||
        ![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;
    sIdentityInspecting = YES;
    @try {
        NSDictionary *label = [FBTFlagCatalog bestMatchForMobileConfigKey:key];
        NSString *config = [label[@"c"] isKindOfClass:NSString.class] ? label[@"c"] : @"";
        NSString *param = [label[@"p"] isKindOfClass:NSString.class] ? label[@"p"] : @"";
        if ([config hasPrefix:@"tw_"]) {
            NSString *source = [NSString stringWithFormat:@"MC.%@.%@.0x%016llx", config, param, (unsigned long long)key];
            FBTEmployeeObserveBool(source, original, effective, caller);
        }
    } @finally { sIdentityInspecting = NO; }
}

NSDictionary *FBTEmployeeDiagnosticsSnapshot(void) {
    pthread_mutex_lock(&sIdentityLock);
    NSArray *values = [sIdentityReads.allValues copy] ?: @[];
    unsigned long long sequence = sIdentitySequence;
    BOOL twArmed = [NSProcessInfo processInfo].systemUptime < sTWDeadline;
    pthread_mutex_unlock(&sIdentityLock);
    values = [values sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"source"] compare:b[@"source"]];
    }];
    Class userClass = NSClassFromString(@"FBUser");
    Method userMethod = userClass ? class_getInstanceMethod(userClass, sel_registerName("isEmployee")) : NULL;
    return @{@"scope": @"process_reads_not_server_identity_or_request_correlation",
        @"state": sequence ? @"observed" : @"not_observed", @"sequence": @(sequence),
        @"reads": values, @"limit": @64, @"tw_probe_armed": @(twArmed),
        @"FBUser_class_loaded": @(userClass != Nil), @"FBUser_isEmployee_selector_found": @(userMethod != NULL),
        @"original_return_meaning": @"Return before this tweak's change; other hooks or native MC overrides may already affect it. This is not a verified SERVER value.",
        @"coverage": @"FBUserPreferences getters/setters and tw_* boolean reads through startup/import hooks; no assertion that all native in-image reads are covered."};
}
void FBTEmployeeDiagnosticsReset(void) {
    pthread_mutex_lock(&sIdentityLock);
    sIdentityReads = [NSMutableDictionary dictionary]; sIdentitySequence = 0; sTWDeadline = 0;
    pthread_mutex_unlock(&sIdentityLock);
}
