#ifndef FBT_RUNTIME_BOOL_BROWSER_H
#define FBT_RUNTIME_BOOL_BROWSER_H

#import <Foundation/Foundation.h>

void FBTRuntimeBoolReloadPrefs(void);
void FBTRuntimeBoolReinstallPersistedHooks(void);
NSArray<NSDictionary *> *FBTRuntimeBoolSearch(NSString *query, NSUInteger limit);
NSDictionary *FBTRuntimeBoolOverridesSnapshot(void);
void FBTRuntimeBoolSetOverride(NSDictionary *candidate, BOOL forcedValue);
void FBTRuntimeBoolClearOverride(NSDictionary *candidate);
void FBTRuntimeBoolClearAllOverrides(void);

#endif /* FBT_RUNTIME_BOOL_BROWSER_H */
