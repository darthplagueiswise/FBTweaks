# Reimportação e leitura nativa de overrides

O usuário confirmou que testou ambos os JSONs dentro do diretório mobileconfig. O arquivo fora desse diretório era experimental e não é causa demonstrada do OAuth #100. A alteração anterior de resolução de caminho não soluciona esse erro.

Objetivo: permitir reimportar o arquivo pelo manager selecionado e distinguir o valor retornado pela tabela nativa do valor alterado pela tweak. Preservar SYS com ignoreOverrideForInternalUse. Suspender somente a camada da tweak durante a leitura nativa, em thread-local com restauração mesmo em exceção.

Usar o getter ObjC de shared_ptr já validado e o export getOrCreateOverridesTable(bool force). No Shared 584.1, 0xd7725c..0xd77274 chama load quando force=true. O retorno de uma tabela não certifica parsing nem aplicação; apresentar leitura posterior e origem. Recusar contexto ausente, ambíguo ou ABI incompatível. A ação não grava JSON, não altera credenciais e não inicia fetch.

Alternativas: reiniciar não oferece evidência de leitura; editar a tabela com updateOverrideForParam testaria outra operação. A chamada force com leitura posterior responde diretamente à recarga do arquivo. Escolha de implementação feita pelo agente dentro do pedido para executar a correção, sem nova rodada de aprovação.

A tela deve oferecer a ação por parâmetro e exportar valor nativo, origem nativa e resultado de retorno da recarga. Não chamar a leitura sintética de execução do consumidor. Configs de startup já copiadas para singletons/fetchers exigem evidência separada no consumidor; recarregar a tabela não reconstrói esses objetos.

Não criar seletor fictício de identidade: ativo/acting/mapa/origem são fontes resolvidas pela sessão, não parâmetros em mc_overrides.json. Nenhuma combinação foi testada com autorização remota neste ambiente.
