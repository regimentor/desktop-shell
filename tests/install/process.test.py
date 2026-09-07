"""Match real manually launched Quickshell instances without touching user services."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[2]
s=importlib.util.spec_from_file_location('installation',ROOT/'scripts/lib/installation.py')
m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
with tempfile.TemporaryDirectory(prefix='daevox-process-test-') as directory:
    home=Path(directory); config=home/'.config/quickshell/daevox-bar'; config.mkdir(parents=True)
    (config/'shell.qml').write_text('import Quickshell\nShellRoot {}\n')
    m.HOME_DIR=home; m.QML=config.parent
    env=dict(os.environ,HOME=str(home),XDG_CONFIG_HOME=str(home/'.config'),XDG_RUNTIME_DIR=str(home),QT_QPA_PLATFORM='offscreen')
    env.pop('QS_CONFIG_PATH',None); env.pop('QS_CONFIG_NAME',None)
    for args, extra in [(['--path',str(config)],{}),(['--path='+str(config/'shell.qml')],{}),(['-c','daevox-bar'],{}),([],{ 'QS_CONFIG_PATH':str(config)})]:
        with (home/'log').open('w') as log:
            proc=subprocess.Popen(['qs','--no-color',*args],env=dict(env,**extra),stdout=log,stderr=log)
            try:
                until=time.monotonic()+5
                while time.monotonic()<until and 'Configuration Loaded' not in (home/'log').read_text():
                    if proc.poll() is not None: raise AssertionError((home/'log').read_text())
                    time.sleep(.05)
                assert str(proc.pid) in m.manual_instances('bar',{'MainPID':'0'}),args
                assert m.manual_instances('bar',{'MainPID':str(proc.pid)})==[],args
                assert m.manual_instances('launcher',{'MainPID':'0'})==[],args
            finally:
                proc.terminate(); proc.wait(timeout=5)
    print('PROCESS PASS: exact file/directory/named/environment configs, service PID exclusion, unrelated config preserved')
