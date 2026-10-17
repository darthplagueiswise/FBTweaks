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
    NSDictionary *out = FBTNamesResponseSummary(UTF8(@"None domain: FBHTTPErrorDomain code: 400 detail: "));
    Check([out[@"body_status"] isEqual:@"native_error_summary_NOT_server_JSON"], @"native description is not a server body");
    out = FBTNamesResponseSummary(UTF8(@"{\"error\":{\"code\":100,\"error_subcode\":33,\"type\":\"ValidationError\",\"message\":\"bad queries 123456789\",\"access_token\":\"secret\"}}"));
    Check([out[@"server_error_code"] intValue] == 100 && [out[@"server_error_subcode"] intValue] == 33, @"remote error codes retained");
    Check(![out.description containsString:@"123456789"] && ![out.description containsString:@"secret"], @"IDs and unallowlisted credentials absent");
    Check(![FBTNamesRedactMessage(@"{\"access_token\":\"sensitive\"} Authorization: Bearer abc.def.ghi") containsString:@"sensitive"] &&
        ![FBTNamesRedactMessage(@"Bearer abc.def.ghi") containsString:@"abc.def.ghi"], @"quoted credentials and bearer sanitized");
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
    NSLog(@"PASS: %lu response summary checks", (unsigned long)count);
} return 0; }
