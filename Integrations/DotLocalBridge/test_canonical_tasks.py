import unittest
import concurrent.futures
import json
import threading
import subprocess
import sys
from pathlib import Path
import urllib.request
import urllib.error
from unittest.mock import patch
from canonical_tasks import CanonicalBridge
from mac_bridge import BridgeError, atomic_json, make_loopback_server
from test_mac_bridge import Fixture, TASK

class CanonicalTests(Fixture, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.source = CanonicalBridge(self.root/'bridge.sqlite', 'test-bridge', self.dot)

    def test_schedule_and_ai_survive_apply_restart(self):
        fields = {'details': '次の一歩', 'aiContext': '元の出典・履歴', 'date': '2026-10-24',
                  'startTime': '10:00', 'endTime': '10:30', 'timeZone': 'Asia/Tokyo',
                  'deadlineDate': '2026-11-07', 'deadlineTime': '17:00'}
        self.source.update(TASK['id'], 1, fields)
        op = {**self.operation(), 'expectedRevision': 2}
        receipt = self.source.receive(op)
        self.assertEqual(receipt['status'], 'applied')
        reopened = CanonicalBridge(self.root/'bridge.sqlite', 'test-bridge', self.dot)
        row = reopened.feed()['tasks'][0]
        for key, value in fields.items(): self.assertEqual(row[key], value)
        self.assertEqual(reopened.receive(op), receipt)
        self.assertEqual(row['revision'], 3)

    def test_invalid_schedule_keeps_canonical_bytes(self):
        before = self.dot.read_bytes()
        for fields in [{'aiContext': 1}, {'startTime': '10:00'},
                       {'date': '2026-10-24', 'startTime': '24:00', 'timeZone': 'Asia/Tokyo'},
                       {'date': '2026-10-24', 'startTime': '10:00:00', 'timeZone': 'Asia/Tokyo'},
                       {'date': '2026-10-24', 'startTime': '10:00', 'endTime': '09:00', 'timeZone': 'Asia/Tokyo'},
                       {'endTime': '10:30'}, {'timeZone': 'Imaginary/Zone'},
                       {'deadlineTime': '17:00'}, {'deadlineDate': '2026-02-30'},
                       {'date': '2026-03-08', 'startTime': '02:30', 'timeZone': 'America/Los_Angeles'}]:
            with self.subTest(fields=fields), self.assertRaises(BridgeError):
                self.source.update(TASK['id'], 1, fields)
            self.assertEqual(self.dot.read_bytes(), before)

    def test_metadata_roundtrip_completion_and_clear(self):
        project = {'id': '11111111-1111-4111-8111-111111111111', 'name': '仕事'}
        tags = [{'id': '22222222-2222-4222-8222-222222222222', 'name': '請求'}]
        changed = self.source.update(TASK['id'], 1, {'project': project, 'tags': tags, 'reminderAt': '2026-10-23T09:00:00+09:00'})
        restarted = CanonicalBridge(self.root/'bridge.sqlite', 'test-bridge', self.dot)
        self.assertEqual(restarted.feed()['tasks'], [changed])
        op = {**self.operation(), 'expectedRevision': 2}
        self.assertEqual(restarted.receive(op)['status'], 'applied')
        row = restarted.feed()['tasks'][0]
        self.assertEqual(row['project'], project)
        self.assertEqual(row['tags'], tags)
        self.assertEqual(row['reminderAt'], changed['reminderAt'])
        cleared = restarted.update(TASK['id'], 3, {'project': None, 'tags': [], 'reminderAt': None})
        self.assertIsNone(cleared['reminderAt'])
        self.assertEqual(cleared['tags'], [])

    def test_bad_metadata_never_writes_source(self):
        before = self.dot.read_bytes()
        ref = {'id': '22222222-2222-4222-8222-222222222222', 'name': '請求'}
        for changes in [{'project': {'id': 'bad', 'name': '仕事'}},
                        {'project': {'id': '11111111111141118111111111111111', 'name': '仕事'}}, {'tags': [ref, ref]},
                        {'tags': None}, {'reminderAt': '2026-10-23T09:00:00'},
                        {'reminderAt': '2026-02-30T09:00:00+09:00'}, {'reminderAt': 42}]:
            with self.subTest(changes=changes), self.assertRaises(BridgeError):
                self.source.update(TASK['id'], 1, changes)
            self.assertEqual(self.dot.read_bytes(), before)

    def test_shared_reference_conflict_is_rejected(self):
        ref = {'id': '11111111-1111-4111-8111-111111111111', 'name': '仕事'}
        self.source.update(TASK['id'], 1, {'project': ref})
        fields = {k: v for k, v in TASK.items() if k not in ('id', 'revision')}
        before = self.dot.read_bytes()
        with self.assertRaises(BridgeError):
            self.source.update('another-task', 0, {**fields, 'project': {**ref, 'name': '別名'}}, create=True)
        self.assertEqual(self.dot.read_bytes(), before)

    def test_dot_update_reaches_feed_and_restart(self):
        changed = self.source.update(TASK['id'], 1, {'title': 'Dotで編集', 'completed': True})
        self.assertEqual(changed['revision'], 2)
        reopened = CanonicalBridge(self.root/'bridge.sqlite', 'test-bridge', self.dot)
        self.assertEqual(reopened.feed()['tasks'], [changed])
        with self.assertRaises(BridgeError): reopened.update(TASK['id'], 1, {'title': 'stale'})

    def test_phone_apply_updates_same_canonical_source(self):
        op = self.operation(); self.source.receive(op)
        with self.assertRaises(BridgeError): self.source.update(TASK['id'], 1, {'title': 'conflicting'})
        self.assertEqual(self.source.apply_to_dot_file(op['operationId'], self.dot)['status'], 'applied')
        self.assertTrue(self.source.feed()['tasks'][0]['completed'])
        self.assertTrue(self.source.read_document()['tasks'][0]['completed'])

    def test_create_and_no_deletion_or_unversioned_edit(self):
        fields = {k: v for k, v in TASK.items() if k not in ('id', 'revision')}
        self.source.update('new-task', 0, fields, create=True)
        self.assertEqual(len(self.source.feed()['tasks']), 2)
        original = self.dot.read_bytes()
        doc = self.source.read_document(); doc['tasks'] = []
        atomic_json(self.dot, doc)
        with self.assertRaises(BridgeError): self.source.feed()
        self.dot.write_bytes(original)
        doc = self.source.read_document(); doc['tasks'][0]['title'] = 'unversioned'
        atomic_json(self.dot, doc)
        with self.assertRaises(BridgeError): self.source.feed()

    def test_file_first_crash_recovers_projection(self):
        def crash(path, value):
            atomic_json(path, value); raise OSError('synthetic crash')
        with patch('canonical_tasks.atomic_json', side_effect=crash):
            with self.assertRaises(OSError): self.source.update(TASK['id'], 1, {'title': 'durable'})
        self.assertEqual(self.source.feed()['tasks'][0]['title'], 'durable')
        self.assertEqual(self.bridge.feed()['tasks'][0]['revision'], 2)

    def test_interrupted_phone_apply_retains_receipt_recovery(self):
        op = self.operation(); self.bridge.receive(op)
        def crash(path, value):
            atomic_json(path, value); raise OSError('synthetic crash')
        with patch('mac_bridge.atomic_json', side_effect=crash):
            with self.assertRaises(BridgeError): self.source.receive(op)
        # Phone fetches before retrying POST. Feed must recover instead of permanently blocking retries.
        self.assertEqual(self.source.feed()['tasks'][0]['revision'], 2)
        self.assertEqual(self.source.receive(op)['status'], 'applied')
        self.assertEqual(self.source.feed()['tasks'][0]['revision'], 2)

    def test_corruption_does_not_fall_back_or_overwrite(self):
        self.dot.write_text('{broken')
        with self.assertRaises(BridgeError): self.source.feed()
        self.assertEqual(self.dot.read_text(), '{broken')
        self.assertEqual(self.bridge.feed()['tasks'], [TASK])

    def test_auto_apply_save_failure_retains_inbox_and_retries(self):
        op = self.operation()
        with patch('mac_bridge.atomic_json', side_effect=OSError('synthetic disk error')):
            with self.assertRaises(BridgeError): self.source.receive(op)
        self.assertEqual(self.bridge.pending(), [op])
        self.assertFalse(self.source.read_document()['tasks'][0]['completed'])
        # Reopen simulates receiver restart; GET resumes a durable operation without new IDs.
        reopened = CanonicalBridge(self.root/'bridge.sqlite', 'test-bridge', self.dot)
        self.assertTrue(reopened.feed()['tasks'][0]['completed'])
        self.assertEqual(reopened.receive(op)['status'], 'applied')
        self.assertEqual(reopened.feed()['tasks'][0]['revision'], 2)

    def test_process_exit_after_file_commit_recovers_without_revision_increment(self):
        op = self.operation()
        code = """
import json,os,sys
from canonical_tasks import CanonicalBridge
import mac_bridge
write=mac_bridge.atomic_json
def interrupted(path, value):
    write(path, value)
    os._exit(71)
mac_bridge.atomic_json=interrupted
bridge=CanonicalBridge(sys.argv[1], 'test-bridge', sys.argv[2])
bridge.receive(json.loads(sys.argv[3]))
"""
        result = subprocess.run([sys.executable, '-c', code, str(self.root/'bridge.sqlite'), str(self.dot), json.dumps(op)], cwd=Path(__file__).parent, timeout=5)
        self.assertEqual(result.returncode, 71)
        self.assertEqual(self.bridge.receipt(op['operationId'])['status'], 'received')
        reopened = CanonicalBridge(self.root/'bridge.sqlite', 'test-bridge', self.dot)
        self.assertEqual(reopened.feed()['tasks'][0]['revision'], 2)
        ack = reopened.receive(op)
        self.assertEqual(ack['status'], 'applied')
        self.assertEqual(reopened.receive(op), ack)
        self.assertEqual(reopened.feed()['tasks'][0]['revision'], 2)

    def test_stale_and_reused_operations_do_not_change_canonical(self):
        op = self.operation()
        ack = self.source.receive(op)
        self.assertEqual(ack['status'], 'applied')
        before = self.dot.read_bytes()
        for changed in [{**op, 'completed': False}, self.operation()]:
            with self.assertRaises(BridgeError): self.source.receive(changed)
        self.assertEqual(self.dot.read_bytes(), before)
        reopen = {**self.operation(), 'expectedRevision': 2, 'completed': False}
        self.assertEqual(self.source.receive(reopen)['status'], 'applied')
        self.assertFalse(self.source.read_document()['tasks'][0]['completed'])
        self.assertEqual(self.source.read_document()['tasks'][0]['revision'], 3)

    def test_external_edit_conflicts_without_overwriting_file(self):
        op = self.operation(); self.bridge.receive(op)
        document = self.source.read_document()
        document['tasks'][0]['title'] = 'synthetic concurrent edit'
        document['tasks'][0]['revision'] = 2
        atomic_json(self.dot, document)
        self.source.feed()
        self.assertEqual(self.source.receipt(op['operationId'])['status'], 'conflict')
        self.assertFalse(self.source.read_document()['tasks'][0]['completed'])
        self.assertEqual(self.source.read_document()['tasks'][0]['title'], 'synthetic concurrent edit')


class CanonicalHTTPTests(Fixture, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.source = CanonicalBridge(self.root/'bridge.sqlite', 'test-bridge', self.dot)
        self.server = make_loopback_server(self.source, 'synthetic-only')
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
    def tearDown(self):
        self.server.shutdown(); self.thread.join(timeout=3); self.server.server_close()
        super().tearDown()
    def post(self, operation, token='synthetic-only'):
        req = urllib.request.Request('http://127.0.0.1:' + str(self.server.server_port) + '/v1/operations', data=json.dumps(operation).encode(), headers={'Authorization': 'Bearer ' + token, 'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=5) as response: return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            with error: return error.code, json.load(error)
    def test_authenticated_post_auto_applies_and_concurrent_replays_ack_once(self):
        op = self.operation()
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(lambda _: self.post(op), range(12)))
        self.assertTrue(all(status == 200 and value['status'] == 'applied' for status,value in results))
        self.assertTrue(all(value == results[0][1] for _,value in results))
        self.assertEqual(results[0][1]['acknowledgment']['target'], 'dot_local_file')
        document = self.source.read_document()
        self.assertTrue(document['tasks'][0]['completed'])
        self.assertEqual(document['tasks'][0]['revision'], 2)
        self.assertEqual(len(document['appliedOperations']), 1)
        self.assertEqual(self.source.pending(), [])
    def test_unauthorized_or_failed_save_never_returns_applied(self):
        op = self.operation()
        self.assertEqual(self.post(op, 'wrong-token')[0], 401)
        self.assertEqual(self.source.pending(), [])
        with patch('mac_bridge.atomic_json', side_effect=OSError('synthetic disk error')):
            self.assertEqual(self.post(op)[0], 503)
        self.assertEqual(self.source.receipt(op['operationId'])['status'], 'received')
        self.assertFalse(self.source.read_document()['tasks'][0]['completed'])
        status, receipt = self.post(op)
        self.assertEqual(status, 200); self.assertEqual(receipt['status'], 'applied')



class RequestTraceTests(Fixture,unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.source=CanonicalBridge(self.root/'bridge.sqlite','test-bridge',self.dot)
    def changes(self):return {key:value for key,value in TASK.items() if key not in ('id','revision')}
    def testSameRequestReplayReusesRevisionAndRejectsOtherSlug(self):
        first=self.source.update('synthetic-request-one',0,self.changes(),create=True,request_ref='synthetic-message:item-one')
        again=self.source.update('synthetic-request-one',0,self.changes(),create=True,request_ref='synthetic-message:item-one')
        self.assertEqual(first,again);self.assertEqual(first['revision'],1)
        with self.assertRaises(BridgeError):self.source.update('synthetic-request-two',0,self.changes(),create=True,request_ref='synthetic-message:item-one')
    def testMultiItemRequestUsesDistinctItemReferences(self):
        self.source.update('synthetic-request-one',0,self.changes(),create=True,request_ref='synthetic-message:item-one')
        self.source.update('synthetic-request-two',0,self.changes(),create=True,request_ref='synthetic-message:item-two')
        self.assertEqual(len(self.source.feed()['tasks']),3)
    def testReadOnlyAuditDoesNotMutateSourceOrResumePending(self):
        from canonical_tasks import audit_document
        before=self.dot.read_bytes()
        report=audit_document(self.dot,self.root/'bridge.sqlite','2026-10-22')
        self.assertTrue(report['readOnly']);self.assertEqual(report['taskCount'],1)
        self.assertEqual(self.dot.read_bytes(),before)

    def testRequestMarkerPreservesExistingContextAndUpdateIsIdempotent(self):
        self.source.update(TASK['id'],1,{'aiContext':'\n元の根拠を保持\n'})
        first=self.source.update(TASK['id'],2,{},request_ref='synthetic-message:edit-one')
        self.assertTrue(first['aiContext'].startswith('\n元の根拠を保持\n'))
        again=self.source.update(TASK['id'],first['revision'],{},request_ref='synthetic-message:edit-one')
        self.assertEqual(first,again)

    def testAuditSeparatesFixedDeadlineFromTentativeDate(self):
        from canonical_tasks import audit_document
        self.source.update(TASK['id'],1,{'date':'2026-10-24','deadlineDate':'2026-11-07','deadlineTime':'17:00','timeZone':'Asia/Tokyo'})
        before=self.dot.read_bytes();report=audit_document(self.dot,self.root/'bridge.sqlite','2026-10-22')
        self.assertEqual(report['fixedDeadlines'][0]['date'],'2026-11-07')
        self.assertEqual(report['scheduledAfterDeadlineCandidates'],[])
        self.assertEqual(self.dot.read_bytes(),before)

if __name__ == '__main__': unittest.main()
