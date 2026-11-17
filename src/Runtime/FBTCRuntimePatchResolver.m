// FBTCRuntimePatchResolver.m
#import "FBTCRuntimePatchResolver.h"
#import "FBTCSymbolStub.h"
#import "FBTSymbolBrowserEngine.h"
#import "../FBTUtils.h"
#import "../../modules/fishhook/fishhook.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <os/log.h>
#import <unistd.h>
#import <stdatomic.h>
#import <string.h>

#define RLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[FBTGate] PatchResolver " fmt, ##__VA_ARGS__)

static NSString *const kFBTCRuntimePatchPlansKey = @"fbt_runtime_patch_plans";
static NSString *const kFBTCRuntimeDataPatchSnapshotsKey = @"fbt_runtime_data_patch_snapshots";

static NSString *FBTCStrategyString(FBTCRuntimePatchStrategy s) {
    switch (s) {
        case FBTCRuntimePatchStrategyObjCBool: return @"objc.bool";
        case FBTCRuntimePatchStrategyFunctionBool: return @"function.bool";
        case FBTCRuntimePatchStrategyFunctionTyped: return @"function.typed";
        case FBTCRuntimePatchStrategyFunctionObserve: return @"function.observe";
        case FBTCRuntimePatchStrategyDataReaderBool: return @"data.reader.bool";
        case FBTCRuntimePatchStrategyDataRebindString: return @"data.rebind.string";
        case FBTCRuntimePatchStrategyDataPatchBytes: return @"data.patch.bytes";
        default: return @"none";
    }
}

static FBTCRuntimePatchStrategy FBTCStrategyFromString(NSString *s) {
    if ([s isEqualToString:@"objc.bool"]) return FBTCRuntimePatchStrategyObjCBool;
    if ([s isEqualToString:@"function.bool"]) return FBTCRuntimePatchStrategyFunctionBool;
    if ([s isEqualToString:@"function.typed"]) return FBTCRuntimePatchStrategyFunctionTyped;
    if ([s isEqualToString:@"function.observe"]) return FBTCRuntimePatchStrategyFunctionObserve;
    if ([s isEqualToString:@"data.reader.bool"]) return FBTCRuntimePatchStrategyDataReaderBool;
    if ([s isEqualToString:@"data.rebind.string"]) return FBTCRuntimePatchStrategyDataRebindString;
    if ([s isEqualToString:@"data.patch.bytes"]) return FBTCRuntimePatchStrategyDataPatchBytes;
    return FBTCRuntimePatchStrategyNone;
}

static NSString *FBTCObjCKey(NSString *className, NSString *selectorName, BOOL classMethod) {
    return [NSString stringWithFormat:@"%@%@#%@", classMethod ? @"+" : @"", className ?: @"", selectorName ?: @""];
}

static NSDictionary *FBTCDictPref(NSString *key) {
    NSDictionary *d = [FBTUtils getDictPref:key];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

static void *FBTCResolveSymbolAddress(NSString *symbol) {
    if (![symbol isKindOfClass:NSString.class] || !symbol.length) return NULL;
    void *p = dlsym(RTLD_DEFAULT, symbol.UTF8String);
    if (!p) {
        NSString *under = [@"_" stringByAppendingString:symbol];
        p = dlsym(RTLD_DEFAULT, under.UTF8String);
    }
    return p;
}

static BOOL FBTCSectionIsExecutable(NSString *section) {
    NSString *s = section ?: @"";
    return [s containsString:@"__TEXT,__text"] || [s hasSuffix:@",__text"];
}

static BOOL FBTCSectionIsPatchableData(NSString *section) {
    if (FBTCSectionIsExecutable(section)) return NO;
    NSString *s = section ?: @"";
    return [s containsString:@"__DATA"] || [s containsString:@"__DATA_CONST"] || [s containsString:@"__TEXT,__const"] || [s containsString:@"__TEXT,__cstring"] || [s containsString:@"__TEXT,__objc_methname"];
}

static BOOL FBTCLooksStringDataSymbol(NSString *name, NSString *section) {
    NSString *n = name ?: @"";
    NSString *s = section ?: @"";
    if ([s containsString:@"__cstring"] || [s containsString:@"__objc_methname"] || [s containsString:@"__cfstring"]) return YES;
    return [n containsString:@"String"] || [n containsString:@"Name"] || [n containsString:@"Key"] || [n hasPrefix:@"k"] || [n hasSuffix:@"Key"];
}

static BOOL FBTCConsumerIsBoolReader(NSArray<FBTXrefHit *> *hits, NSString **consumerOut, NSString **callerOut) {
    for (FBTXrefHit *h in hits ?: @[]) {
        NSString *c = h.calleeSymbol ?: @"";
        if ([c isEqualToString:@"IGMobileConfigBooleanValueForInternalUse"] || [c containsString:@"MobileConfigBoolean"] || [c containsString:@"EasyGatingGetBoolean"]) {
            if (consumerOut) *consumerOut = c;
            if (callerOut) *callerOut = h.callerSymbol;
            return YES;
        }
    }
    return NO;
}

@implementation FBTCRuntimePatchPlan

- (id)copyWithZone:(NSZone *)zone {
    FBTCRuntimePatchPlan *p = [[[self class] allocWithZone:zone] init];
    p.symbol = self.symbol; p.image = self.image; p.section = self.section; p.kind = self.kind; p.abi = self.abi;
    p.runtimeAddress = self.runtimeAddress; p.symtabAddress = self.symtabAddress; p.dataSize = self.dataSize;
    p.function = self.function; p.data = self.data; p.swiftLike = self.swiftLike; p.hasBindPointer = self.hasBindPointer;
    p.objcClassName = self.objcClassName; p.objcSelectorName = self.objcSelectorName; p.objcClassMethod = self.objcClassMethod;
    p.consumerSymbol = self.consumerSymbol; p.callerSymbol = self.callerSymbol; p.strategy = self.strategy;
    p.strategyName = self.strategyName; p.shortStrategyName = self.shortStrategyName; p.reason = self.reason; p.returnKind = self.returnKind;
    p.inlineToggleSafe = self.inlineToggleSafe; p.safeAtLaunch = self.safeAtLaunch; p.requiresPromptValue = self.requiresPromptValue; p.requiresConfirmedConsumer = self.requiresConfirmedConsumer;
    return p;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.symbol) d[@"symbol"] = self.symbol;
    if (self.image) d[@"image"] = self.image;
    if (self.section) d[@"section"] = self.section;
    if (self.kind) d[@"kind"] = self.kind;
    if (self.abi) d[@"abi"] = self.abi;
    if (self.objcClassName) d[@"objcClassName"] = self.objcClassName;
    if (self.objcSelectorName) d[@"objcSelectorName"] = self.objcSelectorName;
    if (self.consumerSymbol) d[@"consumerSymbol"] = self.consumerSymbol;
    if (self.callerSymbol) d[@"callerSymbol"] = self.callerSymbol;
    if (self.returnKind) d[@"returnKind"] = self.returnKind;
    d[@"strategy"] = FBTCStrategyString(self.strategy);
    d[@"runtimeAddress"] = @(self.runtimeAddress);
    d[@"symtabAddress"] = @(self.symtabAddress);
    d[@"dataSize"] = @(self.dataSize);
    d[@"function"] = @(self.function);
    d[@"data"] = @(self.data);
    d[@"swiftLike"] = @(self.swiftLike);
    d[@"hasBindPointer"] = @(self.hasBindPointer);
    d[@"objcClassMethod"] = @(self.objcClassMethod);
    d[@"inlineToggleSafe"] = @(self.inlineToggleSafe);
    d[@"safeAtLaunch"] = @(self.safeAtLaunch);
    d[@"requiresPromptValue"] = @(self.requiresPromptValue);
    d[@"requiresConfirmedConsumer"] = @(self.requiresConfirmedConsumer);
    return d.copy;
}

