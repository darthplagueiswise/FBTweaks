#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

void FBGRLogAppend(NSString *msg);
NSString *FBGRLogSnapshot(void);
void FBGRLogClear(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
