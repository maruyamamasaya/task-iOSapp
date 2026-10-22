"""Recovery fixtures only: never reads ROOT or opens a live database."""
import fcntl
import os
import sqlite3
import unittest
from unittest.mock import patch
from canonical_tasks import CanonicalBridge
from mac_bridge import BridgeError, atomic_json
from test_mac_bridge import Fixture


class BackupRecoveryTests(Fixture, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.source = CanonicalBridge(self.root/'bridge.sqlite', 'test-bridge', self.dot)

    def backup_pair(self):
        directory = self.root/'archive'
        directory.mkdir(mode=0o700)
        source, database = directory/'tasks.json', directory/'bridge.sqlite'
        with open(str(self.dot)+'.lock', 'a') as lock:
            os.chmod(lock.name, 0o600)
            fcntl.flock(lock, fcntl.LOCK_SH)
            self.source.read_document()
            fd = os.open(source, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(fd, 'wb') as stream:
                stream.write(self.dot.read_bytes())
            fd = os.open(database, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            os.close(fd)
            with self.source.connect() as original, sqlite3.connect(database) as destination:
                original.backup(destination)
        return source, database

    def original_state(self):
        with self.source.connect() as db:
            return self.dot.read_bytes(), list(db.iterdump())

    def restore(self, pair):
        return CanonicalBridge(pair[1], 'test-bridge', pair[0])

    def test_applied_receipt_restart_and_replay(self):
        op = self.operation()
        receipt = self.source.receive(op)
        before = self.original_state()
        pair = self.backup_pair()
        restored = self.restore(pair)
        self.assertEqual(restored.feed(), self.source.feed())
        self.assertEqual(restored.receive(op), receipt)
        self.assertEqual(restored.feed()['tasks'][0]['revision'], 2)
        self.assertEqual(restored.read_document()['appliedOperations'], self.source.read_document()['appliedOperations'])
        self.assertEqual(self.original_state(), before)
        for path in pair:
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(pair[0].parent.stat().st_mode & 0o777, 0o700)

    def test_pending_operation_recovers_only_in_copy(self):
        op = self.operation()
        self.bridge.receive(op)
        before = self.original_state()
        restored = self.restore(self.backup_pair())
        self.assertTrue(restored.feed()['tasks'][0]['completed'])
        receipt = restored.receive(op)
        self.assertEqual(receipt['operationId'], op['operationId'])
        self.assertEqual(receipt['status'], 'applied')
        self.assertEqual(restored.pending(), [])
        self.assertEqual(restored.feed()['tasks'][0]['revision'], 2)
        self.assertEqual(self.original_state(), before)
        self.assertEqual(self.bridge.pending(), [op])

    def test_file_commit_before_ack_does_not_increment_twice(self):
        op = self.operation()
        def interrupted(path, document):
            atomic_json(path, document)
            raise OSError('fixture interruption after file commit')
        with patch('mac_bridge.atomic_json', side_effect=interrupted):
            with self.assertRaises(BridgeError):
                self.source.receive(op)
        before = self.original_state()
        self.assertEqual(self.bridge.receipt(op['operationId'])['status'], 'received')
        restored = self.restore(self.backup_pair())
        self.assertEqual(restored.feed()['tasks'][0]['revision'], 2)
        self.assertEqual(restored.receive(op)['status'], 'applied')
        self.assertEqual(restored.feed()['tasks'][0]['revision'], 2)
        self.assertEqual(self.original_state(), before)

    def test_mismatched_pair_refuses_without_overwrite(self):
        pair = self.backup_pair()
        self.source.receive(self.operation())
        with self.source.connect() as newer, sqlite3.connect(pair[1]) as copied:
            newer.backup(copied)
        before = self.original_state()
        old_bytes = pair[0].read_bytes()
        restored = self.restore(pair)
        with self.assertRaises(BridgeError):
            restored.feed()
        self.assertEqual(pair[0].read_bytes(), old_bytes)
        self.assertEqual(self.original_state(), before)

    def test_corrupt_copy_never_falls_back(self):
        pair = self.backup_pair()
        before = self.original_state()
        pair[0].write_text('{broken')
        restored = self.restore(pair)
        with self.assertRaises(BridgeError):
            restored.feed()
        self.assertEqual(pair[0].read_text(), '{broken')
        self.assertEqual(self.original_state(), before)


if __name__ == '__main__':
    unittest.main()