+ (instancetype)planWithDictionary:(NSDictionary<NSString *, id> *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    NSString *symbol = [dict[@"symbol"] isKindOfClass:NSString.class] ? dict[@"symbol"] : nil;
    if (!symbol.length) return nil;
    FBTCRuntimePatchPlan *p = [FBTCRuntimePatchPlan new];
    p.symbol = symbol;
    p.image = [dict[@"image"] isKindOfClass:NSString.class] ? dict[@"image"] : nil;
    p.section = [dict[@"section"] isKindOfClass:NSString.class] ? dict[@"section"] : nil;
    p.kind = [dict[@"kind"] isKindOfClass:NSString.class] ? dict[@"kind"] : nil;
    p.abi = [dict[@"abi"] isKindOfClass:NSString.class] ? dict[@"abi"] : nil;
    p.objcClassName = [dict[@"objcClassName"] isKindOfClass:NSString.class] ? dict[@"objcClassName"] : nil;
    p.objcSelectorName = [dict[@"objcSelectorName"] isKindOfClass:NSString.class] ? dict[@"objcSelectorName"] : nil;
    p.consumerSymbol = [dict[@"consumerSymbol"] isKindOfClass:NSString.class] ? dict[@"consumerSymbol"] : nil;
    p.callerSymbol = [dict[@"callerSymbol"] isKindOfClass:NSString.class] ? dict[@"callerSymbol"] : nil;
    p.returnKind = [dict[@"returnKind"] isKindOfClass:NSString.class] ? dict[@"returnKind"] : nil;
    p.strategy = FBTCStrategyFromString([dict[@"strategy"] isKindOfClass:NSString.class] ? dict[@"strategy"] : nil);
    p.runtimeAddress = [dict[@"runtimeAddress"] respondsToSelector:@selector(longLongValue)] ? (uintptr_t)[dict[@"runtimeAddress"] longLongValue] : 0;
    p.symtabAddress = [dict[@"symtabAddress"] respondsToSelector:@selector(longLongValue)] ? (uintptr_t)[dict[@"symtabAddress"] longLongValue] : 0;
    p.dataSize = [dict[@"dataSize"] respondsToSelector:@selector(longLongValue)] ? (NSUInteger)[dict[@"dataSize"] longLongValue] : 0;
    p.function = [dict[@"function"] boolValue]; p.data = [dict[@"data"] boolValue]; p.swiftLike = [dict[@"swiftLike"] boolValue];
    p.hasBindPointer = [dict[@"hasBindPointer"] boolValue]; p.objcClassMethod = [dict[@"objcClassMethod"] boolValue];
    p.inlineToggleSafe = [dict[@"inlineToggleSafe"] boolValue]; p.safeAtLaunch = [dict[@"safeAtLaunch"] boolValue];
    p.requiresPromptValue = [dict[@"requiresPromptValue"] boolValue]; p.requiresConfirmedConsumer = [dict[@"requiresConfirmedConsumer"] boolValue];
    p.strategyName = [self displayNameForStrategy:p.strategy returnKind:p.returnKind];
    p.shortStrategyName = [self shortNameForStrategy:p.strategy returnKind:p.returnKind];
    p.reason = [dict[@"reason"] isKindOfClass:NSString.class] ? dict[@"reason"] : @"persisted plan";
    return p;
}

