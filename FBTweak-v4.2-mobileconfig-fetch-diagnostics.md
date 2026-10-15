# FBTweak — diagnóstico de MobileConfig/QE-info (15 out. 2026)

## Achado no AppGroup enviado após a tentativa

A evidência separa dois fluxos que antes estavam sendo tratados como se fossem o mesmo:

- **MobileConfig de valores/configuração:** as stores `mobileconfig/*.data` avançaram de geração `1` para `2` às 05:05:43Z e 05:07:13Z (02:05:43 e 02:07:13 em UTC−03). Os `.mctable` e `.meta` da geração mais nova têm hashes diferentes da anterior. A store `sessionless.data` também avançou de geração `2` para `3` às 05:07:19Z. Isto é evidência de que o fetch/sync normal de valores ocorreu.
- **Metadados QE-info:** as duas stores sob `mobileconfig_qce/*_pt_BR_V1.data` estão somente na geração `0`; cada `params_names_v4_u*.txt` é `[]` (0 nomes), e cada `0.mctable` tem 338 bytes. Foram modificadas às 04:47:40Z (01:47:40 UTC−03) e não avançaram junto com as stores gerais.
- Os dois `mc_sync_response_dump` também são de 04:47:40Z. Ambos registram `configs: {}`, `query_hash: null` e `extra.qce: "{}"`. Portanto, são snapshots vazios e **anteriores** à atualização de valores das 02:05–02:07. Não podem ser apresentados como resposta da tentativa mais recente.

## Interpretação

O problema não parece ser “Facebook não faz fetch de MetaConfig” em geral: os índices e tabelas gerais foram atualizados. O gap está no fluxo separado de **QE-info/param metadata** usado pela tela nativa `FBMobileConfigDebugViewController`; o cache QCE exportado continua vazio. O pacote não contém resposta de erro HTTP, status code nem detalhe de autorização, então não dá para distinguir, apenas com esse ZIP, entre uma consulta QE-info que não foi executada, resposta vazia, rejeição/permissão do backend ou falha de rede.

Os dumps de sincronização geral não devem ser usados como prova de que o endpoint QE-info foi chamado: são anteriores ao avanço das stores e representam `ukMobileConfigAdminId`/`ukMobileConfigSessionbased`, não necessariamente o request de param info.

## Instrumentação adicionada à branch `flags`

A nova ferramenta grava um arquivo redigido no container AppGroup ativo:

```text
mobileconfig/fbt_fetch_diagnostics.json
```

Ela registra nome do parâmetro/config, chave, backend (IDs longos mascarados), contextos vivos e horário UTC. A nova versão também fishhooks, sem patch de `__TEXT`, o import C++ `FBMobileConfigQEInfoManager::fetchQEInfoSynchronously` usado por `FBRarelyUsedFramework`: registra início, retorno booleano real e duração. Durante essa chamada, captura metadados de `NSError` (domain, code, HTTP/Tigon status e mensagem de erro disponíveis). No alerta nativo também guarda título e mensagem apresentados. Não lê nem grava cookies, headers, body/valores da resposta ou dados de sessão; mensagens passam por redação de credenciais e query strings.

O controle fica na tela principal: **FBTweak → Runtime → Log de fetch QE-info (ON/OFF)**. Ele começa desligado; ligue antes de reproduzir e desligue depois para pausar gravações. Os registros anteriores permanecem no AppGroup. Em **FBTweak → Runtime → MobileConfig Live**, o botão **Fetch log** mostra o retorno/erro; **Copiar JSON completo** copia o relatório redigido. O arquivo está em `AppGroup/mobileconfig/fbt_fetch_diagnostics.json` (container AppGroup ativo), para incluir no ZIP após reproduzir.

## Como reproduzir e interpretar

1. Instalar o pacote de `flags` e abrir o app.
2. Em `FBTweak → Runtime`, ligar **Log de fetch QE-info (ON/OFF)**. A captura persiste entre relançamentos.
3. Reproduzir a seleção na tela nativa de parâmetros.
4. Abrir `FBTweak → Runtime → MobileConfig Live → Fetch log` e copiar o JSON.
5. Interpretar o resultado:
   - `qe_info_import_hook.hook_installed=false`: o import não foi ligado nessa imagem/versão;
   - `selection_started` sem `qe_info_request_started`: seleção UI chegou, mas não entrou no método QE-info instrumentado;
   - `qe_info_request_returned.fetch_result=false`: método nativo executou e devolveu falha; olhar `native_network_error` e mensagem/status, quando existirem;
   - nenhum `native_network_error`, mas alerta “Refresh did not finish…”: o próprio cliente não obteve código server-side (timeout/rede ou erro sem código);
   - `fetch_result=true` e QCE vazio: a chamada terminou sem nomes em cache; investigar resposta lógica/compatibilidade da consulta.

A instrumentação não força permissões, não simula respostas e não altera valores MetaConfig. O status/código é registrado somente se o cliente o expuser em `NSError`; se o backend/Tigon não disponibilizar esse dado, o relatório indica retorno/duração e a mensagem nativa, mas não inventa um status nem coleta o corpo da resposta.
