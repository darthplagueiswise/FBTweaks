#ifndef FBT_INTERNAL_IMPORTS_H
#define FBT_INTERNAL_IMPORTS_H

#import <Foundation/Foundation.h>

void FBTInstallInternalImportHooks(void);
void FBTInternalImportReloadPrefs(void);
NSDictionary *FBTInternalImportStatus(void);

#endif /* FBT_INTERNAL_IMPORTS_H */
