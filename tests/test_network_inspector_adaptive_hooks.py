"""Contract checks for version-adaptive MobileConfig/Tigon interception."""
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
def src(path): return (ROOT / path).read_text()


class AdaptiveHooksTests(unittest.TestCase):
    def test_symbol_and_RTTI_resolvers_exist(self):
        header = src("src/Runtime/FBTDataSlotRebinding.h")
        implementation = src("src/Runtime/FBTDataSlotRebinding.m")
        self.assertIn("FBTRebindImageVtableSlotBySymbols", header)
        self.assertIn("FBTRebindImageFirstVirtualByRTTI", header)
        self.assertIn('dlsym(RTLD_DEFAULT, vtableSymbol)', implementation)
        self.assertIn('dlsym(RTLD_DEFAULT, anchorMethodSymbol)', implementation)
        self.assertIn('dlsym(RTLD_DEFAULT, expectedMethodSymbol)', implementation)
        self.assertIn('ambiguous_or_missing_vtable_anchor', implementation)
        self.assertIn('vtable_method_signature_or_layout_changed', implementation)
        self.assertIn('ambiguous_or_missing_typeinfo', implementation)
        self.assertIn('ambiguous_or_missing_class_vtable', implementation)
        self.assertIn('FBTRebindSlot(header, slide', implementation)

    def test_tigon_callbacks_derived_from_loaded_vtable(self):
        native = src("src/Runtime/FBTMobileConfigTigonCapture.mm")
        self.assertIn('_ZTVN8facebook5tigon20TigonSimpleCallbacksE', native)
        self.assertIn('FBTRebindImageVtableSlotBySymbols(', native)
        self.assertIn('relativeToResponse[] = {-6, 0, 1, 3, 5}', native)
        self.assertIn('FBTValidateImageVtableSlotBySymbols(', native)
        self.assertIn('installationOrder[] = {0, 2, 3, 4, 1}', native)
        self.assertIn('simple_symbol_resolved_callbacks', native)
        self.assertNotIn('FBTRebindVerifiedImageConstSlot(', native)
        self.assertNotIn('FBTSimpleInstallMethodEntry', native)
        self.assertNotIn('substrate_trampoline_not_returned', native)

    def test_fetcher_RTTI_only_without_build_pinned_fallback(self):
        native = src("src/Runtime/FBTMobileConfigFetcherCapture.mm")
        self.assertIn('N12mobileconfig26FBMobileConfigTigonFetcherE', native)
        self.assertIn('FBTRebindImageFirstVirtualByRTTI(', native)
        self.assertNotIn('FBTRebindVerifiedImageConstSlot(', native)
        self.assertIn('dynamic_RTTI_vtable', native)
        self.assertIn('RTTI_preflight_failed', native)
        self.assertNotIn('legacy_exact_UUID', native)

    def test_unclassified_Tigon_uses_standalone_ID(self):
        native = src("src/Runtime/FBTMobileConfigTigonCapture.mm")
        inspector = src("src/Settings/FBTNetworkInspectorViewController.m")
        self.assertIn('sStandaloneTigonIDs', native)
        self.assertIn('tigon_unclassified', native)
        self.assertIn('FBTNetworkInspectorRecordTigon(context, body)', native)
        self.assertIn('if (!fetcher && !tigon)', inspector)
        self.assertIn('Tigon somente', inspector)
        self.assertIn('Fetcher somente', inspector)
        self.assertNotIn('if (!fetcher || !tigon)', inspector)

    def test_preflight_and_hook_order_prevent_anchor_destruction(self):
        native = src('src/Runtime/FBTMobileConfigTigonCapture.mm')
        rebinder = src('src/Runtime/FBTDataSlotRebinding.m')
        header = src('src/Runtime/FBTDataSlotRebinding.h')
        self.assertIn('FBTValidateImageVtableSlotBySymbols(', native)
        self.assertIn('if (failures.count == 0)', native)
        self.assertIn('static const NSUInteger installationOrder[] = {0, 2, 3, 4, 1}', native)
        self.assertIn('sSimpleInstallAttempted', native)
        self.assertIn('partial_dynamic_vtable_no_retry', native)
        self.assertIn('FBTValidateImageVtableSlotBySymbols(', header)
        self.assertIn('FBTResolveImageVtableSlotBySymbols(', rebinder)
        self.assertIn('if (preflightOnly) return YES;', rebinder)
        self.assertNotIn('FBTSimpleInstallMethodEntry', native)
        self.assertNotIn('legacy_UUID_vtable', native)

    def test_no_blind_patching_on_mismatch(self):
        implementation = src("src/Runtime/FBTDataSlotRebinding.m")
        self.assertIn('selected - slide, uuid, expectedMethod', implementation)
        self.assertIn('target, replacement, original, failure', implementation)
        self.assertIn('VM_PROT_COPY', implementation)
        self.assertIn('ineligible_memory_region', implementation)
        self.assertIn('slot_changed_during_install', implementation)


if __name__ == "__main__":
    unittest.main()
