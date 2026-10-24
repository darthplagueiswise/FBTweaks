"""Stdlib-only, allowlisted summaries. Raw input must never reach the event writer."""
from datetime import datetime, timezone
from collections import Counter
import json
import hashlib
import hmac
import secrets
import zlib
import os
from pathlib import Path
import re
import threading
from urllib.parse import parse_qsl
import uuid

MAX_BODY = 65536
MAX_QUERY = 8192
MAX_FIELDS = 64
MAX_CREDENTIAL = 16384
# One random key per proxy process; no registry, disk state or exported key.
_credential_observation_key = secrets.token_bytes(32)
_CREDENTIAL = re.compile(r'(?:Bearer|OAuth) +([-A-Za-z0-9._~+/]+=*)', re.IGNORECASE | re.ASCII)
ENDPOINTS = frozenset(('mobileconfig_qe_info', 'mobileconfig', 'mobileconfigsessionless'))
SHAPE_FIELDS = frozenset(('queries', 'query', 'variables', 'params', 'data', 'configs', 'experiments', 'query_results', 'error'))
BOOLEAN_FIELDS = frozenset(('needs_name', 'skip_qe', 'with_universe_params',
    'with_current_experiment_group', 'with_only_current_experiment_group',
    'with_all_experiment_groups', 'with_experiment_params', 'with_experiment_universes',
    'with_gatekeepers', 'with_experiments', 'with_params', 'with_groups', 'with_group_params'))
_PATH = re.compile(r'^/(?:v[0-9]{1,3}\.[0-9]{1,3}/)?(mobileconfig_qe_info|mobileconfig|mobileconfigsessionless)$')


class _JSONObject(dict):
    def __init__(self, pairs):
        super().__init__(pairs)
        # Preserve duplicate counts for context/ambiguity without preserving values twice.
        self.field_counts = Counter(key for key, _ in pairs)


def _header(headers, name):
    for key, value in headers.items():
        if key.lower() == name:
            return value
    return ''


def _value_shape(value):
    if isinstance(value, dict):
        return {'kind': 'object', 'count': min(len(value), 1000)}
    if isinstance(value, list):
        return {'kind': 'array', 'count': min(len(value), 1000)}
    if value is None:
        return {'kind': 'null'}
    return {'kind': 'scalar'}


def _parse(data, content_type, limit):
    if len(data) > limit:
        return None, {'kind': 'oversize'}
    if not data:
        return None, {'kind': 'empty'}
    try:
        text = data.decode('utf-8', errors='strict')
        if content_type == 'form':
            pairs = parse_qsl(text, keep_blank_values=True, max_num_fields=MAX_FIELDS)
            return pairs, {'kind': 'form', 'fields': sorted({key for key, _ in pairs if key in SHAPE_FIELDS})}
        value = json.loads(text, object_pairs_hook=_JSONObject)
        shape = _value_shape(value)
        if isinstance(value, dict):
            for field in sorted(SHAPE_FIELDS.intersection(value)):
                shape[field] = _value_shape(value[field])
        return value, shape
    except (ValueError, UnicodeError, RecursionError):
        return None, {'kind': 'invalid'}


def _body(body, headers):
    if body is None:
        return None, {'kind': 'unavailable'}
    if len(body) > MAX_BODY:
        return None, {'kind': 'oversize'}
    encoding = _header(headers, 'content-encoding').strip().lower()
    if encoding == 'gzip':
        try:
            decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
            decoded = decoder.decompress(body, MAX_BODY + 1)
            if len(decoded) > MAX_BODY or decoder.unconsumed_tail:
                return None, {'kind': 'oversize', 'stage': 'decoded'}
            if not decoder.eof or decoder.unused_data:
                return None, {'kind': 'invalid_encoding', 'reason': 'invalid_gzip'}
            body = decoded
        except zlib.error:
            return None, {'kind': 'invalid_encoding', 'reason': 'invalid_gzip'}
    elif encoding not in ('', 'identity'):
        return None, {'kind': 'encoded'}
    media_type = _header(headers, 'content-type').split(';', 1)[0].strip().lower()
    return _parse(body, 'form' if media_type == 'application/x-www-form-urlencoded' else 'json', MAX_BODY)


def _boolean(value):
    if type(value) is bool:
        return value
    if type(value) is int and value in (0, 1):
        return bool(value)
    if isinstance(value, str) and value in ('true', 'false', '0', '1'):
        return value in ('true', '1')
    return 'invalid'


def _api_version(value):
    if type(value) is int and 0 <= value <= 99999:
        return value
    if isinstance(value, str) and 1 <= len(value) <= 5 and value.isascii() and value.isdecimal():
        return int(value)
    return 'invalid'


