#import "FBTUtils.h"
#import "FBTDefaults.h"

// Sessão do host (FBSession), atualizada pelo Tweak.x quando o tab bar aparece.
// Usada pelo opener de "Internal Settings nativo" (Dogfood).
static id gFBTStoredSession = nil;
static BOOL gFBTPresentingSettings = NO;
static char kFBTSettingsPresentationKey;

@implementation FBTUtils

+ (void)setStoredSession:(id)session {
    gFBTStoredSession = session;
}

+ (id)storedSession {
    return gFBTStoredSession;
}

+ (UIWindow *)activeKeyWindow {
    UIWindow *key = nil;
    NSSet *scenes = [UIApplication sharedApplication].connectedScenes;
    for (UIScene *scene in scenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow) { key = w; break; }
        }
        if (key) break;
        if (ws.windows.count) key = ws.windows.firstObject;
    }
    return key;
}

+ (UIViewController *)topMostControllerFromWindow:(UIWindow *)window {
    UIViewController *top = window.rootViewController;
    while (true) {
        if (top.presentedViewController) {
            top = top.presentedViewController;
        } else if ([top isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)top;
            if (nav.topViewController) top = nav.topViewController; else break;
        } else if ([top isKindOfClass:[UITabBarController class]]) {
            UITabBarController *tab = (UITabBarController *)top;
            if (tab.selectedViewController) top = tab.selectedViewController; else break;
        } else {
            break;
        }
    }
    return top;
}

+ (UIViewController *)topMostController {
    return [self topMostControllerFromWindow:[self activeKeyWindow]];
}

+ (UIViewController *)buildSettingsRootController {
    // Caminho primário: painel UIKit via bridge desacoplada (runtime).
    Class bridge = NSClassFromString(@"FBTSettingsBridge");
    if (bridge) {
        SEL sel = NSSelectorFromString(@"makeSettingsController");
        if ([bridge respondsToSelector:sel]) {
            UIViewController *vc =
                ((UIViewController *(*)(id, SEL))objc_msgSend)(bridge, sel);
            if ([vc isKindOfClass:[UIViewController class]]) return vc;
        }
    }
    return nil;
}

+ (void)presentSettingsFromView:(UIView *)sourceView session:(id)session {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self presentSettingsFromView:sourceView session:session]; });
        return;
    }
    if (session) [self setStoredSession:session];

    UIViewController *presenter = [self topMostController];
    if (!presenter || gFBTPresentingSettings || presenter.isBeingDismissed) return;
    for (UIViewController *vc = presenter; vc; vc = vc.parentViewController ?: vc.presentingViewController) {
        if (objc_getAssociatedObject(vc, &kFBTSettingsPresentationKey)) return;
    }

    UIViewController *root = [self buildSettingsRootController];

    if (!root) {
        // Fallback defensivo: bridge UIKit ausente.
        UIAlertController *a =
            [UIAlertController alertControllerWithTitle:@"FBTweak"
                                                message:@"Painel de ajustes indisponível neste build."
                                         preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
        [presenter presentViewController:a animated:YES completion:nil];
        return;
    }

    // O bridge UIKit já retorna um controller pronto (normalmente UINavigationController).
    root.modalPresentationStyle = UIModalPresentationPageSheet;
    objc_setAssociatedObject(root, &kFBTSettingsPresentationKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = root.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[ [UISheetPresentationControllerDetent mediumDetent],
                               [UISheetPresentationControllerDetent largeDetent] ];
            sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
            sheet.prefersGrabberVisible = YES;
            sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
        }
    }

    UIPopoverPresentationController *pop = root.popoverPresentationController;
    if (pop && sourceView) {
        pop.sourceView = sourceView;
        pop.sourceRect = sourceView.bounds;
    }

    gFBTPresentingSettings = YES;
    [presenter presentViewController:root animated:YES completion:^{ gFBTPresentingSettings = NO; }];
}

+ (void)showMessage:(NSString *)message title:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = [self topMostController];
        if (!presenter || [presenter isKindOfClass:[UIAlertController class]]) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

@end
