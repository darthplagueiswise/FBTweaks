#import <Foundation/Foundation.h>
#include <stdint.h>
@interface FBTLocalConfigCatalog : NSObject
+ (NSArray<NSDictionary *> *)configurations;
+ (NSDictionary *)labelForPackedKey:(uint64_t)key;
+ (NSNumber *)packedKeyForConfiguration:(NSDictionary *)configuration parameter:(NSDictionary *)parameter;
+ (void)prepare;
@end

