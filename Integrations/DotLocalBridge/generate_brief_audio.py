"""Explicit local NarrationStudio completion adapter. No scheduler or external TTS."""
import argparse
import json
import time
import uuid
import urllib.request
import urllib.error
from pathlib import Path
from mac_bridge import Bridge, BridgeError
from daily_brief import attach_audio, audio_bytes, brief_id, key

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args): return None

def generate(bridge, day, zone, timeout=1200):
    with bridge.connect() as db:
        row = db.execute('SELECT value FROM metadata WHERE key=?', (key('dailyBrief', day, zone),)).fetchone()
    if not row: raise BridgeError(404, 'brief_missing')
    brief = json.loads(row[0]); identity = brief_id(brief)
    # Already attached: retry does not generate or charge another job.
    if brief.get('audio'):
        try: audio_bytes(bridge,brief['audio']['sha256']); return brief
        except BridgeError: pass
    connection_path = Path.home()/'Library/Application Support/NarrationStudio/Control/connection.json'
    connection = json.loads(connection_path.read_text())
    if connection.get('base_url') != 'http://127.0.0.1:8765': raise ValueError('local_studio_required')
    opener = urllib.request.build_opener(NoRedirect())
    def call(method, path, body=None):
        if not path.startswith('/v1/') or '?' in path or '..' in path: raise ValueError('invalid_studio_path')
        req = urllib.request.Request(connection['base_url'] + path, method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={'Authorization': 'Bearer '+connection['token'], 'Content-Type':'application/json'})
        with opener.open(req, timeout=15) as response:
            data = response.read(1024 * 1024 + 1)
            if len(data)>1024*1024: raise ValueError('studio_response_size')
            return json.loads(data)
    # Stable request IDs let interrupted generation resume the original production.
    request_id = str(uuid.uuid5(uuid.NAMESPACE_URL, 'taskapp-brief:'+identity))
    result = call('POST', '/v1/projects', {'request_id':request_id, 'title':'今日の見通し', 'text':brief['text']})
    path = result['status_url']; deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        state=call('GET', path)
        if state.get('app', {}).get('connected') is not True: raise ValueError('studio_disconnected')
        if state.get('status') in ('failed','cancelled','draft'): raise ValueError('studio_incomplete')
        if (state.get('output') or {}).get('is_current'):
            source=Path(state['output']['audio_path'])
            import hashlib
            if hashlib.sha256(source.read_bytes()).hexdigest()!=state['output']['sha256']: raise ValueError('studio_hash')
            return attach_audio(bridge, day, zone, identity, source)
        if state.get('ready') or state.get('status')=='ready':
            operation=call('POST',path+'/merge',{'request_id':str(uuid.uuid5(uuid.NAMESPACE_URL,identity+':merge:'+state['selection_key'])),
                         'expected_revision':state['revision'],'selection_key':state['selection_key']})
            operation_path=operation['status_url']
            while time.monotonic()<deadline:
                status=call('GET',operation_path)['status']
                if status=='succeeded': break
                if status in ('failed','cancelled'): raise ValueError('studio_merge_failed')
                time.sleep(2)
        time.sleep(2)
    raise TimeoutError('studio_timeout')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--database',required=True); parser.add_argument('--bridge-id',required=True)
    parser.add_argument('--date',required=True); parser.add_argument('--time-zone',required=True)
    args=parser.parse_args()
    try:
        saved=generate(Bridge(args.database,args.bridge_id),args.date,args.time_zone)
        print(json.dumps({'saved':True,'briefID':saved['briefID'],'audioSHA256':saved['audio']['sha256']}))
    except Exception:
        # Credentials, raw source, response bodies and private paths never enter diagnostics.
        raise SystemExit('Local audio generation incomplete; inspect the existing studio UI and retry the same brief.')
