#!/usr/bin/env python3
"""Portable guard against duplicate hook engines and risky cold-start work."""
from pathlib import Path
import sys
R=Path(__file__).resolve().parent.parent
def src(p):return (R/p).read_text(encoding="utf-8")
sym=src("src/Runtime/FBTSymbolBrowserEngine.m")
core=src("src/Runtime/FBTRuntimeBoolBrowser.m")
trace=src("src/Runtime/FBTNativeTrace.mm")
boot=src("src/Tweak.x")
checks={
 "single BOOL runtime installer": "MSHookMessageEx(" not in sym and "MSHookMessageEx(hookClass" in core,
 "no arbitrary browser getter invocation": "objc_msgSend" not in sym,
 "no global C++ ring constructor": "static fbt_trace::Ring sTrace;" not in trace and "static fbt_trace::Ring instance;" in trace,
 "no trace initialization in dyld constructor": "FBTNativeTraceReloadPrefs();" not in boot[boot.index("%ctor {"):].split("FBTNotificationPrefsChanged")[0],
 "no duplicated symbol hook restoration": "[FBTSymbolBrowserEngine reinstallPersistedHooks];" not in boot,
 "ABI-specific BOOL getters": 'strcmp(encoding,"B16@0:8")' in core and 'strcmp(encoding,"c16@0:8")' in core,
 "legacy symbol override migration": '@"fbt_symbol_overrides_migrated_v1"' in core,
}
for k,v in checks.items():print(("PASS" if v else "FAIL")+": "+k)
if not all(checks.values()):sys.exit(1)
