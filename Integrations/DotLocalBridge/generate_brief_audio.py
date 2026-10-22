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

def load_handoff(folder, source):
    """Reuse Studio's review/hash/schema checks; never maintain a second plan schema."""
    import importlib.util, re
    studio = Path.home()/'Development/NarrationStudio'
    spec = importlib.util.spec_from_file_location('taskapp_studio_handoff', studio/'scripts/narration_handoff.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    payload = module.payload_from(Path(folder))
    if payload['text'] != source: raise ValueError('speech_source_does_not_match_brief')
    if any(re.search(r'[0-9０-９]', unit['text']) for unit in payload['speech_plan']['units']):
        raise ValueError('unresolved_spoken_numbers')
    review=json.loads((Path(folder)/'expression-review.json').read_text())
    return payload, review['sources']

def generate(bridge, day, zone, timeout=1200, handoff=None):
    with bridge.connect() as db:
        row = db.execute('SELECT value FROM metadata WHERE key=?', (key('dailyBrief', day, zone),)).fetchone()
    if not row: raise BridgeError(404, 'brief_missing')
    brief = json.loads(row[0]); identity = brief_id(brief)
    authored=None; provenance=None
    if handoff is not None:
        authored,guides=load_handoff(handoff,brief['text'])
        plan_hash=__import__('hashlib').sha256(json.dumps(authored['speech_plan'],ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        provenance={'planSHA256':plan_hash,'speech_plan':authored['speech_plan'],'guideHashes':guides}
    with bridge.connect() as db:
        row=db.execute('SELECT value FROM metadata WHERE key=?',('dailySpeechPlan:'+identity,)).fetchone()
    same_plan=provenance is None or (row is not None and json.loads(row[0]).get('planSHA256')==provenance['planSHA256'])
    # An unchanged reviewed plan reuses the completed edition; a changed plan gets a new delivery ID.
    if brief.get('audio') and same_plan:
        try: audio_bytes(bridge,brief['audio']['sha256']); return brief
        except BridgeError: pass
    if authored is None: raise ValueError('reviewed_speech_handoff_required')
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
    request_id = authored['request_id']
    identity_for_merge=identity+':speech:'+provenance['planSHA256']
    result = call('POST', '/v1/projects', {'request_id':request_id, 'title':'今日の見通し', 'text':brief['text'],'speech_plan':authored['speech_plan']})
    path = result['status_url']; deadline=time.monotonic()+timeout; merge_attempt=0
    while time.monotonic()<deadline:
        state=call('GET', path)
        if state.get('app', {}).get('connected') is not True: raise ValueError('studio_disconnected')
        if state.get('status') in ('failed','cancelled','draft'): raise ValueError('studio_incomplete')
        if (state.get('output') or {}).get('is_current'):
            source=Path(state['output']['audio_path'])
            import hashlib
            if hashlib.sha256(source.read_bytes()).hexdigest()!=state['output']['sha256']: raise ValueError('studio_hash')
            return attach_audio(bridge, day, zone, identity, source, speech=provenance)
        if state.get('ready') or state.get('status')=='ready':
            operation=call('POST',path+'/merge',{'request_id':str(uuid.uuid5(uuid.NAMESPACE_URL,identity_for_merge+':merge:'+state['selection_key']+':rev:'+str(state['revision'])+':attempt:'+str(merge_attempt))),
                         'expected_revision':state['revision'],'selection_key':state['selection_key']})
            operation_path=operation['status_url']
            while time.monotonic()<deadline:
                checked=call('GET',operation_path); status=checked['status']
                if status=='succeeded': break
                if status=='failed' and checked.get('error',{}).get('code') in ('busy','revision_conflict','selection_conflict') and merge_attempt<5:
                    merge_attempt+=1
                    break # Confirmed terminal failure: new ID, refreshed state, never regenerate candidates.
                if status in ('failed','cancelled'): raise ValueError('studio_merge_failed')
                time.sleep(2)
        time.sleep(2)
    raise TimeoutError('studio_timeout')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--database',required=True); parser.add_argument('--bridge-id',required=True)
    parser.add_argument('--date',required=True); parser.add_argument('--time-zone',required=True)
    parser.add_argument('--handoff',type=Path)
    args=parser.parse_args()
    try:
        saved=generate(Bridge(args.database,args.bridge_id),args.date,args.time_zone,handoff=args.handoff)
        print(json.dumps({'saved':True,'briefID':saved['briefID'],'audioSHA256':saved['audio']['sha256']}))
    except Exception:
        # Credentials, raw source, response bodies and private paths never enter diagnostics.
        raise SystemExit('Local audio generation incomplete; inspect the existing studio UI and retry the same brief.')
