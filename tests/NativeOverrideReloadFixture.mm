#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <memory>
#include <cstring>

namespace mobileconfig { class FBMobileConfigManager {}; class FBMobileConfigOverridesTable {}; }
@protocol FBTMCNativeManagerGetter <NSObject>
- (std::shared_ptr<mobileconfig::FBMobileConfigManager>)getCurrentManager;
- (std::shared_ptr<mobileconfig::FBMobileConfigManager>)configManager;
@end
typedef std::shared_ptr<mobileconfig::FBMobileConfigOverridesTable> (*ReloadFn)(mobileconfig::FBMobileConfigManager *, bool);
static ReloadFn sGetOrCreateTable;
static BOOL FBTResolveNativeSymbols(void) { return sGetOrCreateTable != nullptr; }
#include "reload.inc"

static unsigned calls;
static bool forceSeen, emptyManager, emptyTable, throwCPP;
static std::shared_ptr<mobileconfig::FBMobileConfigManager> manager;
static std::shared_ptr<mobileconfig::FBMobileConfigManager> GetManager(id, SEL) {
    return emptyManager ? nullptr : manager;
}
static std::shared_ptr<mobileconfig::FBMobileConfigOverridesTable> Reload(mobileconfig::FBMobileConfigManager *m, bool force) {
    if (m != manager.get()) abort();
    ++calls; forceSeen = force;
    if (throwCPP) throw 42;
    return emptyTable ? nullptr : std::make_shared<mobileconfig::FBMobileConfigOverridesTable>();
}
@interface ReloadOwner : NSObject @end
@implementation ReloadOwner @end
static void Check(BOOL ok, NSString *name) { if (!ok) { NSLog(@"FAIL %@", name); exit(1); } }
int main() { @autoreleasepool {
    const char *abi = "{shared_ptr<mobileconfig::FBMobileConfigManager>=^{FBMobileConfigManager}^{__shared_weak_count}}16@0:8";
    class_addMethod(ReloadOwner.class, @selector(getCurrentManager), (IMP)GetManager, abi);
    id owner = [ReloadOwner new]; NSString *reason = nil;
    Check(!FBTNativeMobileConfigReloadOverridesForContext(nil, &reason) && reason.length, @"nil context refused");
    Check(!FBTNativeMobileConfigReloadOverridesForContext(owner, &reason) && reason.length, @"missing symbol refused");
    sGetOrCreateTable = Reload;
    Check(!FBTNativeMobileConfigReloadOverridesForContext([NSObject new], &reason) && calls == 0, @"missing ABI never invoked");
    manager = std::make_shared<mobileconfig::FBMobileConfigManager>(); emptyManager = true;
    Check(!FBTNativeMobileConfigReloadOverridesForContext(owner, &reason) && calls == 0, @"empty manager refused");
    emptyManager = false;
    Check(FBTNativeMobileConfigReloadOverridesForContext(owner, &reason) && calls == 1 && forceSeen && !reason, @"real bridge invokes force true with owning manager");
    emptyTable = true;
    Check(!FBTNativeMobileConfigReloadOverridesForContext(owner, &reason) && reason.length, @"empty returned table refused");
    emptyTable = false; throwCPP = true;
    Check(!FBTNativeMobileConfigReloadOverridesForContext(owner, &reason) && reason.length, @"C++ exception refused");
    throwCPP = false;
    Check(FBTNativeMobileConfigReloadOverridesForContext(owner, &reason) && !reason, @"later reload recovers");
    NSLog(@"PASS native override reload bridge");
} }
