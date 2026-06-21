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
// São EXPORTADAS mas NÃO importadas pelo exec -> fishhook não alcança
// chamadas internas do mesmo image. v3 tentou patch direto por dlsym, mas
// o crash real provou que isso suja __TEXT assinado nessa instalação.
// Portanto v3.1 não instala hook C direto aqui.
//
// Segurança de ABI: quando a pref está on, instalamos e SEMPRE retornamos
// YES sem chamar orig — logo a assinatura/args originais nunca são
// exercidos pelo nosso caminho (zero risco de ABI). Se a pref está off,
// nada é instalado.
// =====================================================================

// Direct C hooks intentionally absent. The valid paths for Dating are:
// 1) Employee/Internal gating hooks;
// 2) Runtime BOOL Browser for ObjC/Swift-dispatch gates;
// 3) MobileConfig native override/fishhook path for captured params.
// Keeping dummy orig/replacement symbols here breaks CI with -Werror.

// Chamado pelo Tweak.x apenas se a pref estiver on no launch.
void FBTInitDatingGroup(void) {
    FBTLog(@"dating: direct C hooks disabled; use Employee/Internal + Runtime BOOL Browser");
}
