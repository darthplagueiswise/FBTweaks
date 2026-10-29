# MobileConfig path correction implementation plan

> Execute inline. Read the design and preserve the IPA-derived directory order.

**Goal:** Select the same override directory as the native selector before a
live override owner is captured.

**Architecture:** Keep the observed owner path first. In each candidate container,
test mobileconfig then Documents/mobileconfig by directory existence. Return nil
when neither is present. Never choose an exported AppData tree or guess a path.

**Tech stack:** Objective-C++, Foundation, Python unittest, macOS CI/Theos.

**Spec:** ../specs/2026-10-28-mobileconfig-path-design.md

## Task 1: Reproduce and fix path selection

- [ ] Add `tests/OverridePathFixture.mm` and `tests/test_mc_override_path.py`.
- [ ] Run on macOS against the unchanged production resolver; retain failing
  assertions for two copies, an empty root directory, and absent native folders.
- [ ] Change `FBTNativeMobileConfigOverridesFilePath` to the directory policy.
- [ ] Run the full Python suite and the existing macOS/iOS workflow.

## Task 2: Deliver the operational solution

- [ ] Document native operations, host normalization, token sources, employee
  persistence, mapping validation, UUID cleanup and the remaining remote result.
- [ ] Include the patch, commit/build provenance and REA evidence in the report.
- [ ] Review the whole diff and preserve unrelated branch changes.

Review focus: live-owner priority; empty preferred directory; multiple app groups;
missing folders; read-only resolution. Each has a fixture assertion.
