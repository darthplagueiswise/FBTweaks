#import "FBTMobileConfigRuntime.h"
#import "FBTFlagCatalog.h"
#import "FBTNativeMobileConfigOverrides.h"
#import "../FBTDefaults.h"
#import "../FBTPrefix.h"
#include "../../modules/fishhook/fishhook.h"
#import <pthread.h>
#import <dlfcn.h>

NSString * const FBTMobileConfigDidUpdateNotification = @"FBTMobileConfigDidUpdateNotification";

// ABI validada para MSGCSessionedMobileConfigGet*:
//   x0 = context/descriptor, x1 = uint64 packed key, x2 = default, x3 = extra.
typedef BOOL     (*FBTMCBoolFn)(void *ctx, uint64_t key, BOOL defaultValue, void *extra);
typedef int64_t  (*FBTMCInt64Fn)(void *ctx, uint64_t key, int64_t defaultValue, void *extra);
typedef double   (*FBTMCDoubleFn)(void *ctx, uint64_t key, double defaultValue, void *extra);
typedef id       (*FBTMCStringFn)(void *ctx, uint64_t key, id defaultValue, void *extra);

static FBTMCBoolFn   orig_MSGCSessionedMobileConfigGetBoolean = NULL;
static FBTMCInt64Fn  orig_MSGCSessionedMobileConfigGetInt64   = NULL;
static FBTMCDoubleFn orig_MSGCSessionedMobileConfigGetDouble  = NULL;
static FBTMCStringFn orig_MSGCSessionedMobileConfigGetString  = NULL;

static BOOL sInstalled = NO;
static BOOL sCaptureEnabled = NO;
static BOOL sOverridesEnabled = NO;
static NSDictionary *sOverrides = nil;       // decimal key -> {t,v}
static NSMutableDictionary *sSeen = nil;     // decimal key -> mutable entry
static pthread_mutex_t sLock = PTHREAD_MUTEX_INITIALIZER;

static NSString *FBTMCKeyString(uint64_t key) {
    return [NSString stringWithFormat:@"%llu", (unsigned long long)key];
}

static NSString *FBTMCHexKey(uint64_t key) {
    return [NSString stringWithFormat:@"0x%016llx", (unsigned long long)key];
}

static NSString *FBTMCObjectDescription(id obj) {
    if (!obj || obj == (id)kCFNull) return @"nil";
    if ([obj isKindOfClass:[NSString class]]) return obj;
    if ([obj isKindOfClass:[NSNumber class]]) return [obj stringValue];
    return [obj description] ?: @"";
}

static void FBTMCPostUpdateThrottled(void) {
    static CFAbsoluteTime last = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - last < 0.25) return;
    last = now;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:FBTMobileConfigDidUpdateNotification object:nil];
    });
}

static void FBTMCRecord(uint64_t key, NSString *type, NSString *defaultDesc, NSString *resultDesc, BOOL overridden) {
    if (!sCaptureEnabled && !overridden) return;
    @autoreleasepool {
        NSString *ks = FBTMCKeyString(key);
        NSDictionary *flag = [FBTFlagCatalog bestMatchForMobileConfigKey:key];

        pthread_mutex_lock(&sLock);
        if (!sSeen) sSeen = [NSMutableDictionary dictionary];
        NSMutableDictionary *entry = sSeen[ks];
        if (!entry) {
            if (sSeen.count > 2500) {
                // Evita crescimento infinito em sessions longas. Remove uma key
                // arbitrária; snapshot continua servindo para os hot params.
                NSString *first = sSeen.allKeys.firstObject;
                if (first) [sSeen removeObjectForKey:first];
            }
            entry = [NSMutableDictionary dictionary];
            entry[@"key"] = ks;
            entry[@"hex"] = FBTMCHexKey(key);
            entry[@"type"] = type ?: @"?";
            entry[@"count"] = @(0);
            if (flag) {
                entry[@"config"] = flag[@"c"] ?: @"";
                entry[@"param"] = flag[@"p"] ?: @"";
                entry[@"staticType"] = flag[@"t"] ?: @"";
                entry[@"slotId"] = flag[@"sid"] ?: @0;
            }
            sSeen[ks] = entry;
        }
        NSUInteger c = [entry[@"count"] unsignedIntegerValue];
        entry[@"count"] = @(c + 1);
        entry[@"type"] = type ?: entry[@"type"] ?: @"?";
        entry[@"default"] = defaultDesc ?: @"";
        entry[@"result"] = resultDesc ?: @"";
        entry[@"overridden"] = @(overridden);
        entry[@"lastSeen"] = @((NSTimeInterval)[NSDate date].timeIntervalSince1970);
        pthread_mutex_unlock(&sLock);
    }
    FBTMCPostUpdateThrottled();
}

