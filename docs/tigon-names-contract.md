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
