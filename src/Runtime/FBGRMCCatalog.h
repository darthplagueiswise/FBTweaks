#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One param from ReactMobileConfigMetadata.json schema.
/// Identity is (configKey, paramId); slotId is the runtime handle the getter
/// receives wrapped in mc_bool_param_t.
@interface FBGRMCParam : NSObject
@property(nonatomic) uint64_t slotId;
@property(nonatomic) uint64_t configKey;
@property(nonatomic) NSInteger paramId;
@property(nonatomic, copy) NSString *fullKey;    // "group:param"
@property(nonatomic, copy) NSString *group;
@property(nonatomic, copy) NSString *paramName;
@property(nonatomic, copy) NSString *type;       // boolValue|stringValue|i64Value|doubleValue
@property(nonatomic) BOOL defaultBool;
@property(nonatomic) NSInteger unitType;         // 4=iOS 2=user 1=device
@property(nonatomic, readonly) BOOL isBool;      // type == boolValue
@property(nonatomic, copy, readonly) NSArray<NSString *> *tags; // secondary keyword tags
@end

@interface FBGRMCCatalog : NSObject
+ (instancetype)shared;
- (void)loadIfNeeded;

- (nullable FBGRMCParam *)paramForSlotId:(uint64_t)slotId;
- (NSArray<FBGRMCParam *> *)allParams;
- (NSArray<FBGRMCParam *> *)iOSBoolParams;
- (NSArray<FBGRMCParam *> *)searchParams:(NSString *)query;

/// Categories derived from the JSON `group` field. Key = group, value = params.
- (NSDictionary<NSString *, NSArray<FBGRMCParam *> *> *)paramsByGroup;
/// Sorted group names.
- (NSArray<NSString *> *)allGroups;
/// Params whose tags contain `tag` (e.g. "employee", "dogfood", "liquid_glass").
- (NSArray<FBGRMCParam *> *)paramsWithTag:(NSString *)tag;

@property(nonatomic, readonly) NSUInteger totalCount;
@property(nonatomic, readonly) BOOL isLoaded;
@end

NS_ASSUME_NONNULL_END
