#import "FBTMessengerQuickMenu.h"
#import "FBTUIKit26LiquidGlass.h"
#import "../FBTDefaults.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static char kFBTMessengerContextMenuInteractionKey;

@interface FBTMessengerQuickMenuPresenter : NSObject <UIContextMenuInteractionDelegate>
+ (instancetype)sharedPresenter;
- (UIMenu *)menuForInteraction:(UIContextMenuInteraction *)interaction;
- (UITargetedPreview *)targetedPreviewForInteraction:(UIContextMenuInteraction *)interaction;
@end

@implementation FBTMessengerQuickMenuPresenter

+ (instancetype)sharedPresenter {
    static FBTMessengerQuickMenuPresenter *presenter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        presenter = [FBTMessengerQuickMenuPresenter new];
    });
    return presenter;
}

- (void)setRawBool:(BOOL)value forKey:(NSString *)key {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:key];
}

- (void)toggleKey:(NSString *)key {
    BOOL enabled = ![FBTDefaults boolForKey:key];
    [self setRawBool:enabled forKey:key];

    // These are native dependencies, not visual grouping. Internal Tools is
    // constructed only for an employee that can access Internal Settings;
    // Household is a Homebase subresource in Messenger 574.
    if ([key isEqualToString:FBTKeyMessengerInternalToolsEnabled] && enabled) {
        [self setRawBool:YES forKey:FBTKeyMessengerInternalSettingsEnabled];
        [self setRawBool:YES forKey:FBTKeyEmployeeEnabled];
    } else if ([key isEqualToString:FBTKeyMessengerInternalSettingsEnabled] && enabled) {
        [self setRawBool:YES forKey:FBTKeyEmployeeEnabled];
    } else if ([key isEqualToString:FBTKeyMessengerHouseholdEnabled] && enabled) {
        [self setRawBool:YES forKey:FBTKeyMessengerHomebaseEnabled];
    } else if ([key isEqualToString:FBTKeyEmployeeEnabled] && !enabled) {
        [self setRawBool:NO forKey:FBTKeyMessengerInternalSettingsEnabled];
        [self setRawBool:NO forKey:FBTKeyMessengerInternalToolsEnabled];
    } else if ([key isEqualToString:FBTKeyMessengerInternalSettingsEnabled] && !enabled) {
        [self setRawBool:NO forKey:FBTKeyMessengerInternalToolsEnabled];
    } else if ([key isEqualToString:FBTKeyMessengerHomebaseEnabled] && !enabled) {
        [self setRawBool:NO forKey:FBTKeyMessengerHouseholdEnabled];
    }

    // The observer reloads the atomic hot-path cache synchronously. The
    // persisted value is then available before the next app launch builds
    // Settings and the tab model.
    [FBTDefaults notifyPrefsChanged];

    UISelectionFeedbackGenerator *feedback = [UISelectionFeedbackGenerator new];
    [feedback selectionChanged];
}

- (UIAction *)actionWithTitle:(NSString *)title
                     subtitle:(NSString *)subtitle
                         image:(NSString *)imageName
                           key:(NSString *)key
                   interaction:(UIContextMenuInteraction *)interaction {
    __weak typeof(self) weakSelf = self;
    __weak UIContextMenuInteraction *weakInteraction = interaction;
    UIAction *action = [UIAction actionWithTitle:title
                                          image:[UIImage systemImageNamed:imageName]
                                     identifier:nil
                                        handler:^(__unused UIAction *selectedAction) {
        __strong typeof(weakSelf) self = weakSelf;
        UIContextMenuInteraction *strongInteraction = weakInteraction;
        if (!self) return;
        [self toggleKey:key];
        [strongInteraction updateVisibleMenuWithBlock:^UIMenu *(UIMenu *visibleMenu) {
            (void)visibleMenu;
            return [self menuForInteraction:strongInteraction];
        }];
    }];
    action.subtitle = subtitle;
    action.state = [FBTDefaults boolForKey:key]
        ? UIMenuElementStateOn
        : UIMenuElementStateOff;
    action.attributes = UIMenuElementAttributesKeepsMenuPresented;
    return action;
}

