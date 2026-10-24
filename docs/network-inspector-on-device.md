# FBTweak Network Inspector — 100% no iPhone

## Escopo e implementação

O painel **FBTweak → Network Inspector — 100% iPhone** funciona
dentro do processo Facebook, sem CA, VPN, proxy, Frida ou computador.
A implementação agora **não exige o UUID da IPA 583 como único requisito**.

Os hooks são descobertos em runtime na imagem `FBSharedFramework`:

- `TigonSimpleCallbacks`: resolve a vtable exportada `_ZTV...`, encontra
  o método âncora `onResponse` e valida os símbolos exatos de
  `onStarted`, `onBody`, `onEOM` e `onError`. Cada slot precisa
  conter o ponteiro esperado e estar numa seção válida da imagem.
- `FBMobileConfigTigonFetcher`: localiza o RTTI exato pelo nome de classe,
  seu typeinfo e vtable, verifica o primeiro método virtual e a seção
  executável. A ABI de `asyncFetch` **não pode ser comprovada apenas pelo RTTI**:
  o probe continua experimental em builds novos e exige opt-in.
- Builds antigas que coincidam com o UUID/endereços da análise anterior
  ainda usam esse caminho como fallback.

A ferramenta permite **modo completo**, **somente Tigon** e **somente
Fetcher**, conforme os hooks realmente instalados. Se só Tigon funcionar,
captura respostas HTTP com IDs independentes e o marcador
`tigon_unclassified`; NÃO atribui um pedido genérico ao MobileConfig
sem correlação nativa. Se só o fetcher funcionar, registra os parâmetros
e callback nativos, mas não afirma ter visto o corpo HTTP original.

A correspondência é **por recursos e ABI observáveis**, não por versão
numérica do aplicativo. Isso não garante compatibilidade automática com
qualquer release que altere a ABI, remova símbolos ou use ponteiros
autenticados: nesses casos, os hooks recusam a instalação com diagnóstico
explícito, sem ignorar a validação.

Não é interceptação universal de todo o tráfego do Facebook.

### Dados disponíveis em cada registro JSON

- ID de requisição nativa, ID de sessão do processo, data, propósito, método.
- Lista de pares de parâmetros `asyncFetch` antes da construção do TigonRequest,
  sem sanitização. Essa lista **não prova o encoding final de rede**.
- Host, path, query e headers disponíveis no callback Tigon; a API
  `findHeader` permite apenas **nomes explicitamente consultados**, não
  enumeração de todos os headers.
- Código HTTP real, com sua origem (`TigonResponse`), e corpo HTTP
  observado antes da tradução para `FBHTTPErrorDomain`.
- Corpo recebido pelo callback nativo, sucesso/falha e duração.
- Corpo integral codificado em Base64 e SHA-256, além de prévia UTF-8 limitada.
- Observação: `OAuthException (#100) Employee Account or Specific App Conditions`
  é um retorno remoto. O inspetor não modifica identidade nem autenticação.

**Corpo Tigon e corpo do callback são diferentes.** Na falha HTTP 400,
um pode conter JSON do servidor, enquanto o callback pode conter apenas
`None domain: FBHTTPErrorDomain code: 400 detail:`. A distinção evita
atribuir o texto de erro do SDK ao JSON original do backend.


## Diagnóstico de vtables incompatíveis (Tigon)

Se os callbacks mostrarem `ambiguous_or_missing_vtable_anchor`, o Inspector
agora tenta um **segundo mecanismo somente para essa classe C++**:
interceptação das implementações exportadas de `onResponse`, `onBody`,
`onEOM` e `onError` por trampolins do CydiaSubstrate. Cada método precisa
resolver para código executável de `FBSharedFramework`; as chamadas
originais continuam sendo encaminhadas.

`onStarted` é opcional: várias builds compartilham um método vazio (`RET`)
entre dezenas de entradas virtuais. Interceptá-lo como se fosse um callback
exclusivo capturaria operações não relacionadas. Por isso, quando esse método
estiver vazio, a ferramenta o deixa intacto e identifica limitações de
metadados HTTP (host/path/headers). Os outros quatro callbacks podem recuperar
o corpo e os sinais de término da requisição.

