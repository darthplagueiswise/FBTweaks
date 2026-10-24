# Diagnóstico QE e Whitehat

Objetivo autorizado: distinguir a origem local do serviço/contexto usado pelo fetch QE da condição remota de elegibilidade. Não alterar credenciais ou resultados.

1. REA/Ghidra no Mach-O original: construção de Tigon, interceptores de sessão, associação manager/fetcher e importação nativa da CA. Registrar respostas e pseudocódigo.
2. Ampliar o painel existente: identificadores efêmeros de fetcher/serviço, associação demonstrável ao contexto, histórico por pedido e classificação explícita de desconhecidos. Não tratar proximidade temporal como ligação exata.
3. Proxy no computador do desenvolvedor: CA gerada pelo próprio mitmproxy, exportação pública, captura seletiva e sanitizada. Nenhuma chave privada no repositório.
4. Testes comportamentais de concorrência, correlação, isolamento e sanitização; executar suíte existente. Build iOS condicionado a SDK/Theos disponível; nenhuma alegação de teste no aparelho.
5. Entregar commit revisável e evidência REA atualizada. A regra privada do servidor permanece desconhecida até evidência dinâmica ou informação do serviço.
