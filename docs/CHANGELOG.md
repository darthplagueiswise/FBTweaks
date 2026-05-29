# FBTweaks Changelog

## 3.1.0 — Sideload-aware reads + C-symbol fishhook observability

### Leitura direta do container do app (sideload-safe)
`MCCatalog` agora lê `ReactMobileConfigMetadata.json` **direto do bundle do
app** (`[NSBundle mainBundle] pathForResource:...]`), antes de qualquer outro
caminho. Conferido: o arquivo no IPA (`Payload/Facebook.app/
ReactMobileConfigMetadata.json`, 1.379.197 bytes, 5374 params) é
**byte-idêntico** ao que estaríamos shipando.

Vantagens:
- **Funciona em sideload** sem depender de `/Library/Application Support/`
  (que não existe em sideload, só em jailbreak)
- **Zero risco de signature**: bundle do app é read-only e signed, só
  lemos o arquivo já assinado — não modificamos nada
- **Sem version drift**: o JSON do app combina exatamente com o binário do
  app, então não tem como ficar desatualizado
- A cópia em `/Library/Application Support/FBTweaks/runtime/` fica como
  fallback pra jailbreak

O FB também shipa `mobileconfig_res/params_map*.txt` e
`mobileconfig_res/params_names_v4_u*.txt` no bundle — disponíveis pra
ler diretamente quando precisarmos.

### Hook fishhook em `MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter`
Novo arquivo `FBGRMCNativeHooks.xm`. Símbolo C exported pelo
FBSharedFramework e imported pelo Facebook main binary (confirmado via
lief). Mesma técnica do `_METAIsLiquidGlassEnabled` que já funciona.

**Por que é sideload-safe**: fishhook reescreve as entradas do GOT do
binário **em memória do processo**, não toca em nada no disco. A signature
do framework permanece intacta.

**Escopo na v3.1: observabilidade only**. O hook só LOGA as chamadas (com
os 4 primeiros args em hex) quando o Observer está ligado. Não força
ainda nenhum retorno porque a assinatura exata da função ainda não foi
confirmada — forçar sem saber qual arg carrega o slotId resulta em
"forçar todo bool" (muito amplo) ou "forçar nada" (sem efeito).

**Próximo passo (v3.2)**: ligar Observer + reproduzir o gate alvo + ler
os logs → confirma qual arg é o identifier → adiciona forçamento
slot-aware no mesmo hook.

### Sem mexer no store nativo de overrides
Por design: `FBMobileConfigOverridesTable::updateOverrideForParam` exige
desempacotar `shared_ptr` libc++ e ter `this` correto. Em sideload, um
pointer errado crasha sem reverter. **Não faremos isso até ter teste
físico que prove a layout do shared_ptr.**

### Workflow
Branch `beta` é gatilho de build (junto com main/alpha/alpha2/dev).

---

## 3.0.0 — Base reescrita

(ver entrada anterior no histórico do repo)