- (UIMenu *)menuForInteraction:(UIContextMenuInteraction *)interaction {
    NSArray<UIMenuElement *> *children = @[
        [self actionWithTitle:@"Employee"
                     subtitle:@"Identidade e gates locais"
                         image:@"person.crop.circle.badge.checkmark"
                           key:FBTKeyEmployeeEnabled
                   interaction:interaction],
        [self actionWithTitle:@"Internal Settings"
                     subtitle:@"Seção interna em Settings"
                         image:@"gearshape.2"
                           key:FBTKeyMessengerInternalSettingsEnabled
                   interaction:interaction],
        [self actionWithTitle:@"Internal Tools"
                     subtitle:@"Debug e user overrides"
                         image:@"wrench.and.screwdriver"
                           key:FBTKeyMessengerInternalToolsEnabled
                   interaction:interaction],
        [self actionWithTitle:@"Homebase"
                     subtitle:@"Aba, mailbox, calendário e listas"
                         image:@"house"
                           key:FBTKeyMessengerHomebaseEnabled
                   interaction:interaction],
        [self actionWithTitle:@"Household"
                     subtitle:@"Subrecurso nativo do Homebase"
                         image:@"person.2"
                           key:FBTKeyMessengerHouseholdEnabled
                   interaction:interaction],
    ];
    UIMenu *menu = [UIMenu menuWithTitle:@"Messenger Flags" children:children];
    menu.subtitle = @"Aplicação imediata nos getters; abas e Settings ao reabrir";
    return menu;
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                         configurationForMenuAtLocation:(__unused CGPoint)location {
    if (![FBTDefaults boolForKey:FBTKeyOpenLongPress]) return nil;
    __weak typeof(self) weakSelf = self;
    __weak UIContextMenuInteraction *weakInteraction = interaction;
    return [UIContextMenuConfiguration
        configurationWithIdentifier:@"com.fbtweaks.messenger.flags"
                     previewProvider:nil
                      actionProvider:^UIMenu *(__unused NSArray<UIMenuElement *> *suggestedActions) {
        __strong typeof(weakSelf) self = weakSelf;
        return self ? [self menuForInteraction:weakInteraction] : nil;
    }];
}

- (UITargetedPreview *)targetedPreviewForInteraction:(UIContextMenuInteraction *)interaction {
    UIView *sourceView = interaction.view;
    UIWindow *window = sourceView.window;
    if (!sourceView || !window) return nil;

    CGRect sourceBounds = sourceView.bounds;
    BOOL compactSource = CGRectGetWidth(sourceBounds) <= 180.0 &&
        CGRectGetHeight(sourceBounds) <= 96.0;
    UIPreviewParameters *parameters = [UIPreviewParameters new];
    parameters.backgroundColor = UIColor.clearColor;

    if (compactSource) {
        CGFloat radius = MIN(CGRectGetWidth(sourceBounds), CGRectGetHeight(sourceBounds)) * 0.32;
        parameters.visiblePath = [UIBezierPath bezierPathWithRoundedRect:sourceBounds
                                                            cornerRadius:MAX(10.0, radius)];
        return [[UITargetedPreview alloc] initWithView:sourceView parameters:parameters];
    }

    // A whole tab bar is too large to be a useful preview. Give UIKit a
    // compact native-glass source at the exact press location instead, so the
    // context menu expands from and collapses back into that glass capsule.
    UIVisualEffectView *glassSource = [[UIVisualEffectView alloc]
        initWithEffect:FBTUIKit26GlassEffect(NO, YES, nil)];
    glassSource.bounds = CGRectMake(0.0, 0.0, 44.0, 44.0);
    glassSource.backgroundColor = UIColor.clearColor;
    glassSource.layer.cornerRadius = 22.0;
    glassSource.layer.cornerCurve = kCACornerCurveContinuous;
    glassSource.clipsToBounds = YES;
    parameters.visiblePath = [UIBezierPath bezierPathWithOvalInRect:glassSource.bounds];

    CGPoint location = [interaction locationInView:sourceView];
    CGPoint targetCenter = [sourceView convertPoint:location toView:window];
    UIPreviewTarget *target = [[UIPreviewTarget alloc]
        initWithContainer:window
                   center:targetCenter
                transform:CGAffineTransformIdentity];
    return [[UITargetedPreview alloc] initWithView:glassSource
                                        parameters:parameters
                                            target:target];
}

- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                                configuration:(__unused UIContextMenuConfiguration *)configuration
       highlightPreviewForItemWithIdentifier:(__unused id<NSCopying>)identifier API_AVAILABLE(ios(16.0)) {
    return [self targetedPreviewForInteraction:interaction];
}

- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                                configuration:(__unused UIContextMenuConfiguration *)configuration
       dismissalPreviewForItemWithIdentifier:(__unused id<NSCopying>)identifier API_AVAILABLE(ios(16.0)) {
    return [self targetedPreviewForInteraction:interaction];
}

@end

void FBTMessengerInstallQuickMenuInteraction(UIView *sourceView) {
    if (!sourceView ||
        objc_getAssociatedObject(sourceView, &kFBTMessengerContextMenuInteractionKey)) {
        return;
    }

    sourceView.userInteractionEnabled = YES;
    UIContextMenuInteraction *interaction = [[UIContextMenuInteraction alloc]
        initWithDelegate:[FBTMessengerQuickMenuPresenter sharedPresenter]];
    [sourceView addInteraction:interaction];
    objc_setAssociatedObject(sourceView,
                             &kFBTMessengerContextMenuInteractionKey,
                             interaction,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
