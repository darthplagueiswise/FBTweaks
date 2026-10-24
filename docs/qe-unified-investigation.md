# Diagnóstico causal unificado: Facebook 583 MobileConfig / QE-info

## Base

Derivado de `codex/force-name-request-options` commit `85a00ea1f6d0716fbba916a323a98b1b34e8e3fd`, que produziu as capturas `qe_custom_options` com `ten_options_applied`. Não foi incorporado o antigo perfil `FBT_QE_LAB`; `FBT_ENABLE_QE_INVASIVE_HOOKS=0` continua o padrão. **Este patch NÃO introduz nem instala hooks adicionais.**

O end-to-end é **uma investigação**, mesmo quando há diferentes endpoints: preparar os argumentos, montar o HTTP, escolher sessão/autorização, receber resposta, aplicar e persistir nomes e valores. Encontrar um hash ausente em uma camada não prova que ele seja exigido por outra.

## Evidências consolidadas dos dados do usuário

16 exports de `NetworkInspector` fornecidos no contexto foram examinados. Todos são `POST /mobileconfig_qe_info` e registram status HTTP 400; o corpo inclui `OAuthException` código 100 e `Employee Account or Specific App Conditions`. Todas as capturas contêm listas JSON de queries com membros únicos e contagens entre 3.314 e 4.287. Nenhuma das 16 contém `query_hash` nem `one_query_hash` em `request_parameter_pairs`, que são os **argumentos nativos anteriores à construção do TigonRequest**.

14 registros trazem `device_id` com o literal `device_id` (o REA original também identificou esse marcador no caminho `refreshNames`). Outros dois levam um identificador textual diferente, sem alteração do resultado HTTP 400. Isto enfraquece fortemente a hipótese de que simplesmente substituir o literal por UUID resolverá a recusa. Não registrar nem substituir credenciais ou device IDs completos nos logs sanitizados.

`FBTMobileConfigTigonCapture.mm` inspecionava `TigonURLQuery` para inferir `query_hash` e `one_query_hash`. O request usa `POST` e `Content-Type: application/x-www-form-urlencoded`. Logo, `missing` naquele getter significava apenas ausência **na query da URL**, não ausência comprovada no corpo HTTP. A observação original do fetcher, por sua vez, verifica os pares pré-serialização. Esta alteração nomeia as duas etapas sem fingir acesso a um terceiro lugar.

## Correções aplicadas

1. Estados nativos de hash ausente passam a `absent_in_native_pairs`, origem `native_request_parameter_pairs_before_serialization`, e contrato `not_verified_for_qe_info`. O contador/estado de hash presente mantém o comportamento anterior. **Nenhum hash foi fabricado ou inserido na requisição**.
2. Estados do Tigon provenientes da URL mudam para `not_in_url_query`, com origem `url_query_only_not_form_body`. A captura não alega observar o POST body final.
3. O request inicial agora conta consultas estruturadas, entradas com formato inesperado e duplicação (com limite de memória), sem exportar strings das consultas.
4. O painel **Fetch e contexto QE** mostra todas as etapas causalmente, até o código remoto e a ausência de confirmação de importação/persistência.
5. `scripts/qe_pipeline_audit.py` consome capturas locais autorizadas e resume o processo num **JSON minificado de linha única**, sem OAuth, IDs, queries, headers ou textos livres.

## Execução do diagnóstico integrado

```bash
python3 scripts/qe_pipeline_audit.py registro-73.json registro-9.json
```

Faça também uma execução autorizada com `mobileconfig` e `mobileconfigsessionless` e guarde os eventos/sync responses **sem headers de credencial** para verificar seus hashes e a aplicação dos valores. Esse outro tipo de request não é intercambiável com `/mobileconfig_qe_info`, mas deve ser relacionado pelo contexto autenticado, tempo e sequência de execução. **Nenhum esquema de hash QE-info foi comprovado**; não gere MD5/SHA improvisado nem copie `query_hash` do endpoint de valores para QE-info.

`4626:mobileconfig_session` índice 4 (`use_builtin_query_hash`) é uma possível linha de pesquisa para o sync nativo. Sua leitura efetiva e o efeito nessa IPA ainda não foram estabelecidos causalmente para QE-info. Ativar o override local sem essa prova não resolve o erro de elegibilidade do servidor.

O REA/Ghidra fornecido anteriormente identifica `FBMobileConfigQEInfoManager::refreshNames`, `fetchQEInfoSynchronously`, `FBMobileConfigTigonFetcher::asyncFetch` e as callbacks de resposta. O REA não contém o predicado privado de autorização executado no backend Meta; não afirmar que ele foi descoberto.

## Critérios de correção real

- **Consulta:** request nativo contém a lista esperada; nenhuma duplicação ou parâmetro ilegal.
- **Identidade:** campos locais e sessão selecionados conforme contrato e a autenticação efetivamente autorizada (não apenas header OAuth presente).
- **Rede:** request HTTP final verificado em proxy Whitehat, inclusive corpo POST. `TigonURLQuery` sozinho não basta.
- **Backend:** resposta HTTP 2xx com dados válidos para o endpoint QE-info; se 400/100 persistir, a operação continua recusada por elegibilidade remota.
- **Persistência:** parser retorna sucesso, `id_to_names` válido é salvo e recarregado; valores efetivos devem ser verificados pelo sync/reader, não inferidos do download de nomes.
- **Estabilidade:** nenhuma reativação de `FBT_ENABLE_QE_INVASIVE_HOOKS=1`, sem novos hooks/swizzles nesse patch.

Este relatório não contém o token presente nos exports integrais. **Uma credencial OAuth presente nesses arquivos deve ser tratada como segredo exposto e revogada/rotacionada, quando aplicável.** Não compartilhe os JSONs brutos; utilize o auditor sanitizado.

## Limitações

A correção comprova observabilidade e interpretação honesta, não concessão de autorização remota. Não existe evidência que justifique inserir `query_hash` ou `one_query_hash` nos requests QE-info nem um override capaz de tornar elegível uma conta. O próximo bloqueador objetivo é a autorização do servidor, além da validação independente de persistência depois de um retorno permitido.
