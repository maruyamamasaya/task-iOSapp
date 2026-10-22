"""Synthetic subprocess used only by Swift integration test. Never binds LAN."""
import json
from pathlib import Path
import sys
import tempfile
import threading
from mac_bridge import Bridge, make_loopback_server

def main():
    with tempfile.TemporaryDirectory(prefix='dot-local-e2e-') as tmp:
        bridge = Bridge(Path(tmp)/'bridge.sqlite', 'swift-loopback-fixture')
        bridge.upsert([{'id':'sample-task','title':'合成タスク','date':None,'dateLabel':'未定','status':'確認待ち','details':'合成のみ','category':'テスト','completed':False,'revision':1}])
        dot = Path(tmp)/'dot-local.json'; bridge.export_dot_file(dot)
        server = make_loopback_server(bridge, 'synthetic-loopback-only')
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        print(server.server_port, flush=True)
        try:
            for line in sys.stdin:
                command = line.strip().split(' ')
                if command[0] == 'QUIT': break
                if len(command) == 2 and command[0] == 'APPLY':
                    receipt = bridge.apply_to_dot_file(command[1].lower(), dot)
                    print(json.dumps(receipt), flush=True)
        finally:
            server.shutdown(); thread.join(timeout=2); server.server_close()


if __name__ == "__main__": main()
