#!/bin/sh
set -eu
repo="${1:-.}"
fail=0
need(){ grep -q "$2" "$repo/$1" || { echo "missing pattern in $1: $2"; fail=1; }; }
need_absent(){ if grep -q "$2" "$repo/$1"; then echo "forbidden pattern in $1: $2"; fail=1; fi; }
[ -f "$repo/Makefile" ] || { echo missing Makefile; exit 1; }
need Makefile 'iphone:clang:26.2:16.3'
need Makefile '_USE_MODULES = 0'
need src/Runtime/FBGRGateStore.h 'FBGRGateRememberRuntimeHook'
need src/Runtime/FBGRGateStore.m 'fbgr.runtime.hook.index.v1'
need src/Runtime/FBGRGateStore.m 'FBGRGateDiagnostic'
need src/Runtime/FBGRBoolRuntimeInventory.h 'reinstallPersistedHooks'
need src/Runtime/FBGRBoolRuntimeInventory.m 'FBGRGateRememberRuntimeHook'
need src/Runtime/FBGRBoolRuntimeInventory.m 'FBGRBoolRuntimeCtor'
need src/Hooks/FBGRMCGateHooks.xm 'FBGRMCGateHooksCtor'
need src/Hooks/FBGRMCGateHooks.xm 'runtimeSpecs'
need src/Hooks/FBGRLiquidGlassHooks.xm 'fbgr.liquidglass.force'
need src/Menu/FBGRMenuTheme.m 'UIGlassEffect'
need src/Menu/FBGRMenuTheme.m 'UIGlassContainerEffect'
need src/Menu/FBGRMenuTheme.m 'UIColor.whiteColor'
need src/Menu/FBGRMenuTheme.m 'UIColor.blackColor'
need src/Menu/FBGRSurfaceListVC.m 'Limpar todos overrides'
need src/Menu/FBGRSurfaceListVC.m 'FBGRGateDiagnostic'
[ "$fail" -eq 0 ] || exit 1
echo "FBTweaks runtime persistence/liquidglass validation OK"
