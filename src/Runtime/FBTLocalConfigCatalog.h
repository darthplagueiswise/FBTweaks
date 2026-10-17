#import <Foundation/Foundation.h>
#include <stdint.h>
@interface FBTLocalConfigCatalog : NSObject
+ (NSArray<NSDictionary *> *)configurations;
+ (NSDictionary *)labelForPackedKey:(uint64_t)key;
+ (void)prepare;
@end
