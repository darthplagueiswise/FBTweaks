#ifndef FBT_DEFAULTS_H
#define FBT_DEFAULTS_H

#import <Foundation/Foundation.h>

// Preferências registradas. Qualquer key nova entra aqui para backup/export.
extern NSString * const FBTKeyMasterEnabled;
extern NSString * const FBTKeyEmployeeEnabled;
extern NSString * const FBTKeyLiquidGlassEnabled;
extern NSString * const FBTKeyFloatingTabBarEnabled;
extern NSString * const FBTKeyDatingEnabled;
extern NSString * const FBTKeyOpenLongPress;

extern NSString * const FBTKeyMobileConfigRuntimeEnabled;
extern NSString * const FBTKeyMobileConfigCaptureEnabled;
extern NSString * const FBTKeyMobileConfigOverridesEnabled;
extern NSString * const FBTKeyMobileConfigOverrides;

extern NSString * const FBTKeyRuntimeBoolBrowserEnabled;
extern NSString * const FBTKeyRuntimeBoolOverrides;

extern NSString * const FBTNotificationPrefsChanged;

@interface FBTDefaults : NSObject

+ (void)registerDefaultsOnce;
+ (NSDictionary *)registeredDefaults;

+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;

+ (NSString *)stringForKey:(NSString *)key;
+ (void)setString:(NSString *)value forKey:(NSString *)key;

+ (NSDictionary *)dictForKey:(NSString *)key;
+ (void)setDict:(NSDictionary *)value forKey:(NSString *)key;

+ (NSArray *)arrayForKey:(NSString *)key;
+ (void)setArray:(NSArray *)value forKey:(NSString *)key;

+ (void)removeObjectForKey:(NSString *)key;
+ (void)notifyPrefsChanged;

@end

#endif /* FBT_DEFAULTS_H */
