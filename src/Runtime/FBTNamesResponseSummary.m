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

NSDictionary *FBTNamesDiagnosticAdvice(NSDictionary *event) {
    NSInteger code = [event[@"server_error_code"] integerValue];
    NSString *type = [event[@"server_error_type"] isKindOfClass:NSString.class] ? event[@"server_error_type"] : @"";
    NSString *message = [event[@"server_error_message"] isKindOfClass:NSString.class] ? event[@"server_error_message"] : @"";
    if (code == 100 && [type isEqual:@"OAuthException"] &&
        [message rangeOfString:@"Employee Account or Specific App Conditions" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return @{@"classification": @"server_eligibility", @"title": @"Acesso recusado pelo servidor",
            @"explanation": @"O backend exige condições de conta ou aplicativo. A resposta não especifica qual condição faltou. Flags locais de employee e overrides não comprovam elegibilidade no servidor.",
            @"next_step": @"Confirme a elegibilidade da conta e do aplicativo pelo fluxo autorizado. O mapa local continua disponível para consultar e editar configurações; ele não equivale a um download remoto bem-sucedido."};
    }
    if ([event[@"id_to_names_valid"] boolValue]) {
        BOOL names = [event[@"id_to_names_count"] unsignedIntegerValue] > 0;
        return @{@"classification": names ? @"names_received" : @"empty_names",
            @"title": names ? @"Resposta com nomes recebida" : @"Resposta com lista de nomes vazia",
            @"explanation": @"A estrutura id_to_names foi validada. A gravação de id_name_mapping.json e sua leitura pelo aplicativo são etapas separadas.",
            @"next_step": @"Confira os arquivos locais e preserve a origem dos nomes."};
    }
    if ([event[@"http_status"] integerValue] >= 400 || event[@"server_error_code"]) {
        return @{@"classification": @"remote_rejection", @"title": @"Pedido recusado",
            @"explanation": @"Use o código e a mensagem capturados abaixo. O código 100 sozinho não identifica uma falha de employee.",
            @"next_step": @"Confira o contrato enviado e o motivo informado pelo servidor antes de alterar configurações."};
    }
    if ([event[@"body_status"] isEqual:@"not_delivered_to_observed_callback"]) {
        return @{@"classification": @"body_unavailable", @"title": @"Corpo da resposta indisponível",
            @"explanation": @"Nenhum corpo útil foi entregue à superfície observada. Isso não prova que a resposta do servidor era vazia.",
            @"next_step": @"Exporte o diagnóstico para investigar a camada de transporte anterior."};
    }
    return @{@"classification": @"undetermined", @"title": @"Resultado ainda não determinado",
        @"explanation": @"Confira se a captura está pronta e faça uma tentativa pelo menu nativo.",
        @"next_step": @"Nenhuma correção de autorização foi comprovada."};
}
