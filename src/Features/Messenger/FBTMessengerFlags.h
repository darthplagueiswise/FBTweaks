#import <Foundation/Foundation.h>

/// Installs only the Messenger 574 hooks mapped from the supplied IPA.
/// The function is idempotent and deliberately avoids the Facebook-only
/// classes, imports, runtime browsers and native Internal Settings opener.
void FBTInstallMessengerFlags(void);
