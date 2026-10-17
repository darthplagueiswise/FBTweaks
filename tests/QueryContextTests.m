#import <Foundation/Foundation.h>
#import "../src/Runtime/FBTMobileConfigQueryContext.h"
static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
int main(void) { @autoreleasepool {
    NSObject *owner = [NSObject new];
    FBTMobileConfigQueryContext *old = [FBTMobileConfigQueryContext beginForOwner:owner encodedSearchItem:@"1:fb_daily_games_mc:enable_employee_debug_tool:123:0"];
    Check([old.configName isEqual:@"fb_daily_games_mc"] && [old.paramName isEqual:@"enable_employee_debug_tool"], @"native QE search decoder");
    NSArray *matches = [FBTMobileConfigQueryContext contextsMatchingConfig:old.configName param:old.paramName];
    Check(matches.count == 1 && matches.firstObject == old, @"background lookup matches exact current query");
    Check([FBTMobileConfigQueryContext contextsMatchingConfig:old.configName param:@"different"].count == 0, @"different parameter cannot inherit HTTP error");
    FBTMobileConfigQueryContext *current = [FBTMobileConfigQueryContext beginForOwner:owner encodedSearchItem:@"4:gk:react_native:is_enabled:7:4"];
    for (FBTMobileConfigQueryContext *context in matches) context.httpStatus = 400;
    Check([FBTMobileConfigQueryContext contextForOwner:owner] == current && current.httpStatus == 0, @"late failure cannot replace new selection");
    Check([current.configName isEqual:@"react_native"] && [current.paramName isEqual:@"is_enabled"], @"native parameter decoder");
    dispatch_sync(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSArray *background = [FBTMobileConfigQueryContext contextsMatchingConfig:@"react_native" param:@"is_enabled"];
        Check(background.count == 1, @"selection crosses thread dispatch");
        ((FBTMobileConfigQueryContext *)background.firstObject).httpStatus = 400;
    });
    Check([FBTMobileConfigQueryContext contextForOwner:owner].httpStatus == 400, @"UI sees matched background failure");
    FBTMobileConfigQueryContext *config = [FBTMobileConfigQueryContext beginForOwner:owner encodedSearchItem:@"0:react_native"];
    Check([config.configName isEqual:@"react_native"] && config.paramName.length == 0, @"configuration selection decoder");
    for (id invalid in @[@"1:too_short", @"4:too:short", @"unknown:cfg:param:1", @[@"not_a_native_string"]]) {
        Check([FBTMobileConfigQueryContext beginForOwner:owner encodedSearchItem:invalid] == nil, @"malformed or unknown items refused");
        Check([FBTMobileConfigQueryContext contextForOwner:owner] == nil, @"invalid item clears previous selection");
    }
    NSLog(@"PASS: native item parsing, exact query match, cross-thread error delivery, late-result isolation and invalid input");
} return 0; }
