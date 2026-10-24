#!/usr/bin/env python3
"""Integrated, credential-free audit of QE-info native captures (single-line JSON).

Usage: python3 scripts/qe_pipeline_audit.py capture.json [more.json ...]
Never emits OAuth credentials, device IDs, query strings, raw headers or free-form errors.
"""
import argparse
from collections import Counter
import json
from pathlib import Path

FIELDS = ("needs_name","skip_qe","with_universe_params","with_current_experiment_group",
          "with_only_current_experiment_group","with_experiments","with_params",
          "with_groups","with_group_params","with_gatekeepers")
LIMIT = 4 * 1024 * 1024

def one(path):
    path = Path(path)
    if not path.is_file() or path.stat().st_size > LIMIT:
        raise ValueError("missing_or_oversize_capture")
    with path.open(encoding="utf-8") as source:
        data = json.load(source)
    if not isinstance(data, dict) or not isinstance(data.get("request_parameter_pairs"), list):
        raise ValueError("missing_native_parameter_pairs")
    pairs = data["request_parameter_pairs"]
    found = {}
    for pair in pairs:
        if not isinstance(pair, dict) or not isinstance(pair.get("name"), str):
            continue
        name = pair["name"]
        if name in FIELDS or name in ("queries","device_id","query_hash","one_query_hash"):
            found.setdefault(name,[]).append(pair.get("value"))
    query_data = found.get("queries",[])
    count = unique = bad = 0
    well_formed = False
    if len(query_data)==1 and isinstance(query_data[0],str) and len(query_data[0])<2*1024*1024:
        try:
            array = json.loads(query_data[0])
            well_formed = isinstance(array,list)
            if well_formed:
                count = len(array)
                safe = [q for q in array if isinstance(q,str) and 0<len(q)<16384 and
                        all(ch in "0123456789:" for ch in q)]
                bad = count-len(safe)
                unique = len(set(safe))
        except ValueError:
            pass
    boolean_profile = tuple((key,found[key][0]) for key in FIELDS
                            if len(found.get(key,[]))==1 and found[key][0] in ("true","false"))
    identifier = found.get("device_id",[])
    identity = "missing" if not identifier else "duplicate" if len(identifier)!=1 else (
        "field_name_literal" if identifier[0]=="device_id" else "other_unvalidated")
    hashes = {}
    for key in ("query_hash","one_query_hash"):
        value = found.get(key,[])
        hashes[key] = "not_in_native_pairs" if not value else "duplicate" if len(value)!=1 else (
            "empty" if not value[0] else "present")
    status = data.get("tigon_http_status") or data.get("native_completion_status")
    response = data.get("http_response_body")
    error = {}
    if isinstance(response,dict) and isinstance(response.get("utf8_preview"),str):
        try:
            parsed=json.loads(response["utf8_preview"])
            if isinstance(parsed,dict): error=parsed.get("error",{})
        except ValueError:
            pass
    eligibility = status==400 and isinstance(error,dict) and error.get("code")==100 and (
        "Employee Account or Specific App Conditions" in str(error.get("message","")))
    classification = "remote_eligibility_denied" if eligibility else (
        "other_http_error" if type(status) is int and status>=400 else
        "http_success_observed" if status in (200,201,204) else "unclassified")
    return {"endpoint": data.get("purpose")=="mobileconfig_qe_info",
            "request_method": data.get("request_method") if data.get("request_method") in ("GET","POST") else "other",
            "request_pairs":len(pairs),"queries_parsed":well_formed,
            "queries_count":count,"queries_distinct":unique,"queries_invalid_format":bad,
            "options":boolean_profile,"device_id_format":identity,
            "hash_states":hashes,"http_status":status if type(status) is int else None,
            "server_outcome":classification,
            "credential_present_not_authorized":bool(data.get("authorization_credential_present"))}

def summarize(paths):
    records=[one(path) for path in paths]
    if not records: raise ValueError("no_captures")
    outcomes = Counter(r["server_outcome"] for r in records)
    identities = Counter(r["device_id_format"] for r in records)
    return {"schema":1,"capture_count":len(records),
            "query_counts":sorted(set(r["queries_count"] for r in records)),
            "query_schema": "valid_unique" if all(r["queries_parsed"] and r["queries_count"] and
                r["queries_distinct"]==r["queries_count"] and not r["queries_invalid_format"] for r in records)
                else "some_queries_invalid_or_unobserved",
            "profile_variations":len(set(r["options"] for r in records)),
            "hashes_not_in_native_pairs":sum(all(v=="not_in_native_pairs" for v in r["hash_states"].values()) for r in records),
            "hash_protocol": "not_verified_required_for_qe_info",
            "identity_formats":dict(sorted(identities.items())),
            "remote_results":dict(sorted(outcomes.items())),
            "identity_variation_did_not_change_rejection":len(identities)>1 and
                outcomes.get("remote_eligibility_denied",0)==len(records),
            "pipeline":{"query_generation":"observed","native_parameters":"observed_before_Tigon_serialization",
                "final_post_body":"not_verified_by_native_pair_capture",
                "identity":"present_not_validated","credential":"present_not_remote_eligibility",
                "backend":"remote_eligibility_denied" if outcomes.get("remote_eligibility_denied",0) else "not_established",
                "qe_name_mapping":"not_received_if_HTTP_400","value_sync":"requires_separate_correlated_mobileconfig_response"},
            "not_proven":["QE_info_requires_query_hash","QE_info_requires_one_query_hash",
                "device_id_literal_is_sole_cause","OAuth_presence_means_eligible","any_local_override_grants_server_access"],
            "privacy":"sanitized_single_line_no_raw_account_ids_tokens_queries_or_error_text"}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("captures",nargs="+")
    arguments=parser.parse_args()
    try: print(json.dumps(summarize(arguments.captures),sort_keys=True,separators=(",",":"),ensure_ascii=False))
    except (ValueError,OSError,TypeError,UnicodeError) as error:
        parser.error("Invalid capture: "+str(error))

if __name__=="__main__":main()
