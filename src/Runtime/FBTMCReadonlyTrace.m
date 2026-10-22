#import "FBTMCReadonlyTrace.h"
#import "FBTMobileConfigFetchDiagnostics.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <QuartzCore/QuartzCore.h>
#include <string.h>

static const uint8_t kMainUUID[16] = {0x4c,0x4c,0x44,0xaa,0x55,0x55,0x31,0x44,0xa1,0x8e,0x01,0x47,0x41,0xed,0x19,0x0b};
static const uint8_t kSharedUUID[16] = {0x4c,0x4c,0x44,0xfe,0x55,0x55,0x31,0x44,0xa1,0xc2,0x6c,0xca,0xe4,0xed,0x25,0x97};

static BOOL FBTMCReadOnlyImageUUIDMatches(const char *leaf, const uint8_t expected[16]) {
    for (uint32_t i=0, count=_dyld_image_count(); i<count; ++i) {
        const char *name=_dyld_get_image_name(i);
        if (!name) continue;
        const char *actual=strrchr(name, '/');
        if (strcmp(actual ? actual+1 : name, leaf) != 0) continue;
        const struct mach_header *h=_dyld_get_image_header(i);
        if (!h || h->magic != MH_MAGIC_64 || h->cputype != CPU_TYPE_ARM64) return NO;
        const struct mach_header_64 *mh=(const struct mach_header_64 *)h;
        if (mh->ncmds > 1024 || mh->sizeofcmds > 1024*1024) return NO;
        const uint8_t *p=(const uint8_t *)(mh+1);
        size_t remaining=mh->sizeofcmds;
        for (uint32_t j=0; j<mh->ncmds; ++j) {
            if (remaining < sizeof(struct load_command)) return NO;
            const struct load_command *lc=(const struct load_command *)p;
            if (lc->cmdsize < sizeof(*lc) || lc->cmdsize > remaining) return NO;
            if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command))
                return memcmp(((const struct uuid_command *)lc)->uuid,expected,16) == 0;
            remaining-=lc->cmdsize;
            p+=lc->cmdsize;
        }
        return NO;
    }
    return NO;
}

static NSLock *sLock;
static BOOL sUUIDMatch;
static NSString *sCurrentAttempt;
static CFTimeInterval sStarted;
static NSMutableDictionary<NSString *, NSString *> *sExplicitRequests;
static NSMutableArray<NSString *> *sRequestOrder;
static NSUInteger sSequence, sValueReads;

static void FBTMCReadOnlyInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sLock=[NSLock new];
        sExplicitRequests=[NSMutableDictionary dictionary];
        sRequestOrder=[NSMutableArray array];
        sUUIDMatch=FBTMCReadOnlyImageUUIDMatches("Facebook",kMainUUID) &&
            FBTMCReadOnlyImageUUIDMatches("FBSharedFramework",kSharedUUID);
        // The native reader depends only on Foundation and stays independently
        // linkable. This listener is installed with the diagnostics module.
        [[NSNotificationCenter defaultCenter] addObserverForName:@"FBTMCNativeValueSourceObserved"
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                if (!FBTMCReadonlyTracePermitSourceRead()) return;
                FBTMobileConfigFetchDiagnosticsRecord(@"mc_native_value_source_observed",
                    note.userInfo ?: @{});
            }];
    });
}

NSDictionary *FBTMCReadonlyTraceEnrich(NSString *event, NSDictionary *details) {
    FBTMCReadOnlyInit();
    NSMutableDictionary *out=[(details ?: @{}) mutableCopy];
    CFTimeInterval now=CACurrentMediaTime();
    [sLock lock];
    out[@"mc_trace_sequence"]=@(++sSequence);
    out[@"mc_trace_uuid_match"]=@(sUUIDMatch);
    NSString *confidence=@"unlinked";
    NSString *requestId=[details[@"request_id"] isKindOfClass:NSString.class] ? details[@"request_id"] : nil;
    if ([event isEqualToString:@"selection_started"] ||
        [event isEqualToString:@"item_selection_started"] ||
        [event isEqualToString:@"mc_source_inspection_started"]) {
        sCurrentAttempt=NSUUID.UUID.UUIDString;
        sStarted=now;
        sValueReads=0;
        confidence=@"exact_ui_event";
        out[@"mc_trace_attempt"]=sCurrentAttempt;
    } else if (requestId.length && sExplicitRequests[requestId]) {
        out[@"mc_trace_attempt"]=sExplicitRequests[requestId];
        confidence=@"exact_request_id";
    } else if (sCurrentAttempt && now >= sStarted && now-sStarted <= 30.0) {
        // Time proximity is NOT a demonstrated causal link to the selected UI action.
        confidence=@"temporal_candidate_only";
        out[@"mc_trace_attempt"]=sCurrentAttempt;
    }
    if ([event isEqualToString:@"native_mc_fetch_started"] && requestId.length &&
        [confidence isEqualToString:@"temporal_candidate_only"]) {
        sExplicitRequests[requestId]=sCurrentAttempt;
        [sRequestOrder addObject:requestId];
        while (sRequestOrder.count > 64) {
            NSString *old=sRequestOrder.firstObject;
            [sRequestOrder removeObjectAtIndex:0];
            [sExplicitRequests removeObjectForKey:old];
        }
    }
    out[@"mc_trace_link"]=confidence;
    [sLock unlock];
    return out;
}

BOOL FBTMCReadonlyTracePermitSourceRead(void) {
    FBTMCReadOnlyInit();
    [sLock lock];
    BOOL allowed=(sCurrentAttempt != nil && CACurrentMediaTime()-sStarted <= 30.0 &&
                  sValueReads < 48);
    if (allowed) ++sValueReads;
    [sLock unlock];
    return allowed;
}
