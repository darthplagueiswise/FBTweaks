#import <Foundation/Foundation.h>
#import "../src/Runtime/FBTNetworkInspectorStore.h"

static int checks = 0;
static void Assert(BOOL ok, NSString *why) {
    if (!ok) { NSLog(@"FAIL: %@", why); exit(1); }
    checks++;
}
static NSData *UTF8(NSString *value) { return [value dataUsingEncoding:NSUTF8StringEncoding]; }
int main(void) { @autoreleasepool {
    FBTNetworkInspectorSetCapturing(NO);
    FBTNetworkInspectorClear();
    Assert(!FBTNetworkInspectorIsCapturing(), @"disabled at launch");
    FBTNetworkInspectorRecordRequest(@{@"request_id": @1, @"capture_reason": @"mobileconfig_qe_info"},
        @[@{@"name": @"access_token", @"value": @"secret-example"}]);
    Assert(FBTNetworkInspectorSummaries().count == 0, @"disabled means no capture");

    FBTNetworkInspectorSetCapturing(YES);
    NSString *literal = @"{\"error\":{\"code\":100,\"type\":\"OAuthException\"}}";
    NSData *response = UTF8(literal);
    FBTNetworkInspectorRecordRequest(@{@"request_id": @4,
        @"capture_reason": @"mobileconfig_qe_info",
        @"request_method": @"POST",
        @"request_param_count": @2,
        @"tigon_service_snapshot": @"{\"state\":\"observed\"}",
        @"inspector_routing_hint": @"development"},
        @[@{@"name": @"api_version", @"value": @"1"},
          @{@"name": @"access_token", @"value": @"secret-example"}]);
    FBTNetworkInspectorRecordTigon(@{@"request_id": @4, @"http_status": @400,
        @"http_status_source": @"verified_tigon_response_status",
        @"inspector_headers": @{@"Authorization": @"Bearer secret-example"},
        @"inspector_raw_path": @"/method"},
        response);
    FBTNetworkInspectorRecordCompletion(@{@"request_id": @4,
        @"native_transport_success": @NO,
        @"http_status": @400,
        @"payload_provenance": @"native_formatted_transport_error"},
        UTF8(@"None domain: FBHTTPErrorDomain code: 400 detail: "));
    NSArray *list = FBTNetworkInspectorSummaries();
    Assert(list.count == 1, @"all queued events processed");
    NSString *identifier = list.firstObject[@"record_id"];
    NSDictionary *entry = FBTNetworkInspectorRecordWithID(identifier);
    Assert([entry[@"purpose"] isEqual:@"mobileconfig_qe_info"], @"purpose preserved");
    Assert([entry[@"tigon_http_status"] integerValue] == 400, @"HTTP status from Tigon");
    Assert([entry[@"known_request_headers"][@"Authorization"] isEqual:@"Bearer secret-example"], @"header stored only locally");
    Assert([entry[@"request_parameter_pairs"][1][@"value"] isEqual:@"secret-example"], @"request exact values retained");
    NSData *exact = [[NSData alloc] initWithBase64EncodedString:entry[@"http_response_body"][@"base64"] options:0];
    Assert([exact isEqualToData:response], @"raw server response byte exact");
    Assert([entry[@"native_completion_body"][@"base64"] isKindOfClass:NSString.class], @"transport error separate from HTTP response");
    Assert(FBTNetworkInspectorExportURLs().count == 1, @"export selected JSONs");
    FBTNetworkInspectorSetCapturing(NO);
    FBTNetworkInspectorRecordRequest(@{@"request_id": @5}, @[]);
    Assert(FBTNetworkInspectorSummaries().count == 1, @"disarmed ignores later requests");
    FBTNetworkInspectorClear();
    Assert(FBTNetworkInspectorSummaries().count == 0, @"purge eliminates raw files");
    NSLog(@"PASS: %d Network Inspector checks", checks);
} return 0; }
