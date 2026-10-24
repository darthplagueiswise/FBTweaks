# QE-info x hash do MobileConfig: auditoria por fluxo (Facebook 583)

## Evidência do request real

Esta branch deriva de `codex/force-name-request-options` no commit `85a00ea1f6d0716fbba916a323a98b1b34e8e3fd`, porque é ela que gera `experiment_profile=qe_custom_options` e `experiment_state=ten_options_applied`. Não confundir com o hook isolado do PR #9.

No dump nativo fornecido, `FBMobileConfigTigonFetcher::asyncFetch` recebeu 13 pares e `queries` como JSON com 4192 entradas. Nenhum dos pares tinha nome `query_hash` ou `one_query_hash`. A captura tem `request_parameter_capture=complete`, porém sua fonte é **antes** do construtor Tigon; não é prova dos bytes finais na rede. O proxy Whitehat continua sendo a verificação correta.

O valor nativo de `device_id` é o literal `device_id`, conforme `device_id_format=field_name_literal`. Isso pode ser um marcador usado pela API e não deve ser substituído por UUID da captura, UUID Mach-O ou identidade inventada. Sua aceitação não está demonstrada.

## Três hashes que NÃO devem ser confundidos

| Campo/recurso | Local encontrado | Evidência |
|---|---|---|
| `query_hash` | Possível par de `asyncFetch` (somente se fornecido pelo chamador) | **Ausente** nos argumentos capturados para QE-info |
| `one_query_hash.txt` | `Payload/Facebook.app/mobileconfig_res/one_query_hash.txt` | Recurso embarcado com 64 caracteres hexadecimais; NÃO foi comprovado ser parâmetro HTTP de QE-info |
| `request_data_query_hash` | String adjacente a `FBMobileConfigRequester::getQueryParams` no FBSharedFramework original | Pista estática de geração de argumentos do fluxo de sincronização; não foi observado no QE-info |

O override `4626:mobileconfig_session` parâmetro 4 `use_builtin_query_hash` pertence à estratégia do MobileConfig local, sem evidência de que injete hash em `/mobileconfig_qe_info`.

## Mudanças seguras

- `FBTMobileConfigFetcherCapture.mm`: quando não há hash em pares nativos, o estado vira `absent_in_native_arguments`, em vez de `not_observed`. Registra escopo `asyncFetch_native_pairs_not_wire` e verifica **somente presença/formato** do `one_query_hash.txt` do bundle. Não registra seu valor e não o envia ao backend.
- `FBTMobileConfigFetchDiagnostics.m`: salva apenas valores de diagnóstico pré-definidos; não amplia captura de tokens, headers nem hashes.
- Painel **Fetch e contexto QE**: nova seção explicando a separação entre QE-info, hash embarcado e requester de sync.
- `scripts/audit-qe-hash-capture.py`: lê uma captura exportada e, opcionalmente, uma IPA, e emite uma única linha JSON sanitizada. Exemplo:

```bash
python3 scripts/audit-qe-hash-capture.py   /privado/captura.json --ipa /privado/Facebook.ipa
```

A saída não contém Authorization, OAuth token, corpo bruto, `queries`, ID do dispositivo ou valor do hash.

## Como comprovar os fluxos de verdade

1. **QE-info:** confirme a presença/ausência dos pares no argumento nativo e no request final do proxy Whitehat; observe a resposta HTTP. É um fluxo de nomes/metadados.
2. **MobileConfig sync:** dispare o refresh de valores **nativo** e capture `mobileconfig` / `mobileconfigsessionless`, separadamente. Somente depois de recuperar os parâmetros reais desse requester é possível verificar se `request_data_query_hash` é enviado, calculado ou omitido.
3. **Elegibilidade:** a resposta HTTP 400 `OAuthException (#100) Employee Account or Specific App Conditions` não demonstra defeito de hash. Um hash fabricado ou transplantado do bundle não garante autorização.

**SEGURANÇA:** os exports completos do Network Inspector podem conter tokens OAuth em texto legível. Guarde localmente, nunca publique capturas brutas no GitHub e revogue/renove credenciais expostas. O script de auditoria produz um resumo para compartilhar sem o token.

## Limites

Esta branch corrige o diagnóstico e fornece auditoria reproduzível. Não adiciona parâmetros HTTP desconhecidos, não força valores de hash, não faz bypass de elegibilidade e não instala hooks novos. A associação completa `request_data_query_hash` -> serialização do sync ainda precisa de uma captura autorizada de `FBMobileConfigRequester` ou de sua chamada correspondente.
