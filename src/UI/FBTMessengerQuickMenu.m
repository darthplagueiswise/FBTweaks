#import "FBTMessengerQuickMenu.h"
#import "../FBTDefaults.h"
#import <objc/runtime.h>

static char kFBTMessengerContextMenuInteractionKey;

@interface FBTMessengerQuickMenuPresenter : NSObject <UIContextMenuInteractionDelegate>
@property (nonatomic, strong) NSMapTable<UIContextMenuInteraction *, UIView *> *previewSources;
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
        presenter.previewSources = [NSMapTable weakToWeakObjectsMapTable];
    });
    return presenter;
}

- (void)setRawBool:(BOOL)value forKey:(NSString *)key {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:key];
}

- (BOOL)effectiveBoolForKey:(NSString *)key {
    BOOL internalTools = [FBTDefaults boolForKey:FBTKeyMessengerInternalToolsEnabled];
    BOOL internalSettings = internalTools ||
        [FBTDefaults boolForKey:FBTKeyMessengerInternalSettingsEnabled];
    BOOL employee = internalSettings ||
        [FBTDefaults boolForKey:FBTKeyEmployeeEnabled];
    BOOL household = [FBTDefaults boolForKey:FBTKeyMessengerHouseholdEnabled];
    BOOL homebase = household ||
        [FBTDefaults boolForKey:FBTKeyMessengerHomebaseEnabled];

    if ([key isEqualToString:FBTKeyEmployeeEnabled]) return employee;
    if ([key isEqualToString:FBTKeyMessengerInternalSettingsEnabled]) {
        return internalSettings;
    }
    if ([key isEqualToString:FBTKeyMessengerInternalToolsEnabled]) {
        return internalTools;
    }
    if ([key isEqualToString:FBTKeyMessengerHomebaseEnabled]) return homebase;
    if ([key isEqualToString:FBTKeyMessengerHouseholdEnabled]) return household;
    return [FBTDefaults boolForKey:key];
}

- (void)toggleKey:(NSString *)key {
    BOOL enabled = ![self effectiveBoolForKey:key];
    [self setRawBool:enabled forKey:key];

    // Match the dependency graph used by the native consumers. Internal Tools
    // requires Internal Settings + employee identity. Household is a Homebase
    // surface, so its local entry points cannot exist without Homebase.
    if ([key isEqualToString:FBTKeyMessengerInternalToolsEnabled] && enabled) {
        [self setRawBool:YES forKey:FBTKeyMessengerInternalSettingsEnabled];
        [self setRawBool:YES forKey:FBTKeyEmployeeEnabled];
    } else if ([key isEqualToString:FBTKeyMessengerInternalSettingsEnabled] && enabled) {
        [self setRawBool:YES forKey:FBTKeyEmployeeEnabled];
    } else if ([key isEqualToString:FBTKeyEmployeeEnabled] && !enabled) {
        [self setRawBool:NO forKey:FBTKeyMessengerInternalSettingsEnabled];
        [self setRawBool:NO forKey:FBTKeyMessengerInternalToolsEnabled];
    } else if ([key isEqualToString:FBTKeyMessengerInternalSettingsEnabled] && !enabled) {
        [self setRawBool:NO forKey:FBTKeyMessengerInternalToolsEnabled];
    } else if ([key isEqualToString:FBTKeyMessengerHouseholdEnabled] && enabled) {
        [self setRawBool:YES forKey:FBTKeyMessengerHomebaseEnabled];
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
    action.state = [self effectiveBoolForKey:key]
        ? UIMenuElementStateOn
        : UIMenuElementStateOff;
    action.attributes = UIMenuElementAttributesKeepsMenuPresented;
    return action;
}

- (UIMenu *)menuForInteraction:(UIContextMenuInteraction *)interaction {
    NSArray<UIMenuElement *> *children = @[
        [self actionWithTitle:@"Employee"
                     subtitle:@"Identidade + propagação Rage Shake/Bloks"
                         image:@"person.crop.circle.badge.checkmark"
                           key:FBTKeyEmployeeEnabled
                   interaction:interaction],
        [self actionWithTitle:@"Internal Settings"
                     subtitle:@"Gate fb_ford da seção interna"
                         image:@"gearshape.2"
                           key:FBTKeyMessengerInternalSettingsEnabled
                   interaction:interaction],
        [self actionWithTitle:@"Internal Tools"
                     subtitle:@"Labyrinth + EasyGating interno"
                         image:@"wrench.and.screwdriver"
                           key:FBTKeyMessengerInternalToolsEnabled
                   interaction:interaction],
        [self actionWithTitle:@"Homebase"
                     subtitle:@"Aba, mailbox, calendário e listas"
                         image:@"house"
                           key:FBTKeyMessengerHomebaseEnabled
                   interaction:interaction],
        [self actionWithTitle:@"Household"
                     subtitle:@"Homebase + ajustes da conversa"
                         image:@"person.2"
                           key:FBTKeyMessengerHouseholdEnabled
                   interaction:interaction],
    ];
    UIMenu *menu = [UIMenu menuWithTitle:@"Messenger Flags" children:children];
    menu.subtitle = @"Aplicado agora; reabra o Messenger para reconstruir abas/plugins";
    return menu;
}

- (UIView *)previewSourceForInteraction:(UIContextMenuInteraction *)interaction
                               location:(CGPoint)location {
    UIView *interactionView = interaction.view;
    if (!interactionView.window) return nil;

    CGRect bounds = interactionView.bounds;
    BOOL compactInteraction = CGRectGetWidth(bounds) >= 20.0 &&
        CGRectGetHeight(bounds) >= 20.0 &&
        CGRectGetWidth(bounds) <= 180.0 &&
        CGRectGetHeight(bounds) <= 96.0;
    if (compactInteraction) return interactionView;

    // For a full tab bar, target the real control below the finger. UIKit can
    // then lift and morph that existing view. Never manufacture a detached
    // glass capsule: doing so is the extra bubble the user observed.
    UIView *hitView = [interactionView hitTest:location withEvent:nil];
    UIView *deepestCompactView = nil;
    for (UIView *candidate = hitView;
         candidate && candidate != interactionView;
         candidate = candidate.superview) {
        if (candidate.window != interactionView.window ||
            candidate.hidden || candidate.alpha < 0.05) {
            continue;
        }
        CGRect candidateBounds = candidate.bounds;
        BOOL compact = CGRectGetWidth(candidateBounds) >= 20.0 &&
            CGRectGetHeight(candidateBounds) >= 20.0 &&
            CGRectGetWidth(candidateBounds) <= 180.0 &&
            CGRectGetHeight(candidateBounds) <= 96.0;
        if (!compact) continue;
        if (!deepestCompactView) deepestCompactView = candidate;
        if ([candidate isKindOfClass:UIControl.class]) return candidate;
    }
    return deepestCompactView;
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                         configurationForMenuAtLocation:(CGPoint)location {
    if (![FBTDefaults boolForKey:FBTKeyOpenLongPress]) return nil;
    UIView *previewSource = [self previewSourceForInteraction:interaction
                                                     location:location];
    if (previewSource) {
        [self.previewSources setObject:previewSource forKey:interaction];
    } else {
        [self.previewSources removeObjectForKey:interaction];
    }
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
    UIView *sourceView = [self.previewSources objectForKey:interaction];
    if (!sourceView.window) return nil;
    return [[UITargetedPreview alloc] initWithView:sourceView];
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
