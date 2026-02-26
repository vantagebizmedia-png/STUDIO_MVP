import json, sys, datetime
from pathlib import Path

def main():
    if len(sys.argv) < 4:
        print('usage: manifest_audit_inject.py <manifest_path> <providers_json> <text_mode>')
        return 2
    man_path = Path(sys.argv[1])
    prov_path = Path(sys.argv[2])
    text_mode = sys.argv[3]

    man = json.loads(man_path.read_text(encoding='utf-8'))
    prov = json.loads(prov_path.read_text(encoding='utf-8'))

    snap = {
        'schema_version': prov.get('schema_version'),
        'text': {
            'mode': prov.get('text', {}).get('mode'),
            'active_provider': prov.get('text', {}).get('active_provider'),
            'cache': prov.get('text', {}).get('cache'),
            'default_params': prov.get('text', {}).get('default_params'),
        },
        'image': {
            'mode': prov.get('image', {}).get('mode'),
            'active_provider': prov.get('image', {}).get('active_provider'),
            'cache': prov.get('image', {}).get('cache'),
            'default_params': prov.get('image', {}).get('default_params'),
        },
        'voice': {
            'mode': prov.get('voice', {}).get('mode'),
            'active_provider': prov.get('voice', {}).get('active_provider'),
            'cache': prov.get('voice', {}).get('cache'),
            'default_params': prov.get('voice', {}).get('default_params'),
        },
    }

    man.setdefault('audit', {})
    man['audit']['providers_json_snapshot'] = snap
    man['audit']['timestamp_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
    # No inventamos cache_key/hit. Solo marcamos: si text_mode==REPLAY, asumimos cache-hit por definición.
    man['audit']['text_mode'] = text_mode
    man['audit']['text_replay_assumed_cache_hit'] = (text_mode.upper() == 'REPLAY')

    man_path.write_text(json.dumps(man, indent=2, ensure_ascii=False), encoding='utf-8')
    print('OK audit injected ->', str(man_path))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())



