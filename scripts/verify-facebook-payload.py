#!/usr/bin/env python3
"""Read-only checks for the supplied Facebook 583 payload (pip: lief capstone).
Usage: python scripts/verify-facebook-payload.py /path/to/Payload/Facebook.app
"""
import json
import re
import struct
import sys
from pathlib import Path
import capstone
import lief

lief.logging.disable()
app = Path(sys.argv[1])
root = Path(__file__).resolve().parents[1]
checks = []

def check(name, passed, **details):
    checks.append(dict(check=name, passed=bool(passed), **details))

def load(relative):
    path = app / relative
    return lief.MachO.parse(str(path)).at(0), path.read_bytes()

def objc_methods(binary, raw, wanted):
    sections = list(binary.sections)
    def offset(va):
        for section in sections:
            if section.virtual_address <= va < section.virtual_address + section.size:
                return section.offset + va - section.virtual_address
        return None
    def ptr(va):
        off = offset(va)
        return struct.unpack_from('<Q', raw, off)[0] & 0xfffffffff if off is not None else 0
    def text(va):
        off = offset(va)
        if off is None:
            return ''
        return raw[off:raw.find(b'\0', off)].decode('utf-8', errors='replace')
    def methods(va):
        off = offset(va)
        if off is None:
            return {}
        flags, count = struct.unpack_from('<II', raw, off)
        step = 12 if flags & 0x80000000 else flags & 0xffff
        if count > 10000 or step not in (12, 24):
            return {}
        found = {}
        for i in range(count):
            entry = va + 8 + i * step
            at = off + 8 + i * step
            if flags & 0x80000000:
                nr, tr, ir = struct.unpack_from('<iii', raw, at)
                name = entry + nr
                if not flags & 0x40000000:
                    name = ptr(name)
                types, imp = entry + 4 + tr, entry + 8 + ir
            else:
                name, types, imp = (v & 0xfffffffff for v in struct.unpack_from('<QQQ', raw, at))
            found[text(name)] = (text(types), imp)
        return found
    out = {}
    for section in sections:
        if section.name != '__objc_classlist':
            continue
        for va in range(section.virtual_address, section.virtual_address + section.size, 8):
            cls = ptr(va)
            ro = ptr(cls + 32) & ~7
            name = text(ptr(ro + 24))
            if name in wanted:
                meta_ro = ptr(ptr(cls) + 32) & ~7
                out[name] = methods(ptr(ro + 32)) | methods(ptr(meta_ro + 32))
    bindings = {b.address: b.symbol.name for b in binary.bindings if b.has_symbol}
    for section in sections:
        if section.name != '__objc_catlist':
            continue
        for va in range(section.virtual_address, section.virtual_address + section.size, 8):
            cat = ptr(va)
            cls = ptr(cat + 8)
            ro = ptr(cls + 32) & ~7
            name = text(ptr(ro + 24)) or bindings.get(cat + 8, '').removeprefix('_OBJC_CLASS_$_')
            if name in wanted:
                out.setdefault(name, {}).update(methods(ptr(cat + 16)))
                out[name].update(methods(ptr(cat + 24)))
    return out

main, main_raw = load('Facebook')
shared, shared_raw = load('Frameworks/FBSharedFramework.framework/FBSharedFramework')
rare, rare_raw = load('Frameworks/FBRarelyUsedFramework.framework/FBRarelyUsedFramework')
section = next(s for s in shared.sections if s.virtual_address <= 0x8161f88 < s.virtual_address+s.size)
slot_offset = section.offset + 0x8161f88 - section.virtual_address
slot_value = struct.unpack_from('<Q', shared_raw, slot_offset)[0] & 0xfffffffff
check('native_fetcher_data_slot', section.name == '__const' and section.segment_name == '__DATA_CONST' and slot_value == 0xa17f70)
check('shared_uuid', bytes(shared.uuid.uuid).hex() == '4c4c44fe55553144a1c26ccae4ed2597')
check('native_fetcher_callback_rtti', b'asyncFetchERKNS_12basic_string' in shared_raw and b'functionIFvbSB_EEE' in shared_raw)
expected_uuid = bytes([76,76,68,170,85,85,49,68,161,142,1,71,65,237,25,11])
check('main_uuid', bytes(main.uuid.uuid) == expected_uuid, uuid=bytes(main.uuid.uuid).hex())
for address, name in [(0x101010370, '10onResponse'), (0x101010378, '6onBody')]:
    binding = next((b for b in main.bindings if b.address == address and b.has_symbol), None)
    section = next((s for s in main.sections if s.virtual_address <= address < s.virtual_address+s.size), None)
    check(name + '_data_slot', binding and name in binding.symbol.name and section and
          section.segment_name == '__DATA_CONST' and section.name == '__const', address=hex(address))
