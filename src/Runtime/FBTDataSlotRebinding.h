#import <Foundation/Foundation.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
// Only __DATA_CONST,__const in an exact UUID-verified arm64 image is eligible.
BOOL FBTRebindVerifiedMainConstSlot(uint64_t address, const unsigned char uuid[16],
                                   const char *symbol, void *replacement,
                                   void **original, NSString **failure);
BOOL FBTRebindVerifiedImageConstSlot(const char *imageName, uint64_t address,
        const unsigned char uuid[16], uint64_t targetAddress, void *replacement,
        void **original, NSString **failure);
// Resolve a C++ RTTI class name from the loaded Mach-O and inspect its
// unique vtable/typeinfo pair. Hooks the first virtual method ONLY after
// validating its address points to executable code in the same image.
// Manual opt-in still required because C++ virtual ABI stability cannot be
// proven from RTTI alone across every app version.
BOOL FBTRebindImageFirstVirtualByRTTI(const char *imageName, const char *typeName,
        void *replacement, void **original, NSString **failure);

// Version-flexible alternative: discover the vtable and method from their
// exported C++ symbols in the *loaded* image, then verify the target pointer
// and slot belong to that exact image before rebinding. relativeIndex is the
// signed number of pointer-width slots from the unique anchor method.
// No hard-coded LC_UUID or unslid virtual slot addresses are used.
// Validate the full target vtable/slot layout without making any memory
// writes. The installer must validate all required slots before patching any.
BOOL FBTValidateImageVtableSlotBySymbols(const char *imageName,
        const char *vtableSymbol, const char *anchorMethodSymbol,
        const char *expectedMethodSymbol, int relativeIndex, NSString **failure);
BOOL FBTRebindImageVtableSlotBySymbols(const char *imageName,
        const char *vtableSymbol, const char *anchorMethodSymbol,
        const char *expectedMethodSymbol, int relativeIndex,
        void *replacement, void **original, NSString **failure);
#ifdef __cplusplus
}
#endif
