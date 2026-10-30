// Observational diagnostics for Facebook iOS Bloks Lab.
// Deliberately records ONLY Booleans, class/selector names and local timestamps.
// Does not capture tokens, URLs, identities, responses or certificate material.
#import "FBGRBloksTrace.h"
#import "../FBGramPrefix.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <dispatch/dispatch.h>

static NSString *const kTraceEnabled = @"fbgr_bloks_trace_enabled";
static dispatch_queue_t gTraceQueue;
static NSMutableArray<NSString *> *gLines;
static NSString *gTracePath;
static dispatch_once_t gTraceOnce;
static volatile BOOL gTraceEnabled = NO;
static BOOL gReachInstalled = NO;
static BOOL gHelperInstalled = NO;
static NSString *gHelperInfo = @"unavailable";
static NSString *gReachInfo = @"unavailable";
static BOOL gLastVPNValid = NO;
static BOOL gLastVPN = NO;

static void TraceInit(void) {
    dispatch_once(&gTraceOnce, ^{
        gTraceQueue = dispatch_queue_create("com.darthplagueiswise.fbtweaks.blokstrace", DISPATCH_QUEUE_SERIAL);
        gLines = [NSMutableArray arrayWithCapacity:600];
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/FBTweaksDiagnostics"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        gTracePath = [dir stringByAppendingPathComponent:@"BloksLabTrace.jsonl"];
        gTraceEnabled = [FBGRPrefs() boolForKey:kTraceEnabled];
    });
}
static BOOL TraceEnabled(void) {
    return __atomic_load_n(&gTraceEnabled, __ATOMIC_RELAXED);
}
static void TraceEvent(NSString *event, NSDictionary *values) {
    if (!TraceEnabled()) return;
    TraceInit();
    // Generate timestamp / serialize / write on a private queue, never on an app hot path.
    dispatch_async(gTraceQueue, ^{
        NSMutableDictionary *obj = [NSMutableDictionary dictionaryWithDictionary:values ?: @{}];
        obj[@"event"] = event ?: @"unknown";
        obj[@"time_unix_ms"] = @((long long)(NSDate.date.timeIntervalSince1970 * 1000.0));
        NSData *json = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingFragmentsAllowed error:NULL];
        if (!json) return;
        NSString *line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}";
        [gLines addObject:line];
        if (gLines.count > 600) [gLines removeObjectsInRange:NSMakeRange(0, gLines.count-600)];
        if (![[NSFileManager defaultManager] fileExistsAtPath:gTracePath]) {
            [[NSData data] writeToFile:gTracePath atomically:YES];
        }
        // Bounded on-device storage: rotate once at 4 MiB.
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:gTracePath error:NULL];
        if ([attrs fileSize] > (4 * 1024 * 1024)) {
            NSString *prev = [gTracePath stringByAppendingString:@".previous"];
            [[NSFileManager defaultManager] removeItemAtPath:prev error:NULL];
            [[NSFileManager defaultManager] moveItemAtPath:gTracePath toPath:prev error:NULL];
            [[NSData data] writeToFile:gTracePath atomically:YES];
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gTracePath];
        if (!fh) return;
        @try {
            [fh seekToEndOfFile];
            NSMutableData *entry = [NSMutableData dataWithData:json];
            [entry appendBytes:"\n" length:1];
            [fh writeData:entry];
        } @catch (__unused NSException *e) {
            // Disk errors must not crash the host application.
        } @finally { [fh closeFile]; }
    });
}
static BOOL BoolType(const char *s) {
    if (!s) return NO;
    while (*s == 'r' || *s == 'n' || *s == 'N' || *s == 'o' ||
           *s == 'O' || *s == 'R' || *s == 'V') s++;
    return (*s == 'B' || *s == 'c');
}
static BOOL ArgBool(Method m, unsigned int idx) {
    char buf[32] = {0};
    method_getArgumentType(m, idx, buf, sizeof(buf));
    return BoolType(buf);
}
static BOOL ReturnBool(Method m) {
    char buf[32] = {0};
    method_getReturnType(m, buf, sizeof(buf));
    return BoolType(buf);
}
static BOOL ReturnObject(Method m) {
    char buf[32] = {0};
    method_getReturnType(m, buf, sizeof(buf));
    return buf[0] == '@';
}
static BOOL ReturnVoid(Method m) {
    char buf[32] = {0};
    method_getReturnType(m, buf, sizeof(buf));
    return buf[0] == 'v';
}

