// FBTSymbolsBrowserViewController.h
// ABI-aware Mach-O browser for Instagram/FBShared symbols.

#import "FBTBaseSettingsListViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FBTCSymbolsBrowserMode) {
    FBTCSymbolsBrowserModeObjCMethods = 0,
    FBTCSymbolsBrowserModeCFunctions = 1,
    FBTCSymbolsBrowserModeDataParams = 2,
    FBTCSymbolsBrowserModeSwiftDisassembly = 3,
};

@interface FBTSymbolsBrowserViewController : FBTBaseSettingsListViewController <UISearchResultsUpdating>
- (instancetype)initWithMode:(FBTCSymbolsBrowserMode)mode;
@end

NS_ASSUME_NONNULL_END
