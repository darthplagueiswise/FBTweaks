#import "FBTDataSlotRebinding.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <string.h>

static BOOL FBTRebindSlot(const struct mach_header_64 *header, intptr_t slide,
        uint64_t address, const unsigned char uuid[16], void *target,
        void *replacement, void **original, NSString **failure) {
    if (!header || header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64 ||
        !target || !replacement || !original) {
        if (failure) *failure = @"unsupported_image_or_target";
        return NO;
    }
    BOOL uuidMatches = NO;
    const struct load_command *command = (const struct load_command *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        if (command->cmd == LC_UUID && command->cmdsize == sizeof(struct uuid_command)) {
            uuidMatches = memcmp(((const struct uuid_command *)command)->uuid, uuid, 16) == 0;
            break;
        }
        command = (const struct load_command *)((const char *)command + command->cmdsize);
    }
    const struct section_64 *section = getsectbynamefromheader_64(header, "__DATA_CONST", "__const");
    if (!uuidMatches || !section || address < section->addr ||
        address + sizeof(void *) > section->addr + section->size || address % sizeof(void *)) {
        if (failure) *failure = uuidMatches ? @"slot_outside_data_const" : @"uuid_mismatch";
        return NO;
    }
    void **slot = (void **)(address + slide);
    void *current = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
    if (current == replacement && *original) return YES;
    if (current != target) {
        if (failure) *failure = @"unexpected_slot_pointer";
        return NO;
    }
    vm_address_t region = (vm_address_t)slot;
    vm_size_t regionSize = 0;
    vm_region_basic_info_data_64_t info = {0};
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(mach_task_self(), &region, &regionSize,
        VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
    if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
    if (kr != KERN_SUCCESS || region > (vm_address_t)slot ||
        !(info.protection & VM_PROT_READ) || (info.protection & VM_PROT_EXECUTE)) {
        if (failure) *failure = @"ineligible_memory_region";
        return NO;
    }
    vm_address_t page = (vm_address_t)slot & ~((vm_address_t)vm_page_size - 1);
    kr = vm_protect(mach_task_self(), page, vm_page_size, NO,
                    info.protection | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        if (failure) *failure = @"data_page_write_denied";
        return NO;
    }
    *original = target;
    BOOL changed = __atomic_compare_exchange_n(slot, &current, replacement, NO,
                                               __ATOMIC_RELEASE, __ATOMIC_RELAXED);
    kern_return_t restored = vm_protect(mach_task_self(), page, vm_page_size, NO, info.protection);
    if (restored != KERN_SUCCESS) {
        if (changed) {
            void *expected = replacement;
            __atomic_compare_exchange_n(slot, &expected, target, NO, __ATOMIC_RELEASE, __ATOMIC_RELAXED);
        }
        vm_protect(mach_task_self(), page, vm_page_size, NO, info.protection);
        if (failure) *failure = @"protection_restore_failed";
        return NO;
    }
    if (failure) *failure = changed ? @"" : @"slot_changed_during_install";
    return changed;
}

BOOL FBTRebindVerifiedMainConstSlot(uint64_t address, const unsigned char uuid[16],
        const char *symbol, void *replacement, void **original, NSString **failure) {
    return FBTRebindSlot((const struct mach_header_64 *)_dyld_get_image_header(0),
        _dyld_get_image_vmaddr_slide(0), address, uuid,
        symbol ? dlsym(RTLD_DEFAULT, symbol) : NULL, replacement, original, failure);
}

BOOL FBTRebindVerifiedImageConstSlot(const char *imageName, uint64_t address,
        const unsigned char uuid[16], uint64_t targetAddress, void *replacement,
        void **original, NSString **failure) {
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *path = _dyld_get_image_name(i);
        const char *base = path ? strrchr(path, '/') : NULL;
        if (!path || strcmp(base ? base + 1 : path, imageName) != 0) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        return FBTRebindSlot((const struct mach_header_64 *)_dyld_get_image_header(i),
            slide, address, uuid, (void *)(targetAddress + slide), replacement, original, failure);
    }
    if (failure) *failure = @"image_not_loaded";
    return NO;
}

