# Settings Organization Implementation Plan

> For agentic workers: implement with the executing-plans workflow; each deliverable requires its tests and review.

**Goal:** tornar todos os recursos acessíveis por um menu consistente com Liquid Glass.
**Architecture:** catálogo Foundation de seções/rotas pesquisáveis; controller existente mantém os handlers; estilo UIKit compartilhado e aplicado às telas da tweak.
**Tech Stack:** Objective-C/UIKit, Foundation tests, Theos/iOS26.2, GitHub CI.
**Spec:** docs/superpowers/specs/2026-10-24-settings-design.md

## Global Constraints
- Base85a00ea1/build267; não incorporar flags posterior.
- Preservar preferências, handlers, confirmações e recursos.
- Liquid Glass só nas telas da tweak, com acessibilidade e fallback.

## Review Focus
- Rotas QE diretas presentes sem depender de alerta/captura.
- Itens do antigo hook de famílias não desaparecem nem são duplicados.
- Pesquisa encontra aliases e termos com acentos/mais de uma palavra; vazio tem estado próprio.
- Dynamic Type, modo escuro e Reduzir Transparência conservam legibilidade.
- Voltar de um submenu não fecha toda a tweak; root tem Concluído.

### 1. Catálogo e navegação
- [ ] Teste de cobertura de chaves/destinos e busca; observar falha inicial.
- [ ] Extrair catálogo e agrupar; adicionar rotas diretas; retirar injeção posicional do hook mantendo seus efeitos de toggle.
- [ ] Integrar busca global, header e navegação com labels/ícones consistentes.

### 2. Aparência
- [ ] Revisar APIs oficiais e implementar estilo compartilhado com fallback/acessibilidade.
- [ ] Aplicar no root e nos controllers existentes, incluindo diagnóstico/editor QE.
- [ ] Verificação visual em simulador quando possível; documentar limites.

### 3. Validação/entrega
- [ ] Testes de modelo/rota em Foundation, suíte local, arquitetura, revisão independente e build iOS.
- [ ] Publicar branch/PR derivado da build267 e entregar deb com caminho real do menu.
