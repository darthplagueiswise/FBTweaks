#ifndef FBT_FACEBOOK_HEADERS_H
#define FBT_FACEBOOK_HEADERS_H

#import <UIKit/UIKit.h>

// Interfaces verificadas no conjunto atual de Facebook/FBShared/
// FBSharedDynamic/FBReactNativeProducts/FBRarelyUsed. São apenas declarações;
// as implementações pertencem ao aplicativo em runtime.

@interface FBTabBarViewController : UIViewController
- (id)session;
- (void)setSession:(id)session;
@end

@interface FBTabBarAndContentViewController : UIViewController
- (BOOL)isTabBarFloating;
- (void)setIsTabBarFloating:(BOOL)floating animated:(BOOL)animated;
@end

@interface FBTabBarAndContentView : UIView
- (BOOL)isTabBarFloating;
- (void)setIsTabBarFloating:(BOOL)floating animated:(BOOL)animated;
@end

@interface FBTabBar : UIView
- (BOOL)isFloating;
- (void)setIsFloating:(BOOL)floating;
@end

@interface FBUserPreferences : NSObject
- (BOOL)isEmployee;
- (void)setEmployee:(BOOL)isEmployee;
@end

@interface FBBugReportConfiguration : NSObject
- (BOOL)isEmployee;
- (void)setIsEmployee:(BOOL)value;
- (void)setEnableInternalSettingsOption:(BOOL)value;
- (void)setEnableInternalToolsSubmenu:(BOOL)value;
- (void)setForceShowingInternalTools:(BOOL)value;
- (void)setShowTriageToDogfoodingAssistantSession:(BOOL)value;
- (void)setDisableEmployeeProductionReports:(BOOL)value;
@end

@interface FBProductTagCreationLogger : NSObject
- (BOOL)isEmployee;
@end

@interface FBSnacksThreadOwnerMessengerContact : NSObject
- (BOOL)isEmployee;
@end

@interface FBLoggedOutImageNetworkerConfiguration : NSObject
- (BOOL)isViewerEmployee;
@end

@interface FBSessionImageNetworkerConfiguration : NSObject
- (BOOL)isViewerEmployee;
@end

@interface FBRichPushNotificationTypeTraits : NSObject
+ (BOOL)_isEmployeeOrTestUser:(id)arg1;
@end

@interface FBWKWebView : NSObject
- (void)setIsEmployee:(BOOL)value;
@end

@interface FBWKWebViewDelegateAdaptor : NSObject
- (void)setIsEmployee:(BOOL)value;
@end

@interface RCDMobileConfigParams : NSObject
- (BOOL)isEmployee;
- (id)initWithClassesString:(id)classesString
      trackNSObjectBaseClass:(BOOL)trackNSObjectBaseClass
         isEventBasedTrigger:(BOOL)isEventBasedTrigger
                 maxCycleLen:(long long)maxCycleLen
  ignoreAppleClassesWithPrefix:(id)ignoreAppleClassesWithPrefix
              peopleSampling:(long long)peopleSampling
                   isEmployee:(BOOL)isEmployee
          isEnabledProduction:(BOOL)isEnabledProduction
   shouldUseSwiftABITraversal:(BOOL)shouldUseSwiftABITraversal;
@end

@interface FBLoom : NSObject
- (void)userSessionDidUpdateWithValidUser:(BOOL)validUser
                               isEmployee:(BOOL)isEmployee
                        networkDispatcher:(id)networkDispatcher
                      mobileConfigManager:(id)mobileConfigManager
                               qplSession:(long long)qplSession;
@end

@interface FBBugReportInitialCoordinator : NSObject
- (BOOL)triageToDogfoodingAssistantSession;
- (void)updateTriageToDogfoodingAssistantSession:(BOOL)value;
@end

@interface FBSnacksAdsDeliveryConfig : NSObject
- (BOOL)enableDogfoodingView;
@end

// FBReactNativeProductsFramework ------------------------------------------------

@interface RCTCurrentViewer : NSObject
- (void)setIsEmployee:(BOOL)value;
@end

@interface FBInspirationMediaCompositionViewController : UIViewController
- (BOOL)isEligibleForDebugIndicatorWithEmployeeCondition:(BOOL)condition;
@end

@interface RCTDevMenu : NSObject
- (BOOL)devMenuEnabled;
- (void)setDevMenuEnabled:(BOOL)value;
- (BOOL)shakeToShow;
- (void)setShakeToShow:(BOOL)value;
- (BOOL)profilingEnabled;
- (void)setProfilingEnabled:(BOOL)value;
- (BOOL)hotLoadingEnabled;
- (void)setHotLoadingEnabled:(BOOL)value;
- (BOOL)hotkeysEnabled;
- (void)setHotkeysEnabled:(BOOL)value;
- (BOOL)keyboardShortcutsEnabled;
- (void)setKeyboardShortcutsEnabled:(BOOL)value;
@end

@interface RCTDevMenuItem : NSObject
- (BOOL)isDisabled;
- (void)setDisabled:(BOOL)value;
@end

@interface RCTDevSettings : NSObject
- (BOOL)isDeviceDebuggingAvailable;
- (BOOL)isHotLoadingAvailable;
- (BOOL)isShakeToShowDevMenuEnabled;
- (void)setIsShakeToShowDevMenuEnabled:(BOOL)value;
- (BOOL)isShakeGestureEnabled;
- (void)setIsShakeGestureEnabled:(BOOL)value;
- (BOOL)isProfilingEnabled;
- (void)setProfilingEnabled:(BOOL)value;
- (BOOL)isHotLoadingEnabled;
- (void)setHotLoadingEnabled:(BOOL)value;
- (BOOL)startSamplingProfilerOnLaunch;
- (void)setStartSamplingProfilerOnLaunch:(BOOL)value;
- (BOOL)isPerfMonitorShown;
- (void)setIsPerfMonitorShown:(BOOL)value;
@end

@interface FBReactNativeInternalSettingsMenuItemHandler : NSObject
- (id)initWithSession:(id)session;
- (UIViewController *)viewControllerForMenuItem:(id)item
                          viewportSizeEstimate:(CGSize)size
                             tabSwitchingType:(long long)type;
@end

// FBRarelyUsedFramework ---------------------------------------------------------

@interface FFDBInternalSettingsWebViewController : UIViewController
- (BOOL)isInternLoggedIn;
@end

#endif /* FBT_FACEBOOK_HEADERS_H */
