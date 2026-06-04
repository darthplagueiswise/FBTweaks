// FBGRMCPropsObserver.xm — optional getBool: observer.
// No constructor install. Enable from menu only.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"

typedef struct { uint64_t value; } FBObs_mc_bool_param_t;
typedef BOOL (*ObsIMP)(id, SEL, FBObs_mc_bool_param_t, id);

typedef struct {
    Class cls;
    ObsIMP orig;
} FBGRObsEntry;

#define FBGR_OBS_MAX 32

static FBGRObsEntry gObsEntries[FBGR_OBS_MAX];
static uint32_t gObsEntryCount = 0;
static NSMutableDictionary<NSNumber*,NSNumber*> *gCounts = nil;
static NSMutableDictionary<NSNumber*,NSNumber*> *gResults = nil;
static dispatch_queue_t gQ;
static dispatch_once_t gOnce;
static NSString *gDumpPath;
static BOOL gObserverInstalled = NO;
static volatile BOOL gObserverEnabled = NO;

static void obsInit(void) {
    dispatch_once(&gOnce, ^{
        gCounts  = [NSMutableDictionary dictionaryWithCapacity:512];
        gResults = [NSMutableDictionary dictionaryWithCapacity:512];
        gQ       = dispatch_queue_create("com.fbtweaks.obs", DISPATCH_QUEUE_SERIAL);
        NSString *dir = @"/var/mobile/Library/Application Support/FBTweaks";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
            withIntermediateDirectories:YES attributes:nil error:nil];
        gDumpPath = [dir stringByAppendingPathComponent:@"mc_props_dump.json"];
        gObserverEnabled = FBGRPref(kFBGRMCObserverEnabled);
    });
}

static FBGRObsEntry *obsEntryForClass(Class cls) {
    uint32_t n = gObsEntryCount;
    for (uint32_t i = 0; i < n; i++) {
        if (gObsEntries[i].cls == cls) return &gObsEntries[i];
    }
    return NULL;
}

static FBGRObsEntry *obsEntryEnsure(Class cls) {
    FBGRObsEntry *e = obsEntryForClass(cls);
    if (e) return e;
    if (gObsEntryCount >= FBGR_OBS_MAX) return NULL;
    e = &gObsEntries[gObsEntryCount++];
    e->cls = cls;
    e->orig = NULL;
    return e;
}

static BOOL obsTrampoline(id self, SEL _cmd, FBObs_mc_bool_param_t p, id opts) {
    FBGRObsEntry *e = obsEntryForClass(object_getClass(self));
    ObsIMP orig = e ? e->orig : NULL;
    BOOL r = orig ? orig(self, _cmd, p, opts) : NO;

    if (gObserverEnabled) {
        uint64_t s = p.value;
        dispatch_async(gQ, ^{
            NSNumber *k = @(s);
            gCounts[k]  = @([gCounts[k] unsignedIntegerValue] + 1);
            gResults[k] = @(r);
        });
    }
    return r;
}

static void obsInstall(void) {
    obsInit();
    if (gObserverInstalled) return;

    SEL sel = sel_registerName("getBool:withOptions:");
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
        if (!cls || !class_getInstanceMethod(cls, sel)) continue;
        FBGRObsEntry *e = obsEntryEnsure(cls);
        if (!e || e->orig) continue;
        IMP orig = NULL;
        MSHookMessageEx(cls, sel, (IMP)obsTrampoline, &orig);
        if (orig) e->orig = (ObsIMP)orig;
    }
    gObserverInstalled = YES;
}

static void obsFlush(void) {
    obsInit();
    dispatch_async(gQ, ^{
        if (!gDumpPath) return;
        NSArray *keys = [gCounts.allKeys sortedArrayUsingComparator:
            ^NSComparisonResult(NSNumber *a, NSNumber *b) {
                return [@([gCounts[b] unsignedIntegerValue]) compare:@([gCounts[a] unsignedIntegerValue])];
            }];
        NSMutableArray *arr = [NSMutableArray arrayWithCapacity:keys.count];
        for (NSNumber *k in keys)
            [arr addObject:@{@"slotId":k, @"count":gCounts[k], @"lastResult":gResults[k]?:@NO}];
        NSData *d = [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:nil];
        [d writeToFile:gDumpPath atomically:YES];
    });
}

extern "C" void FBGRMCObserverEnsureInstalled(void) { obsInstall(); }

extern "C" void FBGRMCObserverSetEnabled(BOOL enabled) {
    obsInit();
    gObserverEnabled = enabled;
    [FBGRPrefs() setBool:enabled forKey:kFBGRMCObserverEnabled];
    [FBGRPrefs() synchronize];
    if (enabled) obsInstall();
}

extern "C" void FBGRMCObserverFlush(void) { obsFlush(); }

extern "C" NSUInteger FBGRMCObserverSlotCount(void) {
    obsInit();
    __block NSUInteger n = 0;
    if (gQ) dispatch_sync(gQ, ^{ n = gCounts.count; });
    return n;
}

extern "C" NSString *FBGRMCObserverDump(void) {
    obsInit();
    if (gDumpPath) {
        NSString *s = [NSString stringWithContentsOfFile:gDumpPath encoding:NSUTF8StringEncoding error:nil];
        if (s) return s;
    }
    return [NSString stringWithFormat:@"Observer: %lu slotIds tracked (flush para gravar)",
            (unsigned long)FBGRMCObserverSlotCount()];
}
