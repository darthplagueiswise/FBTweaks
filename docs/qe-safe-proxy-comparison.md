# Comparação QE-info sem reativar o observer invasivo

## Estado de origem

Esta branch foi criada a partir **exatamente** do commit `ff80c6bfb6cfd50597315c74aedb6697eb9e29e1` (head do PR #5, `codex/qe-session-proxy-debug`).

O PR #6, que introduziu `FBT_QE_LAB=1` e o experimento de nove campos no `FBMobileConfigTigonFetcher::asyncFetch`, reutilizava a infraestrutura invasiva que havia provocado instabilidade anteriormente. Essa não é uma estratégia aceitável para reproduzir o erro. **O hook de mutação não faz parte desta branch.**

## O que esta branch altera

- Somente o parser e o launcher Whitehat **read-only**, os testes Python, o comparador de eventos e a chamada adicional ao teste no CI.
- Os hosts explicitamente observados pela captura passam a ser `graph.facebook.com`, `graph.prod.facebook.com` e `graph.trunkstable.facebook.com`.
- O limite de corpo interpretável passa a 256 KiB para permitir `queries` grandes; IDs, valores de `queries`, URL completa, token, header bruto e texto livre do servidor não entram no evento exportado.
- `compare_profiles.py` correlaciona apenas **dentro de cada sessão do proxy** a requisição QE e a resposta HTTP por `local_exchange_id`. O script exporta apenas booleanos conhecidos, presença do perfil e classificação/status da resposta.

**Não há alterações em `src/Runtime`, `src/Settings`, `Makefile` ou scripts de build.** Nenhuma flag `FBT_QE_LAB` é definida. O modo padrão do PR #5 continua `FBT_ENABLE_QE_INVASIVE_HOOKS=0`.

Os probes de sessão do PR #5 ainda existem e podem ser ativados manualmente com UUID/ABI checks; este pacote **não afirma que eles foram testados no aparelho ou que são isentos de crash**. Para este teste, não arme esses probes nem use antigos modos LAB.

## Execução sem intervenção no cliente

1. Com uma versão de aplicativo/conta autorizada, inicie o proxy Whitehat seguindo `docs/qe-proxy-whitehat.md`. Ele deve ser o **mesmo proxy** cujo certificado público foi importado; não desabilite validação TLS upstream.
2. Sem ativar probes nativos, reproduza uma operação QE-info e registre o `events.jsonl` sanitizado em um diretório privativo. Esta é a linha de base.
3. Se houver outra reprodução autorizada com configuração diferente, gere uma **segunda** sessão de proxy. Este pacote não cria essa diferença modificando o aplicativo.
4. Compare:

```bash
python3 scripts/qe_proxy/compare_profiles.py \
  /privado/baseline/events.jsonl \
  /privado/segunda-sessao/events.jsonl
```

A saída do comparador é JSON em **linha única**. `full_metadata_observed_on_proxy_wire=true` significa que o proxy observou todos os nove booleanos especificados; não comprova autorização ou sucesso da sincronização. `server_error=eligibility` classifica o `OAuthException (#100) Employee Account or Specific App Conditions` efetivamente recebido.

### Limites

Esta implementação **não força** `skip_qe=false`, `with_params=true` ou outras flags no aplicativo. Para isso é necessário estudar um ponto de extensão isolado e estável, validado *no dispositivo*, sem acionar novamente o bloco global de hooks invasivos. O REA fornece evidências estáticas de funções e ABI, mas não valida por si só a segurança de um hook durante o runtime.

Nenhum resultado de rede ou autorização foi fabricado. O proxy é observacional quanto aos campos HTTP, mas estabelece uma sessão de proxy/TLS opt-in na infraestrutura local do usuário; usar somente em dispositivos/contas sob administração própria. Nunca publique `events.jsonl` sem antes conferir seu conteúdo e nunca publique certificados privados do proxy.
