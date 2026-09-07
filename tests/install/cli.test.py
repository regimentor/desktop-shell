"""Execute public CLIs from another cwd against a disposable HOME and fake services."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='daevox-install-cli-') as directory:
    home=Path(directory); bin_dir=home/'bin'; bin_dir.mkdir()
    (bin_dir/'systemctl').write_text('''#!/usr/bin/python3
import json, os, pathlib, sys
home=pathlib.Path(os.environ['HOME'])
path=home/'services.json'
s=json.loads(path.read_text()) if path.exists() else {}
a=sys.argv[2:]
with (home/'calls.log').open('a') as f: f.write(' '.join(a)+'\\n')
if a[0]=='show':
    unit=a[1]; active=s.get(unit,{}).get('active',unit=='graphical-session.target'); enabled=s.get(unit,{}).get('enabled',False)
    print('LoadState=loaded\\nActiveState='+('active' if active else 'inactive')+'\\nUnitFileState='+('enabled' if enabled else 'disabled')+'\\nMainPID=0\\nEnvironment=\\nEnvironmentFiles=')
elif a[0] in ('start','restart','stop','enable','disable'):
    unit=a[-1]; state=s.setdefault(unit,{})
    if a[0] in ('start','restart','stop'): state['active']=a[0]!='stop'
    else: state['enabled']=a[0]=='enable'
    path.write_text(json.dumps(s))
''')
    (bin_dir/'qs').write_text('#!/usr/bin/python3\nimport json\nprint(json.dumps({"visible":False,"applications":0,"notifications":None}))\n')
    for path in bin_dir.iterdir(): path.chmod(0o755)
    env=dict(os.environ,HOME=str(home),XDG_DATA_HOME=str(home/'data'),PATH=str(bin_dir)+':'+os.environ['PATH'])
    def run(script,*args):
        result=subprocess.run(['bash',str(ROOT/script),*args],env=env,cwd=home,capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        return result.stdout
    run('install-shell.sh')
    runtime=home/'.config/quickshell/daevox-shell'
    assert (runtime/'shell.qml').is_file()
    assert (runtime/'Daevox/Notifications/libdaevoxnotifications.so').is_file()
    assert (runtime/'launcher/audio/AudioPane.qml').is_file()
    assert not (runtime/'launcher/shell.qml').exists()
    assert not list(runtime.rglob('*.md'))
    unit=(home/'.config/systemd/user/daevox-shell.service').read_text()
    assert 'DAEVOX_NOTIFICATIONS=0' in unit and 'QML_IMPORT_PATH=' in unit
    run('uninstall-legacy.sh','all','--dry-run')
    run('uninstall-legacy.sh','all')
    run('uninstall-legacy.sh','all')
    assert (runtime/'shell.qml').exists()
    for name in ('install-shell.sh','uninstall-legacy.sh'): run(name,'--help')
    print('CLI PASS: arbitrary cwd, clean install, native build, portable runtime, real public entrypoints, dry run, repeated absent uninstall')
