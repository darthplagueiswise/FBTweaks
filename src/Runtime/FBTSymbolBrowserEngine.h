// Browse-only facade: one hook owner in FBTRuntimeBoolBrowser.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FBTSymbolImage) {
	FBTSymbolImageFacebook = 0,
	FBTSymbolImageFBShared = 1,
	FBTSymbolImageReactNative = 2,
	FBTSymbolImageFBSharedDynamic = 3,
};

@interface FBTSymbolGetter : NSObject
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic, copy) NSString *ownerClassName;
@property (nonatomic, readonly) NSString *overrideKey;
@property (nonatomic, assign) BOOL isClassMethod;
@property (nonatomic, readonly, nullable) NSNumber *liveValue;
@property (nonatomic, readonly, nullable) NSNumber *override;
@end

@interface FBTSymbolClass : NSObject
@property (nonatomic, copy) NSString *className;
@property (nonatomic, strong) NSArray<FBTSymbolGetter *> *getters;
@end

@interface FBTSymbolBrowserEngine : NSObject

+ (NSArray<FBTSymbolClass *> *)classesForImage:(FBTSymbolImage)image;

+ (nullable NSNumber *)liveValueForClass:(NSString *)className
								selector:(NSString *)selectorName
						 isClassMethod:(BOOL)isClassMethod;

+ (nullable NSNumber *)overrideForKey:(NSString *)overrideKey;
+ (BOOL)hookInstalledForKey:(NSString *)overrideKey;
+ (BOOL)installOverrideForKey:(NSString *)overrideKey;

+ (void)setOverride:(nullable NSNumber *)value
		   forClass:(NSString *)className
		   selector:(NSString *)selectorName
	  isClassMethod:(BOOL)isClassMethod;

+ (void)reinstallPersistedHooks;

@end

NS_ASSUME_NONNULL_END
