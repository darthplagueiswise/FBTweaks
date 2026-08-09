#import "FBTMessengerQuickMenu.h"
#import "FBTUIKit26LiquidGlass.h"
#import "../FBTDefaults.h"
#import <objc/runtime.h>

static const void *kFBTMessengerSwitchKey = &kFBTMessengerSwitchKey;

@interface FBTMessengerQuickMenuPresenter : NSObject
@property (nonatomic, strong) UIControl *backdrop;
@property (nonatomic, strong) FBTUIKit26GlassPanelView *panel;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UISwitch *> *switches;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) CGPoint sourcePointInWindow;
+ (instancetype)sharedPresenter;
- (void)presentFromView:(UIView *)sourceView sourcePoint:(CGPoint)sourcePoint;
@end

static UIWindow *FBTMessengerActiveWindow(UIView *sourceView) {
    if (sourceView.window) return sourceView.window;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) return window;
            }
            for (UIWindow *window in windowScene.windows) {
                if (!window.hidden && window.alpha > 0.0) return window;
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
}

static UILabel *FBTMessengerLabel(CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFontMetrics.defaultMetrics scaledFontForFont:
                  [UIFont systemFontOfSize:size weight:weight]];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    return label;
}

@implementation FBTMessengerQuickMenuPresenter

+ (instancetype)sharedPresenter {
    static FBTMessengerQuickMenuPresenter *presenter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        presenter = [FBTMessengerQuickMenuPresenter new];
    });
    return presenter;
}

- (UIView *)rowWithTitle:(NSString *)title
                subtitle:(NSString *)subtitle
                     key:(NSString *)key {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:50.0].active = YES;

    UILabel *titleLabel = FBTMessengerLabel(15.0, UIFontWeightSemibold, UIColor.labelColor);
    titleLabel.text = title;

    UILabel *subtitleLabel = FBTMessengerLabel(11.5, UIFontWeightRegular, UIColor.secondaryLabelColor);
    subtitleLabel.text = subtitle;
    subtitleLabel.numberOfLines = 1;
    subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[ titleLabel, subtitleLabel ]];
    labels.translatesAutoresizingMaskIntoConstraints = NO;
    labels.axis = UILayoutConstraintAxisVertical;
    labels.spacing = 1.0;

    UISwitch *toggle = [UISwitch new];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.onTintColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
    toggle.accessibilityLabel = title;
    objc_setAssociatedObject(toggle, kFBTMessengerSwitchKey, key,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    self.switches[key] = toggle;

    UIView *separator = [UIView new];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = FBTUIKit26SeparatorColor();

    [row addSubview:labels];
    [row addSubview:toggle];
    [row addSubview:separator];
    [NSLayoutConstraint activateConstraints:@[
        [labels.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16.0],
        [labels.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [labels.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-12.0],
        [toggle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14.0],
        [toggle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [separator.leadingAnchor constraintEqualToAnchor:labels.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14.0],
        [separator.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    ]];
    return row;
}

- (void)buildInWindow:(UIWindow *)window {
    self.switches = [NSMutableDictionary dictionary];

    UIControl *backdrop = [UIControl new];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    backdrop.backgroundColor = UIColor.clearColor;
    backdrop.accessibilityViewIsModal = YES;
    [backdrop addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:backdrop];
    [NSLayoutConstraint activateConstraints:@[
        [backdrop.topAnchor constraintEqualToAnchor:window.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:window.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:window.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:window.bottomAnchor],
    ]];

    FBTUIKit26GlassPanelView *panel = [[FBTUIKit26GlassPanelView alloc] initWithRadius:28.0];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.fbtGlassInteractive = YES;
    panel.fbtGlassClearStyle = NO;
    [panel applyLiquidGlassStyle];
    [backdrop addSubview:panel];

    UIView *header = [UIView new];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [header.heightAnchor constraintEqualToConstant:61.0].active = YES;

    UIImageView *glyph = [[UIImageView alloc] initWithImage:
                          [UIImage systemImageNamed:@"slider.horizontal.3"]];
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    glyph.tintColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
    glyph.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *title = FBTMessengerLabel(17.0, UIFontWeightBold, UIColor.labelColor);
    title.text = @"Messenger Flags";

    UILabel *subtitle = FBTMessengerLabel(11.5, UIFontWeightRegular, UIColor.secondaryLabelColor);
    subtitle.text = @"Gates locais mapeados no Messenger 574";

    UIStackView *headerLabels = [[UIStackView alloc] initWithArrangedSubviews:@[ title, subtitle ]];
    headerLabels.translatesAutoresizingMaskIntoConstraints = NO;
    headerLabels.axis = UILayoutConstraintAxisVertical;
    headerLabels.spacing = 1.0;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = UIColor.secondaryLabelColor;
    close.accessibilityLabel = @"Fechar";
    [close addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];

    [header addSubview:glyph];
    [header addSubview:headerLabels];
    [header addSubview:close];
    [NSLayoutConstraint activateConstraints:@[
        [glyph.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [glyph.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [glyph.widthAnchor constraintEqualToConstant:24.0],
        [glyph.heightAnchor constraintEqualToConstant:24.0],
        [headerLabels.leadingAnchor constraintEqualToAnchor:glyph.trailingAnchor constant:11.0],
        [headerLabels.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [headerLabels.trailingAnchor constraintLessThanOrEqualToAnchor:close.leadingAnchor constant:-8.0],
        [close.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-10.0],
        [close.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:38.0],
        [close.heightAnchor constraintEqualToConstant:38.0],
    ]];

    UIView *employee = [self rowWithTitle:@"Employee"
                                  subtitle:@"Força isEmployee somente no cliente"
                                       key:FBTKeyEmployeeEnabled];
    UIView *internalSettings = [self rowWithTitle:@"Internal Settings"
                                          subtitle:@"Libera a seção nativa de configurações"
                                               key:FBTKeyMessengerInternalSettingsEnabled];
    UIView *internalTools = [self rowWithTitle:@"Internal Tools"
                                       subtitle:@"Ativa os provedores de debug validados"
                                            key:FBTKeyMessengerInternalToolsEnabled];
    UIView *homebase = [self rowWithTitle:@"Homebase"
                                 subtitle:@"Mailbox, aba, calendário, listas e thread"
                                      key:FBTKeyMessengerHomebaseEnabled];
    UIView *household = [self rowWithTitle:@"Household"
                                  subtitle:@"Subrecurso acoplado ao Homebase neste build"
                                       key:FBTKeyMessengerHouseholdEnabled];

    self.statusLabel = FBTMessengerLabel(11.5, UIFontWeightMedium, UIColor.secondaryLabelColor);
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.text = @"Reabra o Messenger para reconstruir abas e Settings.";

    UIView *footer = [UIView new];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [footer.heightAnchor constraintGreaterThanOrEqualToConstant:46.0].active = YES;
    [footer addSubview:self.statusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:16.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-16.0],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
    ]];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        header, employee, internalSettings, internalTools, homebase, household, footer
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0.0;
    [panel.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:panel.contentView.bottomAnchor],
        [panel.centerXAnchor constraintEqualToAnchor:backdrop.centerXAnchor],
        [panel.leadingAnchor constraintGreaterThanOrEqualToAnchor:backdrop.leadingAnchor constant:18.0],
        [panel.trailingAnchor constraintLessThanOrEqualToAnchor:backdrop.trailingAnchor constant:-18.0],
        [panel.widthAnchor constraintLessThanOrEqualToConstant:372.0],
        [panel.bottomAnchor constraintEqualToAnchor:backdrop.safeAreaLayoutGuide.bottomAnchor constant:-16.0],
    ]];
    NSLayoutConstraint *preferredWidth =
        [panel.widthAnchor constraintEqualToAnchor:backdrop.widthAnchor constant:-36.0];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    preferredWidth.active = YES;

    self.backdrop = backdrop;
    self.panel = panel;
    [self refreshSwitches];
}

- (void)refreshSwitches {
    [self.switches enumerateKeysAndObjectsUsingBlock:
     ^(NSString *key, UISwitch *toggle, __unused BOOL *stop) {
        [toggle setOn:[FBTDefaults boolForKey:key] animated:YES];
    }];
}

- (void)setRawBool:(BOOL)value forKey:(NSString *)key {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:key];
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, kFBTMessengerSwitchKey);
    if (!key.length) return;

    BOOL enabled = sender.isOn;
    [self setRawBool:enabled forKey:key];

    // Keep the native dependency chain explicit in the UI. Tools require the
    // Internal Settings section and employee identity; Household is rendered
    // by Homebase and has no independent boolean descriptor in this build.
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

    [FBTDefaults notifyPrefsChanged];
    [self refreshSwitches];
    self.statusLabel.text = @"Aplicado aos hooks; reabra para reconstruir abas e Settings.";

    UISelectionFeedbackGenerator *feedback = [UISelectionFeedbackGenerator new];
    [feedback selectionChanged];
}

