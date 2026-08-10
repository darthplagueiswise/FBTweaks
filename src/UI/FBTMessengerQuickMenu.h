#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs a native context-menu interaction. UIKit owns the iOS 26 Liquid
/// Glass presentation and morphs from the real Messenger view under the press.
void FBTMessengerInstallQuickMenuInteraction(UIView *sourceView);

NS_ASSUME_NONNULL_END
