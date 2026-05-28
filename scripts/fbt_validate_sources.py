#!/usr/bin/env python3
"""fbt_validate_sources.py — pre-build sanity check for FBTweaks."""
import os, re, sys, gzip, json, pathlib

ROOT = pathlib.Path(__file__).parent.parent
errors = []

def ok(msg):  print(f"  OK   {msg}")
def err(msg): errors.append(msg); print(f"  ERR  {msg}")

# 1 — ReactMobileConfigMetadata.json.gz
p = ROOT / "resources/runtime/ReactMobileConfigMetadata.json.gz"
if not p.exists():
    err(f"MISSING: {p}")
else:
    try:
        with gzip.open(p) as f:
            d = json.load(f)
        ok(f"ReactMobileConfigMetadata.json.gz ({len(d.get('schema',{}))} entries)")
    except Exception as e:
        err(f"CORRUPT: {p}: {e}")

# 2 — mc_bool_param_t typedef
prefix = (ROOT / "src/FBGramPrefix.h").read_text()
if "mc_bool_param_t" not in prefix:
    err("FBGramPrefix.h: missing mc_bool_param_t typedef")
else:
    ok("mc_bool_param_t typedef")

# 3 — FBGramPrefix usage without import in .m files
# Only flag files that use MACROS from FBGramPrefix (FBGRPref, FBGRPrefs, kFBGR*, FBGRLog macro, FBGRLogHook)
# NOT functions defined in FBGRLog.h (FBGRLogSnapshot, FBGRLogClear, FBGRLogAppend, FBGRLogInit)
macro_pattern = re.compile(r'\bFBGRPref\b|\bFBGRPrefs\b|\bkFBGR\w+|\bFBGRLog\(|\bFBGRLogHook\(')
src_dir = ROOT / "src"
for fpath in src_dir.rglob("*.m"):
    text = fpath.read_text()
    if macro_pattern.search(text) and "FBGramPrefix" not in text:
        count = len(macro_pattern.findall(text))
        err(f"MISSING FBGramPrefix: {fpath.relative_to(ROOT)} ({count} macro usages)")
ok("FBGramPrefix imports")

# 4 — .color instead of .textColor on UILabel
for fpath in (ROOT/"src").rglob("*.m"):
    text = fpath.read_text()
    for i, line in enumerate(text.splitlines(), 1):
        if re.search(r'\.(textLabel|detailTextLabel)\.color\s*=', line):
            err(f"{fpath.relative_to(ROOT)}:{i} — use .textColor not .color: {line.strip()}")
ok(".textColor check")

# 5 — extern "C" in .m files
for fpath in (ROOT/"src").rglob("*.m"):
    text = fpath.read_text()
    if 'extern "C"' in text:
        err(f'{fpath.relative_to(ROOT)}: extern "C" in .m file')
ok('extern "C" check')

# 6 — dispatch_once_t as @property
for fpath in list((ROOT/"src").rglob("*.m")) + list((ROOT/"src").rglob("*.h")):
    if re.search(r'@property.*dispatch_once', fpath.read_text()):
        err(f"{fpath.relative_to(ROOT)}: dispatch_once_t as @property")
ok("dispatch_once_t check")

# 7 — fishhook present
for f in ["fishhook.c", "fishhook.h"]:
    p = ROOT / "modules/fishhook" / f
    if p.exists(): ok(f)
    else: err(f"MISSING: {p}")

# 8 — Makefile bundles gz
if "json.gz" in (ROOT/"Makefile").read_text():
    ok("Makefile bundles .json.gz")
else:
    err("Makefile: does not bundle .json.gz")

# 9 — FBTabBar hook present (not UITabBar)
tweak = (ROOT/"src/Tweak.x").read_text()
if "%hook FBTabBar" in tweak:
    ok("Tweak.x: %hook FBTabBar (correct)")
else:
    err("Tweak.x: missing %hook FBTabBar — check tab bar hook class")
if "%hook UITabBar\n" in tweak and "%hook FBTabBar" not in tweak:
    err("Tweak.x: only UITabBar hook present (wrong class for Facebook)")

print()
if errors:
    for e in errors: print(f"  ERR  {e}")
    sys.exit(1)
else:
    print("All checks passed.")

# 10 — Headers imported from .xm need __cplusplus guard if they declare C functions
import subprocess
xm_imports = set()
for fpath in (ROOT/"src").rglob("*.xm"):
    for line in fpath.read_text().splitlines():
        m = re.match(r'\s*#import\s+"(.*\.h)"', line)
        if m:
            rel = m.group(1)
            # resolve relative to the .xm file location
            resolved = (fpath.parent / rel).resolve()
            if resolved.exists():
                xm_imports.add(resolved)

for hpath in xm_imports:
    text = hpath.read_text()
    # Check for non-static, non-inline C function declarations
    has_c_funcs = bool(re.search(r'^(?!static\s)(?!#|/|@|\s)[\w].*\(.*\).*;', text, re.MULTILINE))
    has_guard   = "__cplusplus" in text
    if has_c_funcs and not has_guard:
        err(f"{hpath.name}: imported from .xm but missing __cplusplus extern C guard")
    elif has_c_funcs and has_guard:
        ok(f"{hpath.name}: has __cplusplus guard")
