"""Exercise the migration's real file edits and rollback without touching services."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('migration',ROOT/'scripts/notification-migration.py')
migration=importlib.util.module_from_spec(spec); spec.loader.exec_module(migration)

class Migration(unittest.TestCase):
    def test_apply_rollback_and_drift(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            targets=[root/'hyprland.lua',root/'notifications.conf',root/'activation.service']
            original='hl.on("start", function()\n    hl.exec_cmd("mako")\n    hl.exec_cmd("hypridle")\nend)\n'
            targets[0].write_text(original)
            targets[2].write_text('previous activation\n')
            shell=root/'daevox-shell/shell.qml'
            (shell.parent/'Daevox/Notifications').mkdir(parents=True)
            (shell.parent/'Daevox/Notifications/libdaevoxnotifications.so').touch()
            def run(*args):
                if 'MainPID' in ' '.join(args): return '123'
                if args[0]=='qs': return json.dumps({'notifications':{'ready':True}})
                return ''
            with patch.multiple(migration,TARGETS=targets,STATE=root,SHELL=shell), \
                patch.object(migration,'run',side_effect=run), \
                patch.object(migration,'bus',return_value=''), \
                patch.object(migration,'owner_pid',return_value=123), \
                patch.object(migration,'executable',return_value='mako'), \
                patch.object(migration.os,'kill') as kill, \
                patch.object(migration.subprocess,'run') as subprocess_run:
                subprocess_run.return_value.returncode=0
                migration.apply()
                self.assertNotIn('exec_cmd("mako")',targets[0].read_text())
                self.assertIn('exec_cmd("hypridle")',targets[0].read_text())
                self.assertIn('DAEVOX_NOTIFICATIONS=1',targets[1].read_text())
                kill.assert_called_once()
                backup=next((root/'daevox/notification-migration').iterdir())
                changed=targets[0].read_text()
                targets[0].write_text(changed+'-- user edit\n')
                with self.assertRaisesRegex(RuntimeError,'File changed'): migration.restore(backup)
                targets[0].write_text(changed)
                migration.restore(backup)
                self.assertEqual(targets[0].read_text(),original)
                self.assertFalse(targets[1].exists())
                self.assertEqual(targets[2].read_text(),'previous activation\n')

if __name__=='__main__': unittest.main()
