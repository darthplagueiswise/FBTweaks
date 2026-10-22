#import "FBTMobileConfigValueReader.h"
#import "FBTLocalConfigCatalog.h"
#import "FBTNativeMobileConfigOverrides.h"
#import "FBTMobileConfigRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <string.h>

// Facebook 583: all four mc_*_param_t arguments are one uint64_t struct.
typedef struct { uint64_t value; } FBTMCInspectionParam;
static __thread unsigned int sSystemReadDepth;
BOOL FBTMobileConfigIsInspectingSystemValue(void) { return sSystemReadDepth != 0; }

NSString *FBTMobileConfigValueText(id value, NSString *type) {
    if (!value || value == NSNull.null) return @"nil";
    if ([type isEqualToString:@"bool"]) return [value boolValue] ? @"true" : @"false";
    if ([value isKindOfClass:NSString.class]) return [NSString stringWithFormat:@"\"%@\"", value];
    return [value description];
}

static NSDictionary *FBTUnavailable(NSString *reason) {
    return @{@"available": @NO, @"reason": reason ?: @"Leitura indisponível"};
}
static BOOL FBTNoArgMethod(id object, NSString *selector, char returnType) {
    NSMethodSignature *signature = [object methodSignatureForSelector:NSSelectorFromString(selector)];
    if (!signature || signature.numberOfArguments != 2) return NO;
    char ret = signature.methodReturnType[0];
    return ret == returnType || (returnType == 'B' && ret == 'c');
}
static BOOL FBTReaderMatches(id context, SEL selector, NSString *type) {
    NSMethodSignature *signature = [context methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 4) return NO;
    const char *argument = [signature getArgumentTypeAtIndex:2];
    NSUInteger size = 0;
    NSGetSizeAndAlignment(argument, &size, NULL);
    if (size != 8 || (argument[0] != 'Q' && strncmp(argument, "{mc_", 4) != 0)) return NO;
    if ([signature getArgumentTypeAtIndex:3][0] != '@') return NO;
    char ret = signature.methodReturnType[0];
    return ([type isEqualToString:@"bool"] && (ret == 'B' || ret == 'c')) ||
        ([type isEqualToString:@"int64"] && ret == 'q') ||
        ([type isEqualToString:@"double"] && ret == 'd') ||
        ([type isEqualToString:@"string"] && ret == '@');
}
static NSString *FBTNativeSourceName(NSInteger source) {
    // Valid range verified in NSStringFromFBMobileConfigOptionsValueSource.
    // Never guess enum meanings or pass unsupported values to its assertion.
    typedef NSString *(*SourceNameFn)(NSInteger);
    SourceNameFn formatter = (SourceNameFn)dlsym(RTLD_DEFAULT, "NSStringFromFBMobileConfigOptionsValueSource");
    if (formatter && source >= -1 && source <= 25) return formatter(source) ?: @"Origem não informada";
    return [NSString stringWithFormat:@"Origem não decodificada (%ld)", (long)source];
}
static NSString *FBTSourceHint(NSString *source) {
    if ([source isEqualToString:@"SERVER"]) return @"Valor de servidor disponível no mecanismo nativo; esta leitura pode usar o cache.";
    if ([source containsString:@"SCHEMAHASH_MISMATCH"]) return @"O app usou default porque o hash do schema RN não corresponde ao mapa.";
    if ([source containsString:@"MISSING_SERVER_VALUE"]) return @"O app usou default porque não encontrou um valor de servidor válido para este parâmetro.";
    if ([source containsString:@"NO_DATA_ON_DISK"]) return @"O app usou default porque não encontrou dados em disco.";
    if ([source containsString:@"ACCESSED_BEFORE_MC_INIT"]) return @"O app usou default porque MobileConfig ainda não estava inicializado.";
    if ([source containsString:@"MISMATCH_"] || [source containsString:@"INVALID_"]) return @"O app informou incompatibilidade de descritor, tipo, escopo ou mapa; o valor retornado é fallback.";
    if ([source hasPrefix:@"DEFAULT"]) return @"O leitor retornou um default/fallback, não um valor confirmado de servidor.";
    return @"A origem informada não confirma um valor SYS independente de overrides.";
}
static id FBTOptions(BOOL system) {
    Class cls = NSClassFromString(@"FBMobileConfigOptions");
    id options = [[cls alloc] init];
    for (NSString *name in @[@"setWithoutLogging", @"setRequestForValueSource", @"setIgnoreOverrideForInternalUse"]) {
        if (!FBTNoArgMethod(options, name, '@')) return nil;
        if (![name isEqualToString:@"setIgnoreOverrideForInternalUse"] || system)
            ((id (*)(id, SEL))objc_msgSend)(options, NSSelectorFromString(name));
    }
    if (!FBTNoArgMethod(options, @"valueSource", 'q')) return nil;
    return options;
}
static id FBTRead(id context, SEL selector, uint64_t key, NSString *type, id options) {
    FBTMCInspectionParam param = { key };
    if ([type isEqualToString:@"bool"]) return @(((BOOL (*)(id, SEL, FBTMCInspectionParam, id))objc_msgSend)(context, selector, param, options));
    if ([type isEqualToString:@"int64"]) return @(((int64_t (*)(id, SEL, FBTMCInspectionParam, id))objc_msgSend)(context, selector, param, options));
    if ([type isEqualToString:@"double"]) return @(((double (*)(id, SEL, FBTMCInspectionParam, id))objc_msgSend)(context, selector, param, options));
    return ((id (*)(id, SEL, FBTMCInspectionParam, id))objc_msgSend)(context, selector, param, options) ?: NSNull.null;
}

