#import "FBTNamesResponseSummary.h"
#include <zlib.h>
#include <stdint.h>

NSString *FBTNamesRedactMessage(NSString *message) {
    if (![message isKindOfClass:NSString.class]) return @"";
    NSString *text = message;
    NSArray *patterns = @[
        @"(?i)[\"']?(authorization|proxy_authorization|cookie|set-cookie|access[_-]?token|session[_-]?(token|key)|password|client[_-]?secret|app[_-]?secret)[\"']?\\s*[:=]\\s*(?:\"[^\"\\r\\n]*\"|'[^'\\r\\n]*'|[^,;\\r\\n}]+)",
        @"(?i)\\b(?:Bearer|OAuth)\\s+[A-Za-z0-9._~+/=-]+",
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
    const uint8_t *bytes = (const uint8_t *)data.bytes;
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

NSDictionary *FBTNamesResponseMetadata(NSData *data) {
    NSDictionary *summary = FBTNamesResponseSummary(data);
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"body_status", @"decoded_response_bytes", @"id_to_names_valid", @"id_to_names_count"])
        if (summary[key]) out[key] = summary[key];
    for (NSString *key in @[@"server_error_code", @"server_error_subcode"]) {
        id value = summary[key];
        if ([value isKindOfClass:NSNumber.class] && [value doubleValue] >= 0 &&
            [value doubleValue] <= INT32_MAX && [value doubleValue] == [value longLongValue]) out[key] = value;
    }
    NSString *type = [summary[@"server_error_type"] isKindOfClass:NSString.class] ? summary[@"server_error_type"] : nil;
    if (type) out[@"server_error_type"] = [@[@"OAuthException", @"GraphMethodException", @"OAuthAccessTokenException"] containsObject:type] ? type : @"unrecognized";
    NSString *message = [summary[@"server_error_message"] isKindOfClass:NSString.class] ? summary[@"server_error_message"] : @"";
    message = [[message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([message hasPrefix:@"(#100)"]) message = [[message substringFromIndex:6] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([out[@"server_error_code"] isEqual:@100] && [type isEqual:@"OAuthException"] &&
        [message isEqual:@"employee account or specific app conditions"])
        out[@"server_error_message"] = @"Employee Account or Specific App Conditions";
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


static NSInteger FBTNamesBoolean(id value) {
    if ([value isKindOfClass:NSNumber.class]) {
        if ([value isEqual:@0]) return 0;
        if ([value isEqual:@1]) return 1;
    }
    if ([value isKindOfClass:NSString.class]) {
        if ([value isEqual:@"true"] || [value isEqual:@"1"]) return 1;
        if ([value isEqual:@"false"] || [value isEqual:@"0"]) return 0;
    }
    return -1;
}

NSDictionary *FBTNamesAssessRequest(NSDictionary *request, NSDictionary *response, NSDictionary *completion) {
    NSString *summary = [request[@"request_parameter_summary"] isKindOfClass:NSString.class] ? request[@"request_parameter_summary"] : @"";
    NSData *bytes = [summary dataUsingEncoding:NSUTF8StringEncoding];
    id parsed = bytes.length ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
    NSDictionary *shape = [parsed isKindOfClass:NSDictionary.class] ? parsed : @{};
    NSArray *disabledOptions = @[@"with_current_experiment_group", @"with_experiments", @"with_gatekeepers",
        @"with_group_params", @"with_groups", @"with_only_current_experiment_group", @"with_params", @"with_universe_params"];
    BOOL profile = FBTNamesBoolean(shape[@"needs_name"]) == 1 && FBTNamesBoolean(shape[@"skip_qe"]) == 1;
    NSMutableArray *missing = [NSMutableArray array];
    for (NSString *key in [disabledOptions arrayByAddingObjectsFromArray:@[@"needs_name", @"skip_qe"]]) {
        if (FBTNamesBoolean(shape[key]) < 0) [missing addObject:key];
    }
    for (NSString *key in disabledOptions) profile = profile && FBTNamesBoolean(shape[key]) == 0;
    NSInteger http = [response[@"http_status"] respondsToSelector:@selector(integerValue)] ? [response[@"http_status"] integerValue] : 0;
    if (!http && [completion[@"http_status"] respondsToSelector:@selector(integerValue)]) http = [completion[@"http_status"] integerValue];
    NSInteger native = FBTNamesBoolean(completion[@"native_transport_success"]);
    BOOL rejected = http >= 400 || response[@"server_error_code"] != nil;
    NSString *transport = rejected ? @"remote_rejection" : native == 0 ? @"native_failure" : native == 1 ? @"native_success" : @"not_observed";
    NSString *names = response[@"id_to_names_valid"] == nil ? @"not_observed" :
        [response[@"id_to_names_valid"] boolValue] ? @"array_of_strings_observed" : @"expected_array_not_observed";
    NSString *auth = completion[@"authorization_state"] ?: response[@"authorization_state"] ?: @"not_observed";
    NSString *next = rejected ? @"Compare A e B para a mesma ação e conta. Teste FBUser/gates e tw_is_employee separadamente. Confira o perfil realmente consumido, HTTP, corpo e saídas nativas de params/nomes. OAuth presente não prova token válido ou condição employee aceita." :
        native == 1 ? @"Confira id_to_names e a atualização do arquivo. Sucesso do transporte não comprova parsing nem gravação." :
        @"Confira os hooks, o status HTTP e o corpo. Ausência de observação não significa false.";
    return @{@"request_profile": profile ? @"native_names_profile" : missing.count ? @"incomplete_observation" : @"other_profile",
        @"unobserved_or_invalid_options": missing,
        @"request_options_explanation": @"with_* são seleções de conteúdo. No refreshNames nativo, as oito opções ficam false; needs_name e skip_qe ficam true. Não são permissões de employee.",
        @"transport_state": transport, @"names_payload_state": names,
        @"native_callback_explanation": @"No binário analisado, o callback de sucesso do fetcher exige corpo não vazio; o callback de erro devolve false. O processamento de nomes e a gravação são etapas posteriores. Não force o retorno.",
        @"authentication_observation": [auth isEqual:@"not_observed"] ? @"not_captured_at_final_request" : auth,
        @"authentication_explanation": @"O callback onStarted pode observar presença/esquema de Authorization. A etapa é exportada explicitamente. Isso não valida token, ator, escopo, elegibilidade ou headers finais na rede. Ausência do callback fica não observada.",
        @"file_write_observation": @"not_correlated_to_this_request",
        @"whitehat_explanation": @"O controle FBWhitehatSSLPinningBypass analisado configura inspeção TLS e pede reinício. Não altera a elegibilidade remota. Receber OAuthException em JSON já demonstra uma resposta HTTP nesta tentativa.",
        @"next_step": next};
}

NSArray<NSDictionary *> *FBTNamesAssessHistory(NSArray<NSDictionary *> *events, NSString *processSessionID) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *request in events.reverseObjectEnumerator) {
        if (![request isKindOfClass:NSDictionary.class] || ![request[@"event"] isEqual:@"native_mc_fetch_started"] ||
            ![request[@"capture_reason"] isEqual:@"mobileconfig_qe_info"] ||
            ![request[@"process_session_id"] isEqual:processSessionID] || !request[@"request_id"]) continue;
        NSDictionary *response = @{}, *completion = @{};
        for (NSDictionary *event in events.reverseObjectEnumerator) {
            if (![event isKindOfClass:NSDictionary.class] || ![event[@"process_session_id"] isEqual:processSessionID] ||
                ![event[@"request_id"] isEqual:request[@"request_id"]]) continue;
            if ([event[@"event"] isEqual:@"native_mc_fetch_completed"] && !completion.count) completion = event;
            if ([event[@"event"] isEqual:@"names_transport_diagnostic"] &&
                (!response.count || (![response[@"http_status"] integerValue] && [event[@"http_status"] integerValue]))) response = event;
        }
        [out addObject:@{@"request_id": request[@"request_id"], @"process_session_id": processSessionID,
            @"assessment": FBTNamesAssessRequest(request, response, completion)}];
        if (out.count == 8) break;
    }
    return out;
}

