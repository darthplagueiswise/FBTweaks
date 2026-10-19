# Facebook 583 — fluxo nativo de mc_overrides, employee e QE/OAuth

Auditoria estática de Facebook iOS 583 com artefatos originais. Endereços RVA/VA de cada Mach-O, sem ASLR. Nenhum attach ao iPhone nem alteração de credenciais.

## Resultados comprovados

- FBSharedFramework contém `mobileconfig::FBMobileConfigOverridesTable::overridesFilename` em `0x15B9E8`; a função carrega a string `mc_overrides.json` (`0x6319464`). `FBMobileConfigOverridesWriter::importFromUser` está em `0x49F08B4`.
- O armazenamento nativo lê flags tipadas de override via `FBMobileConfigOverridesTable::hasBoolOverrideForParam` em `0x174200`. XREFs diretos: `0x2C885A4` (discrimina tipo bool por `UBFX ... #48, #6`) e `0x4C063DC`.
- O catálogo enviado `ReactMobileConfigMetadata.json` e os mapas da IPA `params_map.txt`/`rn_params_map.txt` declaram `tw_is_employee:enabled` = `configKey 74929 / paramKey 0` e `fb_ford:is_employee` = `configKey 70946 / paramKey 11`. Ambos são bool, `unitType 2`, default `false`. O snapshot histórico `mc_overrides_3_.json` declara ambos como `true`; isto NÃO demonstra o valor efetivo da execução.
- Na amostra do índice nativo de descritores de 43.122 itens não há descritores exatamente correspondentes a essas duas combinações. Isso não exclui leitores RN, indiretos ou gerados.
- `-[FBUserPreferences isEmployee]` em FBSharedFramework `0x6169E0` obtém `CFString` de `0x85E87F8` e chama `0x6168AC`. O ponteiro string `0x6304EAB` contém **`employee`**. `setEmployee:` em `0x1EE2764` usa a mesma chave. A palavra `employee` compartilha por otimização o sufixo de `is_employee` em `0x6304EA8`; compartilhamento de bytes não estabelece vínculo causal entre a flag RN e a propriedade.
- `-[RCDMobileConfigParams isEmployee]` no executável Facebook `0x10004DE08` executa `ldrb w0, [x0,#0xA]`; o inicializador `0x1004ADCCC` escreve ali o argumento isEmployee em `0x1004ADD70`. O getter não faz leitura direta do catálogo.
- O caminho Tigon sessioned passa por `FBHttpUpperStackWithSession` `0x53CB60` e lê a configuração de `validate_auth_header` em `0x53CC58`. Nenhum XREF nativo comprovado conecta `tw_is_employee:enabled` ou `fb_ford:is_employee` à escolha dos headers de autenticação, emissão de token ou regra OAuth do QE-info.
- A captura documentada da build 159 mostra HTTP 400 com `OAuthException`, código 100, e mensagem `Employee Account or Specific App Conditions`. Isso confirma rejeição por uma condição remota, mas não especifica a regra aplicada pelo servidor.

## Delimitação do efeito

O framework **FBSharedFramework** implementa o importador e as tabelas de overrides. Consumidores via FBMobileConfigManager/bridge podem residir no executável Facebook, RN ou outros frameworks sem abrir o JSON. O schema RN só comprova disponibilidade das flags, não quem efetivamente as leu. **Não está demonstrado que `mc_overrides[74929:0]` ou `mc_overrides[70946:11]` alterem `FBUserPreferences.employee`, `FBUser.isEmployee` ou a identidade OAuth enviada à rede.**

## Teste de comprovação que falta

Instrumentação somente observadora no cold start: capturar leituras nativas/RN efetivas de `74929:0` e `70946:11`, com caller image/RVA; capturar `FBUserPreferences.isEmployee` original e efetivo e argumento de `RCDMobileConfigParams`; registrar origem do serviço Tigon e request ID QE-info. Não exportar tokens ou identidades. Comparar com a resposta sanitizada do mesmo request. Distinguir ausente de falso e captura tardia de ausência de leitura. Não alterar um request nem presumir autorização server-side por uma flag local.

Esta auditoria **não valida o patch de hook setManagerFetcher anterior para publicação na branch flags**: ainda faltam build Theos e validação de ABI/runtime. Publicar esse hook sem tais testes confundiria diagnóstico com correção.