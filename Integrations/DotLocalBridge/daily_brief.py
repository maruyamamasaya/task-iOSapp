"""Daily prose exchange only. Never modifies tasks or completion operations."""
import datetime as dt
import hashlib
import json
import re
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from mac_bridge import BridgeError, canonical


def validate_day_zone(day, zone):
    try:
        if not isinstance(day, str) or dt.date.fromisoformat(day).isoformat() != day: raise ValueError()
        if not isinstance(zone, str): raise ValueError()
        ZoneInfo(zone)
    except (ValueError, TypeError, ZoneInfoNotFoundError):
        raise BridgeError(400, 'invalid_brief_day_zone')


def key(kind, day, zone):
    validate_day_zone(day, zone)
    return kind + ':' + day + ':' + zone


def exchange(bridge, body):
    if not isinstance(body, dict) or set(body) != {'inputJSON'} or not isinstance(body['inputJSON'], str):
        raise BridgeError(400, 'invalid_brief_context')
    raw = body['inputJSON']
    if len(raw.encode()) > 256 * 1024: raise BridgeError(413, 'brief_context_too_large')
    try: value = json.loads(raw)
    except ValueError: raise BridgeError(400, 'invalid_brief_context')
    if not isinstance(value, dict) or set(value) != {'date', 'timeZone', 'tasks', 'events'}:
        raise BridgeError(400, 'invalid_brief_context')
    context_key = key('dailyContext', value['date'], value['timeZone'])
    for field in ('tasks', 'events'):
        rows = value[field]
        if not isinstance(rows, list) or len(rows) > 1000: raise BridgeError(400, 'invalid_brief_context')
        ids = []
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get('id'), str) or not isinstance(row.get('title'), str):
                raise BridgeError(400, 'invalid_brief_context')
            if field == 'tasks' and (type(row.get('completed')) is not bool or not isinstance(row.get('details'), str)):
                raise BridgeError(400, 'invalid_brief_context')
            if field == 'events' and (type(row.get('allDay')) is not bool or not all(isinstance(row.get(k), str) for k in ('start', 'end'))):
                raise BridgeError(400, 'invalid_brief_context')
            ids.append(row['id'])
        if len(set(ids)) != len(ids): raise BridgeError(400, 'duplicate_brief_ids')
    context = {'contextID': hashlib.sha256(raw.encode()).hexdigest(), 'input': value,
               'receivedAt': dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')}
    brief_key = key('dailyBrief', value['date'], value['timeZone'])
    with bridge.connect() as db:
        db.execute('INSERT INTO metadata VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
                   (context_key, canonical(context)))
        row = db.execute('SELECT value FROM metadata WHERE key=?', (brief_key,)).fetchone()
    return {'brief': json.loads(row[0]) if row else None}


def read_context(bridge, day, zone):
    with bridge.connect() as db:
        row = db.execute('SELECT value FROM metadata WHERE key=?', (key('dailyContext', day, zone),)).fetchone()
    if not row: raise BridgeError(404, 'daily_context_not_received')
    return json.loads(row[0])


def publish(bridge, value):
    required = {'date', 'timeZone', 'contextID', 'kind', 'text'}
    if not isinstance(value, dict) or set(value) != required: raise BridgeError(400, 'invalid_brief')
    if value['kind'] not in ('outlook', 'reflection') or not isinstance(value['text'], str) or not 1 <= len(value['text'].strip()) <= 2000:
        raise BridgeError(400, 'invalid_brief')
    if not isinstance(value['contextID'], str) or not re.fullmatch('[a-f0-9]{64}', value['contextID']):
        raise BridgeError(400, 'invalid_brief')
    context_key = key('dailyContext', value['date'], value['timeZone'])
    brief_key = key('dailyBrief', value['date'], value['timeZone'])
    result = {**value, 'text': value['text'].strip(),
              'generatedAt': dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')}
    result['briefID'] = brief_id(result)
    with bridge.connect() as db:
        db.execute('BEGIN IMMEDIATE')
        row = db.execute('SELECT value FROM metadata WHERE key=?', (context_key,)).fetchone()
        if not row or json.loads(row[0])['contextID'] != value['contextID']:
            raise BridgeError(409, 'daily_context_changed')
        existing = db.execute('SELECT value FROM metadata WHERE key=?', (brief_key,)).fetchone()
        if existing and brief_id(json.loads(existing[0])) == result['briefID']:
            return json.loads(existing[0])
        db.execute('INSERT INTO metadata VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
                   (brief_key, canonical(result)))
    return result


MAX_AUDIO_BYTES = 12 * 1024 * 1024

def brief_id(value):
    return hashlib.sha256(canonical({k: value[k] for k in ('date', 'timeZone', 'contextID', 'kind', 'text')}).encode()).hexdigest()

def attach_audio(bridge, day, zone, expected_id, source):
    """Explicit local completion event; never accepts arbitrary paths from the network."""
    import os
    from pathlib import Path
    if Path(source).stat().st_size > MAX_AUDIO_BYTES: raise BridgeError(413, 'audio_size')
    data = Path(source).read_bytes()
    if not 44 <= len(data) <= MAX_AUDIO_BYTES: raise BridgeError(413, 'audio_size')
    duration = wav_duration(data)
    digest = hashlib.sha256(data).hexdigest()
    folder = Path(bridge.path).parent / 'daily-audio'
    folder.mkdir(mode=0o700, exist_ok=True)
    target = folder / (digest + '.wav')
    if not target.exists():
        import tempfile
        fd, temp = tempfile.mkstemp(dir=folder)
        try:
            with os.fdopen(fd, 'wb') as stream: stream.write(data); stream.flush(); os.fsync(stream.fileno())
            os.replace(temp, target)
        finally:
            if os.path.exists(temp): os.unlink(temp)
    with bridge.connect() as db:
        db.execute('BEGIN IMMEDIATE')
        row = db.execute('SELECT value FROM metadata WHERE key=?', (key('dailyBrief', day, zone),)).fetchone()
        if not row: raise BridgeError(404, 'brief_missing')
        result = json.loads(row[0])
        if brief_id(result) != expected_id: raise BridgeError(409, 'brief_changed')
        result['briefID'] = expected_id
        result['audio'] = {'sha256': digest, 'byteCount': len(data), 'contentType': 'audio/wav', 'duration': duration}
        db.execute('UPDATE metadata SET value=? WHERE key=?', (canonical(result), key('dailyBrief', day, zone)))
    return result

def audio_bytes(bridge, digest):
    from pathlib import Path
    if not re.fullmatch('[a-f0-9]{64}', digest): raise BridgeError(400, 'invalid_audio_id')
    # Only referenced audio may be fetched; no path input or directory listing.
    with bridge.connect() as db:
        values = db.execute("SELECT value FROM metadata WHERE key LIKE 'dailyBrief:%'").fetchall()
    if not any(json.loads(row[0]).get('audio', {}).get('sha256') == digest for row in values):
        raise BridgeError(404, 'audio_missing')
    path = Path(bridge.path).parent / 'daily-audio' / (digest + '.wav')
    try: data = path.read_bytes()
    except OSError: raise BridgeError(404, 'audio_missing')
    if len(data) > MAX_AUDIO_BYTES or hashlib.sha256(data).hexdigest() != digest:
        raise BridgeError(503, 'audio_corrupt')
    return data


def wav_duration(data):
    """Accept Studio IEEE float WAV and PCM without adding a scipy dependency."""
    import struct, math
    try:
        if data[:4] != b'RIFF' or data[8:12] != b'WAVE' or struct.unpack_from('<I',data,4)[0]+8 != len(data): raise ValueError()
        pos=12; fmt=None; payload=None
        while pos+8<=len(data):
            kind=data[pos:pos+4]; size=struct.unpack_from('<I',data,pos+4)[0]; pos+=8
            if pos+size>len(data): raise ValueError()
            if kind==b'fmt ': fmt=data[pos:pos+size]
            if kind==b'data': payload=data[pos:pos+size]
            pos+=size+(size%2)
        if fmt is None or len(fmt)<16 or not payload: raise ValueError()
        encoding,channels,rate,byte_rate,align,bits=struct.unpack_from('<HHIIHH',fmt)
        if encoding not in (1,3) or channels not in (1,2) or not 8000<=rate<=192000: raise ValueError()
        if bits not in (16,24,32) or align!=channels*bits//8 or byte_rate!=rate*align or len(payload)%align: raise ValueError()
        if encoding==3:
            if bits!=32 or any(not math.isfinite(v[0]) for v in struct.iter_unpack('<f',payload)): raise ValueError()
        return len(payload)/align/rate
    except (ValueError,struct.error): raise BridgeError(400,'invalid_wav')
