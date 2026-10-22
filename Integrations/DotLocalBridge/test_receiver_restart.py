"""Receiver process crash/restart verification with synthetic data and loopback only."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import urllib.request
import uuid
from mac_bridge import Bridge
from test_mac_bridge import TASK

CHILD = '''
import sys
from mac_bridge import Bridge,make_loopback_server
server=make_loopback_server(Bridge(sys.argv[1],'restart-fixture'),'synthetic-only')
print(server.server_port,flush=True)
server.serve_forever()
'''

class ReceiverRestartTests(unittest.TestCase):
    def test_lost_response_after_receive_survives_process_crash(self):
        with tempfile.TemporaryDirectory(prefix='dot-receiver-restart-') as directory:
            db = Path(directory)/'bridge.sqlite'
            Bridge(db, 'restart-fixture').upsert([TASK])
            operation = dict(operationId=str(uuid.uuid4()), taskId=TASK['id'], expectedRevision=1, completed=True)
            def start():
                process = subprocess.Popen([sys.executable, '-u', '-c', CHILD, str(db)], cwd=Path(__file__).parent, stdout=subprocess.PIPE, text=True)
                port = int(process.stdout.readline())
                return process, port
            def submit(port):
                request = urllib.request.Request(f'http://127.0.0.1:{port}/v1/operations', data=json.dumps(operation).encode(), headers={'Authorization':'Bearer synthetic-only', 'Content-Type':'application/json'})
                with urllib.request.urlopen(request, timeout=3) as response:
                    return json.load(response)
            process, port = start()
            try:
                first = submit(port)
                self.assertEqual(first['status'], 'received')
            finally:
                process.kill(); process.wait(timeout=5); process.stdout.close()
            # Same durable DB, new receiver process. Simulates a phone that lost the first response.
            process, port = start()
            try:
                self.assertEqual(submit(port), first)
                bridge = Bridge(db, 'restart-fixture')
                self.assertEqual(bridge.pending(), [operation])
                self.assertFalse(bridge.feed()['tasks'][0]['completed'])
            finally:
                process.terminate(); process.wait(timeout=5); process.stdout.close()
