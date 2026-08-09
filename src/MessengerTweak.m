#import "FBTPrefix.h"
#import "FBTDefaults.h"
#import "Features/Messenger/FBTMessengerFlags.h"

__attribute__((constructor))
static void FBTMessengerConstructor(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier
                isEqualToString:@"com.facebook.Messenger"]) {
            return;
        }
        [FBTDefaults registerDefaultsOnce];
        FBTInstallMessengerFlags();
        FBTLog(@"Messenger ctor done (574 mapped gates)");
    }
}
