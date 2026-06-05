#pragma once
#import <Foundation/Foundation.h>
#import "../FBGramPrefix.h"

@interface FBGRMCParam : NSObject
@property(nonatomic, copy) NSString *fullKey;
@property(nonatomic, copy) NSString *group;
@property(nonatomic, copy) NSString *param;
@property(nonatomic, copy) NSString *type;
@property(nonatomic, copy) NSString *unitType;
@property(nonatomic, assign) uint64_t slotId;
@property(nonatomic, assign) BOOL defaultBool;
@property(nonatomic, assign) FBGRFeatureCategory category;
@end

@interface FBGRMCCatalog : NSObject
@property(nonatomic, readonly) BOOL loaded;
@property(nonatomic, copy, readonly) NSString *sourceDescription;
@property(nonatomic, strong, readonly) NSArray<FBGRMCParam *> *boolParams;
+ (instancetype)shared;
- (void)loadIfNeeded;
- (FBGRMCParam *)paramForSlotId:(uint64_t)slotId;
- (NSArray<FBGRMCParam *> *)paramsForCategory:(FBGRFeatureCategory)cat;
- (NSArray<FBGRMCParam *> *)search:(NSString *)query category:(FBGRFeatureCategory)cat;
@end
