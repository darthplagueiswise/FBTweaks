#ifndef FBT_PREFIX_H
#define FBT_PREFIX_H

// Force-included em TODOS os TUs (inclui fishhook.c, que é C puro).
// Por isso os imports ObjC ficam atrás de __OBJC__: em C, o prefixo é vazio.
#ifdef __OBJC__

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// CydiaSubstrate (vem no IPA injetado). Em rootless, é mobilesubstrate.
#import <substrate.h>

// Logging condicional. Build de produção: FBT_FILELOG=0.
#if defined(FBT_FILELOG) && FBT_FILELOG
  #define FBTLog(fmt, ...) NSLog((@"[FBTweak] " fmt), ##__VA_ARGS__)
#else
  #define FBTLog(fmt, ...) do {} while (0)
#endif

#endif /* __OBJC__ */

#endif /* FBT_PREFIX_H */
