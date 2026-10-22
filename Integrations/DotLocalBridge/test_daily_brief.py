import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import threading
import urllib.request
import urllib.error
from mac_bridge import Bridge, BridgeError, canonical, read_daily_brief, make_loopback_server
from daily_brief import exchange, read_context, publish


class DailyBriefTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.bridge = Bridge(Path(self.temp.name) / 'brief.sqlite', 'synthetic-brief')
        self.value = {'date': '2026-10-22', 'timeZone': 'Asia/Tokyo', 'tasks': [
            {'id': 'synthetic-task', 'title': '合成タスク', 'details': '次の一歩', 'completed': False}],
            'events': [{'id': 'synthetic-event', 'title': '合成予定', 'start': '2026-10-22T09:00:00Z',
                        'end': '2026-10-22T10:00:00Z', 'allDay': False}]}
    def tearDown(self): self.temp.cleanup()
    def send(self): return exchange(self.bridge, {'inputJSON': canonical(self.value)})
    def brief(self):
        context = read_context(self.bridge, '2026-10-22', 'Asia/Tokyo')
        return {'date': '2026-10-22', 'timeZone': 'Asia/Tokyo', 'contextID': context['contextID'],
                'kind': 'outlook', 'text': '合成予定の前にタスクを進めましょう。'}
    def test_roundtrip_and_readback_preserves_task_data(self):
        before = self.bridge.feed()
        self.assertIsNone(self.send()['brief'])
        context = read_context(self.bridge, '2026-10-22', 'Asia/Tokyo')
        self.assertEqual(context['contextID'], hashlib.sha256(canonical(self.value).encode()).hexdigest())
        self.assertEqual(context['input'], self.value)
        saved = publish(self.bridge, self.brief())
        self.assertEqual(read_daily_brief(self.bridge, saved), saved)
        self.assertEqual(self.send()['brief'], saved)
        self.assertEqual(self.bridge.feed(), before)
        self.assertEqual(self.bridge.pending(), [])
    def test_concurrent_context_change_rejects_publish(self):
        self.send(); old = self.brief()
        self.value['tasks'][0]['completed'] = True; self.send()
        with self.assertRaises(BridgeError) as caught: publish(self.bridge, old)
        self.assertEqual(caught.exception.status, 409)
    def test_old_brief_remains_available_with_original_fingerprint(self):
        self.send(); saved = publish(self.bridge, self.brief())
        self.value['events'][0]['title'] = '変更した合成予定'
        self.assertEqual(self.send()['brief'], saved)
        self.assertNotEqual(read_context(self.bridge, '2026-10-22', 'Asia/Tokyo')['contextID'], saved['contextID'])
    def test_day_and_zone_are_separate(self):
        self.send(); publish(self.bridge, self.brief())
        self.value['date'] = '2026-10-23'
        self.assertIsNone(self.send()['brief'])
        self.value['date'] = '2026-10-22'; self.value['timeZone'] = 'UTC'
        self.assertIsNone(self.send()['brief'])
    def test_authenticated_http_exchange_and_rejects_network_publish(self):
        server = make_loopback_server(self.bridge, 'synthetic-brief-token')
        thread = threading.Thread(target=server.serve_forever); thread.start()
        try:
            base = 'http://127.0.0.1:' + str(server.server_port)
            body = canonical({'inputJSON': canonical(self.value)}).encode()
            request = urllib.request.Request(base + '/v1/daily-brief', data=body, headers={
                'Authorization': 'Bearer synthetic-brief-token', 'Content-Type': 'application/json'})
            with urllib.request.urlopen(request) as response:
                self.assertEqual(json.load(response), {'brief': None})
            saved = publish(self.bridge, self.brief())
            with urllib.request.urlopen(request) as response:
                self.assertEqual(json.load(response)['brief'], saved)
            unauthorized = urllib.request.Request(base + '/v1/daily-brief', data=body, headers={'Content-Type': 'application/json'})
            with self.assertRaises(urllib.error.HTTPError) as caught: urllib.request.urlopen(unauthorized)
            self.assertEqual(caught.exception.code, 401)
            caught.exception.close()
            remote_publish = urllib.request.Request(base + '/v1/publish-daily-brief', data=body, headers={
                'Authorization': 'Bearer synthetic-brief-token', 'Content-Type': 'application/json'})
            with self.assertRaises(urllib.error.HTTPError) as caught: urllib.request.urlopen(remote_publish)
            self.assertEqual(caught.exception.code, 404)
            caught.exception.close()
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_invalid_inputs_and_missing_context(self):
        with self.assertRaises(BridgeError): read_context(self.bridge, '2026-10-22', 'Asia/Tokyo')
        for mutate in [lambda v: v.update(date='2026-02-30'), lambda v: v.update(timeZone='Invalid/Zone'),
                       lambda v: v['tasks'][0].update(completed='yes'),
                       lambda v: v['tasks'].append(copy.deepcopy(v['tasks'][0]))]:
            original = copy.deepcopy(self.value); mutate(self.value)
            with self.assertRaises(BridgeError): self.send()
            self.value = original
        self.send()
        for changes in [{'text': ''}, {'text': 'x' * 2001}, {'kind': 'unknown'}, {'contextID': 'bad'}]:
            with self.assertRaises(BridgeError): publish(self.bridge, {**self.brief(), **changes})


if __name__ == '__main__': unittest.main()
