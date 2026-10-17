#import <Foundation/Foundation.h>
// Estados de um param no mc_overrides.json nativo.
typedef NS_ENUM(NSInteger, FBTMCState) { FBTMCStateSys = 0, FBTMCStateOff = 1, FBTMCStateOn = 2 };

@interface FBTMCOverridesFile : NSObject
+ (nullable NSString *)path;                 // path resolvido do mc_overrides.json (AppGroups/getOverridesTablePath)
+ (FBTMCState)stateForConfig:(nonnull NSString *)configKey paramIdx:(NSInteger)idx;
+ (void)setState:(FBTMCState)state forConfig:(nonnull NSString *)configKey paramIdx:(NSInteger)idx name:(nonnull NSString *)name;
+ (BOOL)fileExists;
+ (NSMutableDictionary *)loadOverrides;
+ (NSString *)valueTextForConfigID:(NSInteger)configID paramIdx:(NSInteger)idx;
+ (BOOL)setValueText:(NSString *)value forConfigID:(NSInteger)configID
             paramIdx:(NSInteger)idx configName:(NSString *)configName
            paramName:(NSString *)paramName error:(NSError **)error;
@end
