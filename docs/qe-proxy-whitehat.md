# Diagnóstico local de MobileConfig/QE-info com Whitehat

Este fluxo observa uma reprodução autorizada no seu próprio dispositivo/conta e no computador que executa seu proxy. O objetivo é distinguir formato da requisição, presença de Authorization no proxy e resposta HTTP. Uma resposta `400` com `OAuthException`, código `100`, e mensagem canônica `Employee Account or Specific App Conditions` é classificada como elegibilidade. São aceitos somente diferenças de maiúsculas/minúsculas, espaço nas extremidades e o prefixo opcional `(#100)`; negações, trechos isolados e mensagens desconhecidas ficam `unclassified`. Isso não determina qual condição do servidor falhou nem concede acesso a ela.

O addon não troca credenciais, não injeta headers, não modifica requisições/respostas e não desabilita a verificação TLS do servidor. Certificado e proxy não corrigem elegibilidade remota.

## Antes de instalar um certificado

Com o Whitehat nativo já habilitado, reproduza primeiro sem instalar uma CA adicional e registre o horário UTC. Reinicie completamente o Facebook depois de alterar a configuração Whitehat/proxy e repita uma vez. Observe o resultado real: sucesso TLS, falha de confiança, ausência de tráfego no proxy ou resposta HTTP. Não trate ausência de tráfego como prova de ausência de requisição, nem um HTTP 400 como falha de CA.

A REA do controlador Whitehat em `Rarely` confirmou que o seletor de documentos aceita certificado público DER e PEM: o callback em `0x1630954` lê o primeiro documento e tenta `SecCertificateCreateWithData`; no caminho PEM, remove os delimitadores e espaços, decodifica base64, valida novamente e grava DER. O destino calculado pelo helper `0x1426340` é o diretório Application Support do aplicativo com o nome `ProxyCACert.der`. A mensagem de sucesso exige reiniciar o app. O rótulo de status usa existência desse arquivo.

O importador dentro do aplicativo e um perfil confiável do sistema iOS são caminhos distintos. Não se observou instalação de perfil ou `SecItemAdd` nesse controlador. A presença de `ProxyCACert.der` e o alerta de sucesso não demonstram confiança global nem comprovam que o transporte MobileConfig consome esse arquivo; o consumidor no framework compartilhado e o efeito no aparelho precisam de validação. Essa limitação não altera o formato DER/PEM e o armazenamento local confirmados pela REA.

## Gerar/exportar a CA do proxy correto

