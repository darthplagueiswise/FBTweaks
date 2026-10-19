# Live employee, FBUser and tw_* tests

This change provides independent client experiments. It does not establish the
private server predicate behind `Employee Account or Specific App Conditions`.
No token, cookie, account identifier or user object is exported.

Open **Fetch, FBUser e tw_*** from the existing names diagnostics entry.
Start capture once. The local employee/gates control shows the existing tweak
preference, not a server entitlement. Record its starting state before testing.

## Independent controls

| Control | Actual scope | Rollback |
| --- | --- | --- |
| Local employee | Existing known employee gates, FBUserPreferences and an optional FBUser BOOL getter if that class/selector actually loads | Restore the displayed starting setting; this preference already persists |
| Temporary tw probe | Only `tw_is_employee.enabled` on the observed startup/import boolean readers; other `tw_*` values are observed, never blanket-enabled | Cancel, pause capture, restart, or wait 120 seconds |
| A request | Next native POST with purpose exactly `mobileconfig_qe_info`, unchanged | One request or 120 seconds |
| B request | Same request, append `is_employee=true` to a copied parameter vector; skip if native field exists | One request or 120 seconds |

The request purpose is narrower than FBUser and MobileConfig reads: FBUser is
a client model/getter family and `tw_*` is a config namespace, not an endpoint.
Their probes therefore live at the corresponding getters, not in guessed
HTTP paths or invented headers. No native credential or callback is replaced.
The original parameter vector stays unchanged. The copied vector lives through
the asynchronous completion. Concurrent QE requests consume an arm only once.

## Run and export

1. Start capture. Keep the local employee setting and overrides fixed.
2. Arm A, run Force name download once. Return, arm B and repeat that action.
3. Repeat A/B for the native config/param information fetch. The selected
   native options remain unchanged; a names profile is not copied into params.
4. Test the local employee control and the temporary tw probe independently,
   using request A/native each time. Restore each control before the next test.
5. Share the report from this screen. Do not restart capture between A and B:
   starting a new capture resets identity observations and cancels pending tests.

Check the **actual** `request_id`, `experiment_profile`, `experiment_state`,
parameter summary, `local_employee_enabled` and `tw_probe_armed_at_start`.
Another simultaneous native QE action can consume the arm; use its recorded
profile to decide whether to repeat. No request is sent automatically.

## Evidence and limits

- Schema 7 includes `employee_identity`: original/effective values, count,
  time, sequence and caller image/RVA. The original value means before this
  tweak's change; another hook or native override can already affect it.
  It is not labeled SYS or SERVER.
- FBUserPreferences `isEmployee` and setter input are recorded. The optional
  FBUser getter is installed only when present with a zero-argument BOOL ABI;
  no method is added. Class/selector availability is exported.
- `tw_*` observations include the real packed key and catalog label. SYS
  inspection bypasses both the temporary probe and its observations. Reads
  wholly inside a native image can bypass imported readers and remain unknown.
- Identity sequences at request start/completion delimit process observations.
  They are not a claim that a getter caused or belongs to that request.
- Authorization is summarized using the verified native optional-string getter
  at Tigon `onStarted`: presence, scheme and whether the credential is nonempty.
  It exports no value or hash. This is not the wire, an actor/token comparison,
  a duplicate-header audit, token validity or proof of server eligibility.
  Missing callback/getter remains explicitly unobserved.
- HTTP/body/native completion are still correlated by the existing terminal
  callback. A true callback is not proof of names parsing/writing. Params must
  also produce native universe/gatekeeper outputs; inspect existing
  `qe_info_request_returned` output fields. There is no fabricated Success.

`scripts/verify-employee-probes.py` independently checks the supplied Shared UUID,
six optional-header instructions and the two FBUserPreferences method ABIs.
The optional header getter is enabled at runtime only after the existing
Shared UUID/slot checks succeed and its exported function matches RVA 0x561d4c.

Portable tests cover expiry, cancellation, request scope, immutability and
concurrent consumption. The macOS workflow additionally exercises identity
observation, the exact tw allowlist, SYS exclusion and header-summary privacy.
An on-device A/B result is still required to establish whether any tested
client change affects the server response.
