#import <Foundation/Foundation.h>
#include <pthread.h>
#include <string.h>
#include <stdlib.h>

static BOOL forceEmployee;
static BOOL observe;
static BOOL observedGetterOriginal;
static BOOL observedGetterEffective;
static BOOL observedSetterInput;
static BOOL observedSetterEffective;
static BOOL FBTEmployeeIdentityOn(void) { return forceEmployee; }
static BOOL FBTEmployeeDiagnosticsShouldObserve(void) { return observe; }
static void FBTEmployeeObserveBool(NSString *source, BOOL original, BOOL effective, const void *caller) {
    (void)caller;
    if (!observe) return;
    if ([source isEqualToString:@"FBUserPreferences.isEmployee"]) {
        observedGetterOriginal = original;
        observedGetterEffective = effective;
    } else if ([source isEqualToString:@"FBUserPreferences.setEmployee.input"]) {
        observedSetterInput = original;
        observedSetterEffective = effective;
    }
}
static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL %@", message); exit(1); }
}

@interface FBTEmployeeFixture : NSObject {
    NSString *_domain;
}
@property(nonatomic) NSUInteger writes;
@property(nonatomic) BOOL reenter;
@property(nonatomic) BOOL failNextWrite;
@property(nonatomic, strong) FBTEmployeeFixture *nestedPreferences;
- (instancetype)initWithDomain:(NSString *)domain;
- (BOOL)storedEmployee;
- (BOOL)originalIsEmployee;
- (void)originalSetEmployee:(BOOL)value;
- (BOOL)isEmployee;
- (void)setEmployee:(BOOL)value;
@end
@implementation FBTEmployeeFixture
@synthesize writes = _writes, reenter = _reenter, failNextWrite = _failNextWrite;
- (instancetype)initWithDomain:(NSString *)domain {
    if ((self = [super init])) _domain = [domain copy];
    return self;
}
- (BOOL)storedEmployee {
    return [[[[NSUserDefaults standardUserDefaults] persistentDomainForName:_domain]
             objectForKey:@"employee"] boolValue];
}
- (BOOL)originalIsEmployee { return [self storedEmployee]; }
- (void)originalSetEmployee:(BOOL)value {
    self.writes++;
    if (self.failNextWrite) {
        self.failNextWrite = NO;
        [NSException raise:@"FixtureWriteFailure" format:@"one failed native write"];
    }
    if (self.nestedPreferences) {
        FBTEmployeeFixture *nested = self.nestedPreferences;
        self.nestedPreferences = nil;
        Check([nested isEmployee], @"nested account getter remains forced");
    }
    if (self.reenter) { self.reenter = NO; Check([self isEmployee], @"reentrant forced read"); }
    NSDictionary *domain = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:value] forKey:@"employee"];
    [[NSUserDefaults standardUserDefaults] setPersistentDomain:domain forName:_domain];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
/* PRODUCTION_PREFERENCE_METHODS */
@end

static void *ReadMany(void *value) {
    @autoreleasepool {
        FBTEmployeeFixture *prefs = (__bridge FBTEmployeeFixture *)value;
        for (NSUInteger i = 0; i < 20; i++) Check([prefs isEmployee], @"concurrent read");
    }
    return NULL;
}
int main(int argc, const char **argv) { @autoreleasepool {
    Check(argc == 2, @"one test case required");
    NSString *root = [@"FBTEmployeeFixture." stringByAppendingString:[[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *other = [root stringByAppendingString:@".other"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removePersistentDomainForName:root];
    [defaults removePersistentDomainForName:other];
    FBTEmployeeFixture *prefs = [[FBTEmployeeFixture alloc] initWithDomain:root];
    forceEmployee = YES;
    if (!strcmp(argv[1], "persist")) {
        Check([prefs isEmployee], @"forced getter returns true");
        FBTEmployeeFixture *reopened = [[FBTEmployeeFixture alloc] initWithDomain:root];
        Check([reopened storedEmployee], @"forced getter must persist employee in native store");
        Check(prefs.writes == 1, @"one native setter write");
    } else if (!strcmp(argv[1], "repeat")) {
        pthread_t threads[4];
        for (NSUInteger i=0;i<4;i++) Check(!pthread_create(&threads[i], NULL, ReadMany, (__bridge void *)prefs), @"thread starts");
        for (NSUInteger i=0;i<4;i++) pthread_join(threads[i], NULL);
        Check([prefs storedEmployee] && prefs.writes == 1, @"reads persist once per false preference");
    } else if (!strcmp(argv[1], "accounts")) {
        FBTEmployeeFixture *second = [[FBTEmployeeFixture alloc] initWithDomain:other];
        Check([prefs isEmployee] && [prefs storedEmployee], @"first account persists");
        Check(![second storedEmployee], @"first read must not write another account");
        Check([second isEmployee] && [second storedEmployee], @"second account persists independently");
    } else if (!strcmp(argv[1], "nested")) {
        FBTEmployeeFixture *second = [[FBTEmployeeFixture alloc] initWithDomain:other];
        prefs.nestedPreferences = second;
        second.nestedPreferences = prefs;
        Check([prefs isEmployee], @"cyclic account callback returns");
        Check([prefs storedEmployee] && [second storedEmployee], @"nested accounts both persist");
        Check(prefs.writes == 1 && second.writes == 1, @"cycle does not repeat either setter");
    } else if (!strcmp(argv[1], "disabled")) {
        forceEmployee = NO;
        Check(![prefs isEmployee] && prefs.writes == 0, @"disabled getter is read-only");
        [prefs originalSetEmployee:YES];
        Check([prefs isEmployee] && prefs.writes == 1, @"disabled preserves native true");
    } else if (!strcmp(argv[1], "reentry")) {
        prefs.reenter = YES;
        Check([prefs isEmployee] && [prefs storedEmployee] && prefs.writes == 1, @"setter reentry writes once");
    } else if (!strcmp(argv[1], "exception")) {
        prefs.failNextWrite = YES;
        BOOL raised = NO;
        @try { (void)[prefs isEmployee]; }
        @catch (NSException *error) { raised = [error.name isEqualToString:@"FixtureWriteFailure"]; }
        Check(raised && ![prefs storedEmployee], @"failed write propagates and does not persist");
        Check([prefs isEmployee] && [prefs storedEmployee] && prefs.writes == 2, @"later read retries after exception");
    } else if (!strcmp(argv[1], "diagnostics")) {
        observe = YES;
        Check([prefs isEmployee] && !observedGetterOriginal && observedGetterEffective, @"pre-write getter observation preserved");
        [prefs setEmployee:NO];
        Check(!observedSetterInput && observedSetterEffective && [prefs storedEmployee], @"server false input is observed and forced before persistence");
    } else Check(NO, @"unknown case");
    [defaults removePersistentDomainForName:root];
    [defaults removePersistentDomainForName:other];
    [defaults synchronize];
    NSLog(@"PASS %s", argv[1]);
} return 0; }
