"""Exercise the real QML Socket transport against disposable Unix peers."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
BASE = {
    'version': {'version': '0.56.2'},
    'monitors': [{'name': 'DP-1', 'activeWorkspace': {'id': 1}, 'specialWorkspace': {'id': 0}}],
    'workspaces': [{'id': 1, 'name': '1', 'monitor': 'DP-1', 'lastwindow': '0xa'}],
    'clients': [{'address': '0xa', 'workspace': {'id': 1}, 'class': 'app', 'title': 'Окно ✓'}],
    'activewindow': {'address': '0xa'},
    'devices': {'keyboards': [{'name': 'keyboard', 'main': True, 'layout': 'us,ru', 'active_layout_index': 0}]},
}


def run_case(case):
    with tempfile.TemporaryDirectory(prefix='daevox-transport-') as directory:
        stopped = threading.Event()
        event_peer = [None]
        requests, errors = [], []
        fault = [False]
        peers = []
        listeners = []
        for name in ['.socket.sock', '.socket2.sock']:
            listener = socket.socket(socket.AF_UNIX)
            listener.bind(directory + '/' + name)
            listener.listen()
            listener.settimeout(.1)
            listeners.append(listener)

        def request(peer):
            try:
                command = peer.recv(65536).decode()
                requests.append(command)
                key = command.removeprefix('j/')
                if case == 'command-timeout' and command.startswith('/switch'):
                    time.sleep(.7)
                    return
                if case in ('malformed', 'schema', 'timeout') and key == 'clients' and not fault[0]:
                    fault[0] = True
                    if case == 'timeout':
                        time.sleep(.7)  # Late old-generation reply must not become current.
                    else:
                        peer.sendall(b'{bad json' if case == 'malformed' else b'{}')
                        return
                if case == 'events' and key == 'monitors' and not fault[0]:
                    fault[0] = True
                    event_peer[0].sendall(b'windowtitlev')
                    time.sleep(.015)
                    event_peer[0].sendall(b'2>>a,title\nunknown>>ignored\nactivewindowv2>>a\n')
                body = json.dumps(BASE[key], ensure_ascii=False).encode() if key in BASE else b'ok'
                # One-byte chunks deliberately split UTF-8 codepoints and JSON framing.
                for byte in body:
                    peer.sendall(bytes([byte]))
                    if key == 'clients':
                        time.sleep(.0002)
                if case == 'disconnect' and key == 'devices' and not fault[0]:
                    fault[0] = True
                    time.sleep(.05)
                    event_peer[0].shutdown(socket.SHUT_RDWR)
                    event_peer[0].close()
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass
            except Exception as error:
                errors.append(repr(error))
            finally:
                peer.close()

        def accept_loop(listener, events):
            while not stopped.is_set():
                try:
                    peer, _ = listener.accept()
                except socket.timeout:
                    continue
                except OSError:
                    return
                peers.append(peer)
                if events:
                    event_peer[0] = peer
                else:
                    if event_peer[0] is None:
                        errors.append('request before event subscription')
                    threading.Thread(target=request, args=(peer,), daemon=True).start()

        for index, listener in enumerate(listeners):
            threading.Thread(target=accept_loop, args=(listener, index == 1), daemon=True).start()
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', XDG_RUNTIME_DIR=directory,
                   BAR_TEST_SOCKET_DIR=directory, QS_DISABLE_FILE_WATCHER='1',
                   BAR_TEST_COMMAND='1' if case == 'command-timeout' else '')
        env.pop('WAYLAND_DISPLAY', None)
        process = subprocess.run(['qs', '--no-color', '--log-rules', 'quickshell.io.socket.warning=false',
                                  '--path', str(ROOT / 'tests/bar/state-probe.qml')],
                                 env=env, capture_output=True, text=True, timeout=15)
        stopped.set()
        for peer in peers:
            peer.close()
        for listener in listeners:
            listener.close()
        output = process.stdout + process.stderr
        assert process.returncode == 0, output
        assert not errors, errors
        assert 'PROBE_FINAL true' in output, output
        assert 'Окно ✓' in output, output
        assert 'TypeError' not in output and 'ReferenceError' not in output, output
        if case == 'healthy':
            assert len(requests) == 6, requests  # No polling while idle.
        elif case == 'events':
            assert requests.count('j/clients') >= 2, requests
        else:
            assert 'PROBE_ERROR' in output, output
            assert requests.count('j/version') >= 2, requests
        if case == 'command-timeout':
            assert sum(c.startswith('/switch') for c in requests) == 1, requests
        print('PASS transport:', case, len(requests), 'requests')


for case in ['healthy', 'events', 'malformed', 'schema', 'timeout', 'disconnect', 'command-timeout']:
    run_case(case)