def _request_fields(value, shape):
    if shape['kind'] == 'form':
        counts = Counter(key for key, _ in value)
        fields = dict(value)
    elif isinstance(value, dict):
        fields = value
        counts = value.field_counts
    else:
        return None
    options = {}
    for field in sorted(BOOLEAN_FIELDS | {'api_version'}):
        if counts[field]:
            options[field] = ('duplicate' if counts[field] > 1 else
                              _api_version(fields[field]) if field == 'api_version' else _boolean(fields[field]))
    if options:
        shape['protocol_options'] = options
    shape['app_id_present'] = counts['app_id'] > 0
    shape['app_id_count'] = min(counts['app_id'], 1000)
    if counts['queries']:
        queries = fields['queries']
        if counts['queries'] > 1:
            shape['queries'] = {'kind': 'duplicate'}
        elif isinstance(queries, str):
            try:
                shape['queries'] = _value_shape(json.loads(queries))
            except (ValueError, RecursionError):
                shape['queries'] = {'kind': 'invalid'}
        else:
            shape['queries'] = _value_shape(queries)
    return counts['access_token'] > 0


def _credential_observation_id(authorization):
    if not authorization or len(authorization) > MAX_CREDENTIAL + 7:
        return 'unknown'
    match = _CREDENTIAL.fullmatch(authorization)
    if match is None or len(match.group(1)) > MAX_CREDENTIAL:
        return 'unknown'
    credential = match.group(1).encode('ascii')
    return hmac.new(_credential_observation_key, credential, hashlib.sha256).hexdigest()


def summarize_request(host, path, method, headers, body):
    # Do not normalize arbitrary hosts/paths into matches; no substring matching.
    if host.lower() != 'graph.facebook.com':
        return None
    resource, _, query = path.partition('?')
    match = _PATH.fullmatch(resource)
    if not match:
        return None
    auth = _header(headers, 'authorization')
    first = auth[:16].split(' ', 1)[0].lower()
    scheme = first if first in ('bearer', 'oauth', 'basic') and ' ' in auth[:17] else 'other'
    query_value = None
    if len(query) > MAX_QUERY:
        query_shape = {'kind': 'oversize'}
    else:
        query_value, query_shape = _parse(query.encode('utf-8', errors='replace'), 'form', MAX_QUERY)
    _request_fields(query_value, query_shape)
    body_value, body_shape = _body(body, headers)
    body_auth_field_present = _request_fields(body_value, body_shape)
    return {
        'endpoint': match.group(1),
        'method': method if method in ('GET', 'POST') else 'other',
        'authorization': {'present': any(key.lower() == 'authorization' for key in headers), 'scheme': scheme if auth else 'none', 'stage': 'proxy_wire',
                          'credential_observation_id': _credential_observation_id(auth)},
        'query_shape': query_shape,
        'body_shape': body_shape,
        'body_auth_field_present': body_auth_field_present,
    }


def summarize_response(status, headers, body):
    value, shape = _body(body, headers)
    summary = {'http_status': status if type(status) is int and 100 <= status <= 599 else None,
               'body_shape': shape}
    error = value.get('error') if isinstance(value, dict) else None
    if isinstance(error, dict):
        oauth = error.get('type') == 'OAuthException'
        code100 = type(error.get('code')) is int and error['code'] == 100
        message = error.get('message')
        normalized = message.strip().casefold() if isinstance(message, str) else ''
        if normalized.startswith('(#100)'):
            normalized = normalized[6:].strip()
        eligibility = oauth and code100 and normalized == 'employee account or specific app conditions'
        summary['error'] = {'type': 'oauth_exception' if oauth else 'other',
                            'code': '100' if code100 else 'other',
                            'classification': 'eligibility' if eligibility else 'unclassified'}
    return summary


class EventWriter:
    """Exclusive private JSONL output; stops writing after either cap (no rotation)."""
    def __init__(self, path, max_events=1000, max_bytes=2 * 1024 * 1024):
        self.path = Path(path)
        self.max_events = max_events
        self.max_bytes = max_bytes
        self.count = self.size = 0
        self.lock = threading.Lock()
        fd = os.open(self.path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(fd)

    def write(self, event):
        row = dict(event)
        row['local_event_id'] = str(uuid.uuid4())
        row['timestamp_utc'] = datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
        encoded = (json.dumps(row, separators=(',', ':'), sort_keys=True) + '\n').encode('utf-8')
        with self.lock:
            if self.count >= self.max_events or self.size + len(encoded) > self.max_bytes:
                return False
            fd = os.open(self.path, os.O_WRONLY | os.O_APPEND | getattr(os, 'O_NOFOLLOW', 0))
            with os.fdopen(fd, 'ab') as output:
                os.fchmod(output.fileno(), 0o600)
                output.write(encoded)
            self.size += len(encoded)
            self.count += 1
            return True
