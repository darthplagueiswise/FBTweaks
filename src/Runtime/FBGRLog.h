#pragma once
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void FBGRLogAppend(NSString *msg);
NSString *FBGRLogSnapshot(void);
void FBGRLogClear(void);

#ifdef __cplusplus
}
#endif