+ (NSString *)displayNameForStrategy:(FBTCRuntimePatchStrategy)s returnKind:(NSString *)kind {
    switch (s) {
        case FBTCRuntimePatchStrategyObjCBool: return @"ObjC IMP swizzle (MSHookMessageEx)";
        case FBTCRuntimePatchStrategyFunctionBool: return @"fishhook BOOL hardstub";
        case FBTCRuntimePatchStrategyFunctionTyped: return [NSString stringWithFormat:@"fishhook typed force (%@)", kind.length ? kind : @"typed"];
        case FBTCRuntimePatchStrategyFunctionObserve: return @"validated observe hook";
        case FBTCRuntimePatchStrategyDataReaderBool: return @"MobileConfig descriptor reader-filter";
        case FBTCRuntimePatchStrategyDataRebindString: return @"DATA imported pointer rebind (NSString compatible)";
        case FBTCRuntimePatchStrategyDataPatchBytes: return @"DATA memory patch (vm_protect snapshot/revert)";
        default: return @"none (sideload-safe patch unavailable)";
    }
}

+ (NSString *)shortNameForStrategy:(FBTCRuntimePatchStrategy)s returnKind:(NSString *)kind {
    switch (s) {
        case FBTCRuntimePatchStrategyObjCBool: return @"ObjC live swizzle";
        case FBTCRuntimePatchStrategyFunctionBool: return @"BOOL fishhook";
        case FBTCRuntimePatchStrategyFunctionTyped: return [NSString stringWithFormat:@"%@ fishhook", kind.length ? kind : @"typed"];
        case FBTCRuntimePatchStrategyFunctionObserve: return @"observe hook";
        case FBTCRuntimePatchStrategyDataReaderBool: return @"DATA → MC reader";
        case FBTCRuntimePatchStrategyDataRebindString: return @"DATA pointer rebind";
        case FBTCRuntimePatchStrategyDataPatchBytes: return @"DATA bytes patch";
        default: return @"resolve only";
    }
}

@end

#pragma mark - DATA pointer rebind

typedef struct {
    char symbol[192];
    void *original;
    void *replacement;
    CFTypeRef retainedObject;
    atomic_int installed;
} FBTCDataRebindSlot;

#define MAX_DATA_REBINDS 32
static FBTCDataRebindSlot g_dataRebinds[MAX_DATA_REBINDS];
static int g_dataRebindCount = 0;

static FBTCDataRebindSlot *FBTCDataRebindSlotFor(NSString *symbol, BOOL create) {
    if (!symbol.length) return NULL;
    const char *name = symbol.UTF8String;
    for (int i = 0; i < g_dataRebindCount; i++) if (strcmp(g_dataRebinds[i].symbol, name) == 0) return &g_dataRebinds[i];
    if (!create || g_dataRebindCount >= MAX_DATA_REBINDS) return NULL;
    FBTCDataRebindSlot *slot = &g_dataRebinds[g_dataRebindCount++];
    memset(slot, 0, sizeof(*slot));
    strncpy(slot->symbol, name, sizeof(slot->symbol) - 1);
    return slot;
}

static BOOL FBTCInstallDataRebind(NSString *symbol, id replacementObject) {
    if (!symbol.length || !replacementObject) return NO;
    FBTCDataRebindSlot *slot = FBTCDataRebindSlotFor(symbol, YES);
    if (!slot) return NO;
    if (slot->retainedObject) { CFRelease(slot->retainedObject); slot->retainedObject = NULL; }
    slot->retainedObject = CFBridgingRetain(replacementObject);
    slot->replacement = (void *)slot->retainedObject;
    struct rebinding rb;
    memset(&rb, 0, sizeof(rb));
    rb.name = slot->symbol;
    rb.replacement = slot->replacement;
    rb.replaced = &slot->original;
    int rc = rebind_symbols(&rb, 1);
    atomic_store(&slot->installed, rc == 0 ? 1 : 0);
    RLOG("DATA rebind %{public}s rc=%d original=%p replacement=%p", slot->symbol, rc, slot->original, slot->replacement);
    return rc == 0;
}

static BOOL FBTCRevertDataRebind(NSString *symbol) {
    FBTCDataRebindSlot *slot = FBTCDataRebindSlotFor(symbol, NO);
    if (!slot || !slot->original) return NO;
    struct rebinding rb;
    memset(&rb, 0, sizeof(rb));
    rb.name = slot->symbol;
    rb.replacement = slot->original;
    rb.replaced = NULL;
    int rc = rebind_symbols(&rb, 1);
    if (slot->retainedObject) { CFRelease(slot->retainedObject); slot->retainedObject = NULL; }
    slot->replacement = NULL;
    atomic_store(&slot->installed, 0);
    RLOG("DATA rebind revert %{public}s rc=%d", slot->symbol, rc);
    return rc == 0;
}

#pragma mark - DATA byte patch

