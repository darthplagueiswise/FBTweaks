#!/usr/bin/env python3
"""Read-only QE hash-path audit. Prints one minified, credential-free JSON line."""
import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from zipfile import ZipFile

RESOURCE = "Payload/Facebook.app/mobileconfig_res/one_query_hash.txt"
MAX_INPUT = 8 * 1024 * 1024
HASH_FIELDS = ("query_hash", "one_query_hash")


def bundle_hash_state(ipa_path):
    if ipa_path is None:
        return "not_checked"
    try:
        with ZipFile(ipa_path) as ipa:
            raw = ipa.read(RESOURCE)
    except KeyError:
        return "bundle_resource_missing"
    except (OSError, ValueError):
        return "bundle_unavailable"
    try:
        text = raw.decode("ascii").strip()
    except UnicodeError:
        return "bundle_resource_invalid_encoding"
    if len(text) != 64:
        return "bundle_resource_invalid_length"
    return "bundle_resource_present_64hex" if re.fullmatch(r"[0-9a-f]{64}", text) else "bundle_resource_invalid_hex"


def audit_capture(doc, resource_state="not_checked"):
    if not isinstance(doc, dict):
        raise ValueError("not_an_object")
    raw_pairs = doc.get("request_parameter_pairs")
    if not isinstance(raw_pairs, list):
        raise ValueError("request_parameter_pairs_missing")
    pairs = [(p.get("name"), p.get("value")) for p in raw_pairs if isinstance(p, dict)]
    names = Counter(name for name, _ in pairs if isinstance(name, str))
    qs = [value for name, value in pairs if name == "queries"]
    query_count = None
    if len(qs) == 1 and isinstance(qs[0], str):
        try:
            arr = json.loads(qs[0])
            query_count = len(arr) if isinstance(arr, list) else None
        except ValueError:
            pass
    ids = [v for name, v in pairs if name == "device_id"]
    id_format = ("absent" if not ids else "duplicate" if len(ids) != 1 else
                 "field_name_literal" if ids[0] == "device_id" else
                 "empty" if not ids[0] else "other_unverified")
    status = doc.get("tigon_http_status")
    if type(status) is not int:
        status = doc.get("native_completion_status")
    response = doc.get("http_response_body")
    error_type = "not_observed"
    if isinstance(response, dict) and isinstance(response.get("utf8_preview"), str):
        try:
            result = json.loads(response["utf8_preview"])
            error = result.get("error") if isinstance(result, dict) else None
            if isinstance(error, dict) and error.get("code") == 100 and error.get("type") == "OAuthException":
                error_type = "oauth_exception_100_eligibility"
            elif isinstance(error, dict):
                error_type = "server_error_other"
            else:
                error_type = "no_structured_error"
        except ValueError:
            error_type = "response_not_json"
    return {
        "endpoint": "mobileconfig_qe_info" if doc.get("purpose") == "mobileconfig_qe_info" else "other",
        "observation_stage": "asyncFetch_native_arguments" if doc.get("request_source") ==
            "asyncFetch_parameters_before_Tigon_request_builder" else "other",
        "native_pair_count": len(pairs),
        "query_count": query_count,
        "query_hash_in_native_args": names["query_hash"] == 1,
        "one_query_hash_in_native_args": names["one_query_hash"] == 1,
        "query_hash_count": names["query_hash"],
        "one_query_hash_count": names["one_query_hash"],
        "one_query_bundle_resource_state": resource_state,
        "request_data_query_hash_sync_state": "not_determined_by_qe_info",
        "device_id_format": id_format,
        "http_status": status if type(status) is int else None,
        "server_error_class": error_type,
        "wire_hash_presence": "not_established_from_native_capture",
        "oauth_header_value_exported": False
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", help="Network Inspector JSON for one request")
    parser.add_argument("--ipa", help="Optional original IPA to audit bundled one_query_hash resource")
    args = parser.parse_args(argv)
    p = Path(args.capture)
    if p.stat().st_size > MAX_INPUT:
        parser.error("capture_too_large")
    try:
        doc = json.loads(p.read_text(encoding="utf-8"))
        report = audit_capture(doc, bundle_hash_state(args.ipa))
    except (OSError, UnicodeError, ValueError) as exc:
        parser.error("invalid_or_unavailable_capture")
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
