#!/usr/bin/env python3
"""Reversible cutover of the unified shell service; never removes packages."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time

HOME_DIR = Path.home()
CONFIG = HOME_DIR/'.config'
STATE = Path(os.environ.get('XDG_STATE_HOME', HOME_DIR/'.local/state'))
DATA = Path(os.environ.get('XDG_DATA_HOME', HOME_DIR/'.local/share'))
UNIT = 'daevox-shell.service'
SHELL = CONFIG/'quickshell/daevox-shell/shell.qml'
TARGETS = [CONFIG/'hypr/hyprland.lua', CONFIG/'systemd/user/daevox-shell.service.d/notifications.conf',
           DATA/'dbus-1/services/fr.emersion.mako.service']

def run(*args):
    return subprocess.check_output(args,text=True,stderr=subprocess.STDOUT).strip()

def bus(method, *args):
    return run('gdbus','call','--session','--dest','org.freedesktop.DBus','--object-path','/org/freedesktop/DBus',
               '--method','org.freedesktop.DBus.'+method,*args)

def owner_pid():
    owner=re.search(r"'([^']+)'",bus('GetNameOwner','org.freedesktop.Notifications'))[1]
    return int(re.search(r'uint32 (\d+)',bus('GetConnectionUnixProcessID',owner))[1])

def executable(pid): return Path("/proc",str(pid),"exe").resolve().name

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None

def restore(backup):
    manifest=json.loads((backup/'manifest.json').read_text())
    # Refuse to overwrite changes made after this migration.
    for item in manifest['files']:
        path=Path(item['path'])
        if item.get('written') is not None and digest(path)!=item['written']:
            raise RuntimeError('File changed since migration; review before rollback: '+str(path))
    subprocess.run(['systemctl','--user','stop',UNIT],check=True)
    for index,item in enumerate(manifest['files']):
        path=Path(item['path'])
        if item['existed']:
            path.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(backup/str(index),path)
        elif item.get('written') is not None:
            path.unlink(missing_ok=True)
    run('systemctl','--user','daemon-reload')
    bus('ReloadConfig')
    if manifest['launcher_active']: run('systemctl','--user','start',UNIT)
    # Restore the directly launched notification daemon used before migration.
    try:
        pid=owner_pid()
        if executable(pid)=='mako': return
        raise RuntimeError('Unexpected notification owner during rollback')
    except subprocess.CalledProcessError:
        log=(backup/'mako-rollback.log').open('ab')
        subprocess.Popen(['mako'],stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
        log.close()
    for _ in range(50):
        try:
            if executable(owner_pid())=='mako': return
        except (subprocess.CalledProcessError,FileNotFoundError): pass
        time.sleep(.1)
    raise RuntimeError('Rollback files restored, but mako did not acquire the name')

def apply():
    if not (SHELL.parent/'Daevox/Notifications/libdaevoxnotifications.so').is_file():
        raise RuntimeError('Install Daevox Shell before switching notifications')
    pid=owner_pid()
    if executable(pid)!='mako':
        raise RuntimeError('Expected mako as the current notification owner; no changes made')
    original=TARGETS[0].read_text()
    updated,count=re.subn(r'^\s*hl\.exec_cmd\([\"\']mako[\"\']\)[ \t]*\n','',original,flags=re.MULTILINE)
    if count!=1: raise RuntimeError('Expected exactly one direct mako autostart; no changes made')
    dropin='[Service]\nType=dbus\nBusName=org.freedesktop.Notifications\nEnvironment=DAEVOX_NOTIFICATIONS=1\n'
    activation='[D-BUS Service]\nName=org.freedesktop.Notifications\nExec=/usr/bin/systemctl --user start daevox-shell.service\nSystemdService=daevox-shell.service\n'
    backup=STATE/'daevox/notification-migration'/str(time.time_ns())
    backup.mkdir(parents=True,mode=0o700)
    manifest={'launcher_active':subprocess.run(['systemctl','--user','is-active','--quiet',UNIT]).returncode==0,
              'files':[{'path':str(path),'existed':path.exists(),'written':None} for path in TARGETS]}
    for index,path in enumerate(TARGETS):
        if path.exists(): shutil.copy2(path,backup/str(index))
    (backup/'manifest.json').write_text(json.dumps(manifest,indent=2))
    print('Backup:',backup,flush=True)
    try:
        for index,(path,content) in enumerate(zip(TARGETS,[updated,dropin,activation])):
            path.parent.mkdir(parents=True,exist_ok=True)
            temporary=path.with_name(path.name+'.daevox-new')
            temporary.write_text(content)
            temporary.chmod(path.stat().st_mode & 0o777 if path.exists() else 0o644)
            temporary.replace(path)
            manifest['files'][index]['written']=digest(path)
            (backup/'manifest.json').write_text(json.dumps(manifest,indent=2))
        run('systemctl','--user','daemon-reload')
        bus('ReloadConfig')
        # Re-check PID and executable immediately before stopping that daemon.
        current=owner_pid()
        if current!=pid or executable(current)!='mako':
            raise RuntimeError('Notification owner changed during preparation')
        os.kill(current,signal.SIGTERM)
        run('systemctl','--user','restart',UNIT)
        main_pid=int(run('systemctl','--user','show',UNIT,'--property=MainPID','--value'))
        if owner_pid()!=main_pid: raise RuntimeError('D-Bus owner does not match launcher MainPID')
        status=json.loads(run('qs','ipc','--path',str(SHELL),'call','launcher','status'))
        if not status.get('notifications',{}).get('ready'): raise RuntimeError('Notification endpoint is not ready')
        print('Cutover complete:',json.dumps(status['notifications'],ensure_ascii=False))
        print('Rollback: python3 scripts/notification-migration.py rollback',backup)
        print('mako package retained until new-session acceptance.')
    except Exception:
        print('Cutover failed; restoring previous configuration.',flush=True)
        restore(backup)
        raise

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='command',required=True)
    sub.add_parser('apply')
    rollback=sub.add_parser('rollback'); rollback.add_argument('backup',type=Path)
    args=parser.parse_args()
    if args.command=='apply': apply()
    else: restore(args.backup)
