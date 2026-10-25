# REA + Ghidra: offline IPA decompilation for FBTweaks

This is development-only static analysis. Do NOT add REA, Ghidra, the MCP server or Node to the iOS tweak. Do NOT commit IPA/Mach-O binaries, account data or tokens.

- REA: https://github.com/morluto/rea ; npm package rea-agents@6.7.0 ; provides CLI/MCP.
- The requested Ghidra archive: https://github.com/heaven-hm/re-agent/releases/tag/engine-preview-2026-10-13 ; version 12.1.2; ZIP size 572803866 bytes; SHA256 b62e81a0390618466c019c60d8c2f796ced2509c4c1aea4a37644a77272cf99d.
- The alternative rea-engine-6.4.0.tgz in that release is a separate preview, not required for the morluto package.
- REA docs: https://github.com/morluto/rea/blob/main/docs/installation.md#ghidra ; adapter accepts Ghidra 12.1.x, but upstream verification documents 12.1.4, not 12.1.2. Validate with rea doctor.
- Requirements: supported Node 22.23.4+ or 24.22.1+ or 26.12.1+, full JDK matching host architecture, Linux procps/ps and native Ghidra decompiler. The setup script is opt-in and requires network.

## Commands

    bash scripts/rea-ghidra-setup.sh
    source "$HOME/.local/share/fbt-re-tools/env.sh"
    rea doctor --provider ghidra --json

    python3 scripts/rea-ipa-extract.py /absolute/path/Facebook.ipa
    CASE="scratch/rea-analysis/inputs/<sha256-from-extractor>"
    bash scripts/rea-mobileconfig-investigate.sh "$CASE" shared
    bash scripts/rea-mobileconfig-investigate.sh "$CASE" rare
    bash scripts/rea-mobileconfig-investigate.sh "$CASE" rn

To decompile a selected function, first confirm that the module UUID and code bytes match earlier forensic findings, then:

    bash scripts/rea-mobileconfig-investigate.sh "$CASE" shared 0x49dfe60

The 0x49dfe60 address is a historical lead for FBMobileConfigQEInfoManager::refreshNames, NOT a universal address. REA produces Ghidra pseudocode, XREFs and JSON evidence, not the original source code. Use targeted work on each Mach-O, compare with existing LIEF/Capstone evidence, and classify observations CONFIRMADO / PROVÁVEL / DESCONHECIDO.

Our currently uploaded Facebook(2).ipa is SHA256 79b736c6def224f820f4f5e9ff021d6ab2157854f8d936970e4959b97bd9c728, different from prior reference 219805183da01842b8f8464b5ec404d1fbb6774f49b41de9649a09371661dc2f. Do not transfer static addresses, data assumptions or experiment contexts without verification.

Output: scratch/rea-analysis/inputs/<SHA>/manifest.json and scratch/rea-analysis/inputs/../results/<SHA>/<module>. Keep the IPA and extracted binaries out of Git.

For a local agent/IDE connection, source env.sh, execute rea setup, select your client, review permissions and restart it. A GitHub connector does not itself run Ghidra. Static decompilation does not grant server-side employee/dogfood privileges or fix a QE HTTP 400.