static const char *FBTRebindImageBasename(const char *path) {
    if (!path) return "";
    const char *base = strrchr(path, '/');
    return base ? base + 1 : path;
}

static BOOL FBTRebindSymbolInImage(void *symbol, const char *imageName) {
    Dl_info info = {};
    return symbol && dladdr(symbol, &info) && info.dli_fname &&
        strcmp(FBTRebindImageBasename(info.dli_fname), imageName) == 0;
}

static BOOL FBTResolveImageVtableSlotBySymbols(const char *imageName,
        const char *vtableSymbol, const char *anchorMethodSymbol,
        const char *expectedMethodSymbol, int relativeIndex,
        void *replacement, void **original, BOOL preflightOnly, NSString **failure) {
    if (!imageName || !vtableSymbol || !anchorMethodSymbol || !expectedMethodSymbol ||
        (!preflightOnly && (!replacement || !original)) || relativeIndex < -16 || relativeIndex > 16) {
        if (failure) *failure = @"invalid_symbol_rebinding_arguments";
        return NO;
    }
    // Locate exact symbols rather than preserving a specific build's RVA/UUID.
    void *vtable = dlsym(RTLD_DEFAULT, vtableSymbol);
    void *anchorMethod = dlsym(RTLD_DEFAULT, anchorMethodSymbol);
    void *expectedMethod = dlsym(RTLD_DEFAULT, expectedMethodSymbol);
    if (!vtable || !anchorMethod || !expectedMethod) {
        if (failure) *failure = @"required_CXX_symbol_unavailable";
        return NO;
    }
    if (!FBTRebindSymbolInImage(vtable, imageName) ||
        !FBTRebindSymbolInImage(anchorMethod, imageName) ||
        !FBTRebindSymbolInImage(expectedMethod, imageName)) {
        if (failure) *failure = @"symbol_resolves_to_other_image";
        return NO;
    }
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *path = _dyld_get_image_name(i);
        if (!path || strcmp(FBTRebindImageBasename(path), imageName) != 0) continue;
        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        if (!header || header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64) {
            if (failure) *failure = @"unsupported_loaded_image";
            return NO;
        }
        const struct section_64 *constSec =
            getsectbynamefromheader_64(header, "__DATA_CONST", "__const");
        const struct section_64 *textSec =
            getsectbynamefromheader_64(header, "__TEXT", "__text");
        if (!constSec || !textSec) {
            if (failure) *failure = @"missing_expected_MachO_sections";
            return NO;
        }
        uintptr_t start = (uintptr_t)constSec->addr + slide;
        uintptr_t end = start + (uintptr_t)constSec->size;
        uintptr_t vt = (uintptr_t)vtable;
        uintptr_t textStart = (uintptr_t)textSec->addr + slide;
        uintptr_t textEnd = textStart + (uintptr_t)textSec->size;
        if (end < start || textEnd < textStart || vt < start || vt >= end ||
            (uintptr_t)anchorMethod < textStart || (uintptr_t)anchorMethod >= textEnd ||
            (uintptr_t)expectedMethod < textStart || (uintptr_t)expectedMethod >= textEnd) {
            if (failure) *failure = @"symbol_outside_validated_sections";
            return NO;
        }
        // The target MUST be the C++ class' validated virtual method slot.
        // Search no more than 64 slots within this vtable; an exported anchor
        // must occur exactly once (and the relative target must also match).
        uintptr_t selected = 0;
        NSUInteger anchors = 0;
        for (NSUInteger n = 2; n < 64; n++) {
            uintptr_t address = vt + n * sizeof(void *);
            if (address >= end || address < start || address > end - sizeof(void *)) break;
            void *candidate = __atomic_load_n((void **)address, __ATOMIC_ACQUIRE);
            if (candidate != anchorMethod) continue;
            ++anchors;
            intptr_t target = (intptr_t)address + (intptr_t)relativeIndex * (intptr_t)sizeof(void *);
            if (target < (intptr_t)vt + 2 * (intptr_t)sizeof(void *) ||
                target < (intptr_t)start || target > (intptr_t)end - (intptr_t)sizeof(void *))
                continue;
            void *observed = __atomic_load_n((void **)target, __ATOMIC_ACQUIRE);
            if (observed == expectedMethod) selected = (uintptr_t)target;
        }
        if (anchors != 1 || !selected) {
            if (failure) *failure = anchors != 1 ? @"ambiguous_or_missing_vtable_anchor" :
                @"vtable_method_signature_or_layout_changed";
            return NO;
        }
        // A true preflight performs all Mach-O, image, unique-anchor and
        // exact-method-slot checks without mutating any process memory. Run
        // this for EVERY callback before the first live pointer replacement.
        if (preflightOnly) return YES;
        unsigned char uuid[16] = {};
        BOOL foundUUID = NO;
        const struct load_command *command = (const struct load_command *)(header + 1);
        for (uint32_t n = 0; n < header->ncmds; n++) {
            if (command->cmd == LC_UUID && command->cmdsize == sizeof(struct uuid_command)) {
                memcpy(uuid, ((const struct uuid_command *)command)->uuid, sizeof(uuid));
                foundUUID = YES; break;
            }
            if (command->cmdsize < sizeof(struct load_command)) break;
            command = (const struct load_command *)((const char *)command + command->cmdsize);
        }
        if (!foundUUID) {
            if (failure) *failure = @"loaded_image_missing_UUID";
            return NO;
        }
        // The rebinder still checks the original function pointer, memory
        // permissions and restores the page protection after the atomic swap.
        return FBTRebindSlot(header, slide, selected - slide, uuid, expectedMethod,
                             replacement, original, failure);
    }
    if (failure) *failure = @"image_not_loaded";
    return NO;
}


