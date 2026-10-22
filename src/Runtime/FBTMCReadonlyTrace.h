#ifndef FBT_MC_READONLY_TRACE_H
#define FBT_MC_READONLY_TRACE_H
#import <Foundation/Foundation.h>

// Observes existing FBT diagnostics and native value-source reads.
// No native code patching, no rebinding, no network request, no bypass.
NSDictionary *FBTMCReadonlyTraceEnrich(NSString *event, NSDictionary *details);
BOOL FBTMCReadonlyTracePermitSourceRead(void);
#endif
