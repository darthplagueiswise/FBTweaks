#!/usr/bin/env python3
"""Hook capabilities for signed, sideloaded binaries: no generic direct code rewrites."""
from pathlib import Path
import unittest
BASE=Path(__file__).resolve().parents[1]
def read(p):return (BASE/p).read_text()
class SideloadHookCapabilities(unittest.TestCase):
    def test_generic_swift_direct_symbols_never_get_runtime_toggle(self):
        resolver=read("src/Runtime/FBTCRuntimePatchResolver.m")
        self.assertIn("if (p.swiftLike && !p.objcSelectorName.length)",resolver)
        self.assertIn("FBTCRuntimePatchStrategyNone",resolver)
        browser=read("src/Settings/FBTSymbolsBrowserViewController.m")
        self.assertIn("!entry.swiftLike",browser)
        menu=read("src/Settings/FBTSettingsViewController.m")
        self.assertNotIn('@"title": @"Runtime Browser — ObjC, C, Swift"',menu)
    def test_only_c_import_rebinding_with_explicit_profile_is_offered(self):
        resolver=read("src/Runtime/FBTCRuntimePatchResolver.m")
        self.assertIn("p.hasBindPointer && [FBTCSymbolStub isForceableSymbol",resolver)
        self.assertIn("p.hasBindPointer && [FBTCSymbolStub isTypedForceableSymbol",resolver)
        self.assertIn("fishhook would be a no-op",resolver)
        browser=read("src/Settings/FBTSymbolsBrowserViewController.m")
        self.assertIn("[weakSelf entryHasInlineToggle:entry]",browser)
    def test_objc_bool_remains_type_gated(self):
        m=read("src/Runtime/FBTRuntimeBoolBrowser.m")
        self.assertIn("method_getReturnType",m)
        self.assertIn("ret[0] != 'B'",m)
        self.assertIn('strcmp(encoding,"B16@0:8") != 0',m)
if __name__=="__main__":unittest.main()
