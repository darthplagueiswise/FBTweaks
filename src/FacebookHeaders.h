#ifndef FBT_FACEBOOK_HEADERS_H
#define FBT_FACEBOOK_HEADERS_H

#import <UIKit/UIKit.h>

// =====================================================================
// Declarações de interface para classes do Facebook que vamos hookar.
// Todos os nomes/seletores abaixo foram confirmados no binário
// (FBSharedFramework / executável Facebook v566.1.0).
// Apenas declarações — o app fornece as implementações em runtime.
// =====================================================================

// Host do long-press + dono da `session`.
// inst: viewDidLoad, viewDidAppear:, _handleLongPress:, _handleDoubleTap:,
//       session, setSession:
@interface FBTabBarViewController : UIViewController
- (id)session;
- (void)setSession:(id)session;
@end

// Estado de "floating" do tab bar (VC + view).
@interface FBTabBarAndContentViewController : UIViewController
- (BOOL)isTabBarFloating;
- (void)setIsTabBarFloating:(BOOL)floating animated:(BOOL)animated;
@end

@interface FBTabBarAndContentView : UIView
- (BOOL)isTabBarFloating;
- (void)setIsTabBarFloating:(BOOL)floating animated:(BOOL)animated;
@end

// A barra em si.
@interface FBTabBar : UIView
- (BOOL)isFloating;
- (void)setIsFloating:(BOOL)floating;
@end

// Getters de employee/internal (cada um confirmado na classe indicada).
@interface FBUserPreferences : NSObject
- (BOOL)isEmployee;
- (void)setIsEmployee:(BOOL)isEmployee;
@end

@interface FBBugReportConfiguration : NSObject
- (BOOL)isEmployee;
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

#endif /* FBT_FACEBOOK_HEADERS_H */
