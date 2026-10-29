#import "FBTEmployeeDiagnostics.h"
#import "FBTMCNativeSessionProbes.h"
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

BOOL FBTEmployeeDiagnosticsShouldObserve(void) {
    return [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled] ||
        FBTMCNativeProbeAnyEnabled();
}


static NSArray<NSDictionary *> *FBTEmployeeGetterAvailability(void) {
    // Non-invasive inventory. Do not send messages or infer account status.
    static const char *classes[] = {
        "FBUser", "FBUserPreferences", "FBBugReportConfiguration",
        "FBProductTagCreationLogger", "FBSnacksThreadOwnerMessengerContact",
        "FBLoggedOutImageNetworkerConfiguration", "FBSessionImageNetworkerConfiguration",
        "RCDMobileConfigParams", "MBUISimpleParticipantModel",
        "RCTCurrentViewer", "FFDBInternalSettingsWebViewController"
    };
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < sizeof(classes) / sizeof(classes[0]); ++i) {
        const char *selector = (strcmp(classes[i], "FBLoggedOutImageNetworkerConfiguration") == 0 ||
                                strcmp(classes[i], "FBSessionImageNetworkerConfiguration") == 0) ?
                                "isViewerEmployee" :
                               (strcmp(classes[i], "FFDBInternalSettingsWebViewController") == 0) ?
                                "isInternLoggedIn" : "isEmployee";
        Class cls = objc_getClass(classes[i]);
        Method method = cls ? class_getInstanceMethod(cls, sel_registerName(selector)) : NULL;
        const char *encoding = method ? method_getTypeEncoding(method) : NULL;
        Dl_info origin = {};
        BOOL located = method && dladdr((const void *)method_getImplementation(method), &origin);
        NSString *name = [NSString stringWithUTF8String:classes[i]] ?: @"";
        NSString *signature = encoding ? [NSString stringWithUTF8String:encoding] : @"unavailable";
        [items addObject:@{@"class": name,
            @"selector": [NSString stringWithUTF8String:selector] ?: @"",
            @"class_loaded": @(cls != Nil), @"selector_found": @(method != NULL),
            @"type_encoding": signature ?: @"unavailable",
            @"implementation_image": located && origin.dli_fname ?
                [[NSString stringWithUTF8String:origin.dli_fname] lastPathComponent] : @"unresolved"}];
    }
    return items;
}

void FBTEmployeeArmTWProbe(void) {
    pthread_mutex_lock(&sIdentityLock);
    sTWDeadline = [NSProcessInfo processInfo].systemUptime + 120;
    pthread_mutex_unlock(&sIdentityLock);
}
void FBTEmployeeCancelTWProbe(void) {
    pthread_mutex_lock(&sIdentityLock); sTWDeadline = 0; pthread_mutex_unlock(&sIdentityLock);
}
BOOL FBTEmployeeApplyTWProbe(uint64_t key, BOOL value) {
    if (sIdentityInspecting || FBTMobileConfigShouldBypassTweakOverrides() ||
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
    if (!FBTEmployeeDiagnosticsShouldObserve() || !source.length) return;
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
    if (sIdentityInspecting || FBTMobileConfigShouldBypassTweakOverrides() ||
        !FBTEmployeeDiagnosticsShouldObserve()) return;
    sIdentityInspecting = YES;
    @try {
        NSDictionary *label = [FBTFlagCatalog bestMatchForMobileConfigKey:key];
        NSString *config = [label[@"c"] isKindOfClass:NSString.class] ? label[@"c"] : @"";
        NSString *param = [label[@"p"] isKindOfClass:NSString.class] ? label[@"p"] : @"";
        if ([config hasPrefix:@"tw_"] || [config isEqualToString:@"fb_ford"] ||
            [param rangeOfString:@"employee" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [param rangeOfString:@"test_user" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [param rangeOfString:@"test_account" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [param rangeOfString:@"dogfood" options:NSCaseInsensitiveSearch].location != NSNotFound) {
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
        @"observation_enabled": @(FBTEmployeeDiagnosticsShouldObserve()),
        @"native_session_probe_enabled": @(FBTMCNativeProbeAnyEnabled()),
        @"FBUser_class_loaded": @(userClass != Nil), @"FBUser_isEmployee_selector_found": @(userMethod != NULL),
        @"known_getter_availability": FBTEmployeeGetterAvailability(),
        @"original_return_meaning": @"Return before this tweak's change; other hooks or native MC overrides may already affect it. This is not a verified SERVER value.",
        @"coverage": @"FBUserPreferences getters/setters and tw_* boolean reads through startup/import hooks; no assertion that all native in-image reads are covered."};
}
void FBTEmployeeDiagnosticsReset(void) {
    pthread_mutex_lock(&sIdentityLock);
    sIdentityReads = [NSMutableDictionary dictionary]; sIdentitySequence = 0; sTWDeadline = 0;
    pthread_mutex_unlock(&sIdentityLock);
}
