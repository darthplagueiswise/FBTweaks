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

    // Numeric identity must survive a catalogue alias change in both APIs.
    sPath = [directory stringByAppendingPathComponent:@"fixture_states.json"];
    NSData *stateOriginal = [@"{\n  \"424242:fixture_old_alias\": [\"7: fixture_toggle: true\", \"8: fixture_neighbor: false\"],\n  \"424243:fixture_unrelated\": [\"2: fixture_other: true\"],\n  \"fixture_extra\": {\"keep\": [1, 2]}\n}\n" dataUsingEncoding:NSUTF8StringEncoding];
    Check([stateOriginal writeToFile:sPath atomically:YES], @"write alias fixture");
    Check([FBTMCOverridesFile stateForConfig:@"424242:fixture_new_alias" paramIdx:7] == FBTMCStateOn, @"tri-state lookup uses numeric ID before an edit");
    error = nil;
    Check([FBTMCOverridesFile setState:FBTMCStateOff forConfig:@"424242:fixture_new_alias" paramIdx:7 name:@"fixture_toggle" error:&error] && !error, @"tri-state write reports success through another alias");
    Check([FBTMCOverridesFile stateForConfig:@"424242:fixture_old_alias" paramIdx:7] == FBTMCStateOff &&
          [FBTMCOverridesFile stateForConfig:@"424242:fixture_new_alias" paramIdx:7] == FBTMCStateOff, @"tri-state readback agrees across aliases");
    changed = [FBTMCOverridesFile loadOverrides];
    Check(changed[@"424242:fixture_new_alias"] == nil && [changed[@"424242:fixture_old_alias"] containsObject:@"8: fixture_neighbor: false"], @"tri-state write preserves existing alias and neighbor");
    Check([changed[@"424243:fixture_unrelated"] isEqual:@[@"2: fixture_other: true"]] &&
          [changed[@"fixture_extra"] isEqual:@{@"keep": @[@1, @2]}], @"tri-state write preserves unrelated data");
    NSString *stateBackup = [sPath stringByAppendingString:@".before_local_edit"];
    Check([[NSData dataWithContentsOfFile:stateBackup] isEqual:stateOriginal], @"tri-state backup preserves original bytes including whitespace");
    Check([FBTMCOverridesFile setState:FBTMCStateOn forConfig:@"424242:fixture_new_alias" paramIdx:7 name:@"fixture_toggle"], @"existing tri-state selector returns success");
    Check([FBTMCOverridesFile stateForConfig:@"424242:fixture_new_alias" paramIdx:7] == FBTMCStateOn, @"existing tri-state selector persists selected state");
    Check([FBTMCOverridesFile setState:FBTMCStateSys forConfig:@"424242:fixture_new_alias" paramIdx:7 name:@"fixture_toggle" error:&error], @"SYS removal reports success through another alias");
    Check([FBTMCOverridesFile stateForConfig:@"424242:fixture_new_alias" paramIdx:7] == FBTMCStateSys &&
          [FBTMCOverridesFile stateForConfig:@"424242:fixture_new_alias" paramIdx:8] == FBTMCStateOff, @"SYS removes only the selected numeric parameter");
    Check([[NSData dataWithContentsOfFile:stateBackup] isEqual:stateOriginal], @"subsequent tri-state edits do not replace the first backup");

    NSData *beforeFailure = [NSData dataWithContentsOfFile:sPath];
    NSString *validPath = sPath;
    error = nil;
    Check(![FBTMCOverridesFile setState:FBTMCStateOn forConfig:@"fixture_missing_numeric_id" paramIdx:7 name:@"fixture_toggle" error:&error] && error, @"invalid config key returns an error");
    Check([[NSData dataWithContentsOfFile:sPath] isEqual:beforeFailure], @"invalid config key preserves file bytes");
    sPath = nil; error = nil;
    Check(![FBTMCOverridesFile setState:FBTMCStateOn forConfig:@"424242:fixture_new_alias" paramIdx:7 name:@"fixture_toggle" error:&error] && error, @"unresolved path returns an error");
    Check(![FBTMCOverridesFile setState:FBTMCStateOn forConfig:@"424242:fixture_new_alias" paramIdx:7 name:@"fixture_toggle"], @"existing tri-state selector returns path failure");
    Check([[NSData dataWithContentsOfFile:validPath] isEqual:beforeFailure] &&
          [[NSData dataWithContentsOfFile:stateBackup] isEqual:stateOriginal], @"unresolved path preserves original file and backup bytes");

    NSUInteger invalidIndex = 0;
    for (NSString *invalid in @[@"{broken", @"[]", @"{\"424242:fixture_bad_list\":123}"]) {
        sPath = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"fixture_invalid_%lu.json", (unsigned long)invalidIndex++]];
        NSData *bytes = [invalid dataUsingEncoding:NSUTF8StringEncoding];
        Check([bytes writeToFile:sPath atomically:YES], @"write invalid tri-state fixture");
        error = nil;
        Check(![FBTMCOverridesFile setState:FBTMCStateOn forConfig:@"424242:fixture_new_alias" paramIdx:7 name:@"fixture_toggle" error:&error] && error, @"tri-state write reports invalid JSON or parameter list");
        Check([[NSData dataWithContentsOfFile:sPath] isEqual:bytes], @"failed tri-state write preserves invalid file bytes");
        Check(![NSFileManager.defaultManager fileExistsAtPath:[sPath stringByAppendingString:@".before_local_edit"]], @"failed tri-state write does not create a backup");
    }

    NSString *blockedParent = [directory stringByAppendingPathComponent:@"fixture_parent_file"];
    NSData *parentBytes = [@"fixture parent bytes" dataUsingEncoding:NSUTF8StringEncoding];
    Check([parentBytes writeToFile:blockedParent atomically:YES], @"write blocked-parent fixture");
    sPath = [blockedParent stringByAppendingPathComponent:@"mc_overrides.json"]; error = nil;
    Check(![FBTMCOverridesFile setState:FBTMCStateOn forConfig:@"424242:fixture_new_alias" paramIdx:7 name:@"fixture_toggle" error:&error] && error, @"tri-state write reports directory creation failure");
    Check([[NSData dataWithContentsOfFile:blockedParent] isEqual:parentBytes], @"failed write preserves blocking file bytes");
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
    NSLog(@"PASS: override preservation, backup, alias readback, tri-state errors, string round trip and removal");
} return 0; }
