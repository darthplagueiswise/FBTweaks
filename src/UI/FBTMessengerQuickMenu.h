#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs a native context-menu interaction. On iOS 26 UIKit renders the
/// menu with Liquid Glass and morphs it to/from the targeted source preview.
void FBTMessengerInstallQuickMenuInteraction(UIView *sourceView);

NS_ASSUME_NONNULL_END
