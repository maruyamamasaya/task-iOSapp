import copy
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
import urllib.request
import urllib.error
import uuid

from mac_bridge import Bridge, BridgeError, atomic_json, make_loopback_server, make_lan_server

TASK = {'id': 'sample-task', 'title': '合成タスク', 'date': None, 'dateLabel': '未定', 'status': '確認待ち', 'details': '合成データのみ', 'category': 'テスト', 'completed': False, 'revision': 1}

class Fixture:
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bridge = Bridge(self.root/'bridge.sqlite', 'test-bridge')
        self.bridge.upsert([TASK])
        self.dot = self.root/'dot-local.json'
        self.bridge.export_dot_file(self.dot)
    def tearDown(self): self.temp.cleanup()
    def operation(self): return {'operationId': str(uuid.uuid4()), 'taskId': TASK['id'], 'expectedRevision': 1, 'completed': True}

class BridgeTests(Fixture, unittest.TestCase):
    def test_receive_is_not_apply_and_replay_is_idempotent(self):
        op = self.operation()
        self.assertEqual(self.bridge.receive(op)['status'], 'received')
        self.assertEqual(self.bridge.receive(op)['status'], 'received')
        self.assertFalse(self.bridge.feed()['tasks'][0]['completed'])
        self.assertFalse(json.loads(self.dot.read_text())['tasks'][0]['completed'])
        result = self.bridge.apply_to_dot_file(op['operationId'], self.dot)
        self.assertEqual(result['status'], 'applied')
        self.assertEqual(result['acknowledgment']['target'], 'dot_local_file')
        self.assertTrue(json.loads(self.dot.read_text())['tasks'][0]['completed'])
        self.assertEqual(self.bridge.receive(op), result)
        self.assertEqual(self.bridge.apply_to_dot_file(op['operationId'], self.dot), result)
        self.assertEqual(self.bridge.feed()['tasks'][0]['revision'], 2)
    def test_unknown_stale_and_reused_id_are_rejected(self):
        op = self.operation(); self.bridge.receive(op)
        for value in [{**op, 'completed': False}, {**self.operation(), 'expectedRevision': 9}, {**self.operation(), 'taskId': 'unknown'}]:
            with self.assertRaises(BridgeError): self.bridge.receive(value)
        with self.assertRaises(BridgeError): self.bridge.receive(self.operation())
        self.assertEqual(len(self.bridge.pending()), 1)
    def test_upsert_preserves_existing_and_conflict_stops_apply(self):
        op = self.operation(); self.bridge.receive(op)
        self.bridge.upsert([{**TASK, 'title': 'Mac側の変更'}])
        self.bridge.upsert([])
        self.assertEqual(len(self.bridge.feed()['tasks']), 1)
        self.assertEqual(self.bridge.apply_to_dot_file(op['operationId'], self.dot)['status'], 'conflict')
        self.assertFalse(json.loads(self.dot.read_text())['tasks'][0]['completed'])
    def test_dot_file_changed_without_revision_is_not_overwritten(self):
        op = self.operation(); self.bridge.receive(op)
        value = json.loads(self.dot.read_text()); value['tasks'][0]['title'] = '外部編集'
        atomic_json(self.dot, value)
        self.assertEqual(self.bridge.apply_to_dot_file(op['operationId'], self.dot)['status'], 'conflict')
        self.assertEqual(json.loads(self.dot.read_text())['tasks'][0]['title'], '外部編集')
    def test_crash_after_file_commit_recovers_once(self):
        op = self.operation(); self.bridge.receive(op)
        def crash(path, value): atomic_json(path, value); raise OSError('synthetic crash after fsync')
        with patch('mac_bridge.atomic_json', side_effect=crash):
            with self.assertRaises(BridgeError): self.bridge.apply_to_dot_file(op['operationId'], self.dot)
        self.assertEqual(self.bridge.receipt(op['operationId'])['status'], 'received')
        recovered = Bridge(self.root/'bridge.sqlite', 'test-bridge')
        self.assertEqual(recovered.apply_to_dot_file(op['operationId'], self.dot)['status'], 'applied')
        self.assertEqual(recovered.feed()['tasks'][0]['revision'], 2)
    def test_restart_preserves_pending_namespace_and_no_replace_export(self):
        op = self.operation(); self.bridge.receive(op)
        other = Bridge(self.root/'bridge.sqlite', 'test-bridge')
        self.assertEqual(other.pending(), [op])
        with self.assertRaises(BridgeError): Bridge(self.root/'bridge.sqlite', 'other-bridge')
        with self.assertRaises(BridgeError): self.bridge.export_dot_file(self.dot)
    def test_explicit_reopen_and_second_change_after_ack(self):
        op = self.operation(); self.bridge.receive(op); self.bridge.apply_to_dot_file(op['operationId'], self.dot)
        reopen = {**self.operation(), 'expectedRevision': 2, 'completed': False}
        self.bridge.receive(reopen); self.bridge.apply_to_dot_file(reopen['operationId'], self.dot)
        value = self.bridge.feed()['tasks'][0]
        self.assertFalse(value['completed']); self.assertEqual(value['revision'], 3)
        self.assertEqual(value['status'], '確認待ち') # Rich workflow status never replaced by 未着手.
    def test_concurrent_retries_only_one_operation(self):
        op = self.operation(); results = []
        threads = [threading.Thread(target=lambda: results.append(self.bridge.receive(op))) for _ in range(12)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        self.assertEqual(len(results), 12); self.assertEqual(len(self.bridge.pending()), 1)
    def test_uuid_case_normalization_matches_swift(self):
        op = self.operation(); op['operationId'] = op['operationId'].upper()
        result = self.bridge.receive(op)
        self.assertEqual(self.bridge.receipt(op['operationId'].lower()), result)
    def test_local_review_never_claims_master_or_dot_chat_updated(self):
        op = self.operation(); self.bridge.receive(op)
        self.bridge.apply_to_dot_file(op['operationId'], self.dot)
        before = self.dot.read_bytes()
        report = self.bridge.review_local(self.dot)
        self.assertTrue(report['changes'][0]['localFileReceiptMatches'])
        self.assertFalse(report['masterSourceUpdated']); self.assertFalse(report['dotChatConfirmed'])
        self.assertTrue(report['requiresDotReview']); self.assertEqual(self.dot.read_bytes(), before)
    def test_bootstrap_is_initial_only_and_never_replaces_existing_tasks(self):
        empty = Bridge(self.root/'new.sqlite','new-fixture')
        feed = {'bridgeID':'new-fixture','tasks':[TASK]}
        self.assertEqual(empty.bootstrap(feed),feed)
        self.assertEqual(empty.bootstrap(feed),feed)
        with self.assertRaises(BridgeError):empty.bootstrap({'bridgeID':'new-fixture','tasks':[{**TASK,'title':'changed'}]})
        self.assertEqual(empty.feed(),feed)

class LoopbackTests(Fixture, unittest.TestCase):
    def test_authenticated_loopback_receive_poll_apply(self):
        server = make_loopback_server(self.bridge, 'synthetic-test-only')
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        self.addCleanup(server.server_close); self.addCleanup(thread.join, 2); self.addCleanup(server.shutdown)
        base = 'http://127.0.0.1:' + str(server.server_port)
        def call(path, method='GET', value=None, token='synthetic-test-only', extra=None):
            headers = {'Authorization': 'Bearer '+token, 'Content-Type': 'application/json', **(extra or {})}
            req = urllib.request.Request(base+path, data=json.dumps(value).encode() if value else None, method=method, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=3) as response: return response.status, json.load(response)
            except urllib.error.HTTPError as error:
                try: return error.code, json.load(error)
                finally: error.close()
        self.assertEqual(call('/v1/tasks', token='wrong')[0], 401)
        self.assertEqual(call('/v1/tasks', extra={'Origin':'https://evil.invalid'})[0], 403)
        self.assertEqual(call('/v1/tasks')[1]['tasks'][0]['id'], TASK['id'])
        op = self.operation()
        status, receipt = call('/v1/operations', 'POST', op)
        self.assertEqual(status, 202); self.assertEqual(receipt['status'], 'received')
        self.assertEqual(call('/v1/operations/'+op['operationId'])[1]['status'], 'received')
        self.bridge.apply_to_dot_file(op['operationId'], self.dot)
        self.assertEqual(call('/v1/operations/'+op['operationId'])[1]['status'], 'applied')
        self.assertEqual(call('/v1/operations', 'POST', op)[0], 200)
        audit=json.loads((self.root/'traffic-metadata.json').read_text())
        self.assertEqual(audit['authenticatedLanRequests'],0)
        self.assertGreater(audit['authenticatedSelfRequests'],0)
        self.assertEqual(audit['rejectedRequests'],1)
        self.assertNotIn('synthetic-test-only',json.dumps(audit))
        self.assertNotIn(op['operationId'],json.dumps(audit))
    def test_lan_and_missing_auth_are_not_enabled(self):
        with self.assertRaises(BridgeError): make_loopback_server(self.bridge, 'synthetic-test-only', '0.0.0.0')
        with self.assertRaises(BridgeError): make_loopback_server(self.bridge, '')
        with self.assertRaises(BridgeError): make_lan_server(self.bridge, '', '192.168.1.2', None)
        with self.assertRaises(BridgeError): make_lan_server(self.bridge, '', '0.0.0.0', None, lan_authorized=True)
        with self.assertRaises(BridgeError): make_lan_server(self.bridge, '', '192.168.1.2', None, lan_authorized=True)

if __name__ == '__main__': unittest.main()