BOOL FBTValidateImageVtableSlotBySymbols(const char *imageName,
        const char *vtableSymbol, const char *anchorMethodSymbol,
        const char *expectedMethodSymbol, int relativeIndex, NSString **failure) {
    return FBTResolveImageVtableSlotBySymbols(imageName, vtableSymbol,
        anchorMethodSymbol, expectedMethodSymbol, relativeIndex, NULL, NULL, YES, failure);
}

BOOL FBTRebindImageVtableSlotBySymbols(const char *imageName,
        const char *vtableSymbol, const char *anchorMethodSymbol,
        const char *expectedMethodSymbol, int relativeIndex,
        void *replacement, void **original, NSString **failure) {
    return FBTResolveImageVtableSlotBySymbols(imageName, vtableSymbol,
        anchorMethodSymbol, expectedMethodSymbol, relativeIndex,
        replacement, original, NO, failure);
}

static BOOL FBTImageTextContainsName(const struct section_64 *section, intptr_t slide,
        const char *name, uintptr_t *address) {
    if (!section || !name || !address) return NO;
    uintptr_t start = (uintptr_t)section->addr + slide;
    size_t size = (size_t)section->size;
    size_t length = strlen(name);
    if (length >= size || !length) return NO;
    const char *bytes = (const char *)start;
    uintptr_t match = 0;
    for (size_t n = 0; n <= size - length - 1; n++) {
        // RTTI strings may be adjacent to compiler metadata rather than
        // preceded by NUL; require an exact suffix terminator and full name.
        if (bytes[n + length] == 0 && memcmp(bytes + n, name, length) == 0) {
            if (match) return NO; // ambiguous RTTI name
            match = start + n;
        }
    }
    if (match) *address = match;
    return match != 0;
}

