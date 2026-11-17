# Utilitários compartilhados

Base: bf98d0fe89582b0c17e5d1a4718f4db9fcb283d1. Só refatoração; comentários e testes preservados.

## Problemas e decisão antes da edição

- Runtime/FBTCSymbolStub.m e Runtime/FBTCRuntimePatchResolver.m importam Settings/FBTBrowserCompat.h para acessar preferências. A persistência não pertence à interface de configurações.
- FBTUtils tem sua API distribuída entre a classe principal e uma categoria sem estado ou implementação substituível. Todos os métodos podem pertencer à classe que já os expõe.
- Consolidar declarações e implementações da categoria em FBTUtils; remover os dois arquivos da categoria e seus imports. Manter seletores, corpos, ordem das operações e comportamento de sincronização/toast intactos.
