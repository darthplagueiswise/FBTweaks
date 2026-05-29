#pragma once
#import <Foundation/Foundation.h>

/// Guard __cplusplus: header incluído de .xm (C++) com implementação em .m (C).
#ifdef __cplusplus
extern "C" {
#endif

void      FBGRLogAppend(NSString *msg);
NSString *FBGRLogSnapshot(void);
void      FBGRLogClear(void);

#ifdef __cplusplus
}
#endif
