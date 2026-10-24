# Fetch QE: diagnóstico de serviço e sessão

O painel **Fetch e contexto QE** amplia a captura existente. Ele registra por pedido o perfil de opções, o resultado nativo e HTTP, o serviço/fetcher observado e snapshots dos contextos da UI. Nenhum resultado ou credencial é alterado pelos probes de sessão.

Integração com a branch `flags` atualizada: o Network Inspector existente também recebe `tigon_service_snapshot` com os novos identificadores nos registros por pedido. Ele possui captura integral local, mediante confirmação própria, que pode conter credenciais; seu export é diferente do JSON sanitizado deste painel e do JSONL do proxy. Consulte [network-inspector-on-device.md](network-inspector-on-device.md).

1. Abra o diagnóstico em FBTweaks e toque **Iniciar nova captura**.
2. Toque **Armar probes desta sessão**. Confira os dois hooks instalados e os dois probes habilitados. Se falhar a verificação de UUID/slot, o painel informa captura incompleta. Reiniciar desarma os probes.
3. Reabra Internal Settings > MobileConfig e selecione um item. Isso permite observar a estrutura nativa de contextos e o caminho contexto → manager → fetcher → serviço.
4. Execute separadamente: consulta de informações QE, Advanced Settings > Force name download, refresh dos valores e, se necessário, refresh sessionless. Não altere conta, employee ou overrides entre as tentativas de base.
5. Compare `service_observation_id` e `fetcher_observation_id` dos pedidos e dos eventos `mc_ui_service_snapshot`, no mesmo processo e em horários próximos. Compartilhe o JSON do painel. Para observar HTTP no proxy, siga [qe-proxy-whitehat.md](qe-proxy-whitehat.md).

**Limites do resultado:** o identificador é uma observação efêmera de ponteiro, não identidade permanente do objeto. As leituras da UI são snapshots consistentes nas verificações feitas, sem transação/garantia de vida útil concorrente. Um `ui_context_kind=session` correspondente ao fetcher reduz a incerteza local, mas não identifica a conta do token nem prova autorização remota. Objetos podem ser recriados ou ter endereços reutilizados. IDs ausentes, capacidade esgotada, getter alterado ou captura tardia significam desconhecido. O painel não chama métodos privados C++ para tentar reconstruir a sessão.

O modo padrão deixa controles que modificam employee/request restritos ao build LAB preexistente. A captura normal é observadora, e **Pausar captura** desarma os dois probes. As leituras de `validate_auth_header` mostradas pelo backend legado permanecem observações do construtor no processo; não são o valor efetivamente usado por um pedido sem ligação adicional demonstrada.

## Evidência de layout

Fontes: Mach-O extraído da IPA fornecida, FBSharedFramework SHA-256 `5fe5f5da428a19cafaa5a1a42da8d59776ab8f9ceccad4beab476538d1d2b3ea`, UUID `4c4c44fe55553144a1c26ccae4ed2597`; sessões REA/Ghidra `shared_auth_service_01` e `rarely_whitehat_ca_01` no pacote de evidências.

- `FBMobileConfigContextManager::getManager`, `0xe3a41c`: lê `context+0x248`; metadado Objective-C `^v16@0:8`.
- Getter nativo do fetcher, Rarely `0x109f54`, e `FBMobileConfigManager::setFetcher`, Shared `0x46e934`: manager contém o shared_ptr do fetcher em `+0x148/+0x150`.
- Construtor do Tigon fetcher `0x46e800`: vptr `0x8161f88`, serviço em `+0x50`; `asyncFetch 0xa17f70` chama o slot `+0x10` desse serviço em `0xa185c8`.

O probe requer o rebinder já validado, getter com encoding/IMP originais e tamanho da instância, vptr do fetcher correto e leituras VM verificadas. Compara manager/fetcher novamente antes de emitir o evento. Nenhum ponteiro bruto é exportado.

A captura de callbacks já copia o corpo em memória sob limites. O modo de sessão agora extrai apenas formato, contagens e erro normalizado; não grava o corpo. Uma resposta reconhecida `OAuthException/100/Employee Account or Specific App Conditions` continua sendo rejeição remota. O motivo privado exato — ator, autenticação ou condições da aplicação — exige evidência adicional do pedido/servidor; não há override local comprovado como solução.

## Validação

- Testes comportamentais C++11 do registro de identidades: concorrência, capacidade, nulos e isolamento após reset.
- Testes Python de proxy, incluindo mitmproxy real e TLS local verificado, descritos no guia do proxy.
- Testes Foundation/Objective-C++ adicionados para o modo de metadados, callback preservado e ausência de arquivos de corpo, executados pelo workflow macOS/iOS.
- A aceitação do snapshot no app real e a associação ao ator/token continuam dependentes de teste no aparelho. Nenhuma resposta nova do Facebook foi obtida nesta implementação.
