#import <Foundation/Foundation.h>
#import "../src/Runtime/FBTNamesResponseSummary.h"
#include <zlib.h>

static NSUInteger count;
static void Check(BOOL ok, NSString *name) { if (!ok) { NSLog(@"FAIL %@", name); exit(1); } ++count; }
static NSData *UTF8(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
static NSData *Gzip(NSData *data) {
    z_stream z = {0};
    Check(deflateInit2(&z, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 16 + MAX_WBITS, 8, Z_DEFAULT_STRATEGY) == Z_OK, @"gzip fixture init");
    NSMutableData *out = [NSMutableData dataWithLength:compressBound((uLong)data.length) + 32];
    z.next_in = (Bytef *)data.bytes; z.avail_in = (uInt)data.length;
    z.next_out = out.mutableBytes; z.avail_out = (uInt)out.length;
    Check(deflate(&z, Z_FINISH) == Z_STREAM_END, @"gzip fixture complete");
    [out setLength:z.total_out]; deflateEnd(&z); return out;
}
int main(void) { @autoreleasepool {
    NSDictionary *metadata = FBTNamesResponseMetadata(UTF8(@"{\"error\":{\"code\":100,\"type\":\"OAuthException\",\"message\":\"(#100) Employee Account or Specific App Conditions\"}}"));
    Check([metadata[@"server_error_code"] isEqual:@100] && [metadata[@"server_error_type"] isEqual:@"OAuthException"], @"session probe preserves remote error fields");
    Check([metadata[@"server_error_message"] isEqual:@"Employee Account or Specific App Conditions"], @"recognized eligibility normalized");
    metadata = FBTNamesResponseMetadata(UTF8(@"{\"error\":{\"code\":100,\"type\":\"secret_type\",\"message\":\"private opaque credential goes here\"}}"));
    NSString *metadataText = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:metadata options:0 error:nil] encoding:NSUTF8StringEncoding];
    Check(![metadataText containsString:@"private opaque"] && ![metadataText containsString:@"secret_type"], @"unrecognized remote text not exported");
    Check(metadata[@"server_error_message"] == nil, @"code100 alone not eligibility");
    metadata = FBTNamesResponseMetadata(UTF8(@"{\"error\":{\"code\":100,\"type\":\"OAuthException\",\"message\":\"not Employee Account or Specific App Conditions; opaque private detail\"}}"));
    Check(metadata[@"server_error_message"] == nil, @"substring or negated condition not normalized as eligibility");
    NSDictionary *out = FBTNamesResponseSummary(UTF8(@"None domain: FBHTTPErrorDomain code: 400 detail: "));
    Check([out[@"body_status"] isEqual:@"native_error_summary_NOT_server_JSON"], @"native description is not a server body");
    out = FBTNamesResponseSummary(UTF8(@"{\"error\":{\"code\":100,\"error_subcode\":33,\"type\":\"ValidationError\",\"message\":\"bad queries 123456789\",\"access_token\":\"secret\"}}"));
    Check([out[@"server_error_code"] intValue] == 100 && [out[@"server_error_subcode"] intValue] == 33, @"remote error codes retained");
    Check(![out.description containsString:@"123456789"] && ![out.description containsString:@"secret"], @"IDs and unallowlisted credentials absent");
    Check(![FBTNamesRedactMessage(@"{\"access_token\":\"sensitive\"} Authorization: Bearer abc.def.ghi") containsString:@"sensitive"] &&
        ![FBTNamesRedactMessage(@"Bearer abc.def.ghi") containsString:@"abc.def.ghi"], @"quoted credentials and bearer sanitized");
    Check(![FBTNamesRedactMessage(@"OAuth fixture-secret-token") containsString:@"fixture-secret-token"], @"standalone OAuth credentials sanitized");
    out = FBTNamesResponseSummary(UTF8(@"{\"id_to_names\":[\"1:test:0:flag\"]}"));
    Check([out[@"id_to_names_valid"] boolValue] && [out[@"id_to_names_count"] intValue] == 1 && ![out.description containsString:@"flag"], @"valid names counted without values");
    Check(![FBTNamesResponseSummary(UTF8(@"{\"id_to_names\":[1]}"))[@"id_to_names_valid"] boolValue], @"wrong token types rejected");
    Check([FBTNamesResponseSummary(nil)[@"body_status"] isEqual:@"not_delivered_to_observed_callback"], @"no bytes is unavailable");
    NSData *json = UTF8(@"{\"error\":{\"code\":100,\"message\":\"bad queries\"}}");
    NSData *gzip = Gzip(json); NSString *state;
    Check([FBTNamesDecodeResponse(gzip, &state) isEqual:json] && [state isEqual:@"gzip_decoded"], @"gzip decode exact");
    Check([FBTNamesResponseSummary(gzip)[@"server_error_code"] intValue] == 100, @"gzip error interpretable on device");
    Check(FBTNamesDecodeResponse([gzip subdataWithRange:NSMakeRange(0, gzip.length-2)], &state) == nil && [state isEqual:@"gzip_decode_failed"], @"truncated gzip rejected");
    NSData *bomb = Gzip([NSMutableData dataWithLength:2 * 1024 * 1024 + 1]);
    Check(FBTNamesDecodeResponse(bomb, &state) == nil && [state isEqual:@"gzip_expanded_over_2mb_limit"], @"decompression limit enforced");
    NSDictionary *advice = FBTNamesDiagnosticAdvice(@{@"http_status": @400, @"server_error_code": @100, @"server_error_type": @"OAuthException", @"server_error_message": @"(#100) Employee Account or Specific App Conditions"});
    Check([advice[@"classification"] isEqual:@"server_eligibility"], @"exact observed eligibility error classified");
    advice = FBTNamesDiagnosticAdvice(@{@"http_status": @400, @"server_error_code": @100, @"server_error_type": @"OAuthException", @"server_error_message": @"Invalid parameter"});
    Check([advice[@"classification"] isEqual:@"remote_rejection"], @"generic code 100 is not misclassified as employee rejection");
    Check([FBTNamesDiagnosticAdvice(@{@"body_status": @"not_delivered_to_observed_callback"})[@"classification"] isEqual:@"body_unavailable"], @"missing body remains unknown");
    Check([FBTNamesDiagnosticAdvice(@{@"id_to_names_valid": @YES, @"id_to_names_count": @0})[@"classification"] isEqual:@"empty_names"], @"empty names are not treated as populated");
    Check([FBTNamesDiagnosticAdvice(@{})[@"classification"] isEqual:@"undetermined"], @"no evidence is not reported as success");
    NSDictionary *shape = @{@"needs_name": @"true", @"skip_qe": @"1", @"with_current_experiment_group": @"false",
        @"with_experiments": @0, @"with_gatekeepers": @0, @"with_group_params": @0, @"with_groups": @0,
        @"with_only_current_experiment_group": @0, @"with_params": @0, @"with_universe_params": @0};
    NSString *shapeText = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:shape options:0 error:nil] encoding:NSUTF8StringEncoding];
    NSDictionary *request = @{@"event": @"native_mc_fetch_started", @"request_id": @13, @"process_session_id": @"A",
        @"capture_reason": @"mobileconfig_qe_info", @"request_parameter_summary": shapeText};
    NSDictionary *assessment = FBTNamesAssessRequest(request, @{@"http_status": @400, @"id_to_names_valid": @NO}, @{@"native_transport_success": @NO});
    Check([assessment[@"request_profile"] isEqual:@"native_names_profile"], @"native false options are expected, not authorization failures");
    Check([assessment[@"transport_state"] isEqual:@"remote_rejection"], @"HTTP 400 dominates success claims");
    Check([assessment[@"authentication_observation"] isEqual:@"not_captured_at_final_request"], @"parameter capture cannot establish authentication");
    assessment = FBTNamesAssessRequest(@{}, @{}, @{});
    Check([assessment[@"transport_state"] isEqual:@"not_observed"] && [assessment[@"names_payload_state"] isEqual:@"not_observed"], @"missing result is not false");
    Check([assessment[@"request_profile"] isEqual:@"incomplete_observation"], @"missing false-valued options do not count as observed false");
    assessment = FBTNamesAssessRequest(@{@"request_parameter_summary": @"[]"}, @{}, @{});
    Check([assessment[@"request_profile"] isEqual:@"incomplete_observation"], @"non-object parameter summary handled");
    assessment = FBTNamesAssessRequest(request, @{@"http_status": @200, @"id_to_names_valid": @YES}, @{@"native_transport_success": @YES});
    Check([assessment[@"file_write_observation"] isEqual:@"not_correlated_to_this_request"], @"valid payload and transport do not prove file write");
    NSArray *history = FBTNamesAssessHistory(@[request,
        @{@"event": @"names_transport_diagnostic", @"request_id": @13, @"process_session_id": @"A", @"http_status": @400},
        @{@"event": @"names_transport_diagnostic", @"request_id": @13, @"process_session_id": @"B", @"http_status": @200},
        @{@"event": @"native_mc_fetch_completed", @"request_id": @13, @"process_session_id": @"A", @"native_transport_success": @NO}], @"A");
    Check(history.count == 1 && [history[0][@"assessment"][@"transport_state"] isEqual:@"remote_rejection"], @"assessment does not mix process sessions sharing a request ID");
    Check(FBTNamesAssessHistory(@[request], @"B").count == 0, @"other process requests excluded");
    NSLog(@"PASS: %lu response summary checks", (unsigned long)count);
} return 0; }


