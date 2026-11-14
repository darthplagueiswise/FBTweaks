#import <Foundation/Foundation.h>

// Native owners expose a file NSURL for the directory. Older callers may
// already supply the complete filename as an NSString or file NSURL.
NS_INLINE NSString * _Nullable FBTMCOverridesPathForNativeLocation(id _Nullable location) {
    NSString *path = nil;
    if ([location isKindOfClass:NSURL.class]) {
        if (![location isFileURL]) return nil;
        path = [location path];
    } else if ([location isKindOfClass:NSString.class]) {
        path = location;
    }
    if (!path.length || !path.isAbsolutePath) return nil;
    if ([path.lastPathComponent isEqualToString:@"mc_overrides.json"]) return path;
    return [path stringByAppendingPathComponent:@"mc_overrides.json"];
}
