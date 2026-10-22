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
    with bridge.connect() as db:
        db.execute('BEGIN IMMEDIATE')
        row = db.execute('SELECT value FROM metadata WHERE key=?', (context_key,)).fetchone()
        if not row or json.loads(row[0])['contextID'] != value['contextID']:
            raise BridgeError(409, 'daily_context_changed')
        db.execute('INSERT INTO metadata VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
                   (brief_key, canonical(result)))
    return result
