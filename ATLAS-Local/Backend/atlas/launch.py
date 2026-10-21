"""Start only when the port is free; open UI after actual server readiness."""
import json
import socket
import subprocess
import sys
import time
from . import server as s

def main():
    with socket.socket() as sock:
        sock.settimeout(1)
        if sock.connect_ex(('127.0.0.1',s.PORT))==0:
            print(f'Port {s.PORT} ist bereits belegt. Die alte Atlas-Instanz zuerst mit Ctrl+C beenden.');return 1
    child=subprocess.Popen([sys.executable,'-m','atlas.server'])
    try:
        for _ in range(50):
            if child.poll() is not None:return child.returncode
            try:
                with s.HTTP.open(f'http://127.0.0.1:{s.PORT}/api/state',timeout=1) as r:state=json.load(r)
                if state.get('version')=='0.2.3':
                    subprocess.run(['open',f'http://127.0.0.1:{s.PORT}'],check=True);break
            except (OSError,ValueError):pass
            time.sleep(.1)
        else:print('Start dauert länger. Prüfe die Terminalmeldung und öffne die lokale Adresse manuell.')
        return child.wait()
    except KeyboardInterrupt:return 0
    finally:
        if child.poll() is None:
            child.terminate()
            try:child.wait(timeout=5)
            except subprocess.TimeoutExpired:child.kill();child.wait()
if __name__=='__main__':sys.exit(main())
