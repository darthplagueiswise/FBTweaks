#!/usr/bin/env python3
"""Summarize retained MC diagnostic events and optional app-group ZIP, without credentials.
Usage: python scripts/analyze-mobileconfig-capture.py diagnostics.json [AppGroup.zip]
Only counts, protocol field states and the supplied tweak build are emitted.
"""
import collections
import json
import re
import sys
import zipfile

KNOWN = {'mobileconfig', 'mobileconfigsessionless', 'mobileconfig_qe_info', 'mobileconfiglogging'}
def summarize(diagnostic, archive=None):
    events = diagnostic.get('events', [])
    completions = [e for e in events if e.get('event') == 'native_mc_fetch_completed']
    flows = {}
    for event in completions:
        purpose = event.get('capture_reason')
        if purpose not in KNOWN:
            purpose = 'other'
        flow = flows.setdefault(purpose, {'successes': 0, 'failures': 0, 'http_status_counts': {}})
        flow['successes' if event.get('native_transport_success') else 'failures'] += 1
        status = event.get('http_status')
        if not status:
            match = re.search(r'\bdomain: FBHTTPErrorDomain code: ([1-5][0-9]{2})\b', event.get('message', ''))
            status = int(match[1]) if match else None
        if status:
            key = str(status)
            flow['http_status_counts'][key] = flow['http_status_counts'].get(key, 0) + 1
    states = collections.Counter((e.get('legacy_refresh_override_file_state'),
                                 e.get('builtin_query_hash_override_file_state'))
                                for e in events if e.get('event') == 'qe_info_request_started')
    result = {'scope': 'retained_event_window_not_lifetime_totals',
              'build': diagnostic.get('session_settings', {}).get('build', {}),
              'retained_events': len(events), 'completed_requests': len(completions), 'flows': flows,
              'qe_override_states': [{'legacy_refresh': state[0], 'builtin_query_hash': state[1], 'requests': count}
                                     for state, count in states.items()],
              'native_contexts': diagnostic.get('native_hooks', {}).get('contexts', {})}
    if archive:
        payloads = {'json_count': 0, 'populated_config_responses': 0, 'empty_config_responses': 0,
                    'max_config_count': 0, 'formatted_error_text_count': 0}
        with zipfile.ZipFile(archive) as zipped:
            for item in zipped.infolist():
                if item.filename.startswith('__MACOSX/') or '/fbt_fetch_payloads/' not in item.filename or item.file_size > 2 * 1024 * 1024:
                    continue
                if item.filename.endswith('.txt'):
                    if b'FBHTTPErrorDomain code: 400' in zipped.read(item):
                        payloads['formatted_error_text_count'] += 1
                elif item.filename.endswith('.json') and not item.filename.endswith('.meta.json'):
                    try:
                        body = json.loads(zipped.read(item))
                    except (ValueError, UnicodeDecodeError):
                        continue
                    payloads['json_count'] += 1
                    configs = body.get('configs') if isinstance(body, dict) else None
                    if isinstance(configs, dict):
                        payloads['populated_config_responses' if configs else 'empty_config_responses'] += 1
                        payloads['max_config_count'] = max(payloads['max_config_count'], len(configs))
        result['archive_payloads'] = payloads
    return result

if __name__ == '__main__':
    print(json.dumps(summarize(json.load(open(sys.argv[1])), sys.argv[2] if len(sys.argv) > 2 else None), indent=2))
