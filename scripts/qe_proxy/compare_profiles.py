#!/usr/bin/env python3
"""Compare two sanitized QE-info proxy captures; no credentials or identifiers exported.

Inputs must be JSONL produced by scripts/qe_proxy/addon.py. A proxy observation
represents the final HTTP request seen at that proxy, NOT proof of server access.
"""
import argparse
import json
from pathlib import Path

EXPECTED = {
    'needs_name': True,
    'skip_qe': False,
    'with_experiments': True,
    'with_params': True,
    'with_groups': True,
    'with_group_params': True,
    'with_gatekeepers': True,
    'with_universe_params': True,
    'with_current_experiment_group': True,
}
MAX_CAPTURE_BYTES = 2 * 1024 * 1024


def summarize_exchange(path):
    source = Path(path)
    if not source.is_file() or source.stat().st_size > MAX_CAPTURE_BYTES:
        raise ValueError('sanitized_proxy_capture_unavailable_or_oversize')
    # Never emit raw JSONL lines, arbitrary query values, credential IDs or URLs.
    pending = {}
    completed = []
    with source.open('r', encoding='utf-8') as handle:
        for line in handle:
            event = json.loads(line)
            if not isinstance(event, dict):
                continue
            identifier = event.get('local_exchange_id')
            summary = event.get('summary')
            if not isinstance(identifier, str) or not isinstance(summary, dict):
                continue
            if event.get('event') == 'request' and summary.get('endpoint') == 'mobileconfig_qe_info':
                pending[identifier] = summary
            if event.get('event') == 'response' and identifier in pending:
                completed.append((pending.pop(identifier), summary))
    if not completed:
        return {'exchange': 'not_observed', 'protocol_flags': {}, 'status': None,
                'server_error': 'not_observed', 'wire_profile': 'not_observed'}
    request, response = completed[-1]
    body = request.get('body_shape') if isinstance(request.get('body_shape'), dict) else {}
    query = request.get('query_shape') if isinstance(request.get('query_shape'), dict) else {}
    options = body.get('protocol_options') or query.get('protocol_options') or {}
    flags = {key: options[key] for key in EXPECTED if key in options and type(options[key]) is bool}
    captured = all(key in flags for key in EXPECTED)
    matching = captured and all(flags[key] is desired for key, desired in EXPECTED.items())
    error = response.get('error')
    classification = error.get('classification', 'other') if isinstance(error, dict) else 'none'
    return {
        'exchange': 'observed',
        'request_method': request.get('method') if request.get('method') in ('GET', 'POST') else 'other',
        'wire_profile': 'matches_full_metadata' if matching else 'different' if captured else 'not_fully_observable',
        'protocol_flags': flags,
        'body_kind': body.get('kind') if body.get('kind') in (
            'json', 'form', 'oversize', 'encoded', 'unavailable', 'invalid', 'empty') else 'other',
        'status': response.get('http_status') if type(response.get('http_status')) is int else None,
        'server_error': classification if classification in ('eligibility', 'unclassified', 'other', 'none') else 'other',
        'source': 'final_request_visible_to_explicit_proxy_only',
    }


def compare(baseline_path, experimental_path):
    baseline = summarize_exchange(baseline_path)
    experimental = summarize_exchange(experimental_path)
    return {
        'baseline': baseline,
        'experiment': experimental,
        'profile_changed_on_proxy_wire': (baseline['exchange'] == 'observed' and
            experimental['exchange'] == 'observed' and
            baseline['protocol_flags'] != experimental['protocol_flags']),
        'full_metadata_observed_on_proxy_wire': experimental['wire_profile'] == 'matches_full_metadata',
        'server_eligibility_granted': 'not_inferable_from_client_flags',
        'interpretation': ('remote_eligibility_rejection_remains' if experimental['server_error'] == 'eligibility'
            else 'status_observed_without_remote_eligibility_proof'),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', help='Baseline sanitized proxy events.jsonl')
    parser.add_argument('experimental', help='Experimental sanitized proxy events.jsonl')
    args = parser.parse_args()
    try:
        report = compare(args.baseline, args.experimental)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
        parser.error('Invalid or unavailable sanitized JSONL capture; no raw lines will be echoed')
    print(json.dumps(report, sort_keys=True, separators=(',', ':')))


if __name__ == '__main__':
    main()
