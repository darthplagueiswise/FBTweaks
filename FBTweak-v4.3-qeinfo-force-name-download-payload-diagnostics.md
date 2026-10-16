# FBTweak v4.3 — QE-info / Force name download payload diagnostics

## Purpose

This patch targets the separate QE-info/name-metadata path used by the native MobileConfig parameter UI. The ordinary MobileConfig values stores can advance while `mobileconfig_qce/*` name metadata remains empty; therefore ordinary sync response dumps do not establish that **Force name download** ran successfully.

## Capture model

- Diagnostics are opt-in through **FBTweak → Runtime → Log de fetch QE-info (ON/OFF)**.
- The hook records entry/return for `FBMobileConfigQEInfoManager::fetchQEInfoSynchronously` and for `FBMobileConfigQEInfoManager::refreshNames(force, completion)`, including the real completion bool and elapsed time where exposed.
- A 45-second capture window is armed at these call sites. The runtime attempts to observe matching traffic from both `NSURLSession` completion callbacks and the imported `TigonForwardingRequestCallbacks` callbacks found in the Facebook ARM64 executable.
- Request metadata is limited to host, path, method, and query-hash state/length. It does **not** persist request bodies, URL query values, authorization headers, cookies, session tokens, or other request credentials.
- When a text response body under 2 MiB has no detected credential fields, its bytes are written unchanged to `AppGroup/mobileconfig/fbt_fetch_payloads/qe_payload_<UUID>.json|txt`. No body text is redacted, rewritten, replaced, or summarized in that file. A sibling `.meta.json` holds timestamp, transport, payload size, SHA-256, and query-hash state/length (never hash values).
- If a response body appears to contain credential fields, the **entire body is not written**; the log records `credential_field_detected_not_persisted`. Binary/non-UTF8 and over-limit bodies are also explicitly marked as skipped rather than represented as successful capture. Headers and request bodies are never written.
- The raw body is the exact byte sequence passed to the relevant client callback; it is not a packet/TLS wire capture. Native Tigon HTTP status is marked unavailable unless separately exposed by a callback; the tool does not invent a status code.

## Files

- `src/Runtime/FBTMobileConfigResponseCapture.m`: opt-in URLSession capture, body safety checks, exact-byte persistence and metadata.
- `src/Runtime/FBTMobileConfigTigonCapture.mm`: import hooks for Tigon callbacks, request URL/method getters, query-hash presence/length, IOBuf body-chain copying and response persistence.
- `src/Runtime/FBTMobileConfigDebugUIHooks.mm`: fetch-QE-info and refresh-names events.
- `src/Settings/FBTSettingsViewController.m`: status summary and copy/view actions for the latest raw body.
- `scripts/validate-sdk26.sh`: checks that response and Force name download instrumentation is included.
- `.github/workflows/buildtweak.yml`: runs the SDK 26.2 rootless build for PRs targeting `flags` or `main`.

## Reproduction

1. Install the branch build and restart Facebook if needed.
2. Open **FBTweak → Runtime** and enable **Log de fetch QE-info (ON/OFF)**.
3. Under **Ações**, open **A/B QE-info: isolar refresh/hash**.
4. Choose **0 — Baseline (sem alteração)** first. This snapshots the original tri-state values (`SYS`/`OFF`/`ON`) and leaves them unchanged. Restart Facebook, run **Internal Settings → MobileConfig → Force name download**, then export the baseline diagnostics and response dumps.
5. Choose test A (**legacy refresh OFF**). The tool restores the saved baseline before changing only this candidate. Restart Facebook, run the same action, and export the A snapshot.
6. Choose test B (**builtin query hash OFF**). The saved baseline is reapplied first, so this test does not leave both candidates disabled. Restart Facebook, repeat the same action, and export the B snapshot.
7. Use **Restaurar estado anterior** after the comparison to return both entries to the exact original tri-state values. `SYS` means the tool removes that explicit override entry rather than writing `false`.
8. Open **FBTweak → Runtime → MobileConfig Live → Plist audit** and export the JSON report. Confirm the reported bundle ID and selected plist path before interpreting discrepancies.
9. Open **FBTweak → Runtime → MobileConfig Live → Fetch log**. Inspect:
   - `mobileconfig/fbt_fetch_diagnostics.json`
   - `mobileconfig/fbt_fetch_payloads/`
   - the timestamps and contents of `mc_sync_response_dump*.json`

The event fields `legacy_refresh_override_file_state` and `builtin_query_hash_override_file_state` report what was written in `mc_overrides.json` when QE-info/name-download events occurred. They are deliberately named *file_state*: they do not prove the current executable found the parameter in its active name map or consumed the override.

## mc_overrides ↔ Preferences plist audit

- **MobileConfig Live → Plist audit** reads the exact resolved `mc_overrides.json` path, obtains the running app's `NSBundle.mainBundle.bundleIdentifier`, and derives Preferences/App Group candidates from that bundle ID.
- The `com.facebook.ota` bundle prefers `group.facebook.ota`; the full Facebook bundle prefers `group.com.facebook.Facebook`. Other candidates are used only if an actual plist exists. The audit checks app-container `Library/Preferences`, `Preferences`, and `AppData/Preferences` locations plus matching shared-container locations.
- It selects the best matching plist containing `FBMobileConfigStartupConfigs`, then compares each override row `configName.paramName` with that plist entry's `v` value.
- Results distinguish **match**, **value mismatch**, **not represented in plist**, and **plist entry without v**. A missing key is not reported as a value mismatch because that plist cannot verify the override row.
- The report is saved beside the resolved override file as `fbt_mc_overrides_plist_audit.json`; the UI can copy the complete report as JSON.
- This verifies that persisted preferences agree with the override file for comparable keys. It does not claim every parameter belongs in the startup plist or independently prove that a runtime reader consumed the override.

## Interpretation

- `name_download_started` without `name_download_completed`: completion did not run or the intercepted call differed from the assumed signature.
- `name_download_completed.download_success=false`: the native refresh reports failure; compare it with request and response events.
- `tigon_callback_hooks.hook_installed=false` or missing individual hooks: the current executable did not expose the import bindings as expected.
- `tigon_request_started` with `query_hash_state=empty|missing`: the observed URL did not carry a non-empty query hash. The instrument intentionally does not inspect/persist request-body content; a body-supplied hash requires another instrumented API surface.
- `network_response_body_captured`: open the exact body file; native GraphQL/backend error data, if returned as text, may reveal bad/missing hash, permission errors, or logical rejection.
- `network_response_body_skipped`: read `body_capture_status`; the body was **not** substituted or partially redacted.
- QE-info returns true while `params_names` remains empty: investigate whether the returned metadata is compatible with the active QCE store/schema and whether a write/generation switch occurred.
- No observed request event does not prove no network request was made: Tigon may use a callback/vtable or another networking surface that bypasses these imports. Check hook flags and the `NSURLSession` event too.

## Important limitations

This is static/runtime instrumentation, not a claim that every request is captured. Callback imports may be bypassed by same-image virtual calls. The Tigon status code is not currently decoded from the opaque `TigonResponse` object. The branch should be compiled and tested on-device before trusting any runtime result. No pinning bypass, request replay, fabricated response, or mutation of MobileConfig data is added.
