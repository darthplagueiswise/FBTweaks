#!/usr/bin/env python3
"""ARM64 direct-BL verification from *previously extracted* Instagram 453 instruction words.

This is NOT a disassembly of the full Instagram Mach-O. The input instructions
are exact words reported by the existing FBSharedFramework_direct_bl_xrefs.json
for FBSharedFramework SHA-256
b87afc433805d3579d1e606b36254ad67228a5c873d10601f2c756ca843fe45f.
The full 51.7 MB Mach-O is not uploaded to this repository.
"""
import json
import struct
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN

CASES = [
    # (name, pc, ARM64 32-bit little-endian opcode word, expected target)
    ("XPluginsGetDataForSocket", 0x97A64, 0x97FFFFED, 0x97A18),
    ("XPluginsGetDataForSocket", 0x9BE28, 0x97FFEEFC, 0x97A18),
    ("XPluginsGetFunctionPtrFromID", 0x186CF24, 0x97A0C651, 0x9E868),
    ("XPluginsGetFunctionPtrFromID", 0x187A6B0, 0x97A0906E, 0x9E868),
    ("IGDogfoodingAssistantLauncherClient.clearAllOverrides", 0x172E034, 0x97D4B3FE, 0xC5B02C),
    ("IGDogfoodingAssistantLauncherClient.currentParamValue", 0x117EA88, 0x97FEC9CE, 0x11311C0),
    ("IGMobileConfigForceUpdateConfigs", 0x123F4C8, 0x9417A257, 0x1827E24),
    ("IGMobileConfigForceUpdateConfigs", 0x123F538, 0x9417A23B, 0x1827E24),
    ("FBMobileConfigStorageManager.persistConfigsFromDeltaResponse", 0x8C5020, 0x9400017C, 0x8C5610),
    ("FBMobileConfigManager.getOrCreateOverridesTable", 0x2F5954, 0x97F8E48E, 0x12EB8C),
    ("FBMobileConfigManager.getOrCreateOverridesTable", 0xDB2C6C, 0x97CDEFC8, 0x12EB8C),
]

def main():
    import capstone
    decoder = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
    report = {"tool": "Capstone", "capstone_module_version": capstone.__version__,
       "application": "Instagram iOS 453.0.0", "image": "FBSharedFramework",
       "image_lc_uuid":"4c4c446455553144a1031e54865a1439",
       "image_sha256":"b87afc433805d3579d1e606b36254ad67228a5c873d10601f2c756ca843fe45f",
       "scope":"selected BL words extracted in earlier ARM64 analysis; not full-Mach-O or BLR scan",
       "cases":[]}
    for name,pc,word,target in CASES:
        raw = struct.pack("<I",word)
        instructions = list(decoder.disasm(raw,pc))
        if len(instructions)!=1: raise ValueError(f"Failed disassembly for 0x{pc:x}")
        ins = instructions[0]
        if ins.mnemonic!="bl": raise AssertionError(f"unexpected mnemonic: {ins.mnemonic}")
        actual = int(ins.op_str.lstrip("#"),0)
        if actual != target: raise AssertionError(f"Target mismatch at 0x{pc:x}: 0x{actual:x} != 0x{target:x}")
        report["cases"].append({"name":name,"pc":hex(pc),"word":hex(word),"mnemonic":ins.mnemonic,
          "operand":ins.op_str,"target":hex(actual),"matches_expected":True})
    report["verified_count"]=len(report["cases"])
    with open("ig453_capstone_verified_xrefs.json","w",encoding="utf8") as f:json.dump(report,f,indent=2)
    print(json.dumps(report,indent=2))

if __name__=="__main__":main()
