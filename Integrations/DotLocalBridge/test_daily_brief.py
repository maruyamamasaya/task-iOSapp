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


class BriefAudioTests(unittest.TestCase):
    setUp = DailyBriefTests.setUp
    tearDown = DailyBriefTests.tearDown
    send = DailyBriefTests.send
    brief = DailyBriefTests.brief
    def audio(self):
        import wave
        file = Path(self.temp.name)/'synthetic.wav'
        with wave.open(str(file),'wb') as wav:
            wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(24000); wav.writeframes(b'\0\0'*240)
        return file
    def testAttachRetryIntegrityAndTaskIsolation(self):
        from daily_brief import attach_audio, audio_bytes
        self.send(); original = self.bridge.feed()
        saved=publish(self.bridge,self.brief())
        first=attach_audio(self.bridge,saved['date'],saved['timeZone'],saved['briefID'],self.audio())
        second=attach_audio(self.bridge,saved['date'],saved['timeZone'],saved['briefID'],self.audio())
        self.assertEqual(first,second)
        self.assertEqual(publish(self.bridge,self.brief()),first)
        self.assertEqual(audio_bytes(self.bridge,first['audio']['sha256']),self.audio().read_bytes())
        self.assertEqual(original,self.bridge.feed())
        (Path(self.temp.name)/'daily-audio'/(first['audio']['sha256']+'.wav')).write_bytes(b'bad')
        with self.assertRaises(BridgeError): audio_bytes(self.bridge,first['audio']['sha256'])
    def testRejectWrongBriefInvalidAudioAndPath(self):
        from daily_brief import attach_audio, audio_bytes
        self.send(); saved=publish(self.bridge,self.brief())
        with self.assertRaises(BridgeError): attach_audio(self.bridge,saved['date'],saved['timeZone'],'0'*64,self.audio())
        with self.assertRaises(BridgeError): audio_bytes(self.bridge,'../../private')
        bad=Path(self.temp.name)/'bad.wav'; bad.write_bytes(b'bad')
        with self.assertRaises(BridgeError): attach_audio(self.bridge,saved['date'],saved['timeZone'],saved['briefID'],bad)

    def testAudioEndpointRequiresAuth(self):
        from daily_brief import attach_audio
        self.send(); saved=publish(self.bridge,self.brief())
        ready=attach_audio(self.bridge,saved['date'],saved['timeZone'],saved['briefID'],self.audio())
        server=make_loopback_server(self.bridge,'synthetic-audio-token')
        thread=threading.Thread(target=server.serve_forever); thread.start()
        try:
            url='http://127.0.0.1:'+str(server.server_address[1])+'/v1/daily-audio/'+ready['audio']['sha256']
            with self.assertRaises(urllib.error.HTTPError) as caught: urllib.request.urlopen(url)
            self.assertEqual(caught.exception.code,401); caught.exception.close()
            request=urllib.request.Request(url,headers={'Authorization':'Bearer synthetic-audio-token'})
            with urllib.request.urlopen(request) as response:
                self.assertEqual(response.headers.get_content_type(),'audio/wav')
                self.assertEqual(response.read(),self.audio().read_bytes())
        finally: server.shutdown(); server.server_close(); thread.join()
    def testStudioAdapterNullOutputMergeAndRetry(self):
        from unittest.mock import patch
        import generate_brief_audio
        self.send(); saved=publish(self.bridge,self.brief()); audio=self.audio()
        home=Path(self.temp.name)/'home'; connection=home/'Library/Application Support/NarrationStudio/Control/connection.json'
        connection.parent.mkdir(parents=True); connection.write_text(json.dumps({'base_url':'http://127.0.0.1:8765','token':'synthetic-only'}))
        calls=[]; attempts=[]; merged=[False]
        class Response:
            def __init__(self,value): self.data=json.dumps(value).encode()
            def __enter__(self): return self
            def __exit__(self,*args): pass
            def read(self,n): return self.data
        class Opener:
            def open(inner,request,timeout):
                calls.append(request)
                if request.method=='POST' and request.full_url.endswith('/v1/projects'): return Response({'status_url':'/v1/projects/synthetic'})
                if request.method=='POST':
                    attempts.append(json.loads(request.data)['request_id']); return Response({'status_url':'/v1/operations/synthetic'})
                if '/operations/' in request.full_url:
                    if len(attempts)==1: return Response({'status':'failed','error':{'code':'busy'}})
                    merged[0]=True; return Response({'status':'succeeded'})
                if not merged[0]: return Response({'app':{'connected':True},'status':'ready','revision':1,'selection_key':'synthetic','output':None})
                return Response({'app':{'connected':True},'status':'merged','output':{'is_current':True,'audio_path':str(audio),'sha256':hashlib.sha256(audio.read_bytes()).hexdigest()}})
        with patch('generate_brief_audio.Path.home',return_value=home), patch('generate_brief_audio.urllib.request.build_opener',return_value=Opener()), patch('generate_brief_audio.time.sleep'):
            first=generate_brief_audio.generate(self.bridge,saved['date'],saved['timeZone'])
            count=len(calls)
            second=generate_brief_audio.generate(self.bridge,saved['date'],saved['timeZone'])
        self.assertEqual(first,second); self.assertEqual(len(calls),count)
        self.assertEqual(len(attempts),2); self.assertNotEqual(attempts[0],attempts[1])

    def testStudioFloatWavAndNonfiniteRejected(self):
        import struct
        from daily_brief import wav_duration
        fmt=struct.pack('<HHIIHH',3,1,24000,96000,4,32)
        def wave(payload):
            body=b'WAVEfmt '+struct.pack('<I',len(fmt))+fmt+b'data'+struct.pack('<I',len(payload))+payload
            return b'RIFF'+struct.pack('<I',len(body))+body
        self.assertAlmostEqual(wav_duration(wave(struct.pack('<ff',.1,.2))),2/24000)
        with self.assertRaises(BridgeError): wav_duration(wave(struct.pack('<f',float('nan'))))
