#import "FBTBundleResources.h"

NSURL *FBTBundleBaseURL(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *bases = @[
        @"/var/jb/Library/Application Support/FBTweak.bundle",
        @"/Library/Application Support/FBTweak.bundle",
        [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"FBTweak.bundle"],
    ];
    for (NSString *path in bases) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            return [NSURL fileURLWithPath:path isDirectory:YES];
        }
    }
    return nil;
}

NSURL *FBTBundleURLForResource(NSString *name, NSString *ext) {
    NSURL *base = FBTBundleBaseURL();
    if (base) {
        NSURL *candidate = [[base URLByAppendingPathComponent:name] URLByAppendingPathExtension:ext ?: @""];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) return candidate;
    }
    return [[NSBundle mainBundle] URLForResource:name withExtension:ext];
}
