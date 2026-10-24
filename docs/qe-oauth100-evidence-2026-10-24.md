# OAuthException #100 — 2026-10-24: o que a evidência realmente mostra

## Auditoria das capturas Facebook 583

Foram examinados 15 arquivos de tentativas de `mobileconfig_qe_info` (dados recebidos pelo usuário; **nenhuma requisição de rede foi efetuada nesta auditoria**).

| Observação | Resultado |
| --- | --- |
| Respostas HTTP 400 completas com `OAuthException` / `Employee Account or Specific App Conditions` | 14 |
| Entre as 14, `skip_qe=true` com `device_id` literalmente `device_id` | 12 |
| Entre as 14, `skip_qe=false` com `device_id` não literal | 2 |
| Hosts das 14 rejeições | `graph.facebook.com` (7), `graph.prod.facebook.com` (6), `graph.trunkstable.facebook.com` (1) |
| Tentativa restante | Sem status HTTP/corpo de servidor verificado no recorte |

A presença do cabeçalho OAuth confirma apenas transmissão de credencial observada, **não** validade do token, vínculo de ator/sessão ou permissão remota. O código numérico 100 é genérico; a mensagem específica explicita uma condição de conta/aplicativo sem informar **qual**. Não foi observada resposta 200 do QE-info nessas capturas.

**Conclusão:** alternar `skip_qe`, preencher `device_id` ou trocar entre esses hosts não resolveu a rejeição nas tentativas observadas. O experimento dos nove seletores `with_*` não atribui elegibilidade de conta. Não há evidência de `mc_overrides.json` que autorize o endpoint no servidor.

## Separar dois problemas

1. **Fetch remoto QE-info:** exige que o serviço reconheça a credencial, contexto e condições do aplicativo/conta. A condição faltante só pode ser identificada pelos logs/configuração do backend responsável. Se houver acesso autorizado, enviar a esse time `fbtrace_id`, horário UTC, caminho, host, versão/build e contexto de app **sem enviar OAuth token**.
2. **Ler nomes e configurações locais:** a tweak já oferece `FBTLocalConfigCatalog` com `FBTLocalConfigNames.json.gz` e mapas `mobileconfig_res` da IPA. Caminho: **FBTweak → Fetch e contexto QE → Abrir mapa local**. Esse catálogo permite consulta offline e leitura local do valor efetivo quando o contexto nativo está disponível; não equivale a recuperar `id_to_names` ou valores remotos pelo serviço privado.

O fluxo nativo `refreshNames` usa `needs_name=true`, `skip_qe=true` e demais opções `with_*=false`. O teste isolado de Full Metadata no PR #9 é **outro perfil**, não um reparo do protocolo nativo de Force Name Download.

## Estado da correção

- **Não resolvido:** autorização do endpoint privado. A investigação local não tem acesso às regras/allowlists do backend.
- **Disponível:** diagnóstico de rejeição real, catálogo offline e comparação com os pedidos serializados usando proxy opt-in.
- **Ainda não validado:** efeito do hook isolado em runtime no iPhone e eventual HTTP final da nova variante.

Atenção: os JSONs de origem contêm cabeçalhos `Authorization: OAuth` completos. Trate-os como credenciais sensíveis e não os publique em issues, logs CI ou anexos públicos. Avalie revogação/rotação das credenciais expostas. Este documento não contém tokens.
