#import <Foundation/Foundation.h>
@interface FBTFeatureCatalog : NSObject
+ (NSArray<NSDictionary *> *)features;
// Select whole map records for the visual groups; source/scope and parameters
// remain as supplied by FBTLocalConfigCatalog.
+ (NSArray<NSDictionary *> *)configurationsForFeatureId:(NSString *)featureId
                                  localConfigurations:(NSArray<NSDictionary *> *)configurations;
@end