O status de probes indica `tigon_hook_kind`, a quantidade de métodos
interceptados e as chamadas realmente observadas. Interceptar os símbolos
não garante que uma versão diferente despache por eles; só uma observação
real confirma uso. Não se atribuem corpos de respostas genéricas ao QE-info
sem correlação explícita.

Em fallback de método exportado, o Inspector **não lê offsets internos de
objetos conhecidos somente da versão 583** (tais como `self+0x48` ou
`self+0x80`). Quando a origem não tiver layout comprovado, o status é
classificado como candidato até confirmação.

### Diagnóstico automático dos parâmetros

Na aba Request, `request_diagnostics` mostra os números de configurações e
índices dentro de `queries`, além de `needs_name`, `skip_qe` e
`api_version`. `device_id_state=literal_parameter_name` destaca uma
eventual string placeholder, **somente antes do builder HTTP**.

Uma lista muito extensa e o placeholder merecem comparação com a requisição
serializada, mas não demonstram isoladamente a causa de um HTTP 400.
A resposta HTTP original continua sendo necessária para diferenciar payload
inválido, autenticação e elegibilidade remota.

## Segurança de armazenamento

A captura está **desligada no lançamento** e exige confirmação explícita.
A sessão não ativa novamente ao reiniciar. Os arquivos permanecem em
`Application Support/FBTweak/NetworkInspector`, sem App Group, com
`NSFileProtectionComplete`, permissões 0600, limite de 60 registros,
1 MiB para parâmetros e 2 MiB por corpo. Não há upload automático nem
transmissão para GitHub.

O operador pode abrir o JSON integral na UI (prévia máxima de 160 mil
caracteres), exportar um registro ou exportar todos usando o compartilhamento
do iOS; a UI confirma que esses arquivos podem conter credenciais.
**Apagar capturas** exclui os JSONs do sandbox.

A proteção do arquivo depende da segurança do dispositivo e da política
de backup escolhida no iOS. Não equivale a uma solução de segredo gerenciada
por hardware ou sanitização irreversível.

## Passos para usar

1. Abra FBTweak → **Network Inspector — 100% iPhone**.
2. Toque **Iniciar captura completa (local)** e confirme.
3. O painel valida/arma os probes do Tigon e do fetcher; se qualquer um falhar,
   informa quais foram instalados; quando um não existe, oferece modo parcial
   sem prometer correlação ou conteúdo que não foi observado.
4. Entre em **Internal Settings → MobileConfig → Advanced Settings →
   Force Name Download** ou atualize os valores.
5. Retorne ao painel: cada operação aparece com request ID, propósito e status.
6. Abra um registro, confira `request_parameter_pairs`,
   `known_request_headers`, `http_response_body` e
   `native_completion_body`. O Base64 guarda os bytes exatos.
7. Exporte para Files se desejar comparar os resultados fora do app e apague
   os JSONs quando não forem mais necessários.

### Limitações e próximos pontos de engenharia reversa

- Para captura completa do *request HTTP final*, ainda é necessário
  resolver pelo REA/Ghidra a leitura do corpo efetivamente serializado pelo
  `TigonRequest` e a enumeração geral de headers. O que está disponível
  hoje é a lista completa de parâmetros do `asyncFetch` (até o limite) e
  os headers conhecidos.
- Correlação entre Tigon e request ID usa a conclusão nativa executada dentro
  de `TigonSimpleCallbacks`. Sem o fetcher, o registro utiliza ID local
  independente e o rótulo `tigon_unclassified` em vez de simular um link.
- Nenhum hook modifica bytes de `__TEXT`, solicitações, respostas ou flags.
- O endpoint QE-info pode continuar retornando 400 por elegibilidade remota;
  instrumentação do cliente não concede permissões do servidor.

## Validação

```bash
python3 -m unittest discover -s tests -p "test_network_inspector_contract.py" -v
clang -fobjc-arc -framework Foundation tests/NetworkInspectorStoreTests.m \
  src/Runtime/FBTNetworkInspectorStore.m -o /tmp/fbt-inspector-tests
/tmp/fbt-inspector-tests
```

A compilação e a execução UIKit no dispositivo devem ser verificadas pelo
workflow Theos e num aparelho compatível com o UUID esperado.

Para verificar a descoberta dinâmica e os modos parciais:
```bash
python3 -m unittest discover -s tests -p 'test_network_inspector_adaptive_hooks.py' -v
```
