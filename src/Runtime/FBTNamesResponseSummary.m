#import "FBTNamesResponseSummary.h"
#include <zlib.h>

NSString *FBTNamesRedactMessage(NSString *message) {
    if (![message isKindOfClass:NSString.class]) return @"";
    NSString *text = message;
    NSArray *patterns = @[
        @"(?i)[\"']?(authorization|proxy_authorization|cookie|set-cookie|access[_-]?token|session[_-]?(token|key)|password|client[_-]?secret|app[_-]?secret)[\"']?\\s*[:=]\\s*(?:\"[^\"\\r\\n]*\"|'[^'\\r\\n]*'|[^,;\\r\\n}]+)",
        @"(?i)\\bBearer\\s+[A-Za-z0-9._~+/=-]+",
        @"https?://[^\\s\"']+", @"[\\w.+-]+@[\\w.-]+\\.[A-Za-z]{2,}",
        @"\\bEAA[A-Za-z0-9_-]{15,}\\b", @"(?i)\\b[0-9a-f]{16,}\\b", @"\\b[0-9]{6,}\\b"
    ];
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        text = [re stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"[REDACTED]"];
    }
    return text.length > 1024 ? [text substringToIndex:1024] : text;
}

NSData *FBTNamesDecodeResponse(NSData *data, NSString **status) {
    const NSUInteger limit = 2 * 1024 * 1024;
    if (status) *status = @"ready";
    if (!data.length) { if (status) *status = @"not_delivered_to_observed_callback"; return nil; }
    if (data.length > limit) { if (status) *status = @"over_2mb_limit"; return nil; }
    const uint8_t *bytes = data.bytes;
    if (data.length < 2 || bytes[0] != 0x1f || bytes[1] != 0x8b) return data;
    z_stream stream = {0};
    stream.next_in = (Bytef *)data.bytes;
    stream.avail_in = (uInt)data.length;
    if (inflateInit2(&stream, 16 + MAX_WBITS) != Z_OK) {
        if (status) *status = @"gzip_decode_failed";
        return nil;
    }
    NSMutableData *out = [NSMutableData data];
    uint8_t buffer[16384];
    int result;
    do {
        stream.next_out = buffer; stream.avail_out = sizeof(buffer);
        result = inflate(&stream, Z_NO_FLUSH);
        NSUInteger produced = sizeof(buffer) - stream.avail_out;
        if (out.length + produced > limit) {
            inflateEnd(&stream);
            if (status) *status = @"gzip_expanded_over_2mb_limit";
            return nil;
        }
        [out appendBytes:buffer length:produced];
    } while (result == Z_OK);
    BOOL complete = result == Z_STREAM_END && stream.avail_in == 0;
    inflateEnd(&stream);
    if (!complete) { if (status) *status = @"gzip_decode_failed"; return nil; }
    if (status) *status = @"gzip_decoded";
    return out;
}

NSDictionary *FBTNamesResponseSummary(NSData *data) {
    NSString *decodeStatus;
    NSData *decoded = FBTNamesDecodeResponse(data, &decodeStatus);
    NSMutableDictionary *out = [@{@"response_bytes": @(data.length), @"body_status": decodeStatus ?: @"unknown"} mutableCopy];
    if (!decoded) return out;
    out[@"decoded_response_bytes"] = @(decoded.length);
    NSString *text = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    if (!text) { out[@"body_status"] = @"non_utf8"; return out; }
    if ([text hasPrefix:@"None domain: "] || [text hasPrefix:@"Cancel domain: "]) {
        out[@"body_status"] = @"native_error_summary_NOT_server_JSON";
        return out;
    }
    id json = [NSJSONSerialization JSONObjectWithData:decoded options:NSJSONReadingFragmentsAllowed error:nil];
    if (!json) { out[@"body_status"] = @"non_json_body"; return out; }
    out[@"body_status"] = @"json";
    if (![json isKindOfClass:NSDictionary.class]) return out;
    id names = json[@"id_to_names"];
    BOOL valid = [names isKindOfClass:NSArray.class];
    if (valid) for (id name in names) if (![name isKindOfClass:NSString.class]) { valid = NO; break; }
    out[@"id_to_names_valid"] = @(valid);
    if (valid) out[@"id_to_names_count"] = @([names count]);
    NSDictionary *error = [json[@"error"] isKindOfClass:NSDictionary.class] ? json[@"error"] : nil;
    NSDictionary *keys = @{@"code": @"server_error_code", @"error_subcode": @"server_error_subcode",
                           @"type": @"server_error_type", @"message": @"server_error_message"};
    for (NSString *key in keys) {
        id value = error[key];
        if ([value isKindOfClass:NSNumber.class]) out[keys[key]] = value;
        else if ([value isKindOfClass:NSString.class]) out[keys[key]] = FBTNamesRedactMessage(value);
    }
    return out;
}
