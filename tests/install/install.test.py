"""Isolated filesystem/service transactions; no access to the real user manager."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('installation', ROOT/'scripts/lib/installation.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def info(active=False, enabled=False, **extra):
    return dict(LoadState='loaded', ActiveState='active' if active else 'inactive',
                UnitFileState='enabled' if enabled else 'disabled', MainPID='0', Environment='', EnvironmentFiles='', **extra)


class Installation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='daevox-install-test-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        env_patch = patch.dict(os.environ, {'XDG_DATA_HOME': str(self.home/'.local/share')})
        env_patch.start(); self.addCleanup(env_patch.stop)
        self.qml = self.home/'.config/quickshell'
        self.units = self.home/'.config/systemd/user'
        self.qml.mkdir(parents=True)
        self.units.mkdir(parents=True)
        self.states = {f'daevox-{name}.service': info() for name in ('bar', 'launcher', 'shell')}
        self.states['graphical-session.target'] = info(active=True)
        self.calls = []
        self.fail = None
        for key, value in dict(HOME_DIR=self.home, QML=self.qml, UNITS=self.units).items():
            p = patch.object(m, key, value); p.start(); self.addCleanup(p.stop)
        for key, value in dict(ctl=self.ctl, manual_instances=lambda *args: [], stage_runtime=self.stage,
                               wait_ready=lambda _: None).items():
            p = patch.object(m, key, value); p.start(); self.addCleanup(p.stop)

    def ctl(self, *args, check=True):
        self.calls.append(args)
        if self.fail and self.fail(args):
            raise subprocess.CalledProcessError(1, args, stderr='injected systemd failure')
        command = args[0]
        unit = args[-1]
        if command == 'show':
            unit = args[1]
            return subprocess.CompletedProcess(args, 0, '\n'.join(f'{k}={v}' for k,v in self.states[unit].items()), '')
        if command == 'restart' and unit == m.NEW:
            text = (self.units/m.NEW).read_text()
            if 'Type=dbus' in text and 'DAEVOX_NOTIFICATIONS=1' not in text:
                raise subprocess.TimeoutExpired(args, 90)
        if command in ('stop','restart','start'): self.states[unit]['ActiveState'] = 'inactive' if command == 'stop' else 'active'
        if command in ('enable','disable'): self.states[unit]['UnitFileState'] = 'enabled' if command == 'enable' else 'disabled'
        return subprocess.CompletedProcess(args, 0, '', '')

    def stage(self, path):
        path.mkdir(); (path/'shell.qml').write_text('new shell')

    def legacy(self, name, active=True, enabled=True):
        base = self.qml/f'daevox-{name}'
        base.mkdir()
        for entry in (ROOT/f'scripts/manifests/legacy-{name}.txt').read_text().splitlines():
            path = base/entry; path.parent.mkdir(parents=True, exist_ok=True)
            if entry == 'shared': path.symlink_to('../shared')
            else: path.write_text('legacy')
        (self.units/f'daevox-{name}.service').write_text('old unit')
        dropin = self.units/f'daevox-{name}.service.d'; dropin.mkdir()
        (dropin/'custom.conf').write_text('[Service]\nEnvironment=LANG=ru_RU.UTF-8')
        (base/'personal.txt').write_text('keep')
        (base/'empty-user-directory').mkdir()
        self.states[f'daevox-{name}.service'] = info(active, enabled)
        return base

    def test_remove_each_and_all_repeat(self):
        for selection in [('bar',), ('launcher',), ('bar','launcher')]:
            with self.subTest(selection=selection):
                for name in ('bar','launcher'):
                    base=self.qml/f'daevox-{name}'
                    if not base.exists(): self.legacy(name)
                m.uninstall(selection, False); m.uninstall(selection, False)
                for name in selection:
                    self.assertFalse((self.qml/f'daevox-{name}/shell.qml').exists())
                    self.assertTrue((self.qml/f'daevox-{name}/personal.txt').exists())
                    self.assertTrue((self.qml/f'daevox-{name}/empty-user-directory').is_dir())
                    self.assertTrue((self.units/f'daevox-{name}.service.d/custom.conf').exists())

    def test_dry_run_no_mutations(self):
        self.legacy('bar'); self.legacy('launcher')
        before={str(p): p.read_bytes() for p in self.home.rglob('*') if p.is_file()}
        m.uninstall(m.LEGACY, True)
        self.assertEqual(before,{str(p):p.read_bytes() for p in self.home.rglob('*') if p.is_file()})
        self.assertTrue(all(c[0]=='show' for c in self.calls))

    def test_absent_partial_and_shared(self):
        shared=self.qml/'shared'; shared.mkdir(); (shared/'theme').write_text('keep')
        new=self.qml/'daevox-shell'; new.mkdir(); (new/'shell.qml').write_text('keep')
        base=self.qml/'daevox-bar'; base.mkdir(); (base/'Bar.qml').write_text('old')
        history=self.home/'history.json'; history.write_text('keep')
        m.uninstall(m.LEGACY, False)
        self.assertFalse(base.exists())
        for p in [shared/'theme',new/'shell.qml',history]: self.assertEqual(p.read_text(),'keep')

    def test_never_follow_links(self):
        base=self.legacy('launcher')
        outside=self.home/'outside'; outside.mkdir(); (outside/'qmldir').write_text('keep')
        import shutil
        shutil.rmtree(base/'Daevox'); (base/'Daevox').symlink_to(outside, target_is_directory=True)
        (base/'Launcher.qml').unlink(); (base/'Launcher.qml').symlink_to(outside/'qmldir')
        m.uninstall(['launcher'],False)
        self.assertEqual((outside/'qmldir').read_text(),'keep')
        self.assertTrue((base/'Daevox').is_symlink())

    def test_symlink_root_preserved(self):
        outside=self.home/'outside'; outside.mkdir(); (outside/'shell.qml').write_text('keep')
        (self.qml/'daevox-bar').symlink_to(outside, target_is_directory=True)
        m.uninstall(['bar'],False)
        self.assertEqual((outside/'shell.qml').read_text(),'keep')

    def test_manual_instance_blocks_before_stop(self):
        base=self.legacy('bar')
        with patch.object(m,'manual_instances', return_value=['123']):
            with self.assertRaisesRegex(RuntimeError,'123'): m.uninstall(['bar'],False)
        self.assertTrue((base/'shell.qml').exists())
        self.assertFalse(any(c[0]=='stop' for c in self.calls))

    def test_systemd_failure_preserves_files(self):
        base=self.legacy('bar')
        self.fail=lambda args: args[0]=='stop'
        with self.assertRaises(subprocess.CalledProcessError): m.uninstall(['bar'],False)
        self.assertTrue((base/'shell.qml').exists())

    def test_fresh_install_repeat_backup(self):
        m.install(); m.install()
        self.assertTrue((self.qml/'daevox-shell/shell.qml').exists())
        self.assertTrue((self.units/m.NEW).exists())
        self.assertTrue(list(self.qml.glob('daevox-shell-backup-*')))
        self.assertTrue(m.active(self.states[m.NEW]))
        self.assertFalse(list(self.qml.glob('.daevox-install-*')))

    def test_migrate_environment_and_cleanup(self):
        self.legacy('bar'); self.legacy('launcher')
        self.states['daevox-launcher.service']['Environment']='DAEVOX_NOTIFICATIONS=1 LANG=ru_RU.UTF-8 QML_IMPORT_PATH=/old/launcher'
        self.states['daevox-bar.service']['Environment']='QT_SCALE_FACTOR=1.25'
        self.states['daevox-launcher.service']['EnvironmentFiles']='/tmp/custom.env (ignore_errors=yes)'
        m.install()
        unit=(self.units/m.NEW).read_text()
        self.assertIn('DAEVOX_NOTIFICATIONS=1',unit)
        self.assertNotIn('DAEVOX_NOTIFICATIONS=0',unit)
        self.assertIn('QT_SCALE_FACTOR=1.25',unit)
        self.assertIn('EnvironmentFile="-/tmp/custom.env"',unit)
        self.assertNotIn('/old/launcher',unit)
        for name in m.LEGACY:
            self.assertFalse((self.qml/f'daevox-{name}/shell.qml').exists())
            self.assertFalse(m.enabled(self.states[f'daevox-{name}.service']))

    def test_manager_notification_opt_in_is_preserved(self):
        values, files=m.inherited_environment(self.states, 'DAEVOX_NOTIFICATIONS=1')
        self.assertEqual(values['DAEVOX_NOTIFICATIONS'],'1')
        self.states['daevox-launcher.service']['LoadState']='not-found'
        self.states[m.NEW]['LoadState']='not-found'
        values, files=m.inherited_environment(self.states, 'DAEVOX_NOTIFICATIONS=1')
        self.assertNotIn('DAEVOX_NOTIFICATIONS',values)

    def test_orphan_notification_dropin_is_inherited(self):
        dropin=self.units/'daevox-launcher.service.d'
        dropin.mkdir()
        (dropin/'notifications.conf').write_text('[Service]\nType=dbus\nEnvironment=DAEVOX_NOTIFICATIONS=1\n')
        self.states['daevox-launcher.service']['LoadState']='not-found'
        values, _=m.inherited_environment(self.states)
        self.assertEqual(values.get('DAEVOX_NOTIFICATIONS'),'1')
        self.states[m.NEW]['Environment']='DAEVOX_NOTIFICATIONS=0'
        values, _=m.inherited_environment(self.states)
        self.assertEqual(values.get('DAEVOX_NOTIFICATIONS'),'0')

    def test_notifications_stay_disabled(self):
        self.legacy('launcher'); m.install()
        self.assertIn('DAEVOX_NOTIFICATIONS=0',(self.units/m.NEW).read_text())

    def test_build_failure_never_stops_services(self):
        base=self.legacy('bar')
        with patch.object(m,'stage_runtime', side_effect=RuntimeError('build')):
            with self.assertRaisesRegex(RuntimeError,'build'): m.install()
        self.assertTrue((base/'shell.qml').exists())
        self.assertFalse(any(c[0]=='stop' for c in self.calls))

    def test_activation_failure_restores_legacy(self):
        self.legacy('bar'); self.legacy('launcher',active=False,enabled=False)
        with patch.object(m,'wait_ready',side_effect=RuntimeError('activation')):
            with self.assertRaisesRegex(RuntimeError,'activation'): m.install()
        self.assertTrue(m.active(self.states['daevox-bar.service']))
        self.assertTrue(m.enabled(self.states['daevox-bar.service']))
        self.assertFalse(m.active(self.states['daevox-launcher.service']))
        self.assertFalse(m.enabled(self.states['daevox-launcher.service']))
        self.assertFalse((self.units/m.NEW).exists())
        self.assertFalse((self.qml/'daevox-shell').exists())
        for name in m.LEGACY: self.assertTrue((self.qml/f'daevox-{name}/shell.qml').exists())

    def test_upgrade_failure_restores_previous_new_runtime(self):
        base=self.qml/'daevox-shell'; base.mkdir(); (base/'shell.qml').write_text('previous')
        (self.units/m.NEW).write_text('previous unit'); self.states[m.NEW]=info(True,True)
        with patch.object(m,'wait_ready',side_effect=RuntimeError('activation')):
            with self.assertRaises(RuntimeError): m.install()
        self.assertEqual((base/'shell.qml').read_text(),'previous')
        self.assertEqual((self.units/m.NEW).read_text(),'previous unit')
        self.assertTrue(m.active(self.states[m.NEW]))

    def test_no_graphical_session_no_changes(self):
        self.states['graphical-session.target']=info()
        with self.assertRaisesRegex(RuntimeError,'graphical session'): m.install()
        self.assertFalse(any(c[0]=='stop' for c in self.calls))

    def test_stopping_second_service_failure_restores_first(self):
        self.legacy('bar'); self.legacy('launcher')
        self.fail=lambda args: args==('stop','daevox-launcher.service')
        with self.assertRaises(subprocess.CalledProcessError): m.install()
        self.assertTrue(m.active(self.states['daevox-bar.service']))
        self.assertTrue(m.enabled(self.states['daevox-bar.service']))

    def test_orphan_activation_does_not_wait_for_disabled_notifications(self):
        for unit in ('daevox-bar.service','daevox-launcher.service',m.NEW):
            self.states[unit]['LoadState']='not-found'
        activation=self.home/'.local/share/dbus-1/services/notifications.service'
        activation.parent.mkdir(parents=True)
        activation.write_text('[D-BUS Service]\nName=org.freedesktop.Notifications\nSystemdService=daevox-launcher.service\n')
        m.install()
        self.assertTrue(m.active(self.states[m.NEW]))
        self.assertIn('DAEVOX_NOTIFICATIONS=0',(self.units/m.NEW).read_text())
        self.assertIn('Type=exec',(self.units/m.NEW).read_text())

    def test_activation_entry_migrates_and_rolls_back(self):
        activation=self.home/'.local/share/dbus-1/services/notifications.service'
        activation.parent.mkdir(parents=True)
        original='[D-BUS Service]\nName=org.freedesktop.Notifications\nExec=/usr/bin/systemctl --user start daevox-launcher.service\nSystemdService=daevox-launcher.service\n'
        activation.write_text(original)
        self.legacy('launcher')
        self.states['daevox-launcher.service']['Environment']='DAEVOX_NOTIFICATIONS=1'
        with patch.object(m,'wait_ready',side_effect=RuntimeError('activation')):
            with self.assertRaises(RuntimeError): m.install()
        self.assertEqual(activation.read_text(),original)
        m.install()
        self.assertIn('SystemdService=daevox-shell.service',activation.read_text())
        self.assertIn('Type=exec',(self.units/m.NEW).read_text())
        self.assertIn('BusName=org.freedesktop.Notifications',(self.units/m.NEW).read_text())
        self.assertIn('DAEVOX_NOTIFICATIONS=1',(self.units/m.NEW).read_text())

    def test_failed_recovery_stop_retains_live_and_backup(self):
        base=self.qml/'daevox-shell'; base.mkdir(); (base/'shell.qml').write_text('previous')
        (self.units/m.NEW).write_text('previous unit')
        self.fail=lambda args: args==('stop',m.NEW)
        with patch.object(m,'wait_ready',side_effect=RuntimeError('activation')):
            with self.assertRaises(RuntimeError): m.install()
        self.assertEqual((base/'shell.qml').read_text(),'new shell')
        backup=next(self.qml.glob('daevox-shell-recovery-*'))
        self.assertEqual((backup/'runtime/shell.qml').read_text(),'previous')
        self.assertEqual((backup/m.NEW).read_text(),'previous unit')

    def test_install_refuses_symlink_destination(self):
        outside=self.home/'outside'; outside.mkdir(); (self.qml/'daevox-shell').symlink_to(outside)
        with self.assertRaisesRegex(RuntimeError,'symbolic link'): m.install()


if __name__=='__main__': unittest.main()