void FBTMobileConfigReloadPrefs(void) {
    @autoreleasepool {
        sCaptureEnabled = [FBTDefaults boolForKey:FBTKeyMobileConfigCaptureEnabled];
        sOverridesEnabled = [FBTDefaults boolForKey:FBTKeyMobileConfigOverridesEnabled];
        NSDictionary *raw = [FBTDefaults dictForKey:FBTKeyMobileConfigOverrides];
        sOverrides = [raw copy] ?: @{};
    }
}

static NSDictionary *FBTMCOverride(uint64_t key, NSString *expectedType) {
    if (!sOverridesEnabled) return nil;
    NSDictionary *ov = [sOverrides objectForKey:FBTMCKeyString(key)];
    if (![ov isKindOfClass:[NSDictionary class]]) return nil;
    NSString *t = ov[@"t"];
    if (expectedType && ![t isEqualToString:expectedType]) return nil;
    return ov;
}

NSDictionary *FBTMobileConfigOverrideForKey(uint64_t key) {
    return FBTMCOverride(key, nil);
}

void FBTMobileConfigSetOverride(uint64_t key, NSString *type, id value) {
    if (!type.length || !value) return;
    BOOL nativeApplied = FBTNativeMobileConfigApplyOverride(key, type, value);
    NSMutableDictionary *all = [[FBTDefaults dictForKey:FBTKeyMobileConfigOverrides] mutableCopy] ?: [NSMutableDictionary dictionary];
    all[FBTMCKeyString(key)] = @{ @"t": type, @"v": value, @"native": @(nativeApplied) };
    [FBTDefaults setDict:all forKey:FBTKeyMobileConfigOverrides];
    FBTMobileConfigReloadPrefs();
}

void FBTMobileConfigClearOverride(uint64_t key) {
    FBTNativeMobileConfigRemoveOverride(key);
    NSMutableDictionary *all = [[FBTDefaults dictForKey:FBTKeyMobileConfigOverrides] mutableCopy] ?: [NSMutableDictionary dictionary];
    [all removeObjectForKey:FBTMCKeyString(key)];
    [FBTDefaults setDict:all forKey:FBTKeyMobileConfigOverrides];
    FBTMobileConfigReloadPrefs();
}

void FBTMobileConfigClearAllOverrides(void) {
    NSDictionary *all = [FBTDefaults dictForKey:FBTKeyMobileConfigOverrides];
    for (NSString *ks in all) {
        FBTNativeMobileConfigRemoveOverride((uint64_t)[ks unsignedLongLongValue]);
    }
    [FBTDefaults setDict:@{} forKey:FBTKeyMobileConfigOverrides];
    FBTMobileConfigReloadPrefs();
}

NSArray<NSDictionary *> *FBTMobileConfigSnapshot(void) {
    pthread_mutex_lock(&sLock);
    NSArray *values = [[sSeen allValues] copy] ?: @[];
    pthread_mutex_unlock(&sLock);
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:values.count];
    NSDictionary *overrides = sOverrides ?: @{};
    for (NSDictionary *e in values) {
        NSMutableDictionary *m = [e mutableCopy];
        NSDictionary *ov = overrides[e[@"key"]];
        if ([ov isKindOfClass:[NSDictionary class]]) {
            m[@"forced"] = @YES;
            m[@"forcedType"] = ov[@"t"] ?: @"";
            m[@"forcedValue"] = FBTMCObjectDescription(ov[@"v"]);
        } else {
            m[@"forced"] = @NO;
        }
        m[@"nativeStatus"] = FBTNativeMobileConfigStatus() ?: @"";
        [out addObject:m];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSTimeInterval ta = [a[@"lastSeen"] doubleValue];
        NSTimeInterval tb = [b[@"lastSeen"] doubleValue];
        if (ta > tb) return NSOrderedAscending;
        if (ta < tb) return NSOrderedDescending;
        return [a[@"key"] compare:b[@"key"]];
    }];
    return out;
}

static BOOL fbt_MSGCSessionedMobileConfigGetBoolean(void *ctx, uint64_t key, BOOL defaultValue, void *extra) {
    BOOL original = orig_MSGCSessionedMobileConfigGetBoolean ? orig_MSGCSessionedMobileConfigGetBoolean(ctx, key, defaultValue, extra) : defaultValue;
    NSDictionary *ov = FBTMCOverride(key, @"bool");
    if (ov) {
        BOOL forced = [ov[@"v"] boolValue];
        FBTMCRecord(key, @"bool", defaultValue ? @"true" : @"false", forced ? @"true" : @"false", YES);
        return forced;
    }
    FBTMCRecord(key, @"bool", defaultValue ? @"true" : @"false", original ? @"true" : @"false", NO);
    return original;
}

