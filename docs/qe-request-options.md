# Opções QE e identidade observada

Base: build257, run40044800198, commit ff80c6bfb6cfd50597315c74aedb6697eb9e29e1. Este recurso não incorpora as mudanças posteriores da flags.

No painel **Fetch e contexto QE**, abra **Opções dos pedidos QE / Force Name Download**. Há dez switches para os oito with_*, needs_name e skip_qe. Os valores podem ser combinados livremente; o preset completo liga os oito with_* e needs_name e desliga skip_qe. O preset nativo de nomes restaura os oito with_* desligados, needs_name e skip_qe ligados. Presets não enviam pedidos nem habilitam a aplicação.

**Aplicar opções personalizadas** habilita o perfil nesta sessão e arma o fetcher existente após sua validação. O diagnóstico Tigon também é tentado; confira seu estado no painel principal. **Todos os pedidos QE-info** aplica o perfil às consultas de configs/params e nomes observadas pelo fetcher. Desligar esse switch limita o perfil à execução síncrona do performNameDownload verificado. O modo limitado exige RarelyUsed UUID4c4c448355553144a1face461bbe10aa, IMP0x211e78 e encoding v16@0:8. Sem correspondência, não associa o próximo pedido por temporizador. O modo geral usa a validação Shared já existente na build257.

O perfil começa desabilitado, reside em memória e se perde ao reiniciar. Pausar a captura ou cancelar testes no painel desabilita a aplicação. Os probes têm controles independentes; verifique que o fetcher está armado. Cada pedido obtém uma cópia coerente do perfil. Alterar os switches depois de iniciado não muda o pedido já preparado.

Abra o menu nativo e faça uma única consulta ou Force Name Download. No histórico, `qe_request_options_state=applied` comprova a alteração dos argumentos encaminhados ao fetcher original. `request_parameter_summary` mostra as opções efetivas; `schema_mismatch_native_preserved` significa que faltou algum campo ou houve duplicata e o pedido inteiro permaneceu nativo. Nenhum campo novo é acrescentado. O modo não altera mobileconfig/mobileconfigsessionless, queries, device_id, api_version, token, headers, routing hint ou target. A comprovação dos bytes finais na rede exige o proxy; interceptors posteriores podem acrescentar autenticação e outros dados.

Os resultados originais e os bytes dos callbacks são preservados. Pedir needs_name=false ou outros conjuntos de conteúdo pode impedir o parser de nomes de encontrar o mapa esperado. O teste não garante resposta aceita nem é apresentado como correção da rejeição Employee Account or Specific App Conditions.

`device_id_state`, `device_id_field_count`, `device_id_bytes` e `device_id_format` descrevem o campo nativo sem exportar seu valor. `device_id_observation_id` compara bytes idênticos neste processo; zero significa sem observação comparável (campo ausente, vazio, duplicado, excessivo ou limite da tabela). A tabela armazena no máximo128 valores de até4096 bytes em memória. Não compare IDs entre processos nem confunda esses números com conta, UUID de captura ou identidade do aparelho. UUID textual não é requisito presumido para esse endpoint. O valor e a autorização continuam não validados.

REA adicional da origem de identidade e server_value fica nos artefatos de análise, separadamente do código da tweak. Não há substituição de identificadores nem tentativa de reconstruir uma identidade a partir de UUID Mach-O.
