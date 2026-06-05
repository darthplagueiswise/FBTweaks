#import <Foundation/Foundation.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"

static const uint64_t kSlots[] = {162,192,292,551,818,876,1248,1264,1708,2028,4124,4623};
extern "C" BOOL FBGRDogFoodIsEnabled(void) { return FBGRPref(@"fbgr_dogfood_master"); }
extern "C" void FBGRDogFoodSetEnabled(BOOL enabled) {
    [FBGRPrefs() setBool:enabled forKey:@"fbgr_dogfood_master"];
    [FBGRPrefs() synchronize];
    for (NSUInteger i=0;i<sizeof(kSlots)/sizeof(kSlots[0]);i++) enabled ? FBGRGateSet(kSlots[i], YES) : FBGRGateClear(kSlots[i]);
}
extern "C" BOOL FBGRDogFoodPresentNagSheet(void) { return NO; }
extern "C" NSString *FBGRDogFoodDiagnostic(void) { return @"DogFood preset is applied through real MobileConfig slot overrides. Native nag sheet is intentionally not instantiated."; }
