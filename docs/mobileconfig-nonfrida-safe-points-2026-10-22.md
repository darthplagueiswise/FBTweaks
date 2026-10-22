# MobileConfig fetch — safe-point audit without Frida (Facebook 583)

This is a read-only diagnostics change. It does **not** claim to fix server fetch or observe the two ARM64 guards directly.

## Binary evidence
- Main Mach-O UUID: `4C4C44AA-5555-3144-A18E-014741ED190B`.
- FBSharedFramework UUID: `4C4C44FE-5555-3144-A1C2-6CCAE4ED2597`.
- Main has chained imports for `FBMobileConfigManager::updateConfigsWithParamsListSynchronously`, `FBMobileConfigStorageManager::persistConfigsFromDeltaResponse`, and `FBMobileConfigTigonFetcher::setManagerFetcher`.
- FBSharedFramework exports the manager sync function at `0x49E9838` and delta persistence at `0x138F398`.
- The sync guards at `0x49E987C` and `0x49E98D8` are internal code locations in `__TEXT`. An import trampoline is **not** an exact per-guard observer.
- The existing `FBTRebindVerifiedMainConstSlot` requires `__DATA_CONST,__const`; main chained imports can reside in `__DATA_CONST,__got`. Never pass a GOT slot through the current __const helper.
- The full ABI, hidden return storage, and callsite coverage of C++ sync and persistence imports have not been proved safe for interception. Consequently this change installs **no** hooks for them.

## Implemented instrumentation
- Hooks added: **zero**. The existing `FBT_ENABLE_QE_INVASIVE_HOOKS=0` remains unchanged.
- Existing native UI selection, request diagnostics, and value-reader events gain a process-local trace sequence and a UUID-compatibility marker.
- Read-only `FBMobileConfigOptions::valueSource()` observations record *names* and indices of configurations and parameters; no parameter values, account/device identifiers, tokens, or raw HTTP bodies are recorded.
- `SERVER` means a native reported source and **may come from cache**. `DEFAULT` or `DEFAULT__MISSING_SERVER_VALUE` are not successful server fetches.
- Request IDs are linked exactly only after they are observed. Temporal proximity is explicitly marked `temporal_candidate_only` and must never be interpreted as proof that a background sync belonged to a UI attempt.

## Native configuration names
- `mobileconfig_sessioned_startup_config → disable_rn_config_merge (39594:4)`: override test can separately remove its local forcing and re-enter SYS.
- `mobileconfig_sessioned_startup_config → use_params_map_merge_v2 (39594:5)`: actual ARM64 startup consumer identified.
- `mobileconfig_sessioned_startup_config → vaidate_params_map_merge_v2 (39594:6)`: descriptor present; exact callsites unverified.
- `rn_core → mobile_config_verify_correctness (4897:83)`: default literal `server_value` is **not** proof of newly downloaded data.

## Test method
1. Keep `FBT_ENABLE_QE_INVASIVE_HOOKS=0` (default). Build on the appropriate Theos SDK and the target IPA.
2. Enable safe diagnostics in the FBTweak UI, then select the same native config/parameter or inspect it in MobileConfig local.
3. Export `fbt_fetch_diagnostics.json`. Compare `mc_trace_attempt`, `mc_trace_link`, `mc_trace_uuid_match`, `mc_value_source_bucket`, and native HTTP outcomes.
4. Only a same-request native sync response + delta persistence + subsequent native `SERVER` source proves the full path. This instrumentation does **not** provide all three; it avoids falsely asserting such a result.

## Fail-closed status
On UUID mismatch, `mc_trace_uuid_match=false`; no direct native interceptors are installed. This static audit is **not** a Theos compile test or a device runtime pass.
