# REA + Ghidra: análise forense e decompilação de IPA

O pipeline é **offline e externo à FBTweak**. Ele recebe uma IPA autorizada, extrai os Mach-O originais, registra SHA-256/UUID/criptografia e usa o REA como cliente CLI do decompilador Ghidra. **Não** instala Ghidra no iPhone nem altera o Facebook.

## Versões fixadas

- [REA de morluto](https://github.com/morluto/rea): pacote oficial `rea-agents@6.7.0`.
- [Ghidra da release de heaven-hm](https://github.com/heaven-hm/re-agent/releases/tag/engine-preview-2026-10-13): arquivo `ghidra_12.1.2_PUBLIC_20260605.zip` (572.803.866 bytes), SHA-256 `b62e81a0390618466c019c60d8c2f796ced2509c4c1aea4a37644a77272cf99d`.
- REA requer Node `22.23.4+`, `24.22.1+` ou `26.12.1+`, e Ghidra exige um **JDK 21+ completo**. Outros requisitos: `python3`, `curl`, `unzip`, `npm` e `procps` no Linux.
- REA documenta compatibilidade Ghidra 12.1.x, mas a distribuição 12.1.2 exata precisa passar por `rea doctor` e decompilação real. Nenhum smoke test de decompilação pode ser substituído por um teste com CLI simulada.

## Setup

Executar na raiz da branch `flags`:

```bash
bash scripts/rea/install-ghidra.sh
bash scripts/rea/install-rea.sh
export GHIDRA_INSTALL_DIR="$PWD/.rea-tools/ghidra/ghidra_12.1.2_PUBLIC"
export REA_BIN="$PWD/.rea-tools/rea/node_modules/.bin/rea"
export GHIDRA_HEADLESS_MAXMEM=6G
"$REA_BIN" doctor --provider ghidra --json
"$REA_BIN" providers --json
```

Instalação isolada em `.rea-tools/`; não altera o build do Theos. O download do Ghidra é verificado antes da extração. É possível usar uma instalação de Ghidra confiável já existente, ajustando `GHIDRA_INSTALL_DIR`.

## Extrair a IPA, sem falsificar evidências

```bash
python3 scripts/rea/prepare_ipa.py --ipa /caminho/Facebook.ipa --output /fora-do-git/analise-583
```

A extração considera `Payload/*.app/Facebook` e cinco frameworks relevantes quando existem; registra `CFBundleIdentifier`, versão, SHA-256 da IPA, SHA-256 de cada imagem, `LC_UUID` e `LC_ENCRYPTION_INFO`. A saída fica **fora do Git**. `cryptid != 0` é sinalizado e o REA não tenta decompilar esse alvo. Para exigir uma IPA específica, informe `--expected-ipa-sha256 HEX`.

## Inspecionar todos os Mach-O e decompilar funções selecionadas

```bash
bash scripts/rea/run.sh --ipa /caminho/Facebook.ipa --output /fora-do-git/analise-583 --resume
bash scripts/rea/run.sh --ipa /caminho/Facebook.ipa --output /fora-do-git/analise-583 --addresses scripts/rea/facebook583-addresses.example.json --resume
```

O runner chama `rea doctor --provider ghidra --json` e `rea inspect <imagem> --provider ghidra --json` para cada alvo. Para endereços explicitamente fornecidos no JSON, chama também `rea function`, `rea decompile`, `rea xrefs` e `rea instructions`, salvando os JSONs sem truncá-los. O runner rejeita `addresses` que não coincidam com o **SHA-256 ou UUID** da imagem e não aceita endereços decimais. **Matching de UUID não demonstra a semântica da função**.

Arquivos gerados: `ipa_manifest.json`, `binaries/<modulo>` (proprietários), `rea/doctor.json`, `rea/<modulo>/inspect.json`, `rea/<modulo>/{function,decompile,xrefs,instructions}_0x*.json` e `rea_run.json` (com ações, erros e skips).

Um `--resume` somente aceita a mesma IPA e os mesmos hashes de imagens. Confirmar manualmente pseudocódigo e XREFs, particularmente dispatch ObjC e `BLR`, antes de rotular conclusões como **CONFIRMADO**. Uma flag booleana não prova autenticação employee, dogfood ou sucesso do QE server.

## MCP e agente

Após validar o provider, executar `"$REA_BIN" setup` no host onde a IPA/Ghidra estão instalados, selecionar o cliente MCP compatível e aprovar a configuração. O REA expõe ferramentas para navegar funções e XREFs iterativamente. O conector GitHub **não** fornece acesso automático ao MCP local, aos arquivos da IPA ou ao Ghidra. É necessário instalar o servidor no mesmo host de análise.

## Uso para MobileConfig e Employee

Analisar os leitores de MobileConfig e chamadas reais, gerenciadores de sessioned/sessionless, callbacks, Internal Settings, cadeia QE/Tigon e XREFs dos consumidores. O REA é **evidência estática** e não substitui traces de runtime e testes de fetch em aparelho. O JSON de exemplo foi derivado da análise anterior de FB583 e serve apenas como âncora de investigação.

## Verificação

```bash
python3 -m unittest discover -s tests -p 'test_rea_pipeline.py' -v
python3 -m py_compile scripts/rea/prepare_ipa.py scripts/rea/analyze_ipa.py
for f in scripts/rea/*.sh; do bash -n "$f"; done
```

O CI executa somente contratos sobre uma IPA sintética; **não** baixa 573 MB de Ghidra nem faz upload de binários proprietários. Uma integração operacional fim a fim só é validada com `rea doctor` e `rea decompile` reais.
