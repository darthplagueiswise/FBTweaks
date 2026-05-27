#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Represents one param from ReactMobileConfigMetadata.json
@interface FBGRMCParam : NSObject
@property(nonatomic) uint64_t slotId;
@property(nonatomic, copy) NSString *fullKey;    // "fbios_navigation_floating_tab_bar:enable_scroll_behind_ftb_on_dating"
@property(nonatomic, copy) NSString *group;      // "fbios_navigation_floating_tab_bar"
@property(nonatomic, copy) NSString *paramName;  // "enable_scroll_behind_ftb_on_dating"
@property(nonatomic, copy) NSString *type;       // "boolValue" | "stringValue" | "i64Value" | "doubleValue"
@property(nonatomic) BOOL defaultBool;
@property(nonatomic) NSInteger unitType;         // 4=iOS, 2=user-level, 1=device
@property(nonatomic) uint64_t configKey;
@end

/// Loads and indexes ReactMobileConfigMetadata.json.gz
@interface FBGRMCCatalog : NSObject

+ (instancetype)shared;

- (void)loadIfNeeded;  // lazy, threadsafe

/// Returns nil if slotId not found
- (nullable FBGRMCParam *)paramForSlotId:(uint64_t)slotId;

/// All params, sorted by slotId
- (NSArray<FBGRMCParam *> *)allParams;

/// iOS-specific bool params only (unitType==4, type==boolValue)
- (NSArray<FBGRMCParam *> *)iOSBoolParams;

/// Search by name fragment (case-insensitive)
- (NSArray<FBGRMCParam *> *)searchParams:(NSString *)query;

@property(nonatomic, readonly) NSUInteger totalCount;
@property(nonatomic, readonly) BOOL isLoaded;

@end

NS_ASSUME_NONNULL_END
