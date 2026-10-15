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

Ela registra, para cada seleção na UI nativa, nome do parâmetro/config, chave numérica, tipo/rótulo de backend (IDs longos mascarados), quantidade de contextos vivos e horário UTC. Ao surgir o alerta `Failed to fetch param info from server!`, registra evento de falha e número da tentativa. O snapshot também lista gerações/horários/tamanhos das stores gerais e QCE, quantidade de nomes de parâmetro e resumo dos dumps de sync existentes. Não copia cookies, tokens, valores da resposta ou dados de sessão.

Em `FBTweak → MobileConfig Live`, o botão **Fetch log** mostra um resumo; **Copiar JSON completo** copia o relatório redigido. O próprio arquivo fica no AppGroup para ser incluído no próximo ZIP após reproduzir a falha. Isso permite decidir se a seleção chegou ao método, qual backend foi selecionado e se o cache QE-info mudou no instante da tentativa.

## Como reproduzir e interpretar

1. Instalar o pacote de `flags` que inclui esta instrumentação.
2. Reabrir o app, abrir a tela nativa de parâmetros e selecionar exatamente o parâmetro que falha.
3. Se aparecer o alerta, retornar a `FBTweak → MobileConfig Live → Fetch log` e salvar/copiar o JSON.
4. Interpretar o próximo relatório:
   - nenhum evento `selection_started`: hook/classe/selector da UI não foi alcançado;
   - `selection_started` sem alerta: não é prova de sucesso; conferir a tela e os caches;
   - `qe_info_failure_alert` com QCE ainda vazio: falha persistente no fluxo de metadata;
   - QCE passa a ter nomes/geração nova: resposta foi gravada, então investigar resolução/compatibilidade do parâmetro;
   - stores gerais avançam, mas QCE não: fetch geral funciona; isolar autorização/endpoint QE-info.

A instrumentação não força permissões, não simula respostas e não altera valores MetaConfig. Ela adiciona observabilidade para obter a causa concreta. Para fechar definitivamente um erro HTTP/permissão seria necessário um log do cliente que exponha status/código do request QE-info, sem credenciais.
