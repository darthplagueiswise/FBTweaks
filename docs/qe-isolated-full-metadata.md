# QE Full Metadata: experimento isolado Facebook iOS 583

Base EXATA: head do PR #5, commit ff80c6bfb6cfd50597315c74aedb6697eb9e29e1; CI #257 (40044800198). O PR #6 anterior está descontinuado porque reativava o observer global.

## Arquitetura
O módulo src/Runtime/FBTMCQEIsolatedProfile.mm atua somente no data slot 0x8161f88 de FBSharedFramework, com alvo 0xa17f70 e UUID 4c4c44fe-5555-3144-a1c2-6ccae4ed2597. O rebinder exige UUID, região __DATA_CONST, ponteiro-alvo original e permissões compatíveis; falha fechada. Nunca altera __TEXT, hooka NSURLSession/NSError, muda hooks do Tigon ou instala o antigo QE observer.

FBT_ENABLE_QE_INVASIVE_HOOKS continua 0. O recurso tem define independente FBT_ENABLE_QE_ISOLATED_PROFILE, OFF por padrão: build normal ' ./build.sh rootless ' tem FBT_QE_ISOLATED=0; experimento exige ' FBT_QE_ISOLATED=1 ./build.sh rootless '. O CI publica variante QE-ISOLATED separada. A existência de build bem-sucedido não prova estabilidade no iPhone.

Um único POST com purpose mobileconfig_qe_info consome a autorização de 120 segundos. Requisições de valores mobileconfig/sessionless e GETs nunca são modificadas. Os nove campos precisam estar presentes uma vez e codificados como booleano, senão o request original é encaminhado inalterado.

## Perfil
needs_name=true; skip_qe=false; with_experiments=true; with_params=true; with_groups=true; with_group_params=true; with_gatekeepers=true; with_universe_params=true; with_current_experiment_group=true.
with_only_current_experiment_group é preservado, assim como device_id, USDID, OAuth, queries, api_version, identificação, sessão, roteamento e target. Um callback passthrough conserva a cópia dos pares até a conclusão, sem modificar status ou resposta.

## Compatibilidade de probes
O experimento é mutuamente exclusivo dos probes já existentes no PR #5. Não pressione 'Armar probes desta sessão' antes ou depois de instalar o slot isolado. Se já tiver instalado outro wrapper, reinicie o app; não há tentativa de empilhar hooks. Desarmar interrompe a mutação; para desinstalar o wrapper, reinicie o processo.

## Passo a passo e comparação real
1. Instale a variante QE-ISOLATED, reinicie Facebook 583, abra FBTweak > Fetch e contexto QE.
2. Inicie nova captura; NÃO arme os probes antigos.
3. Execute Force Name Download sem perfil e capture baseline pelo proxy Whitehat, em diretório privado.
4. Arme LAB isolado: QE Full Metadata (1 pedido / 120 s) e execute Force Name Download uma vez.
5. No diagnóstico confira qe_isolated_profile_request (before, after, changed, reason) e qe_isolated_profile_completion.
6. Em sessão separada do proxy Whitehat, capture o request HTTP final e a resposta real.
7. Execute:
   python3 scripts/qe_proxy/compare_profiles.py /privado/baseline/events.jsonl /privado/experimento/events.jsonl
A saída é JSON minificado (linha única) e mostra as nove flags serializadas, HTTP real e classificação do erro. NÃO exporte tokens, bodies completos ou chaves privadas da CA.

Uma resposta HTTP 400 OAuthException #100 Employee Account or Specific App Conditions permanece falha remota. O hook não contorna autorização Employee; HTTP 200 tampouco prova importação dos server_value ao cache.

## Limites
Os testes provam apenas a lógica C++ em isolamento e o contrato de exclusão dos hooks perigosos. CI prova compilação do pacote. Estabilidade em runtime, funcionamento do slot e aceitação do backend exigem captura no aparelho. Nenhuma resposta real foi fabricada.