static BOOL FBTCPatchMemory(uintptr_t address, NSData *bytes, NSData **snapshotOut, NSError **error) {
    if (!address || !bytes.length || bytes.length > 64) {
        if (error) *error = [NSError errorWithDomain:@"FBTCRuntimePatchResolver" code:10 userInfo:@{NSLocalizedDescriptionKey: @"invalid DATA patch address/size"}];
        return NO;
    }
    if (snapshotOut) *snapshotOut = [NSData dataWithBytes:(const void *)address length:bytes.length];
    vm_size_t pageSize = (vm_size_t)getpagesize();
    vm_address_t pageStart = (vm_address_t)(address & ~((uintptr_t)pageSize - 1));
    vm_address_t pageEnd = (vm_address_t)((address + bytes.length + pageSize - 1) & ~((uintptr_t)pageSize - 1));
    vm_size_t span = (vm_size_t)(pageEnd - pageStart);
    kern_return_t kr = vm_protect(mach_task_self(), pageStart, span, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) kr = vm_protect(mach_task_self(), pageStart, span, false, VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        if (error) *error = [NSError errorWithDomain:@"FBTCRuntimePatchResolver" code:11 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"vm_protect failed: %d", kr]}];
        return NO;
    }
    memcpy((void *)address, bytes.bytes, bytes.length);
    // DATA patch only: no instruction-cache flush here. Some Theos/iOS SDK
    // toolchains lower that builtin to an unresolved arm64 runtime symbol, and
    // cache invalidation is only required for executable-code patching, which this
    // resolver intentionally does not perform.
    vm_protect(mach_task_self(), pageStart, span, false, VM_PROT_READ);
    return YES;
}

@implementation FBTCRuntimePatchResolver

+ (NSString *)persistedPlansKey { return kFBTCRuntimePatchPlansKey; }
+ (NSDictionary<NSString *, NSDictionary<NSString *, id> *> *)persistedPatchPlans { return (NSDictionary *)FBTCDictPref(kFBTCRuntimePatchPlansKey); }
+ (NSDictionary<NSString *, id> *)persistedPatchForSymbol:(NSString *)symbol { id v = [self persistedPatchPlans][symbol ?: @""]; return [v isKindOfClass:NSDictionary.class] ? v : nil; }

