#import "FBTPrefix.h"
#import "FBTDefaults.h"
#import <dlfcn.h>

// =====================================================================
// Dating (codinome "gemstone")
//
// Não existe um getter ObjC -isDatingEnabled limpo: o produto Dating é
// dirigido por entry-points + elegibilidade de servidor + gating interno.
// O lever principal é o MODO EMPLOYEE (ver FBTEmployeeMode.x), que destrava
// o gating interno de elegibilidade.
//
// Adicionalmente, forçamos as superfícies de mensageria do gemstone:
// funções C exportadas pelo FBSharedFramework (confirmadas em __text,
// retorno BOOL em w0):
//   _GemstoneMsysEnabled                @ 0x2dcec3c
//   _GemstoneMsysThreadViewEnabled      @ 0x2dee6f8
//   _GemstoneMsysThreadListEnabled      @ 0x2dee734
//   _GemstoneMsysInactivatedThreadList… @ 0x2dee770
// São EXPORTADAS mas NÃO importadas pelo exec -> fishhook não serve
// (só reescreve GOT do importador). Usamos MSHookFunction no endereço
// resolvido por dlsym. Flag latched: alternar exige restart.
//
// Segurança de ABI: quando a pref está on, instalamos e SEMPRE retornamos
// YES sem chamar orig — logo a assinatura/args originais nunca são
// exercidos pelo nosso caminho (zero risco de ABI). Se a pref está off,
// nada é instalado.
// =====================================================================

static BOOL (*orig_GemstoneMsysEnabled)(void) = NULL;
static BOOL (*orig_GemstoneMsysThreadViewEnabled)(void) = NULL;
static BOOL (*orig_GemstoneMsysThreadListEnabled)(void) = NULL;
static BOOL (*orig_GemstoneMsysInactivatedThreadListEnabled)(void) = NULL;

static BOOL fbt_GemstoneMsysEnabled(void) { return YES; }
static BOOL fbt_GemstoneMsysThreadViewEnabled(void) { return YES; }
static BOOL fbt_GemstoneMsysThreadListEnabled(void) { return YES; }
static BOOL fbt_GemstoneMsysInactivatedThreadListEnabled(void) { return YES; }

static void fbt_hookGemstone(const char *name, void *repl, void **orig) {
    void *sym = dlsym(RTLD_DEFAULT, name);
    if (!sym) { FBTLog(@"dating: %s não resolvido", name); return; }
    MSHookFunction(sym, repl, orig);
    FBTLog(@"dating: hook %s instalado", name);
}

// Chamado pelo Tweak.x apenas se a pref estiver on no launch.
void FBTInitDatingGroup(void) {
    fbt_hookGemstone("GemstoneMsysEnabled",
                     (void *)fbt_GemstoneMsysEnabled,
                     (void **)&orig_GemstoneMsysEnabled);
    fbt_hookGemstone("GemstoneMsysThreadViewEnabled",
                     (void *)fbt_GemstoneMsysThreadViewEnabled,
                     (void **)&orig_GemstoneMsysThreadViewEnabled);
    fbt_hookGemstone("GemstoneMsysThreadListEnabled",
                     (void *)fbt_GemstoneMsysThreadListEnabled,
                     (void **)&orig_GemstoneMsysThreadListEnabled);
    fbt_hookGemstone("GemstoneMsysInactivatedThreadListEnabled",
                     (void *)fbt_GemstoneMsysInactivatedThreadListEnabled,
                     (void **)&orig_GemstoneMsysInactivatedThreadListEnabled);
}
