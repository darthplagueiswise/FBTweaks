# Resolução ampliada do diagnóstico de fetch

O diagnóstico recebido após o build 154 contém seis retornos QE-info falsos,
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
