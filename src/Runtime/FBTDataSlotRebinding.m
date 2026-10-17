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
