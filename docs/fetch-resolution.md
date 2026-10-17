# Resolução ampliada do diagnóstico de fetch

O diagnóstico recebido após o build 154 continha seis retornos QE-info falsos,
com duração aproximada de 197–213 ms, e download de nomes falso. Os stores de
valores têm conteúdo, enquanto os stores QCE não têm nomes. A captura genérica
Tigon declara instalação, mas não observa requisição nem corpo. Isso não
identifica a mensagem de erro do servidor e não prova bloqueio do sync inteiro.

## Interceptação no fetcher de MobileConfig

O payload mostra que o pedido `mobileconfig_qe_info` chama a primeira entrada
da vtable de `FBMobileConfigTigonFetcher`. O slot `0x8161f88`, em
`FBSharedFramework/__DATA_CONST/__const`, aponta para `0xa17f70`. RTTI e call site
confirmam o callback `std::function<void(bool, const std::string&)>`. A nova
instrumentação envolve esse callback, registra o resultado nativo e os bytes
retornados e encaminha o resultado e a resposta originais sem alteração.

O rebinding exige UUID `4c4c44fe-5555-3144-a1c2-6ccae4ed2597`, slot, ponteiro e
região de dados não executável compatíveis. Não altera instruções. O campo
`native_transport_success` representa o retorno desse callback; não é fabricado
um status HTTP. Os corpos continuam sujeitos aos limites e filtros da captura.
Credenciais e valores de parâmetros da requisição não são exportados.

O diagnóstico inclui `native_mc_requests`, `native_mc_responses` e
`native_mc_failures`. `native_hooks` mostra os ponteiros atuais, corrigindo a
ambiguidade entre uma tentativa inicial de hook sem imagem carregada e chamadas
posteriormente capturadas. Eventos idênticos de instalação são condensados e o
limite passou a 256, preservando seleções e falhas. O relatório contém as opções
relevantes e a identificação do build.

## Contextos da tela nativa

O ivar `_contextManagers` de `FBMobileConfigDebugViewController` contém seis
objetos, tem 48 bytes e inclui Sessionless, Session, Admin ID, Ad Account ID,
Page ID e Wearable Owner ID. A captura verifica nome, encoding, tamanho e limite
do objeto antes de ler esses campos. Isso registra os managers já existentes na
tela, sem ativar readers ou alterar o comportamento de Aquecer. O relatório
distingue `context_present` e `manager_ready` para cada contexto e permite usar
o caminho de overrides fornecido pelo manager, quando disponível.

## Acesso local aos parâmetros

**MobileConfig local — todos os mapas** lê os mapas v2 de `mobileconfig_res` no
aplicativo em execução. A IPA analisada contém 8.338 grupos de configurações e
63.527 registros de parâmetros nesses mapas, incluindo RN e Page/Admin ID.
Nomes disponíveis no catálogo fornecido são compactados no bundle; IDs e tipos
vêm dos mapas do aplicativo. Um nome ausente permanece numérico. Os mapas v4
binários não são reinterpretados como texto. Atualizações OTA não são declaradas
ativas por inferência.

O navegador permite buscar configuração/parâmetro por nome ou ID e gravar apenas
o tipo declarado no mapa. A gravação usa os IDs numéricos do formato nativo
`configID:nome -> [paramID: nome: valor]`, preserva outros parâmetros e dados QE,
conserva o alias existente e salva os bytes originais antes da primeira edição.
JSON inválido ou uma configuração com estrutura incompatível são recusados.
Valores em tela são overrides do arquivo, não valores atribuídos pelo servidor.
É preciso encerrar e reabrir o Facebook para reimportá-los.

O fallback do alerta de parâmetro agora abre esse catálogo, em vez de abrir uma
tela Live vazia dependente de readers observados. O fallback também está
disponível quando Aquecer está desligado. O painel principal fornece acesso
direto. Live mantém apenas opções do tipo efetivamente observado. A rotulagem
de chaves nativas cruza unidade, ordinal da configuração, ID do parâmetro, tipo
e slot; deixa de usar coincidência fraca com `slotId`/bits inferiores RN.

## Validação

O script LIEF/Capstone confere também o UUID, slot e callback do fetcher. O CI
executa testes Foundation de preservação de overrides, backup, strings com
separadores, remoção de um único parâmetro e recusa de arquivos inválidos antes
de compilar o pacote rootless ARM64. A execução real no aparelho ainda é
necessária para conhecer o retorno do novo ponto de captura e verificar a
reimportação dos valores gravados.

## Reanálise do build 155 — 17/10/2026

O diagnóstico exportado às 12:32 UTC contém 256 eventos retidos e 43 conclusões:

