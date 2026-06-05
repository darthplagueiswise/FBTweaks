#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, FBGRBoolRuntimeImageKind) {
    FBGRBoolRuntimeImageKindExecutable = 0,
    FBGRBoolRuntimeImageKindFBSharedFramework = 1,
};

@interface FBGRBoolRuntimeItem : NSObject
@property(nonatomic, copy) NSString *className;
@property(nonatomic, copy) NSString *selectorName;
@property(nonatomic, copy) NSString *imageName;
@property(nonatomic, assign) BOOL classMethod;
@property(nonatomic, assign) BOOL hooked;
@property(nonatomic, assign) BOOL overrideSet;
@property(nonatomic, assign) BOOL overrideValue;
@end

@interface FBGRBoolRuntimeInventory : NSObject
+ (NSArray<FBGRBoolRuntimeItem *> *)scanImageKind:(FBGRBoolRuntimeImageKind)kind;
+ (void)setOverrideForItem:(FBGRBoolRuntimeItem *)item value:(BOOL)value;
+ (void)clearOverrideForItem:(FBGRBoolRuntimeItem *)item;
+ (void)installHookForItem:(FBGRBoolRuntimeItem *)item;
+ (NSUInteger)reinstallPersistedHooks;
+ (void)clearAllRuntimeOverrides;
+ (NSString *)diagnostic;
@end
