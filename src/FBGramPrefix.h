#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSString * const kFBTweaksSuite = @"com.darthplagueiswise.fbtweaks";
static NSString * const kFBGRMCObserverEnabled = @"fbgr_mc_observer_enabled";

static inline NSUserDefaults *FBGRPrefs(void) {
    static NSUserDefaults *u;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        u = [[NSUserDefaults alloc] initWithSuiteName:kFBTweaksSuite] ?: NSUserDefaults.standardUserDefaults;
    });
    return u;
}

static inline BOOL FBGRPref(NSString *key) {
    return key.length ? [FBGRPrefs() boolForKey:key] : NO;
}

typedef struct { uint64_t value; } mc_bool_param_t;

typedef NS_ENUM(NSInteger, FBGRFeatureCategory) {
    FBGRFeatureCategoryAll = 0,
    FBGRFeatureCategoryUI,
    FBGRFeatureCategoryLiquidGlass,
    FBGRFeatureCategoryTabBar,
    FBGRFeatureCategoryDating,
    FBGRFeatureCategoryExperiments,
    FBGRFeatureCategoryDogfood,
    FBGRFeatureCategoryInternal,
    FBGRFeatureCategoryDebug,
    FBGRFeatureCategoryMarketplace,
    FBGRFeatureCategoryAI,
};

static inline NSString *FBGRFeatureCategoryTitle(FBGRFeatureCategory cat) {
    switch (cat) {
        case FBGRFeatureCategoryUI: return @"UI";
        case FBGRFeatureCategoryLiquidGlass: return @"LiquidGlass";
        case FBGRFeatureCategoryTabBar: return @"TabBar";
        case FBGRFeatureCategoryDating: return @"Namoro";
        case FBGRFeatureCategoryExperiments: return @"Experimentos";
        case FBGRFeatureCategoryDogfood: return @"DogFood";
        case FBGRFeatureCategoryInternal: return @"Internal";
        case FBGRFeatureCategoryDebug: return @"Debug Menus";
        case FBGRFeatureCategoryMarketplace: return @"Marketplace";
        case FBGRFeatureCategoryAI: return @"AI / GenAI";
        default: return @"Todos";
    }
}

static inline NSString *FBGRFeatureCategoryIcon(FBGRFeatureCategory cat) {
    switch (cat) {
        case FBGRFeatureCategoryUI: return @"rectangle.3.group.fill";
        case FBGRFeatureCategoryLiquidGlass: return @"sparkles";
        case FBGRFeatureCategoryTabBar: return @"rectangle.bottomthird.inset.filled";
        case FBGRFeatureCategoryDating: return @"heart.fill";
        case FBGRFeatureCategoryExperiments: return @"flask.fill";
        case FBGRFeatureCategoryDogfood: return @"ladybug.fill";
        case FBGRFeatureCategoryInternal: return @"person.badge.key.fill";
        case FBGRFeatureCategoryDebug: return @"wrench.and.screwdriver.fill";
        case FBGRFeatureCategoryMarketplace: return @"cart.fill";
        case FBGRFeatureCategoryAI: return @"brain.head.profile";
        default: return @"list.bullet.rectangle";
    }
}

#define FBGRLog(fmt,...) NSLog(@"[FBTweaks] " fmt, ##__VA_ARGS__)
#define FBGRLogHook(tag,fmt,...) NSLog(@"[FBTweaks][" tag "] " fmt, ##__VA_ARGS__)
