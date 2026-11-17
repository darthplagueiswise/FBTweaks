#ifndef FBT_UTILS_H
#define FBT_UTILS_H

#import <UIKit/UIKit.h>

@interface FBTUtils : NSObject

// Topo da pilha de apresentação a partir de uma window/qualquer VC.
+ (UIViewController *)topMostControllerFromWindow:(UIWindow *)window;
+ (UIViewController *)topMostController;

// Window key ativa (multi-scene safe).
+ (UIWindow *)activeKeyWindow;

// Apresenta o painel de Settings (UIKit via bridge; fallback nativo).
// `session` é o objeto FBSession do host (pode ser nil).
+ (void)presentSettingsFromView:(UIView *)sourceView session:(id)session;

// Sessão (FBSession) do host, p/ chamadas baseadas em sessão (internal settings).
+ (void)setStoredSession:(id)session;
+ (id)storedSession;
+ (void)showMessage:(NSString *)message title:(NSString *)title;

+ (NSDictionary *)getDictPref:(NSString *)key;
+ (void)setPref:(id)value forKey:(NSString *)key;
+ (UIColor *)FBTColor_Primary;
+ (void)showToastForDuration:(double)duration title:(NSString *)title;
+ (void)showToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle;

@end

#endif /* FBT_UTILS_H */
