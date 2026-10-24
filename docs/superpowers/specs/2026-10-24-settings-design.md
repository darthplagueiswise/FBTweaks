# Ajustes organizados e Liquid Glass

Base exata: build267/head85a00ea1f6d0716fbba916a323a98b1b34e8e3fd, mantendo a linhagem da build257. Pedido direto: corrigir o menu não encontrado e reorganizar visualmente toda a tweak.

Causa observada: a raiz usa o título legado Diagnóstico do download de nomes, enquanto a tela se chama Fetch e contexto QE; o editor QE só é alcançado por um controle interno. A raiz mistura switches, ferramentas, ações e descrições de implementação. Um hook adicional injeta itens por índices fixos de seção.

Decisão: catálogo único de navegação com cinco áreas (MobileConfig, Rede e QE, Identidade e Internal, Interface e recursos, Ferramentas), atalhos diretos para diagnóstico QE, opções QE e inspetor de rede, busca global e estado geral/gesto. Preservar cada chave e ação existente, incluindo famílias acrescentadas pelo hook; retirar apenas a injeção por índice fixo. Identificadores estáveis das rotas e testes de cobertura evitam destinos órfãos.

Design: UIKit nativo com títulos claros em português, SF Symbols, espaçamento consistente, cartões legíveis e hierarquia curta. Liquid Glass real nos controles/painéis apropriados no iOS26; material nativo nos anteriores. Respeitar Reduzir Transparência, contraste, modo escuro e Dynamic Type. Sem personalizar globalmente a UI do Facebook. Busca com aliases encontra nomes antigos e os dez parâmetros QE. Ações destrutivas preservam confirmação.

Alternativas consideradas: apenas renomear a linha não resolve a mistura de controles; substituir tudo por uma UI custom abandona os fluxos existentes. Organizar o catálogo e manter os controllers/handlers atuais atende ao pedido com menor risco de regressão.

Limites: é reorganização e correção de acesso, sem novos privilégios, mudanças de fetch, defaults, overrides ou instrumentação. Build/CI e teste de navegação não substituem execução em aparelho; obter screenshots reais de simulador se o ambiente de CI permitir.
