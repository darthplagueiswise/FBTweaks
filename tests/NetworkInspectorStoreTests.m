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
    Assert([list.firstObject[@"http_status_source"] isEqual:@"verified_tigon_response_status"],
           @"summary preserves observed Tigon status provenance");
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
    FBTNetworkInspectorRecordRequest(@{@"request_id": @5,
        @"capture_reason": @"mobileconfigsessionless",
        @"request_method": @"POST"}, @[]);
    FBTNetworkInspectorRecordTigon(@{@"request_id": @5, @"http_status": @0}, nil);
    FBTNetworkInspectorRecordCompletion(@{@"request_id": @5,
        @"http_status": @400, @"http_status_source": @"native_formatted_transport_error",
        @"native_transport_success": @NO}, UTF8(@"error"));
    NSArray *records = FBTNetworkInspectorSummaries();
    Assert(records.count == 2, @"second request captured");
    NSDictionary *secondSummary = nil;
    for (NSDictionary *candidate in records) {
        if ([candidate[@"request_id"] integerValue] == 5) secondSummary = candidate;
    }
    Assert(secondSummary != nil, @"second request searchable by ID");
    NSDictionary *second = FBTNetworkInspectorRecordWithID(secondSummary[@"record_id"]);
    Assert([second[@"http_response_body"][@"capture_status"] isEqual:@"not_delivered_to_observed_callback"],
           @"missing Tigon body not mistaken for an empty HTTP response");
    Assert([secondSummary[@"http_status"] integerValue] == 400,
           @"missing Tigon status falls back to native status");
    Assert([secondSummary[@"http_status_source"] isEqual:@"native_formatted_transport_error"],
           @"native fallback keeps its distinct status provenance");
    FBTNetworkInspectorSetCapturing(NO);
    FBTNetworkInspectorRecordRequest(@{@"request_id": @6}, @[]);
    Assert(FBTNetworkInspectorSummaries().count == 2, @"disarmed ignores later requests");
    FBTNetworkInspectorClear();
    Assert(FBTNetworkInspectorSummaries().count == 0, @"purge eliminates raw files");
    FBTNetworkInspectorSetCapturing(YES);
    FBTNetworkInspectorRecordRequest(@{@"request_id": @7,
        @"capture_reason": @"mobileconfig_qe_info", @"request_method": @"POST"},
        @[@{@"name": @"queries", @"value": @"[\"35:1:2\",\"4627:42\"]"},
          @{@"name": @"device_id", @"value": @"device_id"},
          @{@"name": @"needs_name", @"value": @"true"},
          @{@"name": @"skip_qe", @"value": @"true"},
          @{@"name": @"api_version", @"value": @"9"}]);
    NSArray *one = FBTNetworkInspectorSummaries();
    Assert(one.count == 1, @"diagnostics request stored");
    NSDictionary *diag = FBTNetworkInspectorRecordWithID(one.firstObject[@"record_id"])[@"request_diagnostics"];
    Assert([diag[@"query_config_count"] integerValue] == 2, @"counts distinct requests without guessing");
    Assert([diag[@"query_parameter_index_count"] integerValue] == 3, @"counts parameter indices");
    Assert([diag[@"device_id_state"] isEqual:@"literal_parameter_name"], @"labels prebuilder placeholder");
    Assert([diag[@"query_parse_status"] isEqual:@"complete_numeric_list"], @"validates query schema");

    FBTNetworkInspectorClear();
    FBTNetworkInspectorRecordRequest(@{@"request_id": @8,
        @"capture_reason": @"mobileconfig_qe_info"}, @[]);
    NSDictionary *pendingSummary = FBTNetworkInspectorSummaries().firstObject;
    NSDictionary *pending = FBTNetworkInspectorRecordWithID(pendingSummary[@"record_id"]);
    Assert(pendingSummary[@"http_status"] == nil, @"pending request has no invented HTTP status");
    Assert([pendingSummary[@"http_status_source"] isEqual:@"not_observed"],
           @"pending request marks HTTP provenance unobserved");
    Assert(pending[@"native_transport_success"] == nil, @"pending request is not a native failure");

    FBTNetworkInspectorRecordCompletion(@{@"request_id": @8}, nil);
    NSDictionary *unobserved = FBTNetworkInspectorRecordWithID(pendingSummary[@"record_id"]);
    Assert(unobserved[@"native_transport_success"] == nil, @"missing callback result stays absent");
    Assert(unobserved[@"native_completion_status"] == nil, @"missing callback HTTP status stays absent");
    Assert(unobserved[@"duration_ms"] == nil, @"missing callback duration stays absent");
    Assert([unobserved[@"native_body_source"] isEqual:@"not_observed"],
           @"missing callback provenance is not labeled decoded");

    FBTNetworkInspectorRecordCompletion(@{@"request_id": @8,
        @"native_transport_success": @NO, @"http_status": @0, @"duration_ms": @0}, nil);
    NSDictionary *failed = FBTNetworkInspectorRecordWithID(pendingSummary[@"record_id"]);
    Assert([failed[@"native_transport_success"] isEqual:@NO], @"observed false remains a native failure");
    Assert([failed[@"duration_ms"] isEqual:@0], @"observed zero duration is retained");
    Assert(failed[@"native_completion_status"] == nil, @"HTTP zero is not a received HTTP status");

    FBTNetworkInspectorRecordCompletion(@{@"request_id": @9,
        @"native_transport_success": @YES, @"response_bytes": @2097153,
        @"payload_provenance": @"native_decoded_completion"}, nil);
    NSDictionary *oversized = nil;
    for (NSDictionary *candidate in FBTNetworkInspectorSummaries()) {
        if ([candidate[@"request_id"] integerValue] == 9)
            oversized = FBTNetworkInspectorRecordWithID(candidate[@"record_id"]);
    }
    Assert(oversized != nil, @"oversized native completion has a record");
    NSDictionary *omittedBody = oversized[@"native_completion_body"];
    Assert([omittedBody[@"capture_status"] isEqual:@"over_capture_limit"],
           @"known oversized body is not mislabeled unobserved");
    Assert([omittedBody[@"length"] isEqual:@2097153], @"omitted body keeps its reported byte length");
    Assert(omittedBody[@"base64"] == nil, @"omitted oversized body adds no captured bytes");
    FBTNetworkInspectorSetCapturing(NO);
    FBTNetworkInspectorClear();
    NSLog(@"PASS: %d Network Inspector checks", checks);
} return 0; }
