#!/usr/bin/env python3
"""Build and run UIKitRegressionHost against the real iOS 26+ Simulator UIKit.

The host and production UI helper/base controller are compiled. A private
temporary Simulator device/app is created and removed; existing devices, HEAD,
and the index are never changed. No tools, SDKs, or runtimes are installed.

Exit 0: every fixed case passed, or a requested baseline behavior regression
was observed. Exit 1: behavioral expectations were not met. Exit 2: build,
Simulator, result validation, or other infrastructure failure (never RED).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
HELPER = Path("src/UI/FBTUIKit26LiquidGlass.m")
HEADER = HELPER.with_suffix(".h")
HEADER_CASES = {"header.narrow", "header.accessibility", "header.resize"}
NAVIGATION_CASES = {
    "navigation.chrome.root", "navigation.chrome.child", "navigation.title.root",
    "navigation.title.child", "navigation.host_return",
}
SELECTION_CASES = {
    "selection.configuration", "selection.highlight_feedback",
    "selection.selected_feedback", "selection.restores",
}
SURFACE_CASES = {
    "screens.shared_table_lifecycle", "surfaces.grouped_table", "surfaces.empty_state",
    "search.native_surface", "header.auto_layout_filters",
    "search.collapsible_configuration", "search.native_activation", "appearance.dark_mode",
}
REQUIRED_CASES = {"runtime.ios26"} | NAVIGATION_CASES | SELECTION_CASES | HEADER_CASES
# Structural configuration checks alone are insufficient to prove the old bug.
REGRESSION_CASES = NAVIGATION_CASES | {
    "selection.highlight_feedback", "selection.selected_feedback",
}


class InfrastructureError(RuntimeError):
    """An error that must not be accepted as an expected behavior regression."""


def version_tuple(value: str) -> tuple[int, ...]:
    match = re.match(r"^(\d+)(?:\.(\d+))?(?:\.(\d+))?", value)
    if not match:
        raise InfrastructureError(f"Cannot parse SDK/runtime version: {value!r}")
    return tuple(int(part or 0) for part in match.groups())


class Runner:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.output = args.output_dir.expanduser().resolve()
        self.run_id = uuid.uuid4().hex
        self.bundle_id = f"org.fbtweak.UIKitRegression.{self.run_id}"
        self.device_id: str | None = None
        self.installed = False
        self.launched = False
        self.log = None
        self.summary = {
            "schema_version": 1, "run_id": self.run_id, "status": "infrastructure_error",
            "expected_regression": args.expect_regression, "baseline_ref": args.baseline_ref,
        }

    def command(self, argv: list[str], *, timeout: float | None = None,
                check: bool = True, quiet: bool = False) -> subprocess.CompletedProcess:
        # Argument arrays are intentional: refs, paths, and device names never reach a shell.
        if self.log:
            self.log.write("$ " + repr([str(value) for value in argv]) + "\n")
            self.log.flush()
        try:
            result = subprocess.run(
                [str(value) for value in argv], cwd=ROOT, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=timeout if timeout is not None else self.args.command_timeout,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise InfrastructureError(f"Command could not finish: {argv[0]}: {error}") from error
        if self.log:
            self.log.write(result.stdout + result.stderr + f"\n[exit {result.returncode}]\n")
            self.log.flush()
        if check and result.returncode:
            detail = (result.stderr or result.stdout).strip()[-6000:]
            raise InfrastructureError(f"Command failed ({result.returncode}): {argv!r}\n{detail}")
        if not quiet and result.stderr.strip() and result.returncode == 0:
            print(result.stderr.strip(), file=sys.stderr)
        return result

    def simctl(self, *args: str, **kwargs) -> subprocess.CompletedProcess:
        return self.command(["xcrun", "simctl", *args], **kwargs)

    def json_command(self, argv: list[str]) -> dict:
        output = self.command(argv).stdout
        try:
            result = json.loads(output)
        except json.JSONDecodeError as error:
            raise InfrastructureError(f"Invalid JSON from {argv!r}: {error}") from error
        if not isinstance(result, dict):
            raise InfrastructureError(f"Expected an object from {argv!r}")
        return result

    def selected_helper(self, temp: Path) -> tuple[Path, str, bool]:
        if not self.args.baseline_ref:
            source_dir = ROOT / HELPER.parent
            source_ref = self.command(["git", "rev-parse", "HEAD"]).stdout.strip() + "+working-tree"
        else:
            requested = self.args.baseline_ref
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/+\-]*", requested):
                raise InfrastructureError("--baseline-ref must be a commit SHA or ordinary Git ref")
            resolved = self.command(
                ["git", "rev-parse", "--verify", "--end-of-options", f"{requested}^{{commit}}"],
                check=False, quiet=True,
            )
            if resolved.returncode:
                # A shallow Actions checkout may not contain build435. Fetch objects only;
                # do not checkout, reset, create a worktree, or modify FETCH_HEAD.
                self.command(["git", "fetch", "--no-tags", "--no-write-fetch-head", "--depth=1", "origin", requested])
                resolved = self.command(["git", "rev-parse", "--verify", "--end-of-options", f"{requested}^{{commit}}"])
            source_ref = resolved.stdout.strip()
            if not re.fullmatch(r"[0-9a-f]{40,64}", source_ref):
                raise InfrastructureError(f"Unexpected resolved baseline commit: {source_ref!r}")
            source_dir = temp / "baseline-helper"
            source_dir.mkdir()
            for relative in (HELPER, HEADER):
                content = self.command(["git", "show", f"{source_ref}:{relative.as_posix()}"]).stdout
                (source_dir / relative.name).write_text(content, encoding="utf-8")
        for name in (HELPER.name, HEADER.name):
            if not (source_dir / name).is_file():
                raise InfrastructureError(f"Missing selected helper file: {source_dir / name}")
        declarations = (source_dir / HEADER.name).read_text(encoding="utf-8")
        has_header = all(re.search(rf"\b{name}\s*\(", declarations) for name in (
            "FBTUIKit26CreateOverviewHeader", "FBTUIKit26UpdateTableHeaderLayout",
        ))
        if not has_header and not self.args.baseline_ref:
            raise InfrastructureError("Fixed helper is missing the overview-header API; header tests cannot be skipped")
        self.summary.update(source_ref=source_ref, has_overview_header=has_header)
        return source_dir, source_ref, has_header

    def select_simulator(self) -> tuple[dict, dict]:
        runtimes = self.json_command(["xcrun", "simctl", "list", "runtimes", "--json"]).get("runtimes", [])
        available = [runtime for runtime in runtimes
                     if runtime.get("isAvailable") is True
                     and "SimRuntime.iOS-" in runtime.get("identifier", "")
                     and version_tuple(runtime.get("version", "0")) >= (26, 0, 0)]
        if self.args.runtime:
            available = [runtime for runtime in available if runtime["identifier"] == self.args.runtime]
        if not available:
            raise InfrastructureError("No available iOS 26+ Simulator runtime; select an installed Xcode/runtime")
        runtime = max(available, key=lambda item: version_tuple(item["version"]))
        device_types = self.json_command(["xcrun", "simctl", "list", "devicetypes", "--json"]).get("devicetypes", [])
        candidates = []
        for device in device_types:
            identifier = device.get("identifier", "")
            if ".iPhone-" not in identifier:
                continue
            if self.args.device_type and identifier != self.args.device_type:
                continue
            minimum = version_tuple(device.get("minRuntimeVersionString", "0"))
            maximum = version_tuple(device.get("maxRuntimeVersionString", "65535.255.255"))
            if minimum <= version_tuple(runtime["version"]) <= maximum:
                candidates.append(device)
        if not candidates:
            raise InfrastructureError(f"No compatible installed iPhone device type for {runtime['identifier']}")
        # simctl lists device generations in order; the last compatible iPhone is suitable.
        return runtime, candidates[-1]

    def build_app(self, temp: Path, sdk: Path, source_dir: Path,
                  source_ref: str, has_header: bool) -> Path:
        app = temp / "FBTUIKitRegression.app"
        app.mkdir()
        plist = {
            "CFBundleDevelopmentRegion": "en", "CFBundleDisplayName": "FBT UIKit Regression",
            "CFBundleExecutable": "FBTUIKitRegressionHost", "CFBundleIdentifier": self.bundle_id,
            "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "FBTUIKitRegression",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
            "LSRequiresIPhoneOS": True, "MinimumOSVersion": "26.0", "UIDeviceFamily": [1],
            "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"], "UILaunchScreen": {},
            "UIApplicationSceneManifest": {
                "UIApplicationSupportsMultipleScenes": False,
                "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{
                    "UISceneConfigurationName": "Regression", "UISceneDelegateClassName": "FBTRegressionSceneDelegate",
                }]},
            },
            "FBTRegressionRunID": self.run_id, "FBTRegressionSourceRef": source_ref,
            "FBTRegressionScreenshots": self.args.screenshots,
        }
        with (app / "Info.plist").open("wb") as destination:
            plistlib.dump(plist, destination)
        architecture = platform.machine()
        if architecture not in {"arm64", "x86_64"}:
            raise InfrastructureError(f"Unsupported macOS architecture: {architecture}")
        framework_search = []
        subframeworks = sdk / "System/Library/SubFrameworks"
        if subframeworks.is_dir():
            framework_search = ["-F", str(subframeworks)]
        self.command([
            "xcrun", "--sdk", "iphonesimulator", "clang",
            "-target", f"{architecture}-apple-ios26.0-simulator", "-isysroot", str(sdk),
            *framework_search,
            "-fobjc-arc", "-fblocks", "-fmodules", "-O0", "-g",
            "-Wno-deprecated-declarations", "-Werror=implicit-function-declaration",
            # Build435's existing UIGlassEffect/UIBlurEffect assignment must remain
            # a logged warning, so it cannot prevent the behavioral baseline run.
            "-Wno-error=incompatible-pointer-types" if self.args.baseline_ref else "-Werror=incompatible-pointer-types",
            "-Werror=objc-method-access",
            f"-DFBT_UIKIT_HAS_OVERVIEW_HEADER={int(has_header)}",
            f"-DFBT_UIKIT_BASELINE_MODE={int(bool(self.args.baseline_ref))}",
            "-I", str(source_dir), str(ROOT / "tests/UIKitRegressionHost.m"),
            str(source_dir / HELPER.name),
            *([] if self.args.baseline_ref else [str(source_dir / "FBTStyledTableViewController.m")]),
            "-framework", "UIKit", "-framework", "Foundation",
            "-framework", "QuartzCore", "-o", str(app / "FBTUIKitRegressionHost"),
        ])
        self.command(["codesign", "--force", "--sign", "-", "--timestamp=none", str(app)])
        return app

    def wait_for_result(self) -> dict:
        container_text = self.simctl("get_app_container", self.device_id, self.bundle_id, "data").stdout.strip()
        container = Path(container_text)
        if not container.is_absolute() or not container.is_dir():
            raise InfrastructureError(f"Invalid app data container: {container_text!r}")
        result_file = container / "Documents/ui-regression.json"
        deadline = time.monotonic() + self.args.test_timeout
        while time.monotonic() < deadline:
            if result_file.is_file():
                try:
                    result = json.loads(result_file.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError) as error:
                    raise InfrastructureError(f"Host wrote invalid result JSON: {error}") from error
                shutil.copy2(result_file, self.output / "result.json")
                if self.args.screenshots:
                    for png in sorted((container / "Documents").glob("*.png")):
                        shutil.copy2(png, self.output / png.name)
                return result
            time.sleep(0.5)
        # The host may have crashed or never reached its run loop. Neither is a regression proof.
        raise InfrastructureError(f"Host produced no completed JSON within {self.args.test_timeout:g}s")

    def evaluate(self, result: dict) -> int:
        if not isinstance(result, dict) or result.get("schema_version") != 1 or result.get("completed") is not True:
            raise InfrastructureError("Incomplete or unsupported host result")
        if result.get("run_id") != self.run_id or result.get("source_ref") != self.summary["source_ref"]:
            raise InfrastructureError("Host run/source identity mismatch; stale output cannot count")
        if result.get("baseline") is not bool(self.args.baseline_ref):
            raise InfrastructureError("Host baseline mode differs from the requested build")
        if result.get("has_overview_header") is not self.summary["has_overview_header"]:
            raise InfrastructureError("Host header feature detection differs from the selected helper")
        cases = result.get("cases")
        if not isinstance(cases, list) or not all(isinstance(case, dict) for case in cases):
            raise InfrastructureError("Malformed host cases")
        ids = [case.get("id") for case in cases]
        if not all(isinstance(name, str) for name in ids) or len(set(ids)) != len(ids):
            raise InfrastructureError("Missing or duplicate host case IDs")
        expected_cases = REQUIRED_CASES | (set() if self.args.baseline_ref else SURFACE_CASES)
        if set(ids) != expected_cases:
            missing, extra = sorted(expected_cases - set(ids)), sorted(set(ids) - expected_cases)
            raise InfrastructureError(f"Host case coverage mismatch: missing={missing}, extra={extra}")
        if version_tuple(str(result.get("os_version", "0"))) < (26, 0, 0):
            raise InfrastructureError("Host did not execute on iOS 26+")
        failures, skipped = [], []
        for case in cases:
            name, status = case["id"], case.get("status")
            expected_kind = "infrastructure" if name == "runtime.ios26" else "behavior"
            if case.get("kind") != expected_kind or status not in {"pass", "fail", "skipped"}:
                raise InfrastructureError(f"Host infrastructure error or malformed case: {case!r}")
            if expected_kind == "infrastructure" and status != "pass":
                raise InfrastructureError("Real UIKit runtime availability check failed")
            if status == "skipped":
                if not self.args.baseline_ref or self.summary["has_overview_header"] or name not in HEADER_CASES:
                    raise InfrastructureError(f"Unexpected skipped case: {name}")
                skipped.append(name)
            if status == "fail":
                failures.append(name)
            print(f"{status.upper():7} {name}")
        if self.args.baseline_ref and not self.summary["has_overview_header"] and set(skipped) != HEADER_CASES:
            raise InfrastructureError("Old helper must explicitly skip exactly the three unavailable header cases")
        regressions = sorted(set(failures) & REGRESSION_CASES)
        self.summary.update(failed_cases=sorted(failures), skipped_cases=sorted(skipped),
                            passed_cases=len(cases) - len(failures) - len(skipped),
                            observed_regressions=regressions)
        if self.args.expect_regression:
            if not regressions:
                self.summary["status"] = "expected_regression_missing"
                print("FAIL: baseline did not reproduce a navigation or visible selection regression", file=sys.stderr)
                return 1
            self.summary["status"] = "expected_regression"
            print("Observed baseline behavior regression: " + ", ".join(regressions))
            return 0
        if failures:
            self.summary["status"] = "behavior_failure"
            return 1
        if not self.args.baseline_ref and skipped:
            raise InfrastructureError("A fixed run must execute every case without skips")
        self.summary["status"] = "passed"
        return 0

    def cleanup(self) -> list[str]:
        errors = []
        if not self.device_id:
            return errors
        # Only the exact UUID returned by this run's create command can be touched.
        actions = []
        if self.launched:
            actions.append(("terminate", self.device_id, self.bundle_id))
        if self.installed:
            actions.append(("uninstall", self.device_id, self.bundle_id))
        actions.extend([("shutdown", self.device_id), ("delete", self.device_id)])
        for action in actions:
            try:
                result = self.simctl(*action, timeout=45, check=False, quiet=True)
                # Terminating an app which has already exited / shutting down an unbooted
                # device is harmless. Deletion must succeed to avoid leaving our device.
                if result.returncode and action[0] == "delete":
                    errors.append(f"Could not delete owned Simulator {self.device_id}: {result.stderr.strip()}")
            except InfrastructureError as error:
                errors.append(str(error))
        return errors

    def run(self) -> int:
        self.output.mkdir(parents=True, exist_ok=True)
        code = 2
        with (self.output / "runner.log").open("w", encoding="utf-8") as log:
            self.log = log
            try:
                if sys.platform != "darwin":
                    raise InfrastructureError("Real UIKit Simulator tests require macOS and an installed Xcode iOS 26+ SDK/runtime")
                for tool in ("xcrun", "codesign", "git"):
                    if not shutil.which(tool):
                        raise InfrastructureError(f"Required existing tool is missing: {tool}")
                sdk_version = self.command(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]).stdout.strip()
                if version_tuple(sdk_version) < (26, 0, 0):
                    raise InfrastructureError(f"Selected Xcode has Simulator SDK {sdk_version}; iOS 26+ is required")
                sdk = Path(self.command(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).stdout.strip())
                if not sdk.is_dir():
                    raise InfrastructureError(f"Selected Simulator SDK does not exist: {sdk}")
                runtime, device = self.select_simulator()
                self.summary.update(sdk_version=sdk_version, runtime=runtime["identifier"], device_type=device["identifier"])
                with tempfile.TemporaryDirectory(prefix="fbt-uikit-regression-") as temporary:
                    temp = Path(temporary)
                    source_dir, source_ref, has_header = self.selected_helper(temp)
                    app = self.build_app(temp, sdk, source_dir, source_ref, has_header)
                    identifier = self.simctl("create", f"FBTUIKitRegression-{self.run_id}", device["identifier"], runtime["identifier"]).stdout.strip()
                    if not re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", identifier):
                        raise InfrastructureError(f"simctl create did not return a device UUID: {identifier!r}")
                    self.device_id = identifier
                    self.summary["created_device"] = identifier
                    print(f"Using private Simulator {identifier} ({runtime['name']}, {device['name']})")
                    self.simctl("boot", identifier)
                    self.simctl("bootstatus", identifier, "-b", timeout=self.args.boot_timeout)
                    self.simctl("install", identifier, str(app))
                    self.installed = True
                    self.simctl("launch", "--terminate-running-process", identifier, self.bundle_id)
                    self.launched = True
                    code = self.evaluate(self.wait_for_result())
            except (InfrastructureError, OSError, ValueError) as error:
                self.summary.update(status="infrastructure_error", error=str(error))
                print(f"INFRASTRUCTURE ERROR: {error}", file=sys.stderr)
                code = 2
            finally:
                cleanup_errors = self.cleanup()
                if cleanup_errors:
                    self.summary.update(status="infrastructure_error", cleanup_errors=cleanup_errors)
                    print("INFRASTRUCTURE ERROR: " + "; ".join(cleanup_errors), file=sys.stderr)
                    code = 2
                self.summary["exit_code"] = code
                (self.output / "runner-summary.json").write_text(json.dumps(self.summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
                self.log = None
        print(f"Artifacts: {self.output}")
        return code


def positive_timeout(value: str) -> float:
    try:
        parsed = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive number of seconds") from error
    if not 0 < parsed <= 600:
        raise argparse.ArgumentTypeError("must be greater than 0 and at most 600 seconds")
    return parsed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "artifacts/uikit-simulator",
                        help="directory for result.json, runner-summary.json, logs and optional PNGs")
    parser.add_argument("--baseline-ref", help="compile the helper and header from this Git commit/ref in a temporary directory")
    parser.add_argument("--expect-regression", action="store_true",
                        help="require a baseline navigation/visible selection failure; infrastructure failures exit 2")
    parser.add_argument("--screenshots", action="store_true", help="retain real UIKit window PNGs for each major test state")
    parser.add_argument("--runtime", help="optional exact identifier of an installed, available iOS 26+ runtime")
    parser.add_argument("--device-type", help="optional compatible iPhone device type identifier; a new private device is always created")
    parser.add_argument("--boot-timeout", type=positive_timeout, default=180, help="Simulator boot limit in seconds (default: 180, max: 600)")
    parser.add_argument("--test-timeout", type=positive_timeout, default=60, help="host result limit in seconds (default: 60, max: 600)")
    parser.add_argument("--command-timeout", type=positive_timeout, default=120, help="per-command limit in seconds (default: 120, max: 600)")
    args = parser.parse_args(argv)
    if args.expect_regression and not args.baseline_ref:
        parser.error("--expect-regression requires --baseline-ref")
    return Runner(args).run()


if __name__ == "__main__":
    raise SystemExit(main())
