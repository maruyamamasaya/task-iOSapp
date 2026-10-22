"""Foreground-only approved relay. No service installation, token output or secret args."""
import argparse,json,os,re,ssl,subprocess,logging,logging.handlers,signal,threading
from pathlib import Path
from mac_bridge import make_lan_server

def lifecycle_logger(root):
    directory = root/'logs'
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    if directory.stat().st_uid != os.getuid() or directory.stat().st_mode & 0o077:
        raise SystemExit('Private log directory permissions are unsafe')
    logger = logging.getLogger('dot-relay-lifecycle')
    logger.setLevel(logging.INFO)
    handler = logging.handlers.RotatingFileHandler(directory/'lifecycle.log', maxBytes=262144, backupCount=3)
    handler.setFormatter(logging.Formatter('%(asctime)s %(message)s'))
    logger.addHandler(handler)
    return logger

def main():
    p=argparse.ArgumentParser();p.add_argument('--foreground',action='store_true',required=True);p.parse_args()
    root=Path.home()/'Library/Application Support/CalendarTaskApp/DotLocalRelay'
    os.umask(0o077)
    logger=lifecycle_logger(root)
    logger.info('starting pid=%s',os.getpid())
    from canonical_tasks import CanonicalBridge
    config=json.loads((root/'relay-config.json').read_text())
    if config['bindAddress']!='192.168.0.35' or config['port']!=8778:raise SystemExit('Unapproved bind target')
    info=subprocess.run(['/sbin/ifconfig','en10'],capture_output=True,text=True,check=True).stdout
    if not re.search(r'\binet 192\.168\.0\.35\b',info):raise SystemExit('Approved en10 address is no longer assigned')
    for path in [root,root/'auth',root/'tls']:
        if path.stat().st_uid!=os.getuid() or path.stat().st_mode&0o077:raise SystemExit('Private directory permissions are unsafe')
    for path in [root/'auth/phone-1.token',root/'tls/server-key.pem']:
        if path.stat().st_uid!=os.getuid() or path.stat().st_mode&0o077:raise SystemExit('Secret file permissions are unsafe')
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(root/'tls/server-cert.pem',root/'tls/server-key.pem')
    bearer=(root/'auth/phone-1.token').read_text().strip()
    bridge=CanonicalBridge(root/'state/bridge.sqlite',config['bridgeID'],root/'state/tasks.json')
    bridge.feed() # Refuse to serve a missing or inconsistent canonical source.
    server=make_lan_server(bridge,bearer,config['bindAddress'],context,port=config['port'],lan_authorized=True)
    print('Authenticated TLS relay active on 192.168.0.35:8778; foreground only; no credentials logged.',flush=True)
    def stop(signum, frame):
        logger.info('stop requested signal=%s', signum)
        threading.Thread(target=server.shutdown, daemon=True).start()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGHUP, stop)
    logger.info('listening approved LAN endpoint')
    try:server.serve_forever()
    except KeyboardInterrupt:logger.info('stop requested keyboard interrupt')
    finally:
        server.server_close()
        logger.info('stopped')

if __name__=='__main__':
    try: main()
    except Exception as error:
        # Never log exception text, headers, bodies, tokens, task content or paths.
        logging.getLogger('dot-relay-lifecycle').error('fatal type=%s',type(error).__name__)
        raise SystemExit(1)
