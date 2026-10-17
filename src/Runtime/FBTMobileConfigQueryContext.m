#import "FBTMobileConfigQueryContext.h"

@implementation FBTMobileConfigQueryContext {
    NSDate *_created;
}
static NSMapTable *sOwners;
static NSLock *sLock;
+ (void)prepare {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sOwners = [NSMapTable weakToStrongObjectsMapTable]; sLock = [NSLock new]; });
}
+ (instancetype)beginForOwner:(id)owner config:(NSString *)config param:(NSString *)param {
    [self prepare];
    FBTMobileConfigQueryContext *context = nil;
    if (owner && [config isKindOfClass:NSString.class] && config.length > 0 && config.length <= 300 &&
        [param isKindOfClass:NSString.class] && param.length <= 300) {
        context = [FBTMobileConfigQueryContext new];
        context->_configName = [config copy]; context->_paramName = [param copy];
        context->_created = [NSDate date];
    }
    [sLock lock];
    if (owner) { if (context) [sOwners setObject:context forKey:owner]; else [sOwners removeObjectForKey:owner]; }
    [sLock unlock];
    return context;
}
+ (instancetype)beginForOwner:(id)owner encodedSearchItem:(id)item {
    NSString *config = @"", *param = @"";
    if ([item isKindOfClass:NSString.class] && [item length] <= 4096) {
        // Verified native componentsSeparatedByString(":") decoders:
        // kind 0 config [1]; kind 1 QE parameter [1,2]; kinds 4/5 native [2,3].
        NSArray *parts = [item componentsSeparatedByString:@":"];
        NSString *kind = parts.firstObject;
        if ([kind isEqualToString:@"0"] && parts.count >= 2) config = parts[1];
        else if ([kind isEqualToString:@"1"] && parts.count >= 4) { config = parts[1]; param = parts[2]; }
        else if (([kind isEqualToString:@"4"] || [kind isEqualToString:@"5"]) && parts.count >= 5) {
            config = parts[2]; param = parts[3];
        }
    }
    return [self beginForOwner:owner config:config param:param];
}
+ (instancetype)contextForOwner:(id)owner {
    if (!owner) return nil;
    [self prepare]; [sLock lock]; id context = [sOwners objectForKey:owner]; [sLock unlock]; return context;
}
+ (NSArray<FBTMobileConfigQueryContext *> *)contextsMatchingConfig:(NSString *)config param:(NSString *)param {
    [self prepare]; NSMutableArray *matches = [NSMutableArray array];
    [sLock lock];
    for (FBTMobileConfigQueryContext *context in sOwners.objectEnumerator) {
        if ([context.configName isEqualToString:config] && [context.paramName isEqualToString:param] &&
            -[context->_created timeIntervalSinceNow] < 60) [matches addObject:context];
    }
    [sLock unlock]; return matches;
}
@end
