#ifndef FBT_FLAG_CATALOG_H
#define FBT_FLAG_CATALOG_H

#import <Foundation/Foundation.h>

@interface FBTFlagCatalog : NSObject
+ (NSURL *)bundleURLForResource:(NSString *)name extension:(NSString *)ext;
+ (NSArray<NSDictionary *> *)allFlags;
+ (NSArray<NSDictionary *> *)headlineFlags;
+ (NSDictionary *)bestMatchForMobileConfigKey:(uint64_t)key;
+ (NSArray<NSDictionary *> *)queryConfigs;
@end

#endif /* FBT_FLAG_CATALOG_H */
