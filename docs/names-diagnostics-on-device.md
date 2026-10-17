# Diagnóstico de nomes dentro da FBTweak

Na branch `flags`, abra **FBTweak → Diagnóstico do download de nomes**. O mesmo painel abre em **MobileConfig Live → Fetch log**.

1. Toque **Iniciar nova captura**. Isso liga apenas o diagnóstico e prepara os hooks; não muda overrides, a conta nem o pedido.
2. Volte à tela nativa **Internal Settings → MobileConfig → Advanced Settings → Force name download** e tente uma vez.
3. Retorne ao painel. Ele mostra o último pedido `mobileconfig_qe_info` e seu resultado, associados pelo ID do pedido e pela sessão do processo. O painel atualiza enquanto está visível.
4. Use o botão Compartilhar para salvar/enviar `fbt_names_diagnostic.json` pelo iPhone, ou **Copiar relatório JSON**. **Pausar captura** interrompe a persistência. Nenhum computador ou Frida participa da execução.

## O que muda na captura nativa

- O fetcher nativo registra `api_version`, os booleanos de protocolo, presença de device ID e forma/quantidade de queries. Valores de identidade, credenciais e conteúdo das queries não são exportados.
- Uma janela de pedidos MC pendentes permite copiar provisoriamente os chunks de SimpleCallbacks mesmo sem `onStarted`. São no máximo 32 contextos de 2 MiB e 60 segundos. Bytes provisórios de outros pedidos ficam apenas em memória e são descartados no terminal sem correlação MC.
- A conclusão nativa dentro de `onEOM` **ou `onError`** confirma a identidade do objeto de callbacks e associa o corpo ao ID exato. A cópia ocorre antes de o callback original consumir o IOBuf; seus argumentos e propriedade continuam intactos.
- O fallback já existente recupera o IOBuf retido em EOM quando os callbacks anteriores não foram observados. O caminho de erro não lê esse layout de EOM.
- Cadeias quebradas e limites excedidos invalidam o corpo completo. Corpo indisponível é registrado explicitamente; a descrição `None domain: FBHTTPErrorDomain code: 400 detail: ` nunca é classificada como resposta HTTP.
- Gzip é descomprimido no próprio aparelho, com limite de 2 MiB descomprimidos. Código, subcódigo, tipo e mensagem remota sanitizada são incluídos no relatório. `id_to_names` é validado como array de strings e contado sem exportar seus valores.
- A exportação usa a folha de compartilhamento do iOS. Se o App Group não estiver disponível, o relatório e os payloads usam o sandbox da tweak no app. O relatório compartilhado não inclui os arquivos de payload bruto.

## Limites observáveis

Os slots e layouts são aceitos apenas no FBSharedFramework UUID `4c4c44fe55553144a1c26ccae4ed2597` da amostra Facebook 583. A tela informa falha de instalação em vez de anunciar captura pronta. O pedido nativo pode continuar retornando HTTP 400: esta mudança investiga a rejeição, sem alterar o contrato ou marcar falha como sucesso.

`not_delivered_to_observed_callback` significa que nenhum corpo útil foi entregue nessa superfície, não que o servidor respondeu JSON vazio. A próxima investigação nesse caso é a camada Tigon anterior. Um retorno com `id_to_names` válido também não comprova, sozinho, que o app gravou `id_name_mapping.json`; a escrita continua sendo responsabilidade do fluxo nativo.

Testes no CI incluem encaminhamento dos callbacks, propriedade do IOBuf, correlação sem onStarted, término por onError, exclusão de tráfego não correlacionado, ausência de corpo, parsing tipado, sanitização, gzip truncado e limite de descompressão. O build e os testes em macOS não substituem a execução do pacote no iPhone.
