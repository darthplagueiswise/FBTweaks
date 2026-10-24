# QE Full Metadata — LAB experimental (Facebook iOS 583)

## Provenance and limits

Based **exactly** on the head of [PR #5](https://github.com/darthplagueiswise/FBTweaks/pull/5), commit `ff80c6bfb6cfd50597315c74aedb6697eb9e29e1`. This work is in `codex/qe-full-metadata-pr5`; it does **not** overwrite PR #5 or the `flags` branch.

This is a one-shot **client request-protocol** experiment, not a bypass of employee authorization. The server's `OAuthException (#100) Employee Account or Specific App Conditions` must be preserved and reported. Merely changing fields does not grant access. No Facebook test requests were made in CI or this development environment.

## Configuration and scope

The hook already owned by `FBTMobileConfigFetcherCapture.mm` intercepts the ABI-verified `FBMobileConfigTigonFetcher::asyncFetch` parameters. The experiment changes an **independent copy** of the nine existing fields, subject to strict validation:

| Field | Forced LAB value |
| --- | --- |
| `needs_name` | true |
| `skip_qe` | false |
| `with_experiments` | true |
| `with_params` | true |
| `with_groups` | true |
| `with_group_params` | true |
| `with_gatekeepers` | true |
| `with_universe_params` | true |
| `with_current_experiment_group` | true |

The test deliberately **does not** set `with_only_current_experiment_group`. It does not modify `device_id`, USDID, queries, OAuth, headers, account IDs, routing or native callback results. If any required field is missing, duplicated or not boolean-encoded, it forwards all original fields unmodified.

A single `POST` with purpose `mobileconfig_qe_info` consumes the profile; unrelated GET/value sync requests cannot consume it. It expires after 120 seconds; starting/pausing a capture or canceling temporary experiments disarms it. Employee request experiments and this profile disarm one another when armed, preventing simultaneous intentional mutations. Native logs record `request_protocol_options_before`, `request_protocol_options_after`, the attempt status, change count and correlation request ID. This is **pre-builder evidence**, not the serialized wire request.

## Build and activate

The default release and PR CI keep `FBT_QE_LAB=0`: no protocol-mutation button, even though observability probes remain available. For this experimental PR branch only, CI additionally packages a **separate** `QE-LAB` artifact with `FBT_QE_LAB=1`; the normal `.deb` remains read-only. Do not confuse or interchange these packages. To build the LAB version locally with Theos SDK 26.2:

```bash
FBT_QE_LAB=1 ./build.sh rootless
```

Or use GitHub Actions **Build FBTweak (rootless, SDK 26.2) → Run workflow**, selecting branch `codex/qe-full-metadata-pr5` with **qe_lab** checked. LAB also enables other existing invasive experimental features, so do not ship it as a production build. The package must match the Facebook 583 Mach-O UUID; hook install failure means no mutation. Restart Facebook after installation. This is an ABI-sensitive experimental build, and on-device behavior remains unverified until tested there.

In Facebook, open **FBTweak → Fetch e contexto QE**:

1. **Iniciar nova captura**, and **Armar probes desta sessão**.
2. First establish baseline without arming this profile: execute one native **Force Name Download** and export the resulting diagnostic. The Network Inspector export includes sensitive raw data; **do not publish it or upload it to the repo**.
3. In a separate reproduction, tap **LAB: QE Full Metadata (1 pedido / 120 s)** and run **Force Name Download** once. The status must show `metadata_profile_applied=true`; otherwise trust `metadata_profile_reason`, not expectations.
4. Check the native completion/status and response body. An HTTP 400 remains a failure regardless of changed flags.

## Verify final serialized HTTP request and actual response

The native hook cannot prove what the Tigon request-builder serialized. PR #5 already provides the opt-in read-only mitmproxy addon, with no Authorization logging or TLS-verification bypass. This branch extends its exact-host list to `graph.facebook.com`, `graph.prod.facebook.com` and `graph.trunkstable.facebook.com` and raises the bounded raw-body limit to 256 KiB for large QE query forms.

Follow [docs/qe-proxy-whitehat.md](qe-proxy-whitehat.md) to configure the **same actual proxy/CA** on a device you administer. The full URL, raw request body, credentials and device IDs are never exported by the addon. The proxy records protocol boolean values actually visible to it at `stage=proxy_wire`, paired to the true server status/error within its own `local_exchange_id`. Neither a native request ID nor a pointer ID can be assumed identical to this proxy exchange ID. Pair reproductions by explicit action/time, not account identifiers.

Produce two **separate proxy** directories by running the launcher twice (one for baseline, one for LAB) and reproduce just one QE-info call per session:

```bash
python3 scripts/qe_proxy/compare_profiles.py \
  /private/baseline/events.jsonl \
  /private/experimental/events.jsonl
```

The comparer emits only a **single-line sanitized JSON** report, including `baseline`, `experiment`, `profile_changed_on_proxy_wire`, `full_metadata_observed_on_proxy_wire`, the HTTP status and the safe error classification. It does **not** export credential observation IDs, local exchange IDs, unknown server error text or parsed `queries` data. Its result is limited to the last complete QE-info request/response pair in each input. If the proxy did not see a usable body, the report says `not_fully_observable`.

Important cases:

- `full_metadata_observed_on_proxy_wire=true`, HTTP 400, `server_error=eligibility`: protocol mutation worked, remote authorization still denied.
- `metadata_profile_applied=true` in the native report but `not_fully_observable` in proxy: native parameter changes are evidenced; **wire delivery is not**.
- `wire_profile=different`: the final request did not contain all nine expected values. Trace the Tigon serialization and do not blame the server for that mismatch.
- HTTP 200: the backend returned success for that request, but client-side flag values alone do not prove the payload was parsed, applied or persisted by MobileConfig Sync.

Use synthetic local tests (`RequestExperimentTests.cpp`, `test_qe_proxy.py`, `test_qe_compare.py`) to check behavior and privacy. These tests do not validate authorization or on-device runtime behavior.