// VPN getter: observation only; returns the actual original result unchanged.
static BOOL (*gOriginalVPN)(id, SEL) = NULL;
static BOOL TraceVPN(id self, SEL cmd) {
    BOOL result = gOriginalVPN ? gOriginalVPN(self,cmd) : NO;
    if (TraceEnabled() && (!gLastVPNValid || gLastVPN != result)) {
        gLastVPNValid = YES;
        gLastVPN = result;
        TraceEvent(@"native.connectedToVPN", @{@"value":@(result)});
    }
    return result;
}

// Bloks deeplink helper: validated Objective-C signature before installing.
// Arguments 4/5/6 are BOOL per the runtime method encoding (indexes include self/_cmd).
typedef id (*HelperObj)(id,SEL,id,id,BOOL,BOOL,BOOL,id,id);
typedef void (*HelperVoid)(id,SEL,id,id,BOOL,BOOL,BOOL,id,id);
typedef BOOL (*HelperBool)(id,SEL,id,id,BOOL,BOOL,BOOL,id,id);
static IMP gOriginalHelper = NULL;
static void TraceHelperArgs(BOOL pass, BOOL internal, BOOL employee) {
    TraceEvent(@"bloks.deeplink.args",
        @{@"passPrototypeShortcode":@(pass),
          @"useInternalNetworkCheck":@(internal), @"isEmployee":@(employee)});
}
static id HelperObject(id s, SEL cmd, id a, id b, BOOL pass, BOOL internal,
                       BOOL employee, id session, id provider) {
    TraceHelperArgs(pass,internal,employee);
    return ((HelperObj)gOriginalHelper)(s,cmd,a,b,pass,internal,employee,session,provider);
}
static void HelperVoidReturn(id s, SEL cmd, id a, id b, BOOL pass, BOOL internal,
                             BOOL employee, id session, id provider) {
    TraceHelperArgs(pass,internal,employee);
    ((HelperVoid)gOriginalHelper)(s,cmd,a,b,pass,internal,employee,session,provider);
}
static BOOL HelperBoolReturn(id s, SEL cmd, id a, id b, BOOL pass, BOOL internal,
                             BOOL employee, id session, id provider) {
    TraceHelperArgs(pass,internal,employee);
    return ((HelperBool)gOriginalHelper)(s,cmd,a,b,pass,internal,employee,session,provider);
}