| Pedido | Sucessos | Falhas | Evidência |
| --- | ---: | ---: | --- |
| `mobileconfig_qe_info` | 0 | 33 | `FBHTTPErrorDomain code: 400` |
| `mobileconfig` | 6 | 0 | JSON de sync, incluindo respostas com configurações |
| `mobileconfigsessionless` | 3 | 0 | JSON de sync |
| `mobileconfiglogging` | 1 | 0 | confirmação de logging |

O ZIP contém 16 payloads JSON: oito respostas com `configs` preenchido, sete
com `configs` vazio e uma confirmação de logging. A maior resposta contém 37
configurações. Há também 56 textos de erro formatado 400. Os números do ZIP
cobrem mais tempo que a janela de eventos e não devem ser somados como pedidos
únicos. Isso refuta a interpretação de que todo o transporte MC está quebrado.
Os dois dumps de 172 bytes são respostas vazias bem-sucedidas; não demonstram
sozinhos perda do cache nem falha de autenticação.

Todas as 29 entradas QE iniciadas que ainda estão na janela têm estados de
arquivo `legacy_refresh=SYS` e `use_builtin_query_hash=OFF`. Não há comparação
ON/OFF nessa amostra. A ausência de `query_hash` nos parâmetros QE não prova
uma requisição malformada: QE e sync usam construtores distintos. A quinta
string está vazia também nos syncs bem-sucedidos e não é tratada como prova de
ausência de autenticação. Credenciais não foram exportadas.

O snapshot nativo confirma Sessionless, Session e Admin ID presentes/prontos;
Page ID, Ad Account ID e Wearable Owner ID estão ausentes da tela. Uma flag
local não cria automaticamente esses contextos. O arquivo mantém 679 entradas,
incluindo `skip_override_import=false`, `disable_rn_config_merge=false` e
`enable_forget_dev_experiment_bundle=true`. O último valor não comprova seleção
de um bundle Forget Dev em runtime. Nenhuma dessas opções foi regravada nesta
correção. O minidump do ZIP é de 04:35:30 UTC, anterior ao commit do build 155.

### Correções decorrentes da evidência

1. O primeiro argumento de `asyncFetch` é o método HTTP (`POST`), confirmado
   pelo construtor `TigonRequest` em `0xa18298`. O log deixa de chamá-lo de URL.
   A quinta string passa a ser descrita apenas como um argumento auxiliar.
2. `TigonSimpleCallbacks::onEOM` lê o status em `self+0x48` e transforma status
   fora de 200–299 em `FBHTTPErrorDomain`, com detalhe vazio, antes da conclusão
   MC. Portanto, os textos de 49 bytes capturados no build 155 não eram corpos
   HTTP originais. O build seguinte os registra como erro formatado e não os
   salva como corpo de resposta.
3. A vtable real de `TigonSimpleCallbacks` em FBSharedFramework é capturada nos
   slots de início, resposta, corpo, EOM e erro. O filtro limita esse caminho a
   URLs MobileConfig. O status vem de `TigonResponse+0`, confirmado pelo `ldrh`
   em `0xfde234`; o corpo é copiado antes da transferência do `unique_ptr` e
   salvo antes da conversão nativa de erro. UUID e os cinco ponteiros são
   conferidos; código executável não é modificado. A captura genérica anterior
   permanece disponível, com status próprio.
4. A instrumentação registra apenas tamanho/presença de campos de protocolo e
   valores booleanos permitidos, sem nomes de parâmetros de autenticação nem
   seus valores. A proveniência dos payloads é explícita. O schema 4 inclui um
   identificador aleatório de processo para distinguir eventos antigos dos
   contadores da execução atual.
5. Uma rejeição HTTP 400/401/403/404/410/422 observada no escopo da seleção
   impede a tentativa adicional do tweak e disponibiliza imediatamente a ação
   local no alerta original. O escopo usa estado compartilhado próprio, não um
   último erro global: callbacks tardios não contaminam a próxima seleção.
   Pedidos, resultados e tentativas do próprio Facebook são preservados.

### Reprodução e limites

`python scripts/analyze-mobileconfig-capture.py diagnostics.json AppGroup.zip`
produz contagens sem exportar credenciais, IDs de contas ou valores das flags.
O verificador LIEF/Capstone tem 37 checks para este IPA. O CI executa testes de
preservação de arquivos e testes dos callbacks reais com originais substituídos:
HTTP 400, corpo encadeado, propriedade do `unique_ptr`, encaminhamento uma vez,
filtro de endpoint, desligamento da captura, limites e escopos aninhados/tardios.

Esses checks e o build não demonstram que o servidor passou a aceitar QE. É
necessária execução do pacote novo para verificar se os callbacks da vtable
são chamados nesse aparelho e obter o corpo/status anteriores à conversão. Uma
resposta de permissão do servidor não pode ser corrigida fabricando metadados
ou reaproveitando um contexto Page ID de outra conta.