NSDictionary *FBTMobileConfigInspectParameter(NSDictionary *configuration, NSDictionary *parameter) {
    @try {
        NSNumber *packed = [FBTLocalConfigCatalog packedKeyForConfiguration:configuration parameter:parameter];
        if (!packed) return FBTUnavailable(@"Descritor nativo não validado para este parâmetro/mapa.");
        uint64_t key = packed.unsignedLongLongValue;
        unsigned int unit = (unsigned int)((key >> 54) & 31);
        NSString *type = parameter[@"type"];
        NSString *verb = @{@"bool": @"Bool", @"int64": @"Int64", @"double": @"Double", @"string": @"String"}[type];
        if (!verb) return FBTUnavailable(@"Tipo sem leitor nativo validado.");
        SEL selector = NSSelectorFromString([NSString stringWithFormat:@"get%@:withOptions:", verb]);
        id selected = nil;
        for (id context in FBTNativeMobileConfigReaderContexts()) {
            if (!FBTNoArgMethod(context, @"getUnitType", 'i') || !FBTReaderMatches(context, selector, type)) continue;
            int candidateUnit = ((int (*)(id, SEL))objc_msgSend)(context, NSSelectorFromString(@"getUnitType"));
            if (candidateUnit != (int)unit) continue;
            if (!FBTNoArgMethod(context, @"hasValidManager", 'B') ||
                !((BOOL (*)(id, SEL))objc_msgSend)(context, NSSelectorFromString(@"hasValidManager"))) continue;
            if (!FBTNoArgMethod(context, @"hasValidConfig", 'B') ||
                !((BOOL (*)(id, SEL))objc_msgSend)(context, NSSelectorFromString(@"hasValidConfig"))) continue;
            if (selected && selected != context) return FBTUnavailable(@"Mais de um contexto para este escopo. Abra o contexto nativo desejado e atualize a leitura.");
            selected = context;
        }
        if (!selected) return FBTUnavailable(@"Contexto deste escopo ainda indisponível. Abra MobileConfig nativo e atualize.");
        id sysOptions = FBTOptions(YES), effectiveOptions = FBTOptions(NO);
        if (!sysOptions || !effectiveOptions) return FBTUnavailable(@"API nativa de origem/bypass incompatível com esta versão.");
        id systemValue;
        ++sSystemReadDepth;
        @try { systemValue = FBTRead(selected, selector, key, type, sysOptions); }
        @finally { --sSystemReadDepth; }
        NSInteger source = ((NSInteger (*)(id, SEL))objc_msgSend)(sysOptions, NSSelectorFromString(@"valueSource"));
        NSString *sourceName = FBTNativeSourceName(source);
        BOOL systemAvailable = [sourceName isEqualToString:@"SERVER"] || [sourceName hasPrefix:@"DEFAULT"];
        NSDictionary *runtimeOverride = FBTMobileConfigOverrideForKey(key);
        id effective = FBTRead(selected, selector, key, type, effectiveOptions);
        NSInteger effectiveSource = ((NSInteger (*)(id, SEL))objc_msgSend)(effectiveOptions, NSSelectorFromString(@"valueSource"));
        NSDictionary *inspection = @{@"available": @YES,
            @"key": [NSString stringWithFormat:@"%llu", (unsigned long long)key],
            @"key_hex": [NSString stringWithFormat:@"0x%016llx", (unsigned long long)key],
            @"unit": @(unit), @"type": type,
            @"descriptor_slot": @(key & 0xffff), @"catalog_slot": parameter[@"slot"] ?: NSNull.null,
            @"system_available": @(systemAvailable),
            @"system_value": systemAvailable ? (systemValue ?: NSNull.null) : NSNull.null,
            @"observed_bypass_value": systemValue ?: NSNull.null, @"effective_value": effective ?: NSNull.null,
            @"source_raw": @(source), @"source": sourceName, @"source_hint": FBTSourceHint(sourceName),
            @"effective_source": runtimeOverride ? @"Override da tweak" : FBTNativeSourceName(effectiveSource),
            @"reader": NSStringFromClass([selected class]), @"read_at": @([NSDate date].timeIntervalSince1970)};
        // This records the native reported source ONLY; never export a parameter value.
        // SERVER may be disk-backed; DEFAULT is not proof of a successful remote fetch.
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"FBTMCNativeValueSourceObserved"
            object:nil
            userInfo:@{
                @"mc_config_name": configuration[@"name"] ?: @"unknown",
                @"mc_config_key": configuration[@"id"] ?: @(-1),
                @"mc_param_name": parameter[@"name"] ?: @"unknown",
                @"mc_param_key": parameter[@"id"] ?: @(-1),
                @"mc_value_source": sourceName ?: @"unknown",
                @"mc_value_source_raw": @(source),
                @"mc_value_source_bucket": [sourceName isEqualToString:@"SERVER"] ? @"SERVER" :
                    ([sourceName hasPrefix:@"DEFAULT"] ? @"DEFAULT" : @"OTHER")
            }];
        return inspection;
    } @catch (NSException *exception) {
        return FBTUnavailable([NSString stringWithFormat:@"Leitor nativo recusou a leitura (%@).", exception.name]);
    }
}