static int64_t fbt_MSGCSessionedMobileConfigGetInt64(void *ctx, uint64_t key, int64_t defaultValue, void *extra) {
    int64_t original = orig_MSGCSessionedMobileConfigGetInt64 ? orig_MSGCSessionedMobileConfigGetInt64(ctx, key, defaultValue, extra) : defaultValue;
    NSDictionary *ov = FBTMCOverride(key, @"int64");
    if (ov) {
        int64_t forced = [ov[@"v"] longLongValue];
        FBTMCRecord(key, @"int64", [NSString stringWithFormat:@"%lld", (long long)defaultValue], [NSString stringWithFormat:@"%lld", (long long)forced], YES);
        return forced;
    }
    FBTMCRecord(key, @"int64", [NSString stringWithFormat:@"%lld", (long long)defaultValue], [NSString stringWithFormat:@"%lld", (long long)original], NO);
    return original;
}

static double fbt_MSGCSessionedMobileConfigGetDouble(void *ctx, uint64_t key, double defaultValue, void *extra) {
    double original = orig_MSGCSessionedMobileConfigGetDouble ? orig_MSGCSessionedMobileConfigGetDouble(ctx, key, defaultValue, extra) : defaultValue;
    NSDictionary *ov = FBTMCOverride(key, @"double");
    if (ov) {
        double forced = [ov[@"v"] doubleValue];
        FBTMCRecord(key, @"double", [NSString stringWithFormat:@"%g", defaultValue], [NSString stringWithFormat:@"%g", forced], YES);
        return forced;
    }
    FBTMCRecord(key, @"double", [NSString stringWithFormat:@"%g", defaultValue], [NSString stringWithFormat:@"%g", original], NO);
    return original;
}

static id fbt_MSGCSessionedMobileConfigGetString(void *ctx, uint64_t key, id defaultValue, void *extra) {
    id original = orig_MSGCSessionedMobileConfigGetString ? orig_MSGCSessionedMobileConfigGetString(ctx, key, defaultValue, extra) : defaultValue;
    NSDictionary *ov = FBTMCOverride(key, @"string");
    if (ov) {
        NSString *forced = [ov[@"v"] isKindOfClass:[NSString class]] ? ov[@"v"] : [ov[@"v"] description];
        FBTMCRecord(key, @"string", FBTMCObjectDescription(defaultValue), forced ?: @"", YES);
        return forced ?: @"";
    }
    FBTMCRecord(key, @"string", FBTMCObjectDescription(defaultValue), FBTMCObjectDescription(original), NO);
    return original;
}

static BOOL FBTMCHookDirect(const char *name, void *replacement, void **orig) {
    // v3.1: intentionally disabled. The v3 crash log proves that
    // MSHookFunction on FBSharedFramework __TEXT produces CODESIGNING
    // Invalid Page on this sideload/iOS build. Keep the signature for older
    // call sites, but never patch executable pages here. Use fishhook only.
    (void)name; (void)replacement; (void)orig;
    return NO;
}

void FBTInstallMobileConfigRuntime(void) {
    if (sInstalled) return;
    sInstalled = YES;
    FBTMobileConfigReloadPrefs();
    FBTInstallNativeMobileConfigContextCapture();

    // v3.2: fishhook for imports/GOT plus native override table for contexts captured via ObjC dispatch. The v3 crash was CODESIGNING / Invalid Page
    // inside FBSharedFramework at MSGCSessionedMobileConfigGetString+796,
    // caused by direct MSHookFunction on signed __TEXT. fishhook only rewrites
    // import pointers/GOT and does not dirty executable pages. It captures
    // calls that cross image boundaries; internal same-image C calls are not
    // safe to patch in this environment.
    struct rebinding rbs[4] = {
        { "MSGCSessionedMobileConfigGetBoolean", (void *)fbt_MSGCSessionedMobileConfigGetBoolean, (void **)&orig_MSGCSessionedMobileConfigGetBoolean },
        { "MSGCSessionedMobileConfigGetInt64",   (void *)fbt_MSGCSessionedMobileConfigGetInt64,   (void **)&orig_MSGCSessionedMobileConfigGetInt64 },
        { "MSGCSessionedMobileConfigGetDouble",  (void *)fbt_MSGCSessionedMobileConfigGetDouble,  (void **)&orig_MSGCSessionedMobileConfigGetDouble },
        { "MSGCSessionedMobileConfigGetString",  (void *)fbt_MSGCSessionedMobileConfigGetString,  (void **)&orig_MSGCSessionedMobileConfigGetString },
    };
    rebind_symbols(rbs, 4);
    FBTLog(@"MobileConfig runtime instalado: fishhook imports + native override context capture");
}
