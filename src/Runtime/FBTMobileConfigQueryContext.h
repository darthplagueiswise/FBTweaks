#import <Foundation/Foundation.h>

// Track the exact native UI query across background dispatch, without a global
// "last error". Replacing an owner's selection isolates any late completions.
@interface FBTMobileConfigQueryContext : NSObject
@property (nonatomic, copy, readonly) NSString *configName;
@property (nonatomic, copy, readonly) NSString *paramName;
@property (atomic, assign) NSInteger httpStatus;
+ (instancetype)beginForOwner:(id)owner config:(NSString *)config param:(NSString *)param;
+ (instancetype)beginForOwner:(id)owner encodedSearchItem:(id)item;
+ (instancetype)contextForOwner:(id)owner;
+ (NSArray<FBTMobileConfigQueryContext *> *)contextsMatchingConfig:(NSString *)config param:(NSString *)param;
@end
