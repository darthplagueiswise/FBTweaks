#ifndef FBT_RUNTIME_BOOL_BROWSER_H
#define FBT_RUNTIME_BOOL_BROWSER_H

#import <Foundation/Foundation.h>

void FBTRuntimeBoolReloadPrefs(void);
void FBTRuntimeBoolReinstallPersistedHooks(void);
void FBTRuntimeBoolRetryPendingHooks(void);
NSArray<NSDictionary *> *FBTRuntimeBoolSearch(NSString *query, NSUInteger limit);
// BOOL storage (B encoding) discovered from ivar metadata, read-only.
NSArray<NSDictionary *> *FBTRuntimeBoolSearchIvars(NSString *query, NSUInteger limit);
NSDictionary *FBTRuntimeBoolOverridesSnapshot(void);
BOOL FBTRuntimeBoolHookInstalledForKey(NSString *key);
NSNumber *FBTRuntimeBoolObservedOriginal(NSString *key);
void FBTRuntimeBoolMigrateLegacySymbolOverrides(void);
BOOL FBTRuntimeBoolInstallPersistedKey(NSString *key);
void FBTRuntimeBoolSetOverride(NSDictionary *candidate, BOOL forcedValue);
void FBTRuntimeBoolClearOverride(NSDictionary *candidate);
void FBTRuntimeBoolObserve(NSDictionary *candidate);
void FBTRuntimeBoolClearAllOverrides(void);
void FBTRuntimeBoolClearSweep(NSString *mode);
NSUInteger FBTRuntimeBoolInstallSweep(NSString *mode, BOOL forcedValue, NSUInteger limit);
NSDictionary *FBTRuntimeBoolSweepStats(void);
// Bounded, per-process snapshot: saved/registered/invoked/pending/rejected and reasons.
// Registration reflects only successful local installer completion; invocation
// counters are the evidence that the installed wrapper actually ran.
NSArray<NSDictionary *> *FBTRuntimeBoolHookAuditSnapshot(void);

#endif /* FBT_RUNTIME_BOOL_BROWSER_H */
