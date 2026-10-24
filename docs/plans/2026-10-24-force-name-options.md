# Force Name Download — editor de opções

Base solicitada: commit ff80c6bfb6cfd50597315c74aedb6697eb9e29e1, build 257 / run 40044800198. Não incorporar mudanças posteriores da flags.

Dez switches: with_universe_params, with_current_experiment_group, with_only_current_experiment_group, with_experiments, with_params, with_groups, with_group_params, with_gatekeepers, needs_name e skip_qe. Perfil em memória, aplicação desabilitada no início, restauração nativa e preset completo. A ampliação pedida pelo usuário inclui todas as consultas QE-info, com opção de limitar ao Force Name Download. Nunca alterar identificadores/credenciais por suposição.

1. Testes C++11 de perfil misto, preservação dos demais campos, isolamento por ação/thread, unwind e rejeição integral de campos ausentes/duplicados.
2. Núcleo e API de sessão; editor UIKit no painel existente. Modo todos QE-info explícito e modo somente performNameDownload com encoding, imagem, UUID e IMP verificados. Aplicação na cópia dos parâmetros antes do asyncFetch original. Snapshot do perfil na entrada da ação; callbacks e resultados preservados. Diagnóstico de device_id registra presença, duplicatas, comprimento, forma e igualdade efêmera entre pedidos, sem exportar identificador nem interpretar a forma como prova de validade.
3. Testes de integração do fetcher e estado no macOS CI, suíte local e arquitetura. PR sobre a branch da build257; CI iOS e pacote para instalação. A aceitação remota e o consumo no aparelho dependem de reprodução real.

O scope cobre o despacho síncrono observado na REA de performNameDownload→refreshNames→asyncFetch. Uma versão que adie o despacho para outra thread não recebe alteração por aproximação temporal; o diagnóstico mostra ausência de aplicação. Nenhum mc_overrides ou token é alterado.

4. REA/Ghidra nova: rastrear o serializer de device_id, a origem de sessão/ator e a fonte de server_value na UI, distinguindo snapshot persistido e consulta QE. Registrar decompilações reais e limites de cada conclusão antes de propor correção de identidade.
