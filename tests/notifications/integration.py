#!/usr/bin/env python3
"""Run with dbus-run-session; every notification belongs to this isolated bus."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
from gi.repository import Gio, GLib

ROOT = Path(__file__).resolve().parents[2]
if os.environ.get('DAEVOX_ISOLATED_TEST') != '1':
    raise SystemExit('Use tests/notifications/run.sh (creates a private D-Bus session)')
work = Path(tempfile.mkdtemp(prefix='daevox-notification-test.'))
qml = work / 'qml'
qml.mkdir()
for directory in ('launcher', 'notifications', 'desktop', 'bar', 'shared'):
    shutil.copytree(ROOT/directory, qml/directory, ignore=shutil.ignore_patterns('.qmlls.ini'))
module = qml/'Daevox/Notifications'
module.mkdir(parents=True)
shutil.copy2(ROOT/'Daevox/Notifications/qmldir', module)
subprocess.run(['bash', str(ROOT/'native/notifications/build.sh'), str(module)], check=True)
def test_source(name):
    return (ROOT/'tests/notifications'/name).read_text().replace('"../../', '"')
(qml/'shell.qml').write_text(test_source('probe.qml'))
env = dict(os.environ, QT_QPA_PLATFORM='offscreen', WAYLAND_DISPLAY='daevox-no-desktop',
           QML_IMPORT_PATH=str(qml), XDG_STATE_HOME=str(work/'state'), XDG_CONFIG_HOME=str(work/'config'), XDG_CACHE_HOME=str(work/'cache'))
log = (work/'runtime.log').open('w')
proc = None
connection = Gio.DBusConnection.new_for_address_sync(os.environ['DBUS_SESSION_BUS_ADDRESS'],
    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
events=[]
connection.signal_subscribe(None,'org.freedesktop.Notifications',None,'/org/freedesktop/Notifications',None,
    Gio.DBusSignalFlags.NONE,lambda conn,sender,path,interface,signal,params,data: events.append((signal,params.unpack())),None)

def start():
    global proc
    proc = subprocess.Popen(['qs','--path',str(qml/'shell.qml'),'--no-color'],env=env,stdout=log,stderr=log)
    until = time.monotonic()+10
    while time.monotonic()<until:
        try:
            info=bus('GetServerInformation')
            assert 'daevox' in info.lower(), info
            ipc('state'); return
        except (subprocess.CalledProcessError, GLib.Error): time.sleep(.05)
    raise AssertionError('server failed to start')

def bus(method,*args):
    signature={'Notify':'(susssasa{sv}i)', 'CloseNotification':'(u)'}.get(method,'()')
    if method=='Notify':
        values=[json.dumps(value) if index in (0,2,3,4) else value for index,value in enumerate(args)]
        expression='('+', '.join(values)+')'
    elif args: expression='('+args[0]+',)'
    else: expression='()'
    parameters=GLib.Variant.parse(GLib.VariantType.new(signature),expression,None,None)
    result=connection.call_sync('org.freedesktop.Notifications','/org/freedesktop/Notifications',
        'org.freedesktop.Notifications',method,parameters,None,Gio.DBusCallFlags.NONE,5000,None)
    return result.print_(True)

def ipc(method,*args):
    return subprocess.check_output(['qs','ipc','--path',str(qml/'shell.qml'),'call','test',method,*args],env=env,text=True).strip()

def state(): return json.loads(ipc('state'))
def notify(summary='Test', replace=0, timeout=0, hints='{}', actions="['default', 'Open', 'inline-reply', 'Reply']"):
    result=bus('Notify','Test',str(replace),'',summary,'Body',actions,hints,str(timeout))
    return int(re.search(r'uint32 (\d+)',result)[1])

def wait_for(predicate):
    until=time.monotonic()+5
    while time.monotonic()<until:
        while GLib.MainContext.default().iteration(False): pass
        result=state()
        if predicate(result): return result
        time.sleep(.03)
    raise AssertionError('timed out: '+json.dumps(state()))

try:
    start()
    assert 'actions' in bus('GetCapabilities')
    id1=notify(timeout=1000)
    row=wait_for(lambda s: len(s['records'])==1)['records'][0]
    assert row['timeout']==1000, row
    assert row['remaining']<=1000 and row['popup']=='visible'
    wait_for(lambda s: s['records'][0]['liveId'] is None)
    assert state()['records'][0]['unread'] is False
    id2=notify('Before')
    row=wait_for(lambda s:len(s['records'])==2)['records'][-1]
    key=row['key']
    assert notify('After',replace=id2)==id2
    wait_for(lambda s:s['records'][-1]['summary']=='After')
    assert len(state()['records'])==2
    ipc('dnd'); assert state()['dnd']
    notify('Suppressed',replace=id2)
    wait_for(lambda s:s['records'][-1]['summary']=='Suppressed')
    ipc('dnd'); assert state()['records'][-1]['popup']=='suppressed'
    transient=notify('Transient',hints="{'transient': <true>}")
    transient_row=wait_for(lambda s:len(s['records'])==3)['records'][-1]
    ipc('dismiss',transient_row['key'])
    wait_for(lambda s:len(s['records'])==2)
    ipc('invoke',key,'default')
    wait_for(lambda s:s['records'][-1]['liveId'] is None)
    assert any(name=='ActionInvoked' and values==(id2,'default') for name,values in events),events
    id3=notify('Reply')
    row=wait_for(lambda s:len(s['records'])==3)['records'][-1]
    assert row['reply'], row
    ipc('reply',row['key'],'hello')
    wait_for(lambda s:s['records'][-1]['liveId'] is None)
    assert any(name=='NotificationReplied' and values==(id3,'hello') for name,values in events),events
    id4=notify('Resident',hints="{'resident': <true>}")
    row=wait_for(lambda s:len(s['records'])==4)['records'][-1]
    ipc('invoke',row['key'],'default')
    assert state()['records'][-1]['liveId']==id4
    bus('CloseNotification',str(id4))
    wait_for(lambda s:s['records'][-1]['liveId'] is None)
    # Exercise image-data via the in-process provider, not a file URL.
    notify('Image',hints="{'image-data': <(2, 2, 8, true, 8, 4, [byte 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255])>}")
    row=wait_for(lambda s:len(s['records'])==5)['records'][-1]
    assert row['image'].startswith('file:'),row
    image=row['image']
    assert Path(image.removeprefix('file://')).exists()
    # Installed API compatibility probe: replacement label changes.
    change=notify('Labels',actions="['default', 'Original']")
    wait_for(lambda s:len(s['records'])==6)
    notify('Labels changed',replace=change,actions="['default', 'Updated']")
    label=wait_for(lambda s:s['records'][-1]['summary']=='Labels changed')['records'][-1]['actions'][0]['text']
    assert label == 'Updated', label
    print('ACTION LABEL REPLACEMENT PASS')
    ipc('dnd'); time.sleep(.2)
    proc.terminate(); proc.wait(timeout=5)
    start()
    result=wait_for(lambda s:len(s['records'])==6)
    assert result['dnd'] and all(r['liveId'] is None and not r['actions'] for r in result['records'])
    assert any(r['image']==image for r in result['records'])
    assert not result['error'],result
    for row in result['records']: ipc('remove',row['key'])
    time.sleep(.3)
    assert not Path(image.removeprefix('file://')).exists()
    print('NOTIFICATION INTEGRATION PASS: timeouts, replacement, DND, transient, actions, reply, resident, close, image-data, restart, cleanup')
    proc.terminate(); proc.wait(timeout=5)
    # Verify initial lock state, transitions and reconnect against a mock compositor.
    subprocess.run(['wayland-scanner','server-header',str(ROOT/'native/notifications/lock.xml'),str(work/'lock-server.h')],check=True)
    subprocess.run(['wayland-scanner','private-code',str(ROOT/'native/notifications/lock.xml'),str(work/'lock-protocol.c')],check=True)
    flags=subprocess.check_output(['pkg-config','--cflags','--libs','wayland-server'],text=True).split()
    subprocess.run(['cc','-Wall','-Wextra','-Werror','-I'+str(work),str(ROOT/'tests/notifications/lock-server.c'),str(work/'lock-protocol.c'),*flags,'-o',str(work/'lock-server')],check=True)
    (qml/'shell.qml').write_text((ROOT/'tests/notifications/lock.qml').read_text())
    env['WAYLAND_DISPLAY']='daevox-lock-test'
    mock=subprocess.Popen([str(work/'lock-server'),'locked'],env=env,stdin=subprocess.PIPE)
    try:
        proc=subprocess.Popen(['qs','--path',str(qml/'shell.qml'),'--no-color'],env=env,stdout=log,stderr=log)
        time.sleep(.3)
        wait_for(lambda s:s['lock']=='locked')
        mock.stdin.write(b'U'); mock.stdin.flush()
        wait_for(lambda s:s['lock']=='unlocked')
        mock.stdin.write(b'L'); mock.stdin.flush()
        wait_for(lambda s:s['lock']=='locked')
        mock.stdin.write(b'Q'); mock.stdin.flush(); mock.wait(timeout=5)
        wait_for(lambda s:s['lock']=='unknown')
        mock=subprocess.Popen([str(work/'lock-server'),'unlocked'],env=env,stdin=subprocess.PIPE)
        wait_for(lambda s:s['lock']=='unlocked')
        print('LOCK OBSERVER PASS: initially locked, unlock, lock, disconnect unknown, reconnect initially unlocked')
    finally:
        mock.terminate(); mock.wait(timeout=5)
        proc.terminate(); proc.wait(timeout=5)
    if 'DAEVOX_UI_WAYLAND' not in env:
        raise SystemExit(0)
    env['QT_QPA_PLATFORM']='wayland'
    env['WAYLAND_DISPLAY']=env['DAEVOX_UI_WAYLAND']
    (qml/'shell.qml').write_text(test_source('ui.qml'))
    env['DAEVOX_TEST_OUTPUT']=str(work)
    proc = subprocess.Popen(['qs','--path',str(qml/'shell.qml'),'--no-color'],env=env,stdout=log,stderr=log)
    proc.wait(timeout=20)
    log.flush()
    ui_log=(work/'runtime.log').read_text()
    assert 'NOTIFICATION UI PASS' in ui_log, ui_log[-5000:]
    assert not re.search(r'TypeError|ReferenceError|Binding loop|FAIL|Unable to assign',ui_log),ui_log[-5000:]
    # Smoke-test the actual entry point, including its deferred runtime loader.
    (qml/'shell.qml').write_text((ROOT/'shell.qml').read_text())
    env['DAEVOX_NOTIFICATIONS']='1'
    proc=subprocess.Popen(['qs','--path',str(qml/'shell.qml'),'--no-color'],env=env,stdout=log,stderr=log)
    until=time.monotonic()+8
    status={}
    while time.monotonic()<until:
        try:
            status=json.loads(subprocess.check_output(['qs','ipc','--path',str(qml/'shell.qml'),'call','launcher','status'],env=env,text=True,stderr=subprocess.DEVNULL))
            if status.get('notifications',{}).get('ready'): break
        except (subprocess.CalledProcessError,json.JSONDecodeError): pass
        time.sleep(.05)
    assert status.get('notifications',{}).get('ready'),status
    notify('Основной файл оболочки')
    time.sleep(.2)
    print('MAIN ENTRY POINT PASS: native endpoint ready through deferred runtime loader')


finally:
    if proc and proc.poll() is None:
        proc.terminate()
        try: proc.wait(timeout=5)
        except subprocess.TimeoutExpired: proc.kill(); proc.wait()
    log.close()
    print('Logs:',work)
    text=(work/'runtime.log').read_text()
    print(text[-12000:])
