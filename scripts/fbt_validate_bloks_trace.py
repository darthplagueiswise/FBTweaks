#!/usr/bin/env python3
"""Static wiring regression test for the opt-in Bloks Lab diagnostic module."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
impl = (root / "src/Runtime/FBGRBloksTrace.m").read_text()
ui = (root / "src/Menu/FBGRBloksLiveDebugVC.m").read_text()
menu = (root / "src/Menu/FBGRSurfaceListVC.m").read_text()
makefile = (root / "Makefile").read_text()
checks = {
    "VPN method": '"connectedToVPN"' in impl,
    "Bloks helper": 'processDeeplinkWith:foaObjectSet:' in impl,
    "safe ABI guard": 'method_getNumberOfArguments(m)==9' in impl and 'ArgBool(m,6)' in impl,
    "original VPN returned": 'gOriginalVPN(self,cmd)' in impl,
    "original helper returned": 'gOriginalHelper)(s,cmd' in impl,
    "no version-bound offsets": '0x41596AC' not in impl and '0x636EE4' not in impl,
    "app-container JSONL": 'Documents/FBTweaksDiagnostics' in impl,
    "rotation": '(4 * 1024 * 1024)' in impl,
    "opt-in": 'fbgr_bloks_trace_enabled' in impl,
    "menu wired": '[FBGRBloksLiveDebugVC new]' in menu,
    "live panel": 'scheduledTimerWithTimeInterval:0.8' in ui,
    "export": 'UIActivityViewController' in ui,
    "Makefile auto-discovery": 'find src -type f' in makefile,
}
for description, ok in checks.items():
    print(("OK " if ok else "FAIL "), description)
assert all(checks.values()), "Bloks diagnostic integration incomplete"
print("PASS:", len(checks), "static checks")