BOOL FBTRebindImageFirstVirtualByRTTI(const char *imageName, const char *typeName,
        void *replacement, void **original, NSString **failure) {
    if (!imageName || !typeName || !replacement || !original) {
        if (failure) *failure = @"invalid_RTTI_arguments";
        return NO;
    }
    // Do not guess offsets: identify the loaded vtable by an exact C++ RTTI
    // type name. A missing or ambiguous typeinfo is an unsupported build.
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *path = _dyld_get_image_name(i);
        if (!path || strcmp(FBTRebindImageBasename(path), imageName) != 0) continue;
        const struct mach_header_64 *header =
            (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (!header || header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64) {
            if (failure) *failure = @"unsupported_loaded_MachO";
            return NO;
        }
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct section_64 *constant =
            getsectbynamefromheader_64(header, "__DATA_CONST", "__const");
        const struct section_64 *text =
            getsectbynamefromheader_64(header, "__TEXT", "__text");
        const struct section_64 *textConstant =
            getsectbynamefromheader_64(header, "__TEXT", "__const");
        const struct section_64 *strings =
            getsectbynamefromheader_64(header, "__TEXT", "__cstring");
        if (!constant || !text) {
            if (failure) *failure = @"required_sections_not_found";
            return NO;
        }
        uintptr_t name = 0;
        if (!FBTImageTextContainsName(textConstant, slide, typeName, &name) &&
            !FBTImageTextContainsName(strings, slide, typeName, &name)) {
            if (failure) *failure = @"RTTI_class_name_not_found";
            return NO;
        }
        uintptr_t first = (uintptr_t)constant->addr + slide;
        uintptr_t limit = first + (uintptr_t)constant->size;
        uintptr_t execFirst = (uintptr_t)text->addr + slide;
        uintptr_t execLimit = execFirst + (uintptr_t)text->size;
        if (limit < first || execLimit < execFirst) {
            if (failure) *failure = @"MachO_section_address_overflow";
            return NO;
        }
        uintptr_t typeinfo = 0;
        unsigned int matches = 0;
        for (uintptr_t pos = first + sizeof(void *); pos <= limit - sizeof(void *); pos += sizeof(void *)) {
            if (*(uintptr_t *)pos != name) continue;
            uintptr_t possibleTypeinfo = pos - sizeof(void *);
            uintptr_t typeinfoVtable = *(uintptr_t *)possibleTypeinfo;
            if (!typeinfoVtable || typeinfoVtable == name) continue;
            ++matches;
            typeinfo = possibleTypeinfo;
        }
        if (matches != 1) {
            if (failure) *failure = @"ambiguous_or_missing_typeinfo";
            return NO;
        }
        // Itanium C++ ABI layout: [offset-to-top=0][typeinfo][method0].
        // Scan the loaded read-only section for an exact typeinfo reference.
        uintptr_t slot = 0;
        unsigned int vtables = 0;
        for (uintptr_t pos = first + sizeof(void *); pos <= limit - 2 * sizeof(void *); pos += sizeof(void *)) {
            if (*(uintptr_t *)pos != typeinfo || *(uintptr_t *)(pos - sizeof(void *)) != 0)
                continue;
            uintptr_t candidate = pos + sizeof(void *);
            uintptr_t method = *(uintptr_t *)candidate;
            if (method < execFirst || method >= execLimit) continue;
            ++vtables;
            slot = candidate;
        }
        if (vtables != 1) {
            if (failure) *failure = @"ambiguous_or_missing_class_vtable";
            return NO;
        }
        unsigned char uuid[16] = {};
        BOOL hasUUID = NO;
        const struct load_command *command = (const struct load_command *)(header + 1);
        for (uint32_t n = 0; n < header->ncmds; n++) {
            if (command->cmd == LC_UUID && command->cmdsize == sizeof(struct uuid_command)) {
                memcpy(uuid, ((const struct uuid_command *)command)->uuid, sizeof(uuid));
                hasUUID = YES;
                break;
            }
            if (command->cmdsize < sizeof(struct load_command)) break;
            command = (const struct load_command *)((const char *)command + command->cmdsize);
        }
        if (!hasUUID) {
            if (failure) *failure = @"loaded_image_without_UUID";
            return NO;
        }
        void *target = (void *)(*(uintptr_t *)slot);
        // The caller must additionally know the first method's ABI. Class RTTI
        // only proves identity and vtable location, not signature stability.
        return FBTRebindSlot(header, slide, slot - slide, uuid,
                             target, replacement, original, failure);
    }
    if (failure) *failure = @"image_not_loaded";
    return NO;
}
