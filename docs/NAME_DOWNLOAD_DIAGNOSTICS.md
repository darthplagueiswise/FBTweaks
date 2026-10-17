# Diagnóstico de Force name download

Este observador foi conferido estaticamente para Facebook **583.0.0 / 1090364060**, módulo FBSharedFramework UUID **4c4c44fe55553144a1c26ccae4ed2597**. **NÃO EXECUTADO NO IPHONE.** Testes em host não comprovam attach nem funcionamento no aparelho.

## Executar no computador conectado ao iPhone

Requer Frida já funcional em um processo de teste autorizado e instrumentável. Ter o FBTweaks instalado não garante que Frida possa anexar ao processo. O observador é uma ferramenta separada; não é incorporado automaticamente à dylib pelo build.

No checkout desta branch:

```bash
python3 -m venv .venv-names
. .venv-names/bin/activate
python3 -m pip install frida-tools
python3 scripts/capture_names.py --process Facebook --output diagnostics/names_diagnostic.jsonl
```

Abra o Facebook antes do comando. Aguarde `observer_ready`, acesse **Internal Settings → MobileConfig → Advanced Settings → Force name download** e faça uma tentativa. Espere `qe_transport_diagnostic` e pressione Ctrl+C. O arquivo JSONL é salvo no computador. Use outro nome de saída para repetir; o coletor não sobrescreve capturas.

Se o nome do processo for diferente, use `--pid NUMERO` ou `--process NOME`. Para escolher um dispositivo já disponível no Frida, use `--device ID`. `observer_start_failed` com `module_UUID_mismatch` ou `instruction_mismatch` significa que a build diverge; os offsets precisam ser revalidados antes de usar.

Alternativa sem o coletor Python, com saída interativa:

```bash
frida -U -n Facebook -l scripts/trace_names_transport.js
```

## O que a análise já comprovou

- A operação é `mobileconfig_qe_info`, com `needs_name=1` e `skip_qe=1` no pedido forçado.
- O ramo de sucesso procura `id_to_names`, integra os nomes e serializa o mapa local em `id_name_mapping.json`.
- O erro nativo `FBHTTPErrorDomain / 400` devolve `false` e pula esse parsing/gravação; a UI exibe o alerta genérico.
- Os 49 bytes `None domain: FBHTTPErrorDomain code: 400 detail: ` são uma descrição nativa, não o corpo HTTP. Seu SHA-256 é `df4eaf85e3c8c97f4c409cefaaeb270d0ae093990e83402fd1a75664d948a719`.

## Ajustes implementados no diagnóstico

O pedido é correlacionado à construção do callback, sem depender de `onStarted` (que retorna imediatamente nesta amostra). Chunks de `onBody` são preservados até `onError` ou `onEOM`. O log distingue corpo remoto, descrição nativa, corpo indisponível, gzip e falha de captura. Credenciais/identificadores não fazem parte do contrato exportado; mensagens são sanitizadas e limitadas. A captura não inclui headers, cookies, tokens ou conteúdo de nomes.

Nesta integração, o sanitizador também trata campos entre aspas e Bearer, erros de leitura do status são isolados, falhas de instalação removem hooks parcialmente instalados, e a perda de um chunk invalida o corpo inteiro. O coletor grava eventos estruturados em arquivo novo com modo inicial 0600. A sanitização é heurística: revise mensagens antes de compartilhar.

## Interpretar e continuar

1. `qe_request_contract`: conferir `api_version`, flags e forma/quantidade de `queries`; IDs não são exportados.
2. `qe_callback_correlated`: confirma a associação ao objeto de callbacks.
3. `qe_transport_diagnostic`: conferir `terminal`, `native_error`, `body_status`, `error.code`, `error_subcode`, `type` e `message` quando presentes.
4. `not_delivered_to_observed_callback`: nenhum corpo chegou a essa superfície. Será necessário observar a camada Tigon anterior; não confundir ausência de captura com resposta vazia.
5. `gzip_not_decoded`: o observador não descomprime a resposta; requer camada após descompressão ou extensão validada do coletor.
6. `capture_error` ou `observer_error`: evidência incompleta. `http_status_candidate` é uma leitura de layout ainda candidata, separada do código de erro nativo.

O coletor deve devolver evidência para decidir a correção. A causa específica do HTTP 400 continua desconhecida. A análise não justifica alterar arbitrariamente `api_version`, hashes, flags ou permissões. O observador não cria `id_name_mapping.json`, não muda argumentos/retornos e não repete requisições.

## Validação no computador

```bash
node --check scripts/trace_names_transport.js
node scripts/test_names_capture.js
python3 -m unittest discover -s tests -p 'test_capture_names.py'
```

APIs primárias: https://frida.re/docs/javascript-api/ e https://frida.re/docs/messages/ . Os layouts C++/IOBuf e endereços derivam dos binários desta build, não de garantias gerais do Frida.