exports = {s.name for b in [main, shared, rare] for s in b.symbols if s.has_export_info}
for relative in ['src/Runtime/FBTNativeMobileConfigOverrides.mm', 'src/Runtime/FBTMobileConfigTigonCapture.mm']:
    names = re.findall(r'dlsym\(RTLD_DEFAULT, "([^"]+)"', (root / relative).read_text())
    for name in names:
        if name == 'FBMobileConfigSetSkipOverrideCheckEnabled':
            continue  # optional API; absence must not disable the native bridge
        check('dlsym_export', '_' + name in exports, symbol=name)
main_classes = objc_methods(main, main_raw, {'RCDMobileConfigParams'})
shared_classes = objc_methods(shared, shared_raw, {'FBNavigationInfo', 'FBBugReportConfiguration', 'FBTabBarViewController', 'FBMobileConfigContextManager'})
rare_classes = objc_methods(rare, rare_raw, {'_TtC31FBSettingsMenuItemHandlerPlugin25FBSettingsMenuItemHandler', 'FBWhitehatSettingsMenuItemHandler', 'FBMobileConfigDebugViewController'})
expected = [
    (shared_classes, 'FBMobileConfigContextManager', 'getCurrentManager', '{shared_ptr<mobileconfig::FBMobileConfigManager>=^{FBMobileConfigManager}^{__shared_weak_count}}16@0:8'),
    (main_classes, 'RCDMobileConfigParams', 'initWithClassesString:trackNSObjectBaseClass:isEventBasedTrigger:maxCycleLen:ignoreAppleClassesWithPrefix:peopleSampling:isEmployee:isEnabledProduction:shouldUseSwiftABITraversal:', '@68@0:8@16B24B28q32@40q48B56B60B64'),
    (shared_classes, 'FBNavigationInfo', 'infoWithViewController:method:options:completion:whenClosed:', '@56@0:8@16Q24Q32@?40@?48'),
    (shared_classes, 'FBTabBarViewController', 'setSession:', 'v24@0:8@16'),
    (rare_classes, 'FBWhitehatSettingsMenuItemHandler', 'viewControllerForMenuItem:viewportSizeEstimate:tabSwitchingType:', '@48@0:8@16{CGSize=dd}24q40'),
]
for classes, cls, selector, encoding in expected:
    actual = classes.get(cls, {}).get(selector, ('', 0))[0]
    check('objc_abi', actual == encoding, cls=cls, selector=selector, encoding=actual)
for selector in ['setEnableInternalSettingsOption:', 'setEnableInternalToolsSubmenu:', 'setForceShowingInternalTools:', 'setShowTriageToDogfoodingAssistantSession:', 'setDisableEmployeeProductionReports:']:
    check('removed_nonexistent_setter', selector not in shared_classes.get('FBBugReportConfiguration', {}), selector=selector)
md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
factory = rare_classes['_TtC31FBSettingsMenuItemHandlerPlugin25FBSettingsMenuItemHandler']['viewControllerForMenuItem:viewportSizeEstimate:tabSwitchingType:'][1]
first = next(md.disasm(bytes(rare.get_content_from_virtual_address(factory, 8)), factory))
check('settings_factory_returns_nil', first.mnemonic == 'mov' and first.op_str == 'x0, #0', address=hex(factory))
for name in ['_FBInternalSettingsViewControllerFromSession', '_FBSettingsControllerOpenBloksAction']:
    check('native_settings_export', name in exports, symbol=name)
print(json.dumps(dict(passed=all(x['passed'] for x in checks), checks=checks), indent=2))
sys.exit(0 if all(x['passed'] for x in checks) else 1)
