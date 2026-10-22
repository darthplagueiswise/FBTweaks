# MobileConfig native callback probes — opt-in, sem Frida

Escopo: Facebook 583 arm64. Esta implementação não altera o request nem o resultado, não edita __TEXT nem usa Frida.

## Dois toggles reais na FBTweak > Runtime
1. **Probe Tigon nativo (sessão / experimental)**: instala apenas cinco slots de `TigonSimpleCallbacks` por rebinding do `__DATA_CONST,__const` do `FBSharedFramework`. UUID `4C4C44FE-5555-3144-A1C2-6CCAE4ED2597`; endereços de slots `0x8100558`, `0x8100588`, `0x8100590`, `0x81005A0`, `0x81005B0`. Nenhum fishhook global, `NSURLSession` ou Frida é instalado pelo toggle.
2. **Probe fetch MobileConfig (sessão / experimental)**: usa `FBMobileConfigTigonFetcher::asyncFetch` com slot `0x8161F88`, alvo `0xA17F70`, UUID idêntico. Intercepta o callback `std::function<void(bool, const std::string&)>`. O wrapper cancela quaisquer experimentos de adição de campos em builds normais, copia os pares de request sem editá-los, e repassa callback original uma vez.

Os dois dependem de **Log QE-info (seguro)**. São **voláteis em memória**, não persistem entre lançamentos e começam desativados. Desligar interrompe a observação; caso os callbacks tenham sido ligados, a memória não é reescrita novamente para desmontá-los enquanto houver chamadas ativas: em modo OFF fazem somente passthrough.

## Evidência versus limitações
- A verificação de UUID/RVA/ponteiro/segmento é requisito antes de trocar o slot, mas **não prova sozinha** ABI perfeita em todas as combinações iOS.
- Esses probes mostram eventos reais de `TigonSimpleCallbacks`, status HTTP, requisições `mobileconfig` e `mobileconfig_qe_info`, conclusão do fetcher, quando os callbacks são exercitados.
- O corpo HTTP bruto nunca é persistido por esses toggles; capturam-se apenas códigos, contagens e origem dos eventos.
- `mobileconfig_sessioned_startup_config → disable_rn_config_merge (39594:4)`, `use_params_map_merge_v2 (39594:5)`, `vaidate_params_map_merge_v2 (39594:6)`: a leitura de startup e merge é independente das etapas acima.
- **Guards internos** do `FBMobileConfigManager::updateConfigsWithParamsListSynchronously` em `0x49E987C` e `0x49E98D8`: estes toggles não observam diretamente as instruções; não seria correto dizer que sim.
- **Persistência delta** em `FBMobileConfigStorageManager::persistConfigsFromDeltaResponse` (`0x138F398`): ABI C++ da função e cobertura dos callers ainda insuficientes para instalar hook sem risco de crash. Toggling do callback Tigon NÃO comprova persistência em disco.
- Não confundir `SERVER` (pode ser cache) com valor recém-baixado. Uma falha HTTP QE-info não implica falha do sync comum.

## Reproduzir
1. Ative Log QE-info (seguro).
2. Ative inicialmente apenas Probe fetch MobileConfig. Realize o mesmo fetch manual e exporte `fbt_fetch_diagnostics.json`.
3. Desligue fetcher, reinicie o Facebook. Teste o Probe Tigon, isoladamente, e exporte novamente.
4. Se houver crash ao armar um toggle, reabra o app: ambos voltam OFF automaticamente (sem persistência). Colete crash report do iOS e compare UUID/build antes de reativar.
