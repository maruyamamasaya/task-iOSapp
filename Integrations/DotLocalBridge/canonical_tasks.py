"""Dot's fixed local source. SQLite is a derived feed plus durable operation inbox."""
import argparse
import contextlib
import copy
import fcntl
import json
import os
import re
import sqlite3
import datetime as dt
import uuid
from pathlib import Path

from mac_bridge import Bridge, BridgeError, MAX_BYTES, atomic_json, canonical, validate_task

ROOT = Path.home() / 'Library/Application Support/CalendarTaskApp/DotLocalRelay'


class CanonicalBridge(Bridge):
    def __init__(self, database, bridge_id, source):
        self.source = Path(source)
        super().__init__(database, bridge_id)

    @contextlib.contextmanager
    def locked(self):
        with open(str(self.source) + '.lock', 'a') as lock:
            os.chmod(lock.name, 0o600)
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield

    def read_document(self):
        try:
            if self.source.stat().st_size > MAX_BYTES: raise ValueError()
            document = json.loads(self.source.read_text())
            rows = document['tasks']
            if document['bridgeID'] != self.bridge_id or not isinstance(document['appliedOperations'], dict): raise ValueError()
            if not isinstance(rows, list) or len(rows) > 500: raise ValueError()
            for row in rows: validate_task(row)
            self.validate_references(rows)
            if len({row['id'] for row in rows}) != len(rows): raise ValueError()
            if 'sourceNotice' in document and not isinstance(document['sourceNotice'], str): raise ValueError()
            return document
        except (OSError, ValueError, KeyError, TypeError):
            raise BridgeError(503, 'canonical_file_unavailable')

    @staticmethod
    def validate_references(rows):
        for field in ('project', 'tags'):
            names = {}
            for row in rows:
                values = ([row['project']] if row.get('project') else []) if field == 'project' else row.get('tags', [])
                for value in values:
                    identifier = str(uuid.UUID(value['id']))
                    if identifier in names and names[identifier] != value['name']:
                        raise BridgeError(409, 'reference_name_conflict')
                    names[identifier] = value['name']

    def project(self, document):
        """File-first commit recovery; never copy SQLite state back into the source."""
        rows = {row['id']: row for row in document['tasks']}
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            previous = {row[0]: json.loads(row[1]) for row in db.execute('SELECT id,payload FROM tasks')}
            if previous.keys() - rows.keys(): raise BridgeError(409, 'canonical_deletion_requires_migration')
            for slug, old in previous.items():
                new = rows[slug]
                if new['revision'] < old['revision'] or (new['revision'] == old['revision'] and new != old):
                    raise BridgeError(409, 'canonical_revision_conflict')
            # A phone apply interrupted after file commit must finish through its receipt path.
            for operation_id, in db.execute("SELECT id FROM operations WHERE status='received'"):
                if operation_id in document['appliedOperations']:
                    raise BridgeError(409, 'retry_interrupted_apply_first')
            for row in rows.values():
                db.execute('INSERT INTO tasks VALUES (?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload', (row['id'], canonical(row)))
            if 'sourceNotice' in document:
                db.execute("INSERT INTO metadata VALUES ('sourceNotice',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (document['sourceNotice'],))

    def feed(self):
        with self.locked():
            self._resume_received_locked()
            document = self.read_document()
            self.project(document)
            return {key: document[key] for key in ('bridgeID', 'tasks', 'sourceNotice') if key in document}

    def _resume_received_locked(self):
        # This also finishes a file commit interrupted before its DB acknowledgment.
        # Keep one file lock across receive/apply/project; pending IDs remain immutable.
        self.read_document()
        for operation in self.pending():
            self._apply_to_locked_dot_file(operation['operationId'], self.source)

    def receive(self, operation):
        with self.locked():
            self._resume_received_locked()
            self.project(self.read_document())
            receipt = super().receive(operation) # Commit durable inbox before touching the file.
            if receipt['status'] != 'received': return receipt
            return self._apply_to_locked_dot_file(receipt['operationId'], self.source)

    def bootstrap(self, feed):
        raise BridgeError(409, 'mac_canonical_source_already_selected')

    def update(self, task_id, expected_revision, changes, create=False, request_ref=None):
        allowed = {'title', 'date', 'dateLabel', 'status', 'details', 'category', 'subcategory', 'parentId', 'completed', 'project', 'tags', 'reminderAt', 'aiContext', 'startTime', 'endTime', 'timeZone', 'deadlineDate', 'deadlineTime', 'taskKind'}
        if not isinstance(changes, dict) or changes.keys() - allowed: raise BridgeError(400, 'invalid_changes')
        if create and expected_revision!=0: raise BridgeError(409,'task_exists')
        with self.locked():
            self._resume_received_locked()
            document = self.read_document()
            self.project(document)
            old = next((row for row in document['tasks'] if row['id'] == task_id), None)
            if request_ref is not None:
                if not isinstance(request_ref,str) or not re.fullmatch(r'[A-Za-z0-9:_-]{1,160}',request_ref):
                    raise BridgeError(400,'invalid_request_reference')
                marker='[request:'+request_ref+']'
                linked=[row for row in document['tasks'] if marker in (row.get('aiContext') or '')]
                changes=copy.deepcopy(changes)
                context=changes.get('aiContext',old.get('aiContext','') if old else '')
                if context is None:context=''
                if not isinstance(context,str):raise BridgeError(400,'invalid_ai_context')
                if marker not in context:context+=('' if not context or context.endswith('\n') else '\n')+marker
                changes['aiContext']=context
                if linked:
                    if len(linked)!=1 or linked[0]['id']!=task_id:
                        raise BridgeError(409,'request_already_recorded')
                    if create:
                        if all(linked[0].get(key)==value for key,value in changes.items()):return linked[0]
                        raise BridgeError(409,'request_already_recorded')
            if create:
                if old or expected_revision != 0: raise BridgeError(409, 'task_exists')
                new = {**changes, 'id': task_id, 'revision': 1}
            else:
                if not old or old['revision'] != expected_revision: raise BridgeError(409, 'canonical_revision_conflict')
                new = {**old, **changes, 'revision': old['revision'] + 1}
                if {**new, 'revision': old['revision']} == old: return old
            validate_task(new)
            # Serialize with network receivers; refuse to invalidate a received phone choice.
            with self.connect() as db:
                db.execute('BEGIN IMMEDIATE')
                if db.execute("SELECT 1 FROM operations WHERE status='received' AND json_extract(payload,'$.taskId')=?", (task_id,)).fetchone():
                    raise BridgeError(409, 'task_has_pending_operation')
                candidate = copy.deepcopy(document)
                candidate['tasks'] = [new if row['id'] == task_id else row for row in candidate['tasks']]
                if create: candidate['tasks'].append(new)
                self.validate_references(candidate['tasks'])
                if len(candidate['tasks']) > 500 or len(canonical(candidate).encode()) > MAX_BYTES: raise BridgeError(413, 'feed_too_large')
                atomic_json(self.source, candidate)
                if self.read_document() != candidate: raise BridgeError(503, 'canonical_readback_failed')
                db.execute('INSERT INTO tasks VALUES (?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload', (task_id, canonical(new)))
            return new



def audit_document(source, database, as_of):
    """Read-only consistency/load candidates, not an autonomous intake queue."""
    from collections import Counter,defaultdict
    import unicodedata,hashlib
    day=dt.date.fromisoformat(as_of)
    raw=Path(source).read_bytes();document=json.loads(raw);rows=document['tasks']
    active=[row for row in rows if not row['completed'] and row['status'] not in ('保留','考え中','検討中','統合済み','統合済') and not row['title'].startswith('【統合済')]
    dates=Counter(row['date'] for row in active if row.get('date') and day<=dt.date.fromisoformat(row['date'])<day+dt.timedelta(days=7))
    titles=defaultdict(list);references=defaultdict(list)
    for row in rows:
        titles[re.sub(r'\s+','',unicodedata.normalize('NFKC',row['title']))].append(row['id'])
        for reference in re.findall(r'\[request:([A-Za-z0-9:_-]{1,160})\]',row.get('aiContext') or ''):references[reference].append(row['id'])
    with sqlite3.connect('file:'+str(Path(database).resolve())+'?mode=ro',uri=True) as db:
        pending=db.execute("SELECT count(*) FROM operations WHERE status='received'").fetchone()[0]
        states={status:count for status,count in db.execute("SELECT status,count(*) FROM operations GROUP BY status")}
    if Path(source).read_bytes()!=raw:raise BridgeError(409,'source_changed_during_audit')
    return {'readOnly':True,'asOf':as_of,'taskCount':len(rows),'uniqueIDs':len({row['id'] for row in rows}),
            'missingProjectIDs':[row['id'] for row in rows if not row.get('project')],
            'missingTagIDs':[row['id'] for row in rows if not row.get('tags')],
            'invalidCategoryIDs':[row['id'] for row in rows if row['category'] not in ('work','private','other')],
            'activeDayCounts':dict(sorted(dates.items())),
            'fixedDeadlines':[{'id':row['id'],'date':row['deadlineDate'],'time':row.get('deadlineTime')} for row in rows if row.get('deadlineDate')],
            'overdueScheduledIDs':[row['id'] for row in active if row.get('date') and dt.date.fromisoformat(row['date'])<day],
            'scheduledAfterDeadlineCandidates':[row['id'] for row in active if row.get('date') and row.get('deadlineDate') and row['date']>row['deadlineDate']],
            'daysAboveThreeItems':{date:count for date,count in dates.items() if count>3},
            'sameTitleCandidates':[ids for ids in titles.values() if len(ids)>1],
            'duplicateRequestReferences':{ref:ids for ref,ids in references.items() if len(set(ids))>1},
            'tasksWithoutRequestReference':sum(not re.search(r'\[request:',row.get('aiContext') or '') for row in rows),
            'pendingOperations':pending,'operationStates':states,'canonicalSHA256':hashlib.sha256(raw).hexdigest(),
            'limits':'No intake queue, automatic scheduling or phone receipt assertion. Candidates are not automatic edits.'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['initialize', 'read', 'pending', 'update', 'create', 'apply', 'audit'])
    parser.add_argument('--as-of', help='YYYY-MM-DD, required for read-only audit')
    parser.add_argument('--request-ref', help='Stable request + item reference, recorded in aiContext')
    parser.add_argument('--task-id')
    parser.add_argument('--expected-revision', type=int)
    parser.add_argument('--changes-file', type=Path)
    parser.add_argument('--operation-id')
    args = parser.parse_args()
    config = json.loads((ROOT / 'relay-config.json').read_text())
    source = ROOT / 'state/tasks.json'
    if args.action=='audit':
        if not args.as_of: parser.error('--as-of required for audit')
        print(canonical(audit_document(source,ROOT/'state/bridge.sqlite',args.as_of))); return
    bridge = CanonicalBridge(ROOT / 'state/bridge.sqlite', config['bridgeID'], source)
    try:
        if args.action == 'initialize':
            # One-time snapshot under both locks; no task attributes or completion changes.
            with bridge.locked(), bridge.connect() as db:
                db.execute('BEGIN IMMEDIATE')
                if source.exists(): raise BridgeError(409, 'destination_exists')
                rows = [json.loads(row[0]) for row in db.execute('SELECT payload FROM tasks ORDER BY id')]
                if not rows: raise BridgeError(409, 'empty_initial_source')
                for row in rows: validate_task(row)
                bridge.validate_references(rows)
                notice = db.execute("SELECT value FROM metadata WHERE key='sourceNotice'").fetchone()
                document = {'bridgeID': bridge.bridge_id, 'tasks': rows, 'appliedOperations': {row[0]: json.loads(row[1]) for row in db.execute("SELECT id,receipt FROM operations WHERE status='applied'")}}
                if notice: document['sourceNotice'] = notice[0]
                atomic_json(source, document)
                assert bridge.read_document() == document
            result = {'initialized': True, 'taskCount': len(rows), 'source': str(source)}
        elif args.action == 'read': result = bridge.feed()
        elif args.action == 'pending': result = {'pending': bridge.pending()}
        elif args.action == 'apply':
            if not args.operation_id: parser.error('--operation-id required')
            result = bridge.apply_to_dot_file(args.operation_id, source)
        else:
            if not args.task_id or args.expected_revision is None or not args.changes_file:
                parser.error('--task-id, --expected-revision and --changes-file required')
            result = bridge.update(args.task_id, args.expected_revision, json.loads(args.changes_file.read_text()), create=args.action == 'create',request_ref=args.request_ref)
        print(canonical(result))
    except BridgeError as error:
        print(canonical({'error': error.code})); raise SystemExit(1)


if __name__ == '__main__': main()
