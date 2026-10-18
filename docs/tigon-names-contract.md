# Force name download: request options, results and a controlled rollback

Validated against Facebook 583 reference binaries, FBSharedFramework SHA-256
0d9c6ba20a60aced36ed7678305e987da18262ae7c7d4414e0b8f53e4631161b.

- `refreshNames` at 0x49dfe60 builds the names profile. At 0x49dff70 it clears
  the option storage and at 0x49dff80–84 writes 0x0101 for needs_name/skip_qe.
- `asyncFetch` at 0xa17f70 constructs TigonRequest and TigonSimpleCallbacks.
  Its success callable's vtable slot 0x8162088 targets 0x1389f98; error slot
  0x8162118 targets 0x4c56f50. These addresses were read from the original bytes.
- The success callable rejects absent/empty bodies. A nonempty body causes
  `w1=1` at 0x1389ff0 before invoking the caller. It does not validate names.
- The error callable formats TigonError and follows the shared false-return
  helper. HTTP 400 with an OAuthException body is not a TLS connection failure.
- The names continuation at 0x4c0416c branches around response parsing when
  the transport boolean is not 1. On its ordinary return path it forwards
  that boolean. Do not equate a callback boolean with a verified file write.
- In the main executable, 0x10005ad84 loads `_ios_tigon_property_migration`;
  +0x10 selects parameter 2. Its boolean enters the HTTP stack initializer
  `...useTigonPropertyMigration:enabledPropertyMigrations:` at 0x10005add4.
  Thus restoring 118554:2 to SYS is a concrete one-variable rollback test,
  not a demonstrated fix or a server authorization setting.
- `ios_tigon_qpl.enabled` has a concrete reader at 0x43e3dc. Instrumentation
  is separate from authorization. Do not change credential-domain allowlists
  or token stripping based only on historical catalog names.

Diagnostics schema 5 adds correlated request assessments in both the in-app
screen and JSON export. Missing observations remain unknown. It explains the
native false options, native transport status, observed names structure,
unobserved final authentication, and uncorrelated file persistence.
The hook does not change requests, native returns, tokens or server decisions.

A useful device test keeps account, app and request profile unchanged, restores
only migration v2 to SYS, fully restarts Facebook, and compares one names request
with the original. A merge-only import cannot remove an existing override;
replace the file or reset the specific parameter. If the exact eligibility
rejection remains, that rollback has not fixed it. Authentication at the final
request and the private backend eligibility predicate remain unobserved.

## Follow-up: service injection and actual flag reads

The executable's 0x10009a0d4 calls FBHttpUpperStackWithSession at
0x10009a228, obtains `service`, and captures that shared_ptr in the block
0x10009b580. Its call at 0x10009b62c installs the manager fetcher.
Another construction at FBSharedFramework 0x4a54adc obtains the same kind
of session upper stack and passes its service to setManagerFetcher at
0x4a54b58. The general lifecycle path instead obtains InitParams.tigonService
at 0x467e3c and installs it immediately or via a deferred block; it must not
be labelled session-authenticated without tracing the supplied InitParams.

The fetcher constructor stores the service at +0x50 (0x46e860-64).
asyncFetch loads it at 0xa18580 and dispatches vtable +0x10 at 0xa185c8
(outlined slot lookup 0x21bc8). FBHttpUpperStack creates a TigonStack with
vtable 0x811c498; slot 0x811c4a8 is 0x45be80, TigonStack::sendRequest.
That method forwards to its current inner service, not directly to a socket.

Session upper stack construction follows 0x53cb60 -> initializer 0x53cbec
-> provider 0x53cbf8 -> 0x53cc04. The provider builds the request-interceptor
vector, including the branch on validate_auth_header. This closes the static
link from the session fetcher to the auth-selector construction. It does not
prove which session/constructor produced a particular runtime request.

The read-only capture now exports `tigon_service_snapshot` per native request
and `auth_validation_read_snapshot`. The latter records only genuine returns
from getBool:withDefault: to the two verified constructor sites, separated
into session and logged-out scopes. It is process-level history, not an
identity-to-request correlation, and never contains tokens or account IDs.
Missing observations stay `not_observed`, without a fabricated false value.
The hook is gated on the verified framework UUID, exact method ABI and
original IMP RVA. Late installation cannot reconstruct earlier reads.

The exporter also no longer overwrites schema 5 with schema 4. Tests cover
unknown versus false, constructor-site filtering, unchanged getter results,
unmapped memory, UUID/layout gating, null service and unknown dispatch.
No part of this capture changes HTTP acceptance, employee eligibility,
authentication headers, native request parameters or callback results.