// Observe builder BOOL setters if they are actually exported to the ObjC runtime.
// Unknown methods and ABI layouts are NOT hooked.
#define MAX_SETTERS 20
static struct { Class cls; SEL sel; IMP orig; } gSetters[MAX_SETTERS];
static unsigned int gSetterCount = 0;
static IMP OriginalSetter(id self, SEL cmd) {
    Class cls = object_getClass(self);
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        for (unsigned int i=0; i<gSetterCount; i++)
            if (gSetters[i].cls == c && gSetters[i].sel == cmd) return gSetters[i].orig;
    }
    return NULL;
}
static void TraceSetter(id self, SEL cmd, BOOL value) {
    IMP orig = OriginalSetter(self,cmd);
    if (TraceEnabled())
        TraceEvent(@"bloks.builder.bool", @{
            @"selector":NSStringFromSelector(cmd), @"value":@(value),
            @"class":NSStringFromClass(object_getClass(self))
        });
    if (orig) ((void(*)(id,SEL,BOOL))orig)(self,cmd,value);
}
static void InstallSetters(Class cls) {
    if (!cls) return;
    NSArray<NSString *> *candidates = @[
        @"setIsEmployee:", @"setIsOnVPN:", @"setIsOnVpn:",
        @"setHasNetworkConnection:", @"setPassesMinVersion:",
        @"setIsEmployeeValue:", @"setIsOnVpnValue:",
        @"setHasNetworkConnectionValue:", @"setPassesMinVersionValue:"
    ];
    for (NSString *s in candidates) {
        if (gSetterCount >= MAX_SETTERS) return;
        SEL sel = NSSelectorFromString(s);
        Method m = class_getInstanceMethod(cls,sel);
        if (!m || method_getNumberOfArguments(m) != 3 ||
            !ArgBool(m,2) || !ReturnVoid(m)) continue;
        BOOL duplicate=NO;
        for (unsigned int i=0;i<gSetterCount;i++)
            if (gSetters[i].cls==cls && gSetters[i].sel==sel) duplicate=YES;
        if (duplicate) continue;
        IMP orig=NULL;
        MSHookMessageEx(cls, sel, (IMP)TraceSetter, &orig);
        if (!orig) continue;
        gSetters[gSetterCount].cls=cls;
        gSetters[gSetterCount].sel=sel;
        gSetters[gSetterCount].orig=orig;
        gSetterCount++;
    }
}
void FBGRBloksTraceInstall(void) {
    TraceInit();
    static dispatch_once_t lockOnce;
    static dispatch_queue_t installQ;
    dispatch_once(&lockOnce, ^{
        installQ = dispatch_queue_create("com.fbtweaks.blokstrace.install",DISPATCH_QUEUE_SERIAL);
    });
    dispatch_sync(installQ, ^{
        if (!gReachInstalled) {
            Class cls = NSClassFromString(@"FBReachabilityAnnouncer");
            SEL sel = NSSelectorFromString(@"connectedToVPN");
            Method m = cls ? class_getInstanceMethod(cls,sel) : NULL;
            if (m && method_getNumberOfArguments(m)==2 && ReturnBool(m)) {
                IMP orig=NULL;
                MSHookMessageEx(cls,sel,(IMP)TraceVPN,&orig);
                if (orig) { gOriginalVPN=(BOOL(*)(id,SEL))orig; gReachInstalled=YES; }
            }
            gReachInfo = gReachInstalled ? @"hook installed" :
                (cls ? @"selector/ABI unavailable" : @"class not loaded");
        }
        if (!gHelperInstalled) {
            Class cls = NSClassFromString(@"BKBloksLabDeeplinkHelper");
            SEL sel = NSSelectorFromString(@"processDeeplinkWith:foaObjectSet:passPrototypeShortcode:useInternalNetworkCheck:isEmployee:session:containerConfigProvider:");
            Method m = cls ? class_getInstanceMethod(cls,sel) : NULL;
            Class host = cls;
            if (!m && cls) {
                m = class_getClassMethod(cls,sel);
                if (m) host = object_getClass((id)cls);
            }
            if (m && method_getNumberOfArguments(m)==9 &&
                ArgBool(m,4) && ArgBool(m,5) && ArgBool(m,6)) {
                IMP replacement = ReturnVoid(m)?(IMP)HelperVoidReturn:
                    ReturnObject(m)?(IMP)HelperObject:
                    ReturnBool(m)?(IMP)HelperBoolReturn:NULL;
                if (replacement) {
                    IMP orig=NULL;
                    MSHookMessageEx(host,sel,replacement,&orig);
                    if (orig) { gOriginalHelper=orig; gHelperInstalled=YES; }
                }
            }
            gHelperInfo = gHelperInstalled ? @"hook installed" :
                (cls ? @"selector/ABI unavailable" : @"class not loaded");
        }
        for (NSString *cls in @[@"BKBloksLabLandingScreenQueryBuilder",
                                @"BKBloksLabLandingScreenQueryBridgedBuilder"])
            InstallSetters(NSClassFromString(cls));
    });
}
void FBGRBloksTraceSetEnabled(BOOL enabled) {
    TraceInit();
    __atomic_store_n(&gTraceEnabled,enabled,__ATOMIC_RELAXED);
    [FBGRPrefs() setBool:enabled forKey:kTraceEnabled];
    if (enabled) {
        FBGRBloksTraceInstall();
        TraceEvent(@"trace.enabled",@{});
    }
}
BOOL FBGRBloksTraceIsEnabled(void) { TraceInit(); return TraceEnabled(); }
NSString *FBGRBloksTraceSnapshot(void) {
    TraceInit();
    __block NSString *s;
    dispatch_sync(gTraceQueue, ^{ s=[gLines componentsJoinedByString:@"\n"]; });
    return s ?: @"";
}
NSString *FBGRBloksTraceStatus(void) {
    TraceInit();
    return [NSString stringWithFormat:@"VPN: %@ | Deeplink: %@ | BOOL setters: %u\nFile: %@",
            gReachInfo,gHelperInfo,gSetterCount,gTracePath.lastPathComponent];
}
NSURL *FBGRBloksTraceFileURL(void) {
    TraceInit();
    return [NSURL fileURLWithPath:gTracePath];
}
void FBGRBloksTraceClear(void) {
    TraceInit();
    dispatch_async(gTraceQueue, ^{
        [gLines removeAllObjects];
        [[NSFileManager defaultManager] removeItemAtPath:gTracePath error:NULL];
    });
}
void FBGRBloksTraceMark(NSString *label) {
    if (!TraceEnabled()) return;
    // Fixed allowlist: callers cannot inject credentials into logs.
    if ([label isEqualToString:@"user.marker"])
        TraceEvent(@"user.marker", @{});
}
__attribute__((constructor))
static void FBGRBloksTraceConstructor(void) {
    @autoreleasepool {
        TraceInit();
        if (!TraceEnabled()) return;
        // Classes may be registered after tweak initialization.
        dispatch_async(dispatch_get_main_queue(), ^{
            FBGRBloksTraceInstall();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),
                           dispatch_get_main_queue(),^{ FBGRBloksTraceInstall(); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),
                           dispatch_get_main_queue(),^{ FBGRBloksTraceInstall(); });
        });
    }
}