- (CGAffineTransform)transformTowardSourceWithScale:(CGFloat)scale amount:(CGFloat)amount {
    CGPoint panelCenter = self.panel.center;
    CGFloat dx = (self.sourcePointInWindow.x - panelCenter.x) * amount;
    CGFloat dy = (self.sourcePointInWindow.y - panelCenter.y) * amount;
    CGAffineTransform transform = CGAffineTransformMakeTranslation(dx, dy);
    return CGAffineTransformScale(transform, scale, scale);
}

- (void)presentFromView:(UIView *)sourceView sourcePoint:(CGPoint)sourcePoint {
    if (self.backdrop.superview) return;
    UIWindow *window = FBTMessengerActiveWindow(sourceView);
    if (!window) return;

    [self buildInWindow:window];
    self.sourcePointInWindow = [sourceView convertPoint:sourcePoint toView:window];
    [window layoutIfNeeded];

    self.backdrop.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.0];
    self.panel.alpha = 0.0;
    self.panel.transform = [self transformTowardSourceWithScale:0.78 amount:0.42];

    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];

    [UIView animateWithDuration:0.40
                          delay:0.0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.35
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.backdrop.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.22];
        self.panel.alpha = 1.0;
        self.panel.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismiss {
    if (!self.backdrop.superview) return;
    [UIView animateWithDuration:0.20
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn |
                                UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.backdrop.backgroundColor = UIColor.clearColor;
        self.panel.alpha = 0.0;
        self.panel.transform = [self transformTowardSourceWithScale:0.84 amount:0.30];
    } completion:^(__unused BOOL finished) {
        [self.backdrop removeFromSuperview];
        self.backdrop = nil;
        self.panel = nil;
        self.switches = nil;
        self.statusLabel = nil;
    }];
}

@end

void FBTMessengerPresentQuickMenu(UIView *sourceView, CGPoint sourcePoint) {
    if (!sourceView) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[FBTMessengerQuickMenuPresenter sharedPresenter]
            presentFromView:sourceView
                 sourcePoint:sourcePoint];
    });
}
