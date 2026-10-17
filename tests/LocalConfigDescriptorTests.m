#import <Foundation/Foundation.h>
#import "../src/Runtime/FBTLocalConfigCatalog.h"
#import "../src/Runtime/FBTFlagCatalog.h"

const uint64_t fbt_fixture_descriptor[] = {
    ((uint64_t)0x0041 << 48) | ((uint64_t)7 << 32) | ((uint64_t)2 << 16) | 3,
    ((uint64_t)0x0042 << 48) | ((uint64_t)7 << 32) | ((uint64_t)5 << 16) | 4
};
@implementation FBTFlagCatalog
+ (NSURL *)bundleURLForResource:(NSString *)name extension:(NSString *)extension { return nil; }
@end
static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
int main(void) { @autoreleasepool {
    NSDictionary *parameter = @{@"id": @2, @"type": @"bool", @"slot": @9};
    NSMutableDictionary *config = [@{@"name": @"fbt_fixture_descriptor", @"source": @"params_map.txt", @"ordinal": @7, @"params": @[parameter, @{}]} mutableCopy];
    NSNumber *key = [FBTLocalConfigCatalog packedKeyForConfiguration:config parameter:parameter];
    Check(key && key.unsignedLongLongValue == fbt_fixture_descriptor[0], @"compiled key preserved despite different map slot");
    config[@"ordinal"] = @8;
    Check(![FBTLocalConfigCatalog packedKeyForConfiguration:config parameter:parameter], @"wrong native ordinal rejected");
    config[@"ordinal"] = @7;
    Check(![FBTLocalConfigCatalog packedKeyForConfiguration:config parameter:@{@"id": @2, @"type": @"int64", @"slot": @3}], @"wrong parameter type rejected");
    Check(![FBTLocalConfigCatalog packedKeyForConfiguration:config parameter:@{@"id": @8, @"type": @"bool", @"slot": @3}], @"missing parameter rejected");
    config[@"source"] = @"params_map_kMobileConfigAdminId.txt";
    Check(![FBTLocalConfigCatalog packedKeyForConfiguration:config parameter:parameter], @"different universe rejected");
    config[@"source"] = @"rn_params_map.txt";
    Check(![FBTLocalConfigCatalog packedKeyForConfiguration:config parameter:parameter], @"RN slot not treated as native key");
    config[@"source"] = @"params_map.txt"; config[@"name"] = @"symbol_not_available";
    Check(![FBTLocalConfigCatalog packedKeyForConfiguration:config parameter:parameter], @"missing export rejected");
    NSLog(@"PASS: 7 compiled descriptor validation checks");
} return 0; }
