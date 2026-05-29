// FBGRMCPropsObserver.xm — logs all getBool: calls → mc_props_dump.json
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRLog.h"

typedef struct { uint64_t value; } FBObs_mc_bool_param_t;
typedef BOOL (*ObsIMP)(id, SEL, FBObs_mc_bool_param_t, id);

// C-level storage — same pattern as FBGRMCGateHooks (no ObjC in hot path)
#define OBS_MAX_CLS 8
static struct { Class cls; IMP orig; } gObsClasses[OBS_MAX_CLS];
static int gObsN = 0;
static IMP FBGROBSGetOrig(Class cls) {
    for (int i = 0; i < gObsN; i++)
        if (gObsClasses[i].cls == cls) return gObsClasses[i].orig;
    return NULL;
}

static NSMutableDictionary<NSNumber*,NSNumber*> *gCounts = nil; // slotId→count
static NSMutableDictionary<NSNumber*,NSNumber*> *gResults = nil;// slotId→lastResult
static NSMutableDictionary<NSString*,NSValue*>  *gOrigs  = nil;
static dispatch_queue_t gQ;
static dispatch_once_t gOnce;
static NSString *gDumpPath;

static void obsInit(void) {
    dispatch_once(&gOnce, ^{
        gCounts  = [NSMutableDictionary dictionaryWithCapacity:512];
        gResults = [NSMutableDictionary dictionaryWithCapacity:512];
        gOrigs   = [NSMutableDictionary dictionaryWithCapacity:8];
        gQ       = dispatch_queue_create("com.fbtweaks.obs", DISPATCH_QUEUE_SERIAL);
        NSString *dir = @"/var/mobile/Library/Application Support/FBTweaks";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
            withIntermediateDirectories:YES attributes:nil error:nil];
        gDumpPath = [dir stringByAppendingPathComponent:@"mc_props_dump.json"];
    });
}

static __thread BOOL gFBGRObsGuard = NO;

static BOOL obsTrample(id self, SEL _cmd, FBObs_mc_bool_param_t p, id opts) {
    // Pure C lookup — no NSStringFromClass, no ObjC before guard check
    ObsIMP orig = (ObsIMP)FBGROBSGetOrig(object_getClass(self));
    if (gFBGRObsGuard) return orig ? orig(self, _cmd, p, opts) : NO;
    gFBGRObsGuard = YES;
    BOOL r = orig ? orig(self, _cmd, p, opts) : NO;
    gFBGRObsGuard = NO;
    if (FBGRPref(kFBGRMCObserverEnabled)) {
        uint64_t s = p.value;
        dispatch_async(gQ, ^{
            NSNumber *k = @(s);
            gCounts[k]  = @([gCounts[k] unsignedIntegerValue] + 1);
            gResults[k] = @(r);
        });
    }
    return r;
}

static void obsFlush(void) {
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

static void obsInstall(void) {
    obsInit();
    SEL sel = sel_registerName("getBool:withOptions:");
    for (NSString *cn in @[
        @"FBMobileConfigContextManager",
        @"FBMobileConfigUserSessionContextManager",
        @"FBMobileConfigSessionlessContextManager",
        @"FBMobileConfigFBTAPI", @"FBMobileConfigFBTContextManager",
        @"FBMobileConfigAPI", @"FBMobileConfigGlobalContext",
    ]) {
        Class cls = NSClassFromString(cn);
        if (!cls || gObsN >= OBS_MAX_CLS) continue;
        if (!class_getInstanceMethod(cls, sel)) continue;
        // Check already hooked
        BOOL already = NO;
        for (int i = 0; i < gObsN; i++) if (gObsClasses[i].cls == cls) { already = YES; break; }
        if (already) continue;
        IMP orig = NULL;
        MSHookMessageEx(cls, sel, (IMP)obsTrample, &orig);
        if (orig) { gObsClasses[gObsN].cls = cls; gObsClasses[gObsN].orig = orig; gObsN++; }
    }
}

extern "C" void FBGRMCObserverEnsureInstalled(void) { obsInstall(); }
extern "C" void    FBGRMCObserverFlush(void)           { obsInit(); obsFlush(); }
extern "C" NSUInteger FBGRMCObserverSlotCount(void) {
    __block NSUInteger n = 0;
    if (gQ) dispatch_sync(gQ, ^{ n = gCounts.count; });
    return n;
}
extern "C" NSString *FBGRMCObserverDump(void) {
    if (gDumpPath) {
        NSString *s = [NSString stringWithContentsOfFile:gDumpPath encoding:NSUTF8StringEncoding error:nil];
        if (s) return s;
    }
    return [NSString stringWithFormat:@"Observer: %lu slotIds tracked (flush para gravar)",
            (unsigned long)FBGRMCObserverSlotCount()];
}

// No constructor: observer hooks install only when the MC Observer toggle is enabled.