Instale uma versão suportada do [mitmproxy](https://docs.mitmproxy.org/stable/overview/installation/) **no computador que efetivamente será o proxy**. Python 3 executa o helper e seu núcleo usa somente a biblioteca padrão; o processo de interceptação depende de `mitmdump` instalado. Não se gera uma CA neste ambiente para atribuí-la ao seu proxy.

A primeira inicialização do mitmproxy cria sua CA em `confdir`. O helper usa a CLI documentada `--set confdir=...`, em um diretório novo e exclusivo, e mantém o processo ativo. Execute na raiz deste repositório:

```bash
python3 scripts/qe_proxy/run_proxy.py \
  --directory "$HOME/qe-proxy-$(date -u +%Y%m%dT%H%M%SZ)" \
  --listen-host 192.168.1.10 \
  --listen-port 8080
```

Troque `192.168.1.10` pelo endereço LAN do computador autorizado que o telefone consegue acessar. O padrão do helper é `127.0.0.1`, acessível apenas localmente. O diretório pai precisa existir; o diretório de sessão não pode existir. Configure o proxy Wi-Fi do telefone para esse endereço/porta. Não use `--ssl-insecure`, `-k`, injeção de Authorization, HAR ou salvamento de flows brutos.

O helper imprime os caminhos depois que o **próprio mitmdump** cria um certificado público completo, abre o listener e inicializa o arquivo privado do addon. São disponibilizados:

| Arquivo | Conteúdo |
| --- | --- |
| `public-ca/proxy-ca.pem` | Certificado público PEM desta instância |
| `public-ca/proxy-ca.der` | Mesmo certificado público, DER |
| `public-ca/sha256.txt` | Fingerprint SHA-256 do DER |
| `events.jsonl` | Somente os resumos permitidos descritos abaixo |

Se a reprodução sem CA adicional exigir a importação, transfira somente `public-ca/proxy-ca.der` para o seletor de certificado do Whitehat e reinicie completamente o app após a mensagem de sucesso. O PEM público também corresponde ao formato aceito identificado na REA. Compare o fingerprint no computador e no caminho de importação/confiança usado no telefone antes de reproduzir. Um certificado de outra instalação do mitmproxy ou do Burp não corresponde a esta sessão. Mantenha o processo inicializado pelo helper como o proxy durante o teste; iniciar outro proxy com outro `confdir` produz outra CA.

O diretório de sessão, `confdir` e pasta de exportação são privados (`0700`); os arquivos gerados/herdados pelo processo usam `0600`. A chave privada permanece no `confdir` do computador do proxy. **Não compartilhe `confdir`, `mitmproxy-ca.pem`, arquivos de chave, PKCS#12 ou dumps brutos.** O helper copia apenas o `mitmproxy-ca-cert.pem` público, rejeita conteúdo de chave privada e exporta os formatos públicos. Não exporta a chave nem cria uma CA substituta.

A saída normal do mitmdump é suprimida para evitar URLs/headers no terminal. Se a inicialização falhar, a mensagem do helper é fixa: confira localmente a instalação, a porta e as opções suportadas (`mitmdump --options`). Não cole logs brutos para depuração.

## Se o proxy existente for Burp

Na **instância atual** do Burp, abra Settings → Tools → Proxy → Proxy Listeners → Import / export CA certificate e selecione Export → Certificate in DER format. Não exporte chave privada. Confira o fingerprint no computador do Burp e no telefone; não use os arquivos de CA produzidos pelo helper mitmproxy para confiar no Burp. As instruções de instalação/perfil/confiança do sistema continuam distintas do importador no app. Este addon é do mitmproxy e não é executado dentro do Burp; não há importador de históricos Burp/HAR neste pacote.

## O que é registrado

São selecionados somente `graph.facebook.com` e os caminhos exatos `/mobileconfig_qe_info`, `/mobileconfig` ou `/mobileconfigsessionless`, opcionalmente precedidos por uma versão como `/v20.0/`. Sufixos, outros hosts, caminhos com IDs e outros endpoints ficam de fora. Os CSVs revisados do build 159 preservam o nome da operação, sem URL/path; não confirmam prefixos `/me/`, `/method/` ou IDs de ator. A ocorrência `/method/` nos testes nativos é uma fixture sintética. Se sua versão usa outro caminho, confirme somente o formato do path por evidência local antes de ampliar a seleção; não exporte IDs de conta ou a URL completa.

Cada linha contém evento, horário UTC, UUID local e resumo com enumerações fixas. O resumo da requisição inclui método permitido, rótulo do endpoint, presença/esquema de Authorization observado em `proxy_wire`, e forma dos campos permitidos. Nunca inclui o valor de Authorization. Nem presença nem esquema comprovam validade do token, identidade ou elegibilidade. Um header ausente no proxy não prova ausência em outro transporte/caminho.

Os formatos JSON e formulário URL-encoded preservam valores somente para uma lista explícita de opções de protocolo: `needs_name`, `skip_qe`, os `with_*` já documentados no fetcher nativo e `api_version`. Booleanos são normalizados a true/false; outros valores recebem `invalid`; opções repetidas recebem `duplicate`. `api_version` aceita somente inteiro não negativo com até cinco dígitos. Isso permite comparar o perfil de download de nomes (`needs_name`/`skip_qe` e opções de conteúdo) sem tratar essas opções como permissões de employee. Campos arbitrários com prefixo `with_` não são incluídos.

`queries` contém somente forma e quantidade limitada, inclusive quando o formulário transporta um array JSON como string. `app_id_present` e `app_id_count` registram apenas existência e quantidade de ocorrências, incluindo duplicatas; nenhum ID de app/conta é exportado. `body_auth_field_present` informa somente se o campo de corpo `access_token` existia: true/false quando o corpo foi analisado, null quando indisponível/inválido/excedido. Essa presença também não comprova validade da autenticação.

A resposta inclui status HTTP, forma limitada e erro classificado. Somente `OAuthException`/outro, `100`/outro e `eligibility`/`unclassified` são exportados; mensagem, trace ID e detalhes desconhecidos não saem. O texto do erro é usado somente para reconhecer a mensagem canônica completa descrita acima e é descartado. Corpos/formulários JSON são limitados a 64 KiB; query string a 8 KiB; formulários a 64 campos; contagens são limitadas a 1000. Corpos codificados/comprimidos recebem `encoded`, sem descompressão. Corpos transmitidos sem retenção recebem `unavailable`; isso não prova corpo vazio. Formato inválido/excedido tem rótulo fixo. Os conteúdos de queries/variables, parâmetros de identidade, tokens, contas, URLs e corpos não são exportados; somente os valores de protocolo explicitamente permitidos acima são preservados.

O proxy encaminha tráfego e termina TLS normalmente para conexões que passam por ele; ele tem acesso ao tráfego bruto em memória. O addon limita o que analisa e registra. O helper desativa dumps de console e não grava HAR/flows, e usa `stream_large_bodies=64k` sem armazenar corpos transmitidos. Mantenha a reprodução pequena e feche outros aplicativos que possam usar o proxy.

O arquivo para após 1000 eventos ou 2 MiB; não há rotação nem sobrescrita. Uma requisição e sua resposta ocupam duas linhas. UUIDs `local_exchange_id` associam apenas esses eventos dentro do proxy. **Não são IDs de sessão do aplicativo e não demonstram correlação automática com os eventos nativos.** Compare manualmente horário UTC, sequência de ações, endpoint e resultado com o diagnóstico nativo; anote eventual diferença entre relógios.

## Reprodução e interpretação

1. Anote versão/build do Facebook e FBTweaks, sistema, horário UTC e estado Whitehat. Ative o diagnóstico nativo seguro conforme a interface do tweak; não habilite hooks invasivos para este teste.
2. Faça uma única ação QE-info, espere a resposta e marque o horário. Preserve o nome da ação, não parâmetros/valores de experimento.
3. Compare o status e a classe do erro com o alerta nativo. Se houver `eligibility`, o servidor devolveu a condição reconhecida; isso não revela se a causa é conta, app, versão ou uma combinação. Não há correção remota implementada aqui.
4. Para investigação posterior, forneça apenas metadados: versões, plataforma, endpoint permitido, método, HTTP status, enumeração do erro, presença/esquema de Authorization e horários UTC. Não forneça credenciais, conta/UID, valores de queries, URLs completas, corpos, CA privada ou arquivos de sessão nativa brutos.
5. Encerre com Ctrl+C. Desative o proxy do telefone e remova uma confiança/perfil de teste que você tenha instalado quando concluir. A CA pública só deve permanecer confiável enquanto esse proxy autorizado for necessário.

Os testes padrão validam o núcleo, objetos de fluxo sintéticos, permissões, limites, exportação pública/fingerprint e o ciclo de processo com executável fixture. A validação opcional adicional foi executada com **mitmproxy 12.3.0, Python 3.12.14 e OpenSSL 4.0.3**, instalados somente em um venv temporário: interface real `http.HTTPFlow`, geração da CA pelo mitmdump, equivalência PEM/DER e CONNECT HTTPS até um servidor de loopback com certificado assinado por uma CA local separada. O cliente verificou a CA exportada do proxy; o proxy aceitou o upstream quando a CA da fixture foi explicitamente confiada e rejeitou esse upstream com HTTP 502 sem essa confiança. Nenhuma requisição foi enviada ao Facebook. Esses resultados não comprovam instalação no iOS, consumo do arquivo importado pelo transporte, autenticação nem aceitação do backend. A semântica de formato/armazenamento do importador acima vem da REA, não dos testes TLS.

```bash
python3 -m unittest discover -s tests -p test_qe_proxy.py -v
```

Para repetir o teste de integração em um venv isolado (sem acrescentar dependências ao projeto):

```bash
python3 -m venv /tmp/qe-proxy-mitmproxy-venv
/tmp/qe-proxy-mitmproxy-venv/bin/pip install 'mitmproxy==12.3.0'
FBT_QE_PROXY_LIVE=1 /tmp/qe-proxy-mitmproxy-venv/bin/python \
  -m unittest discover -s tests -p test_qe_proxy.py -v
```

O teste adicional escuta somente em loopback, cria certificados temporários de fixture e termina os processos ao concluir. O helper oferece `--upstream-ca /caminho/ca-publica.pem` para confiar explicitamente numa CA de um upstream controlado de laboratório, usando a opção oficial `ssl_verify_upstream_trusted_ca`; a verificação TLS continua habilitada. O teste não exige essa opção para tráfego normal com cadeias públicas válidas.

## Referências oficiais

- [mitmproxy: certificados e distinção entre CA privada e certificado público](https://docs.mitmproxy.org/stable/concepts/certificates/)
- [mitmproxy: opções `confdir`, `flow_detail`, `stream_large_bodies` e `store_streamed_bodies`](https://docs.mitmproxy.org/stable/concepts/options/)
- [mitmproxy: hooks de eventos HTTP e ciclo do addon](https://docs.mitmproxy.org/stable/api/events.html)
- [Burp: exportar certificado CA](https://portswigger.net/burp/documentation/desktop/tools/proxy/manage-certificates)
