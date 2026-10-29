#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSFileManager *realManager;
static NSDictionary<NSString *, NSURL *> *containers;
static NSArray *observedObjects;
static NSArray<NSString *> *groups;
static NSUInteger failures;
static NSUInteger checks;

// Only entitlement-dependent lookup is replaced. Directory/file checks use
// the real filesystem, including an empty preferred directory.
@interface PathFileManager : NSFileManager
@end
@implementation PathFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)identifier {
    return containers[identifier];
}
- (BOOL)fileExistsAtPath:(NSString *)path {
    return [realManager fileExistsAtPath:path];
}
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    return [realManager fileExistsAtPath:path isDirectory:isDirectory];
}
@end

@interface ObservedOverrides : NSObject
@property(nonatomic, copy) NSString *path;
- (NSString *)getOverridesTablePath;
@end
@implementation ObservedOverrides
- (NSString *)getOverridesTablePath { return self.path; }
@end

static NSArray *FBTNativeOverrideObjectsSnapshot(void) { return observedObjects ?: @[]; }
static NSArray<NSString *> *FBTNativeMobileConfigGroupCandidates(void) { return groups ?: @[]; }
#include "resolver.inc"

static void Expect(NSString *actual, NSString *expected, const char *name) {
    ++checks;
    if (actual == expected || [actual isEqualToString:expected]) return;
    ++failures;
    fprintf(stderr, "FAIL %s: got=%s expected=%s\n", name,
        actual.UTF8String ?: "nil", expected.UTF8String ?: "nil");
}
static void MakeDirectory(NSString *path) {
    NSError *error = nil;
    if (![realManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"fixture setup failed: %@", error); exit(2);
    }
}
static void Write(NSString *path) {
    MakeDirectory(path.stringByDeletingLastPathComponent);
    if (![[NSData data] writeToFile:path atomically:YES]) exit(2);
}
static void Remove(NSString *path) { [realManager removeItemAtPath:path error:nil]; }

int main(void) { @autoreleasepool {
    realManager = NSFileManager.defaultManager;
    PathFileManager *fakeManager = [PathFileManager new];
    Method getter = class_getClassMethod(NSFileManager.class, @selector(defaultManager));
    IMP previous = method_setImplementation(getter, imp_implementationWithBlock(^id(id cls) {
        (void)cls; return fakeManager;
    }));
    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *first = [base stringByAppendingPathComponent:@"first"];
    NSString *second = [base stringByAppendingPathComponent:@"second"];
    MakeDirectory(first); MakeDirectory(second);
    groups = @[@"group.fixture.first", @"group.fixture.second"];
    containers = @{groups[0]: [NSURL fileURLWithPath:first], groups[1]: [NSURL fileURLWithPath:second]};
    NSString *rootDirectory = [first stringByAppendingPathComponent:@"mobileconfig"];
    NSString *docsDirectory = [first stringByAppendingPathComponent:@"Documents/mobileconfig"];
    NSString *rootPath = [rootDirectory stringByAppendingPathComponent:@"mc_overrides.json"];
    NSString *docsPath = [docsDirectory stringByAppendingPathComponent:@"mc_overrides.json"];
    NSString *secondPath = [second stringByAppendingPathComponent:@"mobileconfig/mc_overrides.json"];

    @try {
        // A native owner is authoritative even if its file does not exist yet.
        ObservedOverrides *owner = [ObservedOverrides new];
        owner.path = [base stringByAppendingPathComponent:@"actual-owner/mc_overrides.json"];
        observedObjects = @[owner];
        Expect(FBTNativeMobileConfigOverridesFilePath(), owner.path, "observed owner wins");
        observedObjects = @[];

        Write(docsPath);
        Expect(FBTNativeMobileConfigOverridesFilePath(), docsPath, "only Documents directory");
        Write(rootPath);
        Expect(FBTNativeMobileConfigOverridesFilePath(), rootPath, "both copies use native root-first order");
        Remove(rootPath);
        Expect(FBTNativeMobileConfigOverridesFilePath(), rootPath, "empty root directory beats Documents JSON");
        Remove(rootDirectory); Remove(docsDirectory);
        MakeDirectory(rootDirectory);
        Expect(FBTNativeMobileConfigOverridesFilePath(), rootPath, "root directory without a JSON file");
        Write(secondPath);
        Expect(FBTNativeMobileConfigOverridesFilePath(), rootPath, "first container directory beats second container JSON");
        Remove(rootDirectory); Remove(secondPath.stringByDeletingLastPathComponent);
        Expect(FBTNativeMobileConfigOverridesFilePath(), nil, "no native directory means unresolved");
        NSString *unknown = [first stringByAppendingPathComponent:@"AppData/Documents/mobileconfig/mc_overrides.json"];
        Write(unknown);
        Expect(FBTNativeMobileConfigOverridesFilePath(), nil, "export-only AppData tree is not selected");
        // Resolution must remain read-only.
        Expect([realManager fileExistsAtPath:rootDirectory] ? @"created" : nil, nil, "resolver does not create directories");
    } @finally {
        method_setImplementation(getter, previous);
        Remove(base);
    }
    if (failures) return 1;
    printf("PASS override path cases: %lu\n", (unsigned long)checks);
    return 0;
} }
