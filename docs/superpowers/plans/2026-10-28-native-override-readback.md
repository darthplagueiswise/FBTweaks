# Native override readback Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan.

**Goal:** Reimportar o arquivo no contexto escolhido e expor o retorno nativo sem forcing da tweak.
**Architecture:** Ponte C++ restrita ao manager capturado; inspeção ObjC compartilha seleção de contexto, distingue SYS/nativo/tweak e mantém a recarga explícita.
**Tech Stack:** Objective-C, Objective-C++, Foundation, XCTest-style fixture executável, Python unittest, REA/Ghidra.
**Spec:** docs/superpowers/specs/2026-10-28-native-override-readback-design.md

## Global Constraints

- Sem patch de __TEXT, gravação de credenciais ou escolha arbitrária de tokens.
- Retorno da recarga não é sucesso de parsing nem de OAuth.
- Sem recarga implícita nas leituras existentes.

## Review Focus

- Exceções não deixam bypass da tweak ativo.
- Contextos ambíguos não são recarregados.
- Retorno de tabela não é rotulado como importação confirmada.
- SYS continua ignorando overrides nativos e da tweak.
- Valores de startup não são rotulados como já consumidos pela rede.

### Task 1: Recarga explícita e leitura posterior

Files: src/Runtime/FBTNativeMobileConfigOverrides.{h,mm}; src/Runtime/FBTMobileConfigValueReader.{h,m}; src/Runtime/FBTMobileConfigRuntime.m; tests/MobileConfigValueReaderTests.m.

- [ ] Testar leitura nativa distinta da tweak, recarga antes da leitura, falha e ambiguidade.
- [ ] Observar falha no fixture macOS do CI.
- [ ] Implementar FBTNativeMobileConfigReloadOverridesForContext(id, NSString **) e FBTMobileConfigReloadAndInspectParameter(NSDictionary *, NSDictionary *).
- [ ] Manter leitura existente sem recarga e fornecer native_effective_value/source.

### Task 2: Ação e documentação

Files: src/Settings/FBTLocalConfigViewController.m; relatório de investigação.

- [ ] Expor reimportação explícita no menu do parâmetro, mostrar resultado sem afirmar parsing confirmado.
- [ ] Documentar nomes completos, fontes de token e limitações de validação.
- [ ] Rodar suite completa, build iOS e revisão independente; registrar REA e CI.
