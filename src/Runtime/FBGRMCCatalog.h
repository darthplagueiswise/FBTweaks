#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface FBGRMCParam : NSObject
@property(nonatomic) uint64_t slotId;
@property(nonatomic, copy) NSString *fullKey;
@property(nonatomic, copy) NSString *group;
@property(nonatomic, copy) NSString *paramName;
@property(nonatomic, copy) NSString *type;
@property(nonatomic) BOOL defaultBool;
@property(nonatomic) NSInteger unitType;
@property(nonatomic) uint64_t configKey;
@end

@interface FBGRMCCatalog : NSObject
+ (instancetype)shared;
- (void)loadIfNeeded;
- (nullable FBGRMCParam *)paramForSlotId:(uint64_t)slotId;
- (NSArray<FBGRMCParam *> *)allParams;
- (NSArray<FBGRMCParam *> *)boolParams;
- (NSArray<FBGRMCParam *> *)iOSBoolParams;
- (NSArray<FBGRMCParam *> *)searchParams:(NSString *)query;
@property(nonatomic, readonly) NSUInteger totalCount;
@property(nonatomic, readonly) BOOL isLoaded;
@property(nonatomic, readonly, copy) NSString *sourcePath;
@end
NS_ASSUME_NONNULL_END
