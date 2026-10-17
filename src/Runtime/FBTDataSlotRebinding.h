#import <Foundation/Foundation.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
// Only __DATA_CONST,__const in the exact supplied arm64 executable is eligible.
BOOL FBTRebindVerifiedMainConstSlot(uint64_t address, const unsigned char uuid[16],
                                   const char *symbol, void *replacement,
                                   void **original, NSString **failure);
#ifdef __cplusplus
}
#endif
