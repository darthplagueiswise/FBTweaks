#import <Foundation/Foundation.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"

static const uint64_t kDogFoodSlots[] = {162, 192, 292, 551, 818, 876, 1248, 1264, 1708, 2028, 4124, 4623};

extern "C" BOOL FBGRDogFoodIsEnabled(void) { return FBGRPref(@"fbgr_dogfood_master"); }

extern "C" void FBGRDogFoodSetEnabled(BOOL enabled) {
    [FBGRPrefs() setBool:enabled forKey:@"fbgr_dogfood_master"];
    [FBGRPrefs() synchronize];
    for (NSUInteger i = 0; i < sizeof(kDogFoodSlots)/sizeof(kDogFoodSlots[0]); i++) {
        if (enabled) FBGRGateSet(kDogFoodSlots[i], YES);
        else FBGRGateClear(kDogFoodSlots[i]);
    }
}

extern "C" NSString *FBGRDogFoodDiagnostic(void) {
    return @"DogFood preset applies known MC bool slot overrides and then requires MC hooks.";
}
