#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBGRFeaturedFlag : NSObject
@property(nonatomic) uint64_t slotId;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *detail;
@end

@interface FBGRGateProvider : NSObject
@property(nonatomic, copy) NSString *providerID;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *icon;        // SF Symbol name
@property(nonatomic, copy) NSString *accentColor; // "cyan","purple","orange","green","blue","pink"
@property(nonatomic, strong) NSArray<FBGRFeaturedFlag *> *featured;
@end

@interface FBGRGateRegistry : NSObject
+ (NSArray<FBGRGateProvider *> *)allProviders;
@end

NS_ASSUME_NONNULL_END
