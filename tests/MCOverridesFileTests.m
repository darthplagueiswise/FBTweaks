#import <Foundation/Foundation.h>
#import "../src/Runtime/FBTMCOverridesFile.h"
static NSString *sPath;
NSString *FBTNativeMobileConfigOverridesFilePath(void) { return sPath; }
static void Check(BOOL result, NSString *message) { if (!result) { NSLog(@"FAIL: %@", message); exit(1); } }
int main(void) { @autoreleasepool {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    sPath = [directory stringByAppendingPathComponent:@"mc_overrides.json"];
    NSDictionary *original = @{@"18396:old_alias": @[@"1: untouched: true", @"236: skip_override_import: true", @"garbage: preserved: false"],
        @"QE": @[@"experiment_a", @"experiment_b"], @"other": @{ @"nested": @[@1,@2] }};
    NSData *initial = [NSJSONSerialization dataWithJSONObject:original options:0 error:nil];
    [initial writeToFile:sPath atomically:YES];
    NSError *error = nil;
    Check([FBTMCOverridesFile setValueText:@"false" forConfigID:18396 paramIdx:236 configName:@"new_alias" paramName:@"skip_override_import" error:&error], @"write existing ID");
    NSDictionary *changed = [FBTMCOverridesFile loadOverrides];
    Check([changed[@"QE"] isEqual:original[@"QE"]] && [changed[@"other"] isEqual:original[@"other"]], @"unrelated QE and arbitrary data preserved");
    Check(changed[@"18396:new_alias"] == nil && [changed[@"18396:old_alias"] containsObject:@"1: untouched: true"], @"existing alias and other parameters preserved");
    Check([changed[@"18396:old_alias"] containsObject:@"garbage: preserved: false"], @"malformed parameter prefix preserved");
    Check([[NSData dataWithContentsOfFile:[sPath stringByAppendingString:@".before_local_edit"]] isEqual:initial], @"backup exact original bytes");
    Check([FBTMCOverridesFile setValueText:@"a:b: true" forConfigID:18396 paramIdx:0 configName:@"ignored" paramName:@"text" error:&error], @"string with colons");
    Check([[FBTMCOverridesFile valueTextForConfigID:18396 paramIdx:0] isEqual:@"a:b: true"], @"string round trip");
    Check([FBTMCOverridesFile setValueText:nil forConfigID:18396 paramIdx:236 configName:@"ignored" paramName:@"skip_override_import" error:&error], @"remove parameter");
    Check([FBTMCOverridesFile valueTextForConfigID:18396 paramIdx:236] == nil, @"SYS removes only selected override");
    for (NSString *invalid in @[@"{broken", @"[]", @"{\"18396:wrong\":123}"]) {
        NSData *bytes = [invalid dataUsingEncoding:NSUTF8StringEncoding]; [bytes writeToFile:sPath atomically:YES]; error = nil;
        Check(![FBTMCOverridesFile setValueText:@"true" forConfigID:18396 paramIdx:0 configName:@"cfg" paramName:@"param" error:&error], @"invalid input rejected");
        Check([[NSData dataWithContentsOfFile:sPath] isEqual:bytes], @"invalid file never overwritten");
    }
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
    NSLog(@"PASS: override preservation, backup, string round trip, removal and invalid-file rejection");
} return 0; }
