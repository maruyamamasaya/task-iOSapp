"""Synthetic canonical receiver for Swift undo integration; loopback only."""
import json
from pathlib import Path
import sys
import tempfile
import threading
from mac_bridge import Bridge, make_loopback_server
from canonical_tasks import CanonicalBridge


def main():
    with tempfile.TemporaryDirectory(prefix='dot-undo-http-') as directory:
        root = Path(directory)
        base = Bridge(root/'bridge.sqlite', 'undo-loopback-fixture')
        base.upsert([{'id':'sample-task','title':'Synthetic','date':None,'dateLabel':'','status':'','details':'','category':'test','completed':False,'revision':1}])
        source = root/'tasks.json'; base.export_dot_file(source)
        bridge = CanonicalBridge(root/'bridge.sqlite', 'undo-loopback-fixture', source)
        server = make_loopback_server(bridge, 'synthetic-loopback-only')
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        print(server.server_port, flush=True)
        try:
            for line in sys.stdin:
                if line.strip() == 'QUIT': break
                if line.strip() == 'READ':
                    feed = bridge.feed()
                    print(json.dumps({'task':feed['tasks'][0], 'operationCount':len(json.loads(source.read_text())['appliedOperations'])}), flush=True)
        finally:
            server.shutdown(); thread.join(timeout=3); server.server_close()


if __name__ == '__main__': main()
