"""Real installed tree, real IPC and lifecycle on a private bus and archive."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT=Path(__file__).resolve().parents[2]
assert os.environ.get('DAEVOX_ISOLATED_TEST')=='1', 'Use tests/shell/run.sh'
spec=importlib.util.spec_from_file_location('installation',ROOT/'scripts/lib/installation.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
work=Path(tempfile.mkdtemp(prefix='daevox-shell-integration-'))
repository = '--repository' in sys.argv[1:]
if repository:
    runtime=ROOT
    subprocess.run(['bash',str(ROOT/'native/notifications/build.sh'),str(ROOT/'Daevox/Notifications')],check=True)
else:
    runtime=work/'runtime'; m.stage_runtime(runtime)
    assert not any(p.suffix in ('.cpp','.md','.html') for p in runtime.rglob('*'))
    assert not any(p.is_symlink() for p in runtime.rglob('*'))
    assert len(list(runtime.rglob('shell.qml')))==1
runtime_dir=Path(os.environ['XDG_RUNTIME_DIR'])
(runtime_dir/'hypr').symlink_to(os.environ['DAEVOX_TEST_HYPR_DIR'])
env=dict(os.environ, WAYLAND_DISPLAY=os.environ['DAEVOX_TEST_WAYLAND'], QT_QPA_PLATFORM='wayland',
    QML_IMPORT_PATH=str(runtime), XDG_STATE_HOME=str(work/'state'), XDG_CONFIG_HOME=str(work/'config'),
    XDG_CACHE_HOME=str(work/'cache'), PIPEWIRE_RUNTIME_DIR=str(work/'no-audio'), QS_DISABLE_FILE_WATCHER='1')
proc=None
log=(work/'shell.log').open('w')

def ipc(method):
    return subprocess.check_output(['qs','ipc','--path',str(runtime/'shell.qml'),'call','launcher',method],env=env,text=True,stderr=subprocess.DEVNULL).strip()

def status(): return json.loads(ipc('status'))

def wait(predicate):
    until=time.monotonic()+10
    while time.monotonic()<until:
        if proc.poll() is not None: raise AssertionError('shell exited')
        try:
            value=status()
            if predicate(value): return value
        except (subprocess.CalledProcessError,ValueError): pass
        time.sleep(.05)
    raise AssertionError('shell state timeout')

def start(enabled):
    global proc
    env['DAEVOX_NOTIFICATIONS']='1' if enabled else '0'
    proc=subprocess.Popen(['qs','--no-color','--log-rules','quickshell.io.socket.warning=false','--path',str(runtime/'shell.qml')],env=env,stdout=log,stderr=log)
    return wait(lambda s: (s['notifications'] is not None and s['notifications']['ready']) if enabled else s['notifications'] is None)

def stop():
    proc.terminate(); proc.wait(timeout=5)

try:
    module=runtime/'Daevox'
    if not repository: module.rename(work/'module')
    first=start(False)
    assert first['visible'] is False
    ipc('notifications'); wait(lambda s:s['visible'] and s['mode']=='notifications' and s['notifications'] is None)
    ipc('open'); wait(lambda s:s['visible'] and s['mode']=='apps' and s['query']=='')
    ipc('close'); wait(lambda s:not s['visible'])
    ipc('toggle'); wait(lambda s:s['visible'] and s['mode']=='apps')
    ipc('toggle'); wait(lambda s:not s['visible'])
    # No endpoint is imported/constructed when disabled, even without the binary.
    owners=subprocess.check_output(['gdbus','call','--session','--dest','org.freedesktop.DBus','--object-path','/org/freedesktop/DBus','--method','org.freedesktop.DBus.NameHasOwner','org.freedesktop.Notifications'],env=env,text=True)
    assert 'false' in owners
    stop()
    if not repository: (work/'module').rename(module)
    start(True)
    pid=proc.pid
    subprocess.run(['gdbus','call','--session','--dest','org.freedesktop.Notifications','--object-path','/org/freedesktop/Notifications','--method','org.freedesktop.Notifications.Notify','Shell test','0','','Received while closed','body',"['default', 'Open']",'{}','0'],env=env,check=True,capture_output=True)
    wait(lambda s:not s['visible'] and s['notifications']['total']==1)
    ipc('notifications'); wait(lambda s:s['visible'] and s['mode']=='notifications')
    ipc('close'); wait(lambda s:not s['visible'] and s['notifications']['total']==1)
    assert proc.pid==pid and proc.poll() is None
    # D-Bus ownership is held by that same long-lived shell process.
    owner=subprocess.check_output(['gdbus','call','--session','--dest','org.freedesktop.DBus','--object-path','/org/freedesktop/DBus','--method','org.freedesktop.DBus.GetConnectionUnixProcessID','org.freedesktop.Notifications'],env=env,text=True)
    assert str(pid) in owner
    time.sleep(.5); stop(); start(True)
    wait(lambda s:not s['visible'] and s['notifications']['total']==1)
    print('SHELL PASS:', 'repository' if repository else 'staged tree', ' no plugin when disabled, IPC modes/toggle/close/status, one endpoint PID, receive while closed, history after restart')
finally:
    if proc and proc.poll() is None: stop()
    log.close()
    output=(work/'shell.log').read_text()
    print('Logs:',work)
    assert not re.search(r'TypeError|ReferenceError|Binding loop|Unable to assign|Failed to load configuration',output),output
