"""Local-only bridge prototype. No cloud, daemon install, credential generation.
Transport receipt is NOT a dot apply acknowledgment. Explicit local tool apply required.
"""
import contextlib
import datetime as dt
import fcntl
import hashlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import re
import sqlite3
import ssl
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import uuid
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

MAX_BYTES = 1024 * 1024


class BridgeError(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.bridge-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as file:
            os.fchmod(file.fileno(), 0o600)
            file.write(canonical(value))
            file.flush(); os.fsync(file.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try: os.fsync(directory)
        finally: os.close(directory)
    finally:
        if os.path.exists(name): os.unlink(name)


def validate_task(row):
    required = {'id', 'title', 'date', 'dateLabel', 'status', 'details', 'category', 'completed', 'revision'}
    optional = {'subcategory', 'parentId', 'project', 'tags', 'reminderAt', 'aiContext', 'startTime', 'endTime', 'timeZone', 'deadlineDate', 'deadlineTime', 'taskKind'}
    if not isinstance(row, dict) or row.keys() - required - optional or not required <= row.keys():
        raise BridgeError(400, 'invalid_task')
    if any(not isinstance(row[k], str) for k in required - {'date', 'completed', 'revision'}):
        raise BridgeError(400, 'invalid_task')
    if not re.fullmatch('[a-z0-9]+(?:-[a-z0-9]+)*', row['id']) or not row['title'].strip():
        raise BridgeError(400, 'invalid_task')
    if type(row['completed']) is not bool or type(row['revision']) is not int or row['revision'] < 1:
        raise BridgeError(400, 'invalid_task')
    if row['date'] is not None:
        try:
            if dt.date.fromisoformat(row['date']).isoformat() != row['date']: raise ValueError()
        except (ValueError, TypeError): raise BridgeError(400, 'invalid_date')
    if any(k in row and not isinstance(row[k], str) for k in ('subcategory', 'parentId')): raise BridgeError(400, 'invalid_task')
    if row.get('taskKind') is not None and row['taskKind'] not in ('event', 'task', 'idea', 'errand'):
        raise BridgeError(400, 'invalid_task_kind')
    if row.get('aiContext') is not None and not isinstance(row['aiContext'], str): raise BridgeError(400, 'invalid_ai_context')
    for field in ('startTime', 'endTime', 'deadlineTime'):
        value = row.get(field)
        if value is not None and (not isinstance(value, str) or not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d', value)):
            raise BridgeError(400, 'invalid_time')
    deadline = row.get('deadlineDate')
    if deadline is not None:
        try:
            if dt.date.fromisoformat(deadline).isoformat() != deadline: raise ValueError()
        except (ValueError, TypeError): raise BridgeError(400, 'invalid_deadline')
    zone = row.get('timeZone')
    if zone is not None:
        try:
            if not isinstance(zone, str): raise ValueError()
            ZoneInfo(zone)
        except (ValueError, ZoneInfoNotFoundError): raise BridgeError(400, 'invalid_timezone')
    start, end = row.get('startTime'), row.get('endTime')
    if (start is not None and (row['date'] is None or zone is None)) or (end is not None and (start is None or end <= start)):
        raise BridgeError(400, 'invalid_schedule')
    if row.get('deadlineTime') is not None and (deadline is None or zone is None): raise BridgeError(400, 'invalid_deadline')
    # Reject nonexistent wall times rather than silently moving a task during DST.
    for day, clock in ((row['date'], start), (row['date'], end), (deadline, row.get('deadlineTime'))):
        if day is not None and clock is not None:
            local = dt.datetime.fromisoformat(day + 'T' + clock).replace(tzinfo=ZoneInfo(zone))
            if local.astimezone(dt.timezone.utc).astimezone(local.tzinfo).replace(tzinfo=None) != local.replace(tzinfo=None):
                raise BridgeError(400, 'nonexistent_time')
    def reference(value):
        if not isinstance(value, dict) or set(value) != {'id', 'name'}: return False
        try:
            if not isinstance(value['id'], str) or str(uuid.UUID(value['id'])) != value['id'].lower(): return False
        except (ValueError, TypeError, AttributeError): return False
        return isinstance(value['name'], str) and bool(value['name'].strip()) and len(value['name']) <= 100
    if row.get('project') is not None and not reference(row['project']): raise BridgeError(400, 'invalid_project')
    tags = row.get('tags', [])
    if not isinstance(tags, list) or len(tags) > 50 or not all(reference(tag) for tag in tags): raise BridgeError(400, 'invalid_tags')
    if len({str(uuid.UUID(tag['id'])) for tag in tags}) != len(tags): raise BridgeError(400, 'duplicate_tags')
    reminder = row.get('reminderAt')
    if reminder is not None:
        try:
            if not isinstance(reminder, str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})', reminder): raise ValueError()
            parsed = dt.datetime.fromisoformat(reminder.replace('Z', '+00:00'))
            if parsed.utcoffset() is None: raise ValueError()
        except (ValueError, TypeError): raise BridgeError(400, 'invalid_reminder')


def validate_operation(value):
    if not isinstance(value, dict) or set(value) != {'operationId', 'taskId', 'expectedRevision', 'completed'}:
        raise BridgeError(400, 'invalid_operation')
    try: uuid.UUID(value['operationId'])
    except (ValueError, TypeError, AttributeError): raise BridgeError(400, 'invalid_operation')
    if not isinstance(value['taskId'], str) or not re.fullmatch('[a-z0-9]+(?:-[a-z0-9]+)*', value['taskId']):
        raise BridgeError(400, 'invalid_operation')
    if type(value['expectedRevision']) is not int or value['expectedRevision'] < 1 or type(value['completed']) is not bool:
        raise BridgeError(400, 'invalid_operation')


class Bridge:
    def __init__(self, database, bridge_id):
        if not re.fullmatch('[a-zA-Z0-9-]{1,80}', bridge_id): raise ValueError('Invalid bridge namespace')
        self.path, self.bridge_id = str(database), bridge_id
        Path(database).parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        try:
            descriptor = os.open(database, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            os.close(descriptor)
        except FileExistsError: pass
        with self.connect() as db:
            db.executescript('''CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY,value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, payload TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS operations (id TEXT PRIMARY KEY,payload TEXT NOT NULL,status TEXT NOT NULL,receipt TEXT);
            CREATE UNIQUE INDEX IF NOT EXISTS one_pending_per_task ON operations(json_extract(payload,'$.taskId')) WHERE status='received';''')
            previous = db.execute("SELECT value FROM metadata WHERE key='bridgeID'").fetchone()
            if previous and previous[0] != bridge_id: raise BridgeError(409, 'wrong_bridge')
            db.execute("INSERT OR IGNORE INTO metadata VALUES ('bridgeID',?)", (bridge_id,))
        os.chmod(database, 0o600)

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=5)
        db.execute('PRAGMA synchronous=FULL')
        try:
            with db: yield db
        finally: db.close()

    def feed(self):
        with self.connect() as db:
            rows = [json.loads(row[0]) for row in db.execute('SELECT payload FROM tasks ORDER BY id')]
            notice = db.execute("SELECT value FROM metadata WHERE key='sourceNotice'").fetchone()
        result = {'bridgeID': self.bridge_id, 'tasks': rows}
        if notice: result['sourceNotice'] = notice[0]
        return result

    def upsert(self, rows):
        """Explicit Mac bootstrap/update only. No deletes; preserve current completion.
        External changes increase revision, so received operations can conflict later.
        """
        if not isinstance(rows, list) or len(rows) > 500: raise BridgeError(400, 'invalid_tasks')
        if len(canonical(rows).encode()) > MAX_BYTES: raise BridgeError(413, 'feed_too_large')
        for row in rows: validate_task(row)
        if len({r['id'] for r in rows}) != len(rows): raise BridgeError(400, 'duplicate_ids')
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            for row in rows:
                old = db.execute('SELECT payload FROM tasks WHERE id=?', (row['id'],)).fetchone()
                if old:
                    previous = json.loads(old[0])
                    new = {**row, 'completed': previous['completed'], 'revision': previous['revision']}
                    if canonical(new) != canonical(previous): new['revision'] += 1
                else: new = row
                db.execute('INSERT INTO tasks VALUES (?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload', (row['id'], canonical(new)))

    def bootstrap(self, feed):
        # Authenticated, explicit initial registration only. Never replace an existing feed.
        if not isinstance(feed, dict) or set(feed) != {'bridgeID', 'tasks'} or feed['bridgeID'] != self.bridge_id:
            raise BridgeError(409, 'wrong_bridge')
        rows = feed['tasks']
        if not isinstance(rows, list) or not rows or len(rows) > 500 or len(canonical(rows).encode()) > MAX_BYTES:
            raise BridgeError(400, 'invalid_tasks')
        for row in rows:
            validate_task(row)
            if row['revision'] != 1: raise BridgeError(409, 'not_initial_feed')
        if len({r['id'] for r in rows}) != len(rows): raise BridgeError(400, 'duplicate_ids')
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            previous = [json.loads(r[0]) for r in db.execute('SELECT payload FROM tasks ORDER BY id')]
            if previous:
                if canonical(previous) != canonical(sorted(rows, key=lambda r:r['id'])): raise BridgeError(409, 'already_initialized')
            else:
                for row in rows: db.execute('INSERT INTO tasks VALUES (?,?)', (row['id'],canonical(row)))
        return self.feed()

    def receive(self, operation):
        validate_operation(operation)
        operation = {**operation, 'operationId': str(uuid.UUID(operation['operationId']))}
        payload = canonical(operation)
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            old = db.execute('SELECT payload,status,receipt FROM operations WHERE id=?', (operation['operationId'],)).fetchone()
            if old:
                if old[0] != payload: raise BridgeError(409, 'operation_id_reused')
                return self._receipt(operation['operationId'], old[1], old[2])
            row = db.execute('SELECT payload FROM tasks WHERE id=?', (operation['taskId'],)).fetchone()
            if not row: raise BridgeError(404, 'unknown_task')
            if json.loads(row[0])['revision'] != operation['expectedRevision']:
                raise BridgeError(409, 'revision_conflict')
            try: db.execute('INSERT INTO operations VALUES (?,?,?,NULL)', (operation['operationId'], payload, 'received'))
            except sqlite3.IntegrityError: raise BridgeError(409, 'task_has_pending_operation')
        return self._receipt(operation['operationId'], 'received', None)

    def _receipt(self, operation_id, status, receipt):
        return {'bridgeID': self.bridge_id, 'operationId': operation_id, 'status': status,
                'acknowledgment': json.loads(receipt) if receipt else None}

    def receipt(self, operation_id):
        with self.connect() as db:
            row = db.execute('SELECT status,receipt FROM operations WHERE id=?', (operation_id,)).fetchone()
        if not row: raise BridgeError(404, 'unknown_operation')
        return self._receipt(operation_id, *row)

    def pending(self):
        with self.connect() as db:
            return [json.loads(row[0]) for row in db.execute("SELECT payload FROM operations WHERE status='received' ORDER BY rowid")]

    def review_local(self, destination):
        """Read-only evidence for this Mac task to return to the main dot chat.
        Never claims that Site/master task source or ChatGPT conversation has changed.
        """
        document = json.loads(Path(destination).read_text())
        if document.get('bridgeID') != self.bridge_id: raise BridgeError(409, 'wrong_dot_file')
        entries = []
        with self.connect() as db:
            for operation_id, payload, status, receipt in db.execute('SELECT id,payload,status,receipt FROM operations ORDER BY rowid'):
                operation = json.loads(payload)
                ack = json.loads(receipt) if receipt else None
                target = next((r for r in document['tasks'] if r['id'] == operation['taskId']), None)
                entry = {'operation': operation, 'macStatus': status, 'localFileReceiptMatches': bool(ack and document['appliedOperations'].get(operation_id) == ack), 'currentLocalTask': target}
                entries.append(entry)
        return {'bridgeID': self.bridge_id, 'scope': 'local_mirror_only', 'masterSourceUpdated': False,
                'dotChatConfirmed': False, 'requiresDotReview': True, 'changes': entries}

    def export_dot_file(self, destination):
        """Explicit local tool action; refuses to replace an existing dot file."""
        destination = Path(destination)
        if destination.exists(): raise BridgeError(409, 'destination_exists')
        atomic_json(destination, {**self.feed(), 'appliedOperations': {}})

    def apply_to_dot_file(self, operation_id, destination):
        """Apply to a selected local file; never to the hosted Site or conversation."""
        destination = Path(destination)
        lock = os.open(str(destination) + '.lock', os.O_CREAT | os.O_RDWR, 0o600)
        try:
            with os.fdopen(lock, 'a') as lock_file:
                fcntl.flock(lock_file, fcntl.LOCK_EX)
                return self._apply_to_locked_dot_file(operation_id, destination)
        except (OSError, ValueError, KeyError): raise BridgeError(503, 'dot_file_unavailable')

    def _apply_to_locked_dot_file(self, operation_id, destination):
        """Caller owns destination.lock. Avoid reopening/flocking the same lock."""
        try:
            with self.connect() as db:
                db.execute('BEGIN IMMEDIATE')
                stored = db.execute('SELECT payload,status,receipt FROM operations WHERE id=?', (operation_id,)).fetchone()
                if not stored: raise BridgeError(404, 'unknown_operation')
                if stored[1] != 'received': return self._receipt(operation_id, stored[1], stored[2])
                operation = json.loads(stored[0]); digest = hashlib.sha256(stored[0].encode()).hexdigest()
                document = json.loads(destination.read_text())
                if document.get('bridgeID') != self.bridge_id or not isinstance(document.get('appliedOperations'), dict):
                    raise BridgeError(409, 'wrong_dot_file')
                rows = document.get('tasks', [])
                if len({r['id'] for r in rows}) != len(rows): raise BridgeError(409, 'invalid_dot_file')
                target = next((r for r in rows if r['id'] == operation['taskId']), None)
                current = db.execute('SELECT payload FROM tasks WHERE id=?', (operation['taskId'],)).fetchone()
                prior_receipt = document['appliedOperations'].get(operation_id)
                # Recover a crash after atomic file commit but before SQLite acknowledgment.
                current_task = json.loads(current[0]) if current else None
                recovered_base = {**target, 'revision': operation['expectedRevision'], 'completed': current_task['completed']} if target and current_task else None
                recovered = prior_receipt and prior_receipt.get('operationDigest') == digest and target and target.get('revision') == operation['expectedRevision'] + 1 and target.get('completed') == operation['completed'] and current_task and canonical(recovered_base) == canonical(current_task)
                if recovered:
                    acknowledgment = prior_receipt
                elif not target or target.get('revision') != operation['expectedRevision'] or not current_task or canonical(current_task) != canonical(target):
                    db.execute("UPDATE operations SET status='conflict' WHERE id=?", (operation_id,))
                    return self._receipt(operation_id, 'conflict', None)
                else:
                    target['completed'] = operation['completed']
                    target['revision'] += 1
                    acknowledgment = {'taskId': operation['taskId'], 'revision': target['revision'], 'completed': target['completed'], 'target': 'dot_local_file', 'operationDigest': digest}
                    document['appliedOperations'][operation_id] = acknowledgment
                    atomic_json(destination, document)
                # Confirm file readback before declaring applied, then update local mirror.
                persisted = json.loads(destination.read_text())
                if persisted['appliedOperations'].get(operation_id) != acknowledgment or next((r for r in persisted['tasks'] if r['id'] == operation['taskId']), None) != target: raise BridgeError(503, 'dot_readback_failed')
                validate_task(target)
                db.execute('UPDATE tasks SET payload=? WHERE id=?', (canonical(target), operation['taskId']))
                db.execute("UPDATE operations SET status='applied',receipt=? WHERE id=?", (canonical(acknowledgment), operation_id))
                return self._receipt(operation_id, 'applied', canonical(acknowledgment))

        except (OSError, ValueError, KeyError): raise BridgeError(503, 'dot_file_unavailable')


def make_loopback_server(bridge, test_bearer, host='127.0.0.1'):
    """Only loopback HTTP. LAN TLS listener/pairing is deliberately NOT enabled here."""
    if not ipaddress.ip_address(host).is_loopback: raise BridgeError(403, 'lan_listener_requires_approval')
    if not test_bearer: raise BridgeError(503, 'authentication_not_configured')
    return _make_server(bridge, test_bearer, host)


def make_lan_server(bridge, bearer, bind_address, tls_context, *, port=8778, lan_authorized=False):
    """Prepared only. Caller must obtain explicit pairing/LAN approval before invoking.
    Certificate/private key and bearer must already be provided through approved means.
    This module never generates/stores them or changes firewall/trust settings.
    """
    if not lan_authorized: raise BridgeError(403, 'lan_listener_requires_approval')
    address = ipaddress.ip_address(bind_address)
    if address.version != 4 or not address.is_private or address.is_loopback or address.is_unspecified or address.is_link_local:
        raise BridgeError(403, 'invalid_lan_address')
    if not isinstance(tls_context, ssl.SSLContext) or tls_context.protocol != ssl.PROTOCOL_TLS_SERVER or not isinstance(bearer, str) or len(bearer) < 32:
        raise BridgeError(503, 'pairing_not_configured')
    if type(port) is not int or not 1024 <= port <= 65535: raise BridgeError(400, 'invalid_port')
    tls_context.minimum_version = ssl.TLSVersion.TLSv1_2
    server = _make_server(bridge, bearer, bind_address, port=port)
    try: server.socket = tls_context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
    except Exception:
        server.server_close(); raise BridgeError(503, 'tls_not_configured')
    return server


def _make_server(bridge, test_bearer, host, *, port=0):
    audit_path = Path(bridge.path).parent/'traffic-metadata.json'
    audit_lock = threading.Lock()
    try:
        audit = json.loads(audit_path.read_text())
        if audit.get('version') != 1: raise ValueError()
    except (OSError, ValueError):
        audit = {'version':1,'authenticatedSelfRequests':0,'authenticatedLanRequests':0,'rejectedRequests':0,
                 'lastAuthenticatedLanAt':None,'lastRouteKind':None}

    def record(peer, authenticated, path):
        # Counts/time/fixed route category only. Never persist IP, headers, token, IDs or body.
        with audit_lock:
            if not authenticated: audit['rejectedRequests'] += 1
            elif peer in ('127.0.0.1','::1','192.168.0.35','192.168.0.211'): audit['authenticatedSelfRequests'] += 1
            else:
                audit['authenticatedLanRequests'] += 1
                audit['lastAuthenticatedLanAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
            audit['lastRouteKind'] = 'feed' if path == '/v1/tasks' else 'bootstrap' if path == '/v1/bootstrap' else 'submit' if path == '/v1/operations' else 'receipt' if path.startswith('/v1/operations/') else 'other'
            try: atomic_json(audit_path, audit)
            except OSError: pass # Lost audit never becomes a fabricated successful phone confirmation.

    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'
        def log_message(self, *args): pass
        def setup(self):
            super().setup(); self.connection.settimeout(5)
        def reply(self, status, value):
            data = canonical(value).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Connection', 'close')
            self.end_headers(); self.wfile.write(data)
            self.close_connection = True
        def audio_reply(self, data):
            self.send_response(200)
            self.send_header('Content-Type', 'audio/wav')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Connection', 'close')
            self.end_headers(); self.wfile.write(data); self.close_connection = True
        def dispatch(self):
            try:
                authenticated = hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + test_bearer)
                record(self.client_address[0], authenticated, self.path)
                if not authenticated: raise BridgeError(401, 'authentication_required')
                if self.headers.get('Origin') or self.headers.get('Sec-Fetch-Site') not in (None, 'none'): raise BridgeError(403, 'browser_request_rejected')
                if '?' in self.path or self.headers.get('Transfer-Encoding'): raise BridgeError(400, 'invalid_request')
                if self.command == 'GET' and re.fullmatch('/v1/daily-audio/[a-f0-9]{64}', self.path):
                    from daily_brief import audio_bytes
                    return self.audio_reply(audio_bytes(bridge, self.path.rsplit('/', 1)[-1]))
                if self.command == 'GET' and self.path == '/v1/tasks': return self.reply(200, bridge.feed())
                if self.command == 'GET' and re.fullmatch('/v1/operations/[a-fA-F0-9-]{36}', self.path):
                    return self.reply(200, bridge.receipt(self.path.rsplit('/', 1)[-1]))
                if self.command == 'POST' and self.path in ('/v1/operations', '/v1/bootstrap', '/v1/daily-brief'):
                    if self.headers.get('Content-Type', '').split(';')[0] != 'application/json': raise BridgeError(415, 'json_required')
                    try: length = int(self.headers.get('Content-Length', '0'))
                    except ValueError: raise BridgeError(400, 'invalid_length')
                    if length < 1 or length > (MAX_BYTES if self.path in ('/v1/bootstrap', '/v1/daily-brief') else 4096): raise BridgeError(413, 'body_too_large')
                    try: body = json.loads(self.rfile.read(length))
                    except (ValueError, TimeoutError): raise BridgeError(400, 'invalid_body')
                    if self.path == '/v1/bootstrap': return self.reply(200, bridge.bootstrap(body))
                    if self.path == '/v1/daily-brief':
                        from daily_brief import exchange
                        return self.reply(200, exchange(bridge, body))
                    result = bridge.receive(body)
                    return self.reply(202 if result['status'] == 'received' else 200, result)
                raise BridgeError(404, 'not_found')
            except BridgeError as error: self.reply(error.status, {'error': error.code})
            except Exception: self.reply(503, {'error': 'bridge_unavailable'})
        do_GET = dispatch
        do_POST = dispatch
        do_PUT = dispatch
        do_DELETE = dispatch
    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = False
    return server


def read_daily_brief(bridge, value):
    from daily_brief import key
    with bridge.connect() as db:
        row = db.execute('SELECT value FROM metadata WHERE key=?', (key('dailyBrief', value['date'], value['timeZone']),)).fetchone()
    return json.loads(row[0]) if row else None


def main():
    import argparse
    p = argparse.ArgumentParser(description='Explicit local dot bridge operations. Does not start a listener.')
    p.add_argument('--database', required=True); p.add_argument('--bridge-id', required=True)
    sub = p.add_subparsers(dest='action', required=True)
    audio = sub.add_parser('attach-brief-audio')
    audio.add_argument('--date', required=True); audio.add_argument('--time-zone', required=True)
    audio.add_argument('--brief-id', required=True); audio.add_argument('--audio-file', required=True)
    sub.add_parser('pending')
    sub.add_parser('traffic')
    context = sub.add_parser('daily-context'); context.add_argument('--date', required=True); context.add_argument('--time-zone', required=True)
    brief = sub.add_parser('publish-daily-brief'); brief.add_argument('--input', required=True)
    spoken = sub.add_parser('publish-spoken-brief'); spoken.add_argument('--input', required=True); spoken.add_argument('--handoff', required=True)
    review = sub.add_parser('review-local'); review.add_argument('--destination', required=True)
    export = sub.add_parser('export-dot-file'); export.add_argument('--destination', required=True)
    apply = sub.add_parser('apply'); apply.add_argument('--operation-id', required=True); apply.add_argument('--destination', required=True)
    args = p.parse_args(); bridge = Bridge(args.database, args.bridge_id)
    if args.action == 'attach-brief-audio':
        from daily_brief import attach_audio
        result = attach_audio(bridge, args.date, args.time_zone, args.brief_id, args.audio_file)
        print(canonical({'saved': result, 'readback': read_daily_brief(bridge, result)}))
    if args.action == 'daily-context':
        from daily_brief import read_context
        print(canonical(read_context(bridge, args.date, args.time_zone)))
    if args.action == 'publish-spoken-brief':
        from daily_brief import publish
        from generate_brief_audio import generate
        result = publish(bridge, json.loads(Path(args.input).read_text()))
        try: result = generate(bridge, result['date'], result['timeZone'], handoff=args.handoff)
        except Exception: raise SystemExit('Audio incomplete; text saved. Retry the same input after checking NarrationStudio.')
        print(canonical({'saved': result, 'readback': read_daily_brief(bridge, result)}))
    if args.action == 'publish-daily-brief':
        from daily_brief import publish
        result = publish(bridge, json.loads(Path(args.input).read_text()))
        print(canonical({'saved': result, 'readback': read_daily_brief(bridge, result)}))
    if args.action == 'pending': print(canonical({'pending': bridge.pending()}))
    if args.action == 'traffic':
        path=Path(args.database).parent/'traffic-metadata.json'
        print(path.read_text() if path.exists() else canonical({'observed':False,'reason':'no_traffic_metadata'}))
    if args.action == 'review-local': print(canonical(bridge.review_local(args.destination)))
    if args.action == 'export-dot-file': bridge.export_dot_file(args.destination); print(canonical({'exported': True}))
    if args.action == 'apply': print(canonical(bridge.apply_to_dot_file(args.operation_id, args.destination)))


if __name__ == '__main__': main()
