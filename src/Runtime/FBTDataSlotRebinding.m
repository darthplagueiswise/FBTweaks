#import "FBTDataSlotRebinding.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <string.h>

BOOL FBTRebindVerifiedMainConstSlot(uint64_t address, const unsigned char uuid[16],
                                   const char *symbol, void *replacement,
                                   void **original, NSString **failure) {
    const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(0);
    if (!header || header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64 ||
        !symbol || !replacement || !original) {
        if (failure) *failure = @"unsupported_image";
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

    void *target = dlsym(RTLD_DEFAULT, symbol);
    void **slot = (void **)(address + _dyld_get_image_vmaddr_slide(0));
    void *current = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
    if (current == replacement && *original) return YES;
    if (!target || current != target) {
        if (failure) *failure = target ? @"unexpected_slot_pointer" : @"symbol_unavailable";
        return NO;
    }

    mach_vm_address_t region = (mach_vm_address_t)slot;
    mach_vm_size_t regionSize = 0;
    vm_region_basic_info_data_64_t info = {0};
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t kr = mach_vm_region(mach_task_self(), &region, &regionSize,
        VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
    if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
    if (kr != KERN_SUCCESS || region > (mach_vm_address_t)slot ||
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
    // Publish the forwarding target before another thread can enter the hook.
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
