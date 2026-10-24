#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface FBTSettingsCatalog : NSObject
+ (NSArray<NSDictionary *> *)categories;
+ (NSArray<NSDictionary *> *)allSections;
+ (NSArray<NSDictionary *> *)sectionsForCategory:(nullable NSString *)category query:(nullable NSString *)query;
@end
NS_ASSUME_NONNULL_END