+ (void)savePatchPlan:(FBTCRuntimePatchPlan *)plan extra:(NSDictionary<NSString *, id> *)extra {
    if (!plan.symbol.length || plan.strategy == FBTCRuntimePatchStrategyNone) return;
    NSMutableDictionary *all = [[self persistedPatchPlans] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *d = [[plan dictionaryRepresentation] mutableCopy];
    if (plan.reason) d[@"reason"] = plan.reason;
    if (extra) [d addEntriesFromDictionary:extra];
    all[plan.symbol] = d.copy;
    [FBTUtils setPref:all.copy forKey:kFBTCRuntimePatchPlansKey];
}

+ (void)forgetPatchPlanForSymbol:(NSString *)symbol {
    if (!symbol.length) return;
    NSMutableDictionary *all = [[self persistedPatchPlans] mutableCopy] ?: [NSMutableDictionary dictionary];
    [all removeObjectForKey:symbol];
    [FBTUtils setPref:all.copy forKey:kFBTCRuntimePatchPlansKey];
    NSMutableDictionary *snaps = [FBTCDictPref(kFBTCRuntimeDataPatchSnapshotsKey) mutableCopy] ?: [NSMutableDictionary dictionary];
    [snaps removeObjectForKey:symbol];
    [FBTUtils setPref:snaps.copy forKey:kFBTCRuntimeDataPatchSnapshotsKey];
}

+ (FBTCRuntimePatchPlan *)resolvePlanForEntryInfo:(NSDictionary<NSString *, id> *)entryInfo xrefHits:(NSArray<FBTXrefHit *> *)xrefHits {
    FBTCRuntimePatchPlan *p = [FBTCRuntimePatchPlan new];
    p.symbol = [entryInfo[@"symbol"] isKindOfClass:NSString.class] ? entryInfo[@"symbol"] : @"";
    p.image = [entryInfo[@"image"] isKindOfClass:NSString.class] ? entryInfo[@"image"] : nil;
    p.section = [entryInfo[@"section"] isKindOfClass:NSString.class] ? entryInfo[@"section"] : nil;
    p.kind = [entryInfo[@"kind"] isKindOfClass:NSString.class] ? entryInfo[@"kind"] : nil;
    p.abi = [entryInfo[@"abi"] isKindOfClass:NSString.class] ? entryInfo[@"abi"] : nil;
    p.function = [entryInfo[@"function"] boolValue];
    p.data = [entryInfo[@"data"] boolValue];
    p.swiftLike = [entryInfo[@"swiftLike"] boolValue];
    p.hasBindPointer = [entryInfo[@"hasBindPointer"] boolValue];
    p.runtimeAddress = [entryInfo[@"runtimeAddress"] respondsToSelector:@selector(longLongValue)] ? (uintptr_t)[entryInfo[@"runtimeAddress"] longLongValue] : 0;
    p.symtabAddress = [entryInfo[@"symtabAddress"] respondsToSelector:@selector(longLongValue)] ? (uintptr_t)[entryInfo[@"symtabAddress"] longLongValue] : 0;
    p.dataSize = [entryInfo[@"dataSize"] respondsToSelector:@selector(longLongValue)] ? (NSUInteger)[entryInfo[@"dataSize"] longLongValue] : 0;
    p.objcClassName = [entryInfo[@"objcClassName"] isKindOfClass:NSString.class] ? entryInfo[@"objcClassName"] : nil;
    p.objcSelectorName = [entryInfo[@"objcSelectorName"] isKindOfClass:NSString.class] ? entryInfo[@"objcSelectorName"] : nil;
    p.objcClassMethod = [entryInfo[@"objcClassMethod"] boolValue];
    NSString *consumer = nil, *caller = nil;
    BOOL boolReader = FBTCConsumerIsBoolReader(xrefHits, &consumer, &caller);
    p.consumerSymbol = consumer;
    p.callerSymbol = caller;
    p.returnKind = [FBTCSymbolStub returnKindForSymbol:p.symbol];

    if (p.objcSelectorName.length && p.objcClassName.length) {
        p.strategy = FBTCRuntimePatchStrategyObjCBool;
        p.reason = @"ObjC no-arg BOOL getter; backend is live MSHookMessageEx override cache.";
        p.inlineToggleSafe = YES; p.safeAtLaunch = YES;
    } else if (p.function && p.hasBindPointer && [FBTCSymbolStub isForceableSymbol:p.symbol]) {
        p.strategy = FBTCRuntimePatchStrategyFunctionBool;
        p.reason = @"validated BOOL-return C symbol with confirmed imported bind pointer; fishhook can replace the slot.";
        p.inlineToggleSafe = YES; p.safeAtLaunch = YES;
    } else if (p.function && p.hasBindPointer && [FBTCSymbolStub isTypedForceableSymbol:p.symbol]) {
        p.strategy = FBTCRuntimePatchStrategyFunctionTyped;
        p.reason = @"validated typed C reader with confirmed imported bind pointer; value prompt required.";
        p.inlineToggleSafe = NO; p.safeAtLaunch = YES; p.requiresPromptValue = YES;
    } else if (p.data && ([FBTCSymbolStub isParamDescriptorSymbol:p.symbol] || (boolReader && [FBTCSymbolStub canForceAsParamDescriptor:p.symbol]))) {
        p.strategy = FBTCRuntimePatchStrategyDataReaderBool;
        p.reason = boolReader ? @"runtime xref confirmed MobileConfig BOOL reader consumer; force is descriptor-pointer filtered." : @"curated MobileConfig DATA descriptor; force is descriptor-pointer filtered.";
        p.inlineToggleSafe = YES; p.safeAtLaunch = YES; p.requiresConfirmedConsumer = ![FBTCSymbolStub isParamDescriptorSymbol:p.symbol];
    } else if (p.data && p.hasBindPointer && FBTCLooksStringDataSymbol(p.symbol, p.section)) {
        p.strategy = FBTCRuntimePatchStrategyDataRebindString;
        p.reason = @"DATA symbol has imported pointer slot and looks NSString/key-compatible; replacement string prompt required.";
        p.inlineToggleSafe = NO; p.safeAtLaunch = YES; p.requiresPromptValue = YES;
    } else if (p.data && p.runtimeAddress && p.dataSize > 0 && p.dataSize <= 64 && FBTCSectionIsPatchableData(p.section)) {
        p.strategy = FBTCRuntimePatchStrategyDataPatchBytes;
        p.reason = @"bounded non-code DATA symbol with known size; vm_protect patch uses snapshot/revert.";
        p.inlineToggleSafe = NO; p.safeAtLaunch = YES; p.requiresPromptValue = YES;
    } else if (p.function && p.hasBindPointer && [FBTCSymbolStub isHookableSymbol:p.symbol]) {
        p.strategy = FBTCRuntimePatchStrategyFunctionObserve;
        p.reason = @"ABI validated but not value-forceable; observe hook only.";
        p.inlineToggleSafe = YES; p.safeAtLaunch = YES;
    } else {
        p.strategy = FBTCRuntimePatchStrategyNone;
        if (p.function && [FBTCSymbolStub isHookableSymbol:p.symbol] && !p.hasBindPointer) p.reason = @"ABI known, but no imported bind pointer was resolved; fishhook would be a no-op.";
        else if (p.swiftLike) p.reason = @"Swift/C++ direct dispatch: requires xref/ObjC consumer hook; no sideload-safe generic patch.";
        else if (p.data) p.reason = @"DATA has no confirmed reader, imported pointer, or safe bounded layout yet.";
        else p.reason = [FBTCSymbolStub notForceableReasonForSymbol:p.symbol] ?: @"unknown ABI; classify before hook.";
    }
    p.strategyName = [FBTCRuntimePatchPlan displayNameForStrategy:p.strategy returnKind:p.returnKind];
    p.shortStrategyName = [FBTCRuntimePatchPlan shortNameForStrategy:p.strategy returnKind:p.returnKind];
    return p;
}

+ (BOOL)isAppliedPlan:(FBTCRuntimePatchPlan *)plan {
    if (!plan.symbol.length) return NO;
    switch (plan.strategy) {
        case FBTCRuntimePatchStrategyObjCBool: return [FBTSymbolBrowserEngine overrideForKey:FBTCObjCKey(plan.objcClassName, plan.objcSelectorName, plan.objcClassMethod)] != nil;
        case FBTCRuntimePatchStrategyFunctionBool: return [FBTCSymbolStub forceForSymbol:plan.symbol] != nil;
        case FBTCRuntimePatchStrategyFunctionTyped: return [FBTCSymbolStub typedForceForSymbol:plan.symbol] != nil || [FBTCSymbolStub observeForSymbol:plan.symbol];
        case FBTCRuntimePatchStrategyFunctionObserve: return [FBTCSymbolStub observeForSymbol:plan.symbol];
        case FBTCRuntimePatchStrategyDataReaderBool: return [FBTCSymbolStub forceForParamDescriptorSymbol:plan.symbol] != nil || [FBTCSymbolStub observeForParamDescriptorSymbol:plan.symbol];
        case FBTCRuntimePatchStrategyDataRebindString: return [self persistedPatchForSymbol:plan.symbol] != nil;
        case FBTCRuntimePatchStrategyDataPatchBytes: return [self persistedPatchForSymbol:plan.symbol] != nil;
        default: return NO;
    }
}

+ (NSUInteger)hitCountForPlan:(FBTCRuntimePatchPlan *)plan {
    if (plan.strategy == FBTCRuntimePatchStrategyDataReaderBool) return [FBTCSymbolStub paramDescriptorCallCountForSymbol:plan.symbol];
    return [FBTCSymbolStub callCountForSymbol:plan.symbol];
}

+ (BOOL)isHookInstalledForPlan:(FBTCRuntimePatchPlan *)plan {
    switch (plan.strategy) {
        case FBTCRuntimePatchStrategyObjCBool: return [FBTSymbolBrowserEngine hookInstalledForKey:FBTCObjCKey(plan.objcClassName, plan.objcSelectorName, plan.objcClassMethod)];
        case FBTCRuntimePatchStrategyDataReaderBool: return [FBTCSymbolStub hookInstalledForSymbol:@"IGMobileConfigBooleanValueForInternalUse"];
        case FBTCRuntimePatchStrategyDataRebindString: { FBTCDataRebindSlot *s = FBTCDataRebindSlotFor(plan.symbol, NO); return s && atomic_load(&s->installed); }
        case FBTCRuntimePatchStrategyDataPatchBytes: return [self persistedPatchForSymbol:plan.symbol] != nil;
        default: return [FBTCSymbolStub hookInstalledForSymbol:plan.symbol];
    }
}

+ (id)currentForcedValueForPlan:(FBTCRuntimePatchPlan *)plan {
    switch (plan.strategy) {
        case FBTCRuntimePatchStrategyObjCBool: return [FBTSymbolBrowserEngine overrideForKey:FBTCObjCKey(plan.objcClassName, plan.objcSelectorName, plan.objcClassMethod)];
        case FBTCRuntimePatchStrategyFunctionBool: return [FBTCSymbolStub forceForSymbol:plan.symbol];
        case FBTCRuntimePatchStrategyFunctionTyped: return [FBTCSymbolStub typedForceForSymbol:plan.symbol][@"value"];
        case FBTCRuntimePatchStrategyDataReaderBool: return [FBTCSymbolStub forceForParamDescriptorSymbol:plan.symbol];
        default: return [self persistedPatchForSymbol:plan.symbol][@"value"] ?: [self persistedPatchForSymbol:plan.symbol][@"patchHex"];
    }
}

+ (id)currentNativeValueForPlan:(FBTCRuntimePatchPlan *)plan {
    if (!plan.symbol.length) return nil;
    switch (plan.strategy) {
        case FBTCRuntimePatchStrategyObjCBool:
            return [FBTSymbolBrowserEngine liveValueForClass:plan.objcClassName ?: @"" selector:plan.objcSelectorName ?: @"" isClassMethod:plan.objcClassMethod];
        case FBTCRuntimePatchStrategyFunctionBool:
            return [FBTCSymbolStub observedValueForSymbol:plan.symbol];
        case FBTCRuntimePatchStrategyFunctionTyped:
            return [FBTCSymbolStub observedTypedValueForSymbol:plan.symbol];
        case FBTCRuntimePatchStrategyDataReaderBool:
            return [FBTCSymbolStub observedValueForParamDescriptorSymbol:plan.symbol];
        default:
            return nil;
    }
}

+ (BOOL)isEffectivelyEnabledForPlan:(FBTCRuntimePatchPlan *)plan {
    id forced = [self currentForcedValueForPlan:plan];
    if ([forced isKindOfClass:NSNumber.class]) return [forced boolValue];
    id native = [self currentNativeValueForPlan:plan];
    if ([native isKindOfClass:NSNumber.class]) return [native boolValue];
    return [self isAppliedPlan:plan];
}

+ (NSString *)stateSummaryForPlan:(FBTCRuntimePatchPlan *)plan {
    NSMutableArray<NSString *> *bits = [NSMutableArray array];
    id native = [self currentNativeValueForPlan:plan];
    id forced = [self currentForcedValueForPlan:plan];
    if ([native isKindOfClass:NSNumber.class]) [bits addObject:[NSString stringWithFormat:@"native %@", [native boolValue] ? @"ON" : @"OFF"]];
    else if (native) [bits addObject:[NSString stringWithFormat:@"native %@", native]];
    else [bits addObject:@"native unknown"];
    if ([forced isKindOfClass:NSNumber.class]) [bits addObject:[NSString stringWithFormat:@"override %@", [forced boolValue] ? @"ON" : @"OFF"]];
    else if (forced) [bits addObject:[NSString stringWithFormat:@"override %@", forced]];
    else [bits addObject:@"no override"];
    [bits addObject:[self isHookInstalledForPlan:plan] ? @"hook installed" : @"hook not installed"];
    NSUInteger hits = [self hitCountForPlan:plan];
    if (hits) [bits addObject:[NSString stringWithFormat:@"hits %lu", (unsigned long)hits]];
    return [bits componentsJoinedByString:@" · "];
}

+ (BOOL)applyPlan:(FBTCRuntimePatchPlan *)plan value:(id)value error:(NSError **)error {
    if (!plan.symbol.length || plan.strategy == FBTCRuntimePatchStrategyNone) return NO;
    BOOL ok = NO;
    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    switch (plan.strategy) {
        case FBTCRuntimePatchStrategyObjCBool: {
            NSNumber *v = [value isKindOfClass:NSNumber.class] ? value : @YES;
            [FBTSymbolBrowserEngine setOverride:v forClass:plan.objcClassName ?: @"" selector:plan.objcSelectorName ?: @"" isClassMethod:plan.objcClassMethod];
            ok = YES; extra[@"value"] = v;
            break;
        }
        case FBTCRuntimePatchStrategyFunctionBool: {
            NSNumber *v = [value isKindOfClass:NSNumber.class] ? value : @YES;
            ok = [FBTCSymbolStub setForce:v forSymbol:plan.symbol]; extra[@"value"] = v;
            break;
        }
        case FBTCRuntimePatchStrategyFunctionTyped: {
            if (!value) {
                ok = [FBTCSymbolStub setObserve:YES forSymbol:plan.symbol];
                extra[@"observeOnly"] = @YES;
                break;
            }
            ok = [FBTCSymbolStub setTypedForceValue:value returnKind:(plan.returnKind ?: [FBTCSymbolStub returnKindForSymbol:plan.symbol] ?: @"int64") forSymbol:plan.symbol];
            extra[@"value"] = value;
            break;
        }
        case FBTCRuntimePatchStrategyFunctionObserve: {
            ok = [FBTCSymbolStub setObserve:YES forSymbol:plan.symbol];
            break;
        }
        case FBTCRuntimePatchStrategyDataReaderBool: {
            NSNumber *v = [value isKindOfClass:NSNumber.class] ? value : @YES;
            ok = [FBTCSymbolStub setParamDescriptorForce:v forSymbol:plan.symbol]; extra[@"value"] = v;
            break;
        }
        case FBTCRuntimePatchStrategyDataRebindString: {
            NSString *str = [value isKindOfClass:NSString.class] ? value : [value description];
            if (!str.length) { if (error) *error = [NSError errorWithDomain:@"FBTCRuntimePatchResolver" code:21 userInfo:@{NSLocalizedDescriptionKey:@"replacement string required"}]; return NO; }
            ok = FBTCInstallDataRebind(plan.symbol, str);
            extra[@"value"] = str;
            break;
        }
        case FBTCRuntimePatchStrategyDataPatchBytes: {
            NSData *bytes = [value isKindOfClass:NSData.class] ? value : nil;
            if (!bytes.length) { if (error) *error = [NSError errorWithDomain:@"FBTCRuntimePatchResolver" code:22 userInfo:@{NSLocalizedDescriptionKey:@"patch bytes required"}]; return NO; }
            uintptr_t addr = (uintptr_t)FBTCResolveSymbolAddress(plan.symbol);
            if (!addr) addr = plan.runtimeAddress;
            NSData *snapshot = nil;
            ok = FBTCPatchMemory(addr, bytes, &snapshot, error);
            if (ok) {
                NSString *patchB64 = [bytes base64EncodedStringWithOptions:0];
                NSString *snapB64 = [snapshot base64EncodedStringWithOptions:0];
                extra[@"patch"] = patchB64 ?: @"";
                extra[@"snapshot"] = snapB64 ?: @"";
                extra[@"patchHex"] = [self hexStringFromData:bytes];
                NSMutableDictionary *snaps = [FBTCDictPref(kFBTCRuntimeDataPatchSnapshotsKey) mutableCopy] ?: [NSMutableDictionary dictionary];
                snaps[plan.symbol] = snapB64 ?: @"";
                [FBTUtils setPref:snaps.copy forKey:kFBTCRuntimeDataPatchSnapshotsKey];
            }
            break;
        }
        default: break;
    }
    if (ok) [self savePatchPlan:plan extra:extra.copy];
    return ok;
}

+ (BOOL)revertPlan:(FBTCRuntimePatchPlan *)plan error:(NSError **)error {
    if (!plan.symbol.length) return NO;
    BOOL ok = YES;
    NSDictionary *persisted = [self persistedPatchForSymbol:plan.symbol];
    switch (plan.strategy) {
        case FBTCRuntimePatchStrategyObjCBool:
            [FBTSymbolBrowserEngine setOverride:nil forClass:plan.objcClassName ?: @"" selector:plan.objcSelectorName ?: @"" isClassMethod:plan.objcClassMethod]; break;
        case FBTCRuntimePatchStrategyFunctionBool:
            ok = [FBTCSymbolStub setForce:nil forSymbol:plan.symbol]; break;
        case FBTCRuntimePatchStrategyFunctionTyped:
            ok = [FBTCSymbolStub setTypedForceValue:nil returnKind:(plan.returnKind ?: @"int64") forSymbol:plan.symbol];
            [FBTCSymbolStub setObserve:NO forSymbol:plan.symbol];
            break;
        case FBTCRuntimePatchStrategyFunctionObserve:
            ok = [FBTCSymbolStub setObserve:NO forSymbol:plan.symbol]; break;
        case FBTCRuntimePatchStrategyDataReaderBool:
            [FBTCSymbolStub setParamDescriptorForce:nil forSymbol:plan.symbol];
            [FBTCSymbolStub setParamDescriptorObserve:NO forSymbol:plan.symbol]; break;
        case FBTCRuntimePatchStrategyDataRebindString:
            ok = FBTCRevertDataRebind(plan.symbol); break;
        case FBTCRuntimePatchStrategyDataPatchBytes: {
            NSString *b64 = [persisted[@"snapshot"] isKindOfClass:NSString.class] ? persisted[@"snapshot"] : FBTCDictPref(kFBTCRuntimeDataPatchSnapshotsKey)[plan.symbol];
            NSData *snapshot = b64.length ? [[NSData alloc] initWithBase64EncodedString:b64 options:0] : nil;
            if (!snapshot.length) { ok = NO; if (error) *error = [NSError errorWithDomain:@"FBTCRuntimePatchResolver" code:23 userInfo:@{NSLocalizedDescriptionKey:@"missing DATA patch snapshot"}]; break; }
            uintptr_t addr = (uintptr_t)FBTCResolveSymbolAddress(plan.symbol);
            if (!addr) addr = plan.runtimeAddress;
            ok = FBTCPatchMemory(addr, snapshot, NULL, error);
            break;
        }
        default: ok = NO; break;
    }
    if (ok) [self forgetPatchPlanForSymbol:plan.symbol];
    return ok;
}

+ (void)reinstallSafePersistedPatchPlansAtLaunch {
    NSDictionary *plans = [self persistedPatchPlans];
    if (!plans.count) return;
    RLOG("reinstall persisted plans count=%lu", (unsigned long)plans.count);
    for (NSString *symbol in plans) {
        FBTCRuntimePatchPlan *plan = [FBTCRuntimePatchPlan planWithDictionary:plans[symbol]];
        if (!plan.safeAtLaunch || plan.strategy == FBTCRuntimePatchStrategyNone) continue;
        @try {
            switch (plan.strategy) {
                case FBTCRuntimePatchStrategyObjCBool: {
                    if ([FBTSymbolBrowserEngine overrideForKey:FBTCObjCKey(plan.objcClassName, plan.objcSelectorName, plan.objcClassMethod)] != nil) [FBTSymbolBrowserEngine installOverrideForKey:FBTCObjCKey(plan.objcClassName, plan.objcSelectorName, plan.objcClassMethod)];
                    break;
                }
                case FBTCRuntimePatchStrategyFunctionBool:
                    if ([FBTCSymbolStub isForceableSymbol:plan.symbol] && [FBTCSymbolStub forceForSymbol:plan.symbol] != nil) [FBTCSymbolStub installStubForSymbol:plan.symbol];
                    break;
                case FBTCRuntimePatchStrategyFunctionTyped:
                    if ([FBTCSymbolStub isTypedForceableSymbol:plan.symbol] && ([FBTCSymbolStub typedForceForSymbol:plan.symbol] != nil || [FBTCSymbolStub observeForSymbol:plan.symbol])) [FBTCSymbolStub installStubForSymbol:plan.symbol];
                    break;
                case FBTCRuntimePatchStrategyFunctionObserve:
                    if ([FBTCSymbolStub isHookableSymbol:plan.symbol] && [FBTCSymbolStub observeForSymbol:plan.symbol]) [FBTCSymbolStub installStubForSymbol:plan.symbol];
                    break;
                case FBTCRuntimePatchStrategyDataReaderBool:
                    if ([FBTCSymbolStub forceForParamDescriptorSymbol:plan.symbol] != nil) [FBTCSymbolStub setParamDescriptorForce:[FBTCSymbolStub forceForParamDescriptorSymbol:plan.symbol] forSymbol:plan.symbol];
                    else if ([FBTCSymbolStub observeForParamDescriptorSymbol:plan.symbol]) [FBTCSymbolStub setParamDescriptorObserve:YES forSymbol:plan.symbol];
                    break;
                case FBTCRuntimePatchStrategyDataRebindString: {
                    NSString *replacement = [plans[symbol][@"value"] isKindOfClass:NSString.class] ? plans[symbol][@"value"] : nil;
                    if (replacement.length && plan.hasBindPointer) FBTCInstallDataRebind(plan.symbol, replacement);
                    break;
                }
                case FBTCRuntimePatchStrategyDataPatchBytes: {
                    NSString *b64 = [plans[symbol][@"patch"] isKindOfClass:NSString.class] ? plans[symbol][@"patch"] : nil;
                    NSData *bytes = b64.length ? [[NSData alloc] initWithBase64EncodedString:b64 options:0] : nil;
                    if (bytes.length && bytes.length <= 64 && FBTCSectionIsPatchableData(plan.section)) {
                        // Launch reapply must never reuse an old ASLR address.
                        // DATA byte patches are cold-launch safe only when the
                        // current process can resolve the symbol again.
                        uintptr_t addr = (uintptr_t)FBTCResolveSymbolAddress(plan.symbol);
                        if (addr) FBTCPatchMemory(addr, bytes, NULL, NULL);
                    }
                    break;
                }
                default: break;
            }
        } @catch (__unused id e) {}
    }
}

+ (NSData *)dataFromHexString:(NSString *)hex error:(NSError **)error {
    NSString *clean = hex ?: @"";
    clean = [clean stringByReplacingOccurrencesOfString:@" " withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"0x" withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"," withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    if (!clean.length || (clean.length % 2) != 0) {
        if (error) *error = [NSError errorWithDomain:@"FBTCRuntimePatchResolver" code:30 userInfo:@{NSLocalizedDescriptionKey:@"hex must contain an even number of digits"}];
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithCapacity:clean.length / 2];
    for (NSUInteger i = 0; i < clean.length; i += 2) {
        NSString *byteStr = [clean substringWithRange:NSMakeRange(i, 2)];
        unsigned int b = 0;
        NSScanner *sc = [NSScanner scannerWithString:byteStr];
        if (![sc scanHexInt:&b]) {
            if (error) *error = [NSError errorWithDomain:@"FBTCRuntimePatchResolver" code:31 userInfo:@{NSLocalizedDescriptionKey:@"invalid hex byte"}];
            return nil;
        }
        uint8_t v = (uint8_t)b;
        [data appendBytes:&v length:1];
    }
    return data.copy;
}

+ (NSString *)hexStringFromData:(NSData *)data {
    if (![data isKindOfClass:NSData.class] || !data.length) return @"";
    const uint8_t *b = data.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [s appendFormat:@"%02x", b[i]];
    return s.copy;
}

@end
