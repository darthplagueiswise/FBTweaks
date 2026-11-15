# Correção de caminho, persistência e diagnóstico MobileConfig

Um contexto nativo podia fornecer `getOverridesTablePath` como `NSURL`, mas o editor aceitava apenas `NSString`. O caminho observado era descartado e a resolução caía nos grupos candidatos. Quando recebia uma string de diretório, o editor também podia tratá-la como o próprio arquivo. O leitor de valores seguia outro contrato e acrescentava `mc_overrides.json` ao diretório.

O normalizador compartilhado agora aceita URL de arquivo ou string absoluta. Acrescenta o nome quando recebe um diretório e preserva um caminho completo terminado em `mc_overrides.json`. URLs remotas e caminhos relativos são rejeitados. A consulta ao proprietário nativo confere uma assinatura de retorno de objeto sem argumentos adicionais antes do dispatch.

O controle SYS/OFF/ON agora recebe o erro da gravação, relê o estado do arquivo e só anuncia sucesso se a seleção foi persistida. O readback usa o ID numérico da configuração, acompanhando o writer que preserva um alias já existente. Falha de caminho, JSON inválido e erro de I/O deixam de aparecer como gravação bem-sucedida. O backup e a preservação das demais entradas continuam no writer existente.

## Evidência estática da IPA 587

A conferência adicional usou Facebook 587.0.0/build 1110946418. O SHA-256 de FBSharedFramework é `39c0233e3ffd5dc01b5849c2df8c82f47d550b22c98d9dc0e2fd97a16fb7161d`.

- A entrada Objective-C de `FBMobileConfigContextManager.getOverridesTablePath` é `0x2a18b64`. A chamada em `0x2a18b84` aponta ao getter C++ em `0x4ba66c`.
- O caminho de construção do resultado passa pelo helper `0x3f59400`. Seu tail aponta ao stub `0x5bdd314`, que referencia `_OBJC_CLASS_$_NSURL` e o seletor `fileURLWithPath:isDirectory:`. Isso confirma que aceitar somente `NSString` perde um tipo de retorno usado nesse ramo.
- O formatter nativo `overridesFilename`, em `0x19c070`, referencia o literal `mc_overrides.json` em `0x66e413c`.

Foram produzidos quatro dossiês REA/Ghidra 12.1.4 a partir de janelas ARM64 verificadas contra o Mach-O: `ev_7b279b4fe0ca503d9ca6539dd48d74a7209881d36edeb52c767be7f1010f5179`, `ev_aaf9fa269a0cdef65218e066d9f70ad7a85205d66af62520fb798da3e2d77c11`, `ev_c188fc56121921e0e1713baafb88cb4cf4e5d8ad71ce80451db9778b7f627b63` e `ev_1b424e0059e0d3b69974926d030f8318878bae3092e50a3cb03dc73087ce4cc8`.

Os recortes não contêm todos os helpers/dados externos. Eles estabelecem os vínculos acima, sem provar qual contexto está ativo no aparelho ou que todos os consumidores aceitem um override específico. A correção do caminho local não demonstra uma causa nem uma solução para rejeição remota de employee, Search ou Force Name Download.

## Diagnóstico no aparelho

O Inspector agora diferencia resultado nativo ausente de `false` observado e duração ausente de zero observado. O resumo conserva a origem do status HTTP e mostra ausência de observação quando não há código válido. Um corpo nativo omitido acima de 2 MiB conserva seu comprimento conhecido e o motivo `over_capture_limit`.

O modo anteriormente rotulado “Completo” passa a “Fetcher + Tigon”. Esses hooks não observam, por si, a espera síncrona do Search, a conclusão final de nomes ou a gravação do mapping. Os dados capturados continuam separados entre corpo HTTP e callback nativo.

## Verificação

A suíte Python executou 81 testes com sucesso, com três skips por dependerem de macOS/Foundation no host Linux. Há regressões Objective-C adicionais para URLs de diretório/arquivo, aliases, falhas de gravação, preservação de bytes/backup, campos ausentes, origem de HTTP e limite de corpo.

O workflow `mobileconfig-regressions.yml` executa as regressões Foundation no macOS em PRs para `flags` e `main`. Esse job não instala o tweak nem faz requisições ao Facebook. A execução dessas regressões no macOS e a validação funcional no iPhone devem ser acompanhadas separadamente; um teste de parser ou de persistência não demonstra sucesso com o servidor.
