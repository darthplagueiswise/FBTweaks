#import "FBTPrefix.h"
#import "FacebookHeaders.h"
#import "FBTDefaults.h"

// =====================================================================
// Floating Tab Bar
// Força os getters de estado "floating" a retornarem YES. Getters BOOL
// sem args (ABI trivial) confirmados em:
//   FBTabBarAndContentViewController -isTabBarFloating
//   FBTabBarAndContentView           -isTabBarFloating
//   FBTabBar                         -isFloating
// Nota: existe a função C FBTabBarDefaultFloatingStyle (in-image, NÃO
// importada pelo exec). Não usamos fishhook nela (fishhook só troca
// imports/GOT) e evitamos MSHookFunction por dlsym instável em símbolo
// interno de framework; os getters acima já controlam o estado visível.
// =====================================================================

%group FBTFloatingTabBar

%hook FBTabBarAndContentViewController
- (BOOL)isTabBarFloating {
    if ([FBTDefaults boolForKey:FBTKeyFloatingTabBarEnabled]) return YES;
    return %orig;
}
%end

%hook FBTabBarAndContentView
- (BOOL)isTabBarFloating {
    if ([FBTDefaults boolForKey:FBTKeyFloatingTabBarEnabled]) return YES;
    return %orig;
}
%end

%hook FBTabBar
- (BOOL)isFloating {
    if ([FBTDefaults boolForKey:FBTKeyFloatingTabBarEnabled]) return YES;
    return %orig;
}
%end

%end // FBTFloatingTabBar

void FBTInitFloatingTabBarGroup(void) {
    %init(FBTFloatingTabBar);
}
