#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
/// Read-only probes. Never change auth, VPN, network, employee or Bloks results.
void FBGRBloksTraceInstall(void);
void FBGRBloksTraceSetEnabled(BOOL enabled);
BOOL FBGRBloksTraceIsEnabled(void);
NSString *FBGRBloksTraceSnapshot(void);
NSString *FBGRBloksTraceStatus(void);
NSURL *FBGRBloksTraceFileURL(void);
void FBGRBloksTraceClear(void);
void FBGRBloksTraceMark(NSString *label);
#ifdef __cplusplus
}
#endif
