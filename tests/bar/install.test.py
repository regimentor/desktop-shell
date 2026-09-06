"""Run the actual installers twice in a private filesystem with a fake user manager."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='daevox-install-') as directory:
    stage = Path(directory)
    config = stage / 'config'
    config.mkdir()
    bin_dir = stage / 'bin'
    bin_dir.mkdir()
    (bin_dir / 'systemctl').write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$HOME/.config/systemctl.log"
exit 0
''')
    (bin_dir / 'systemctl').chmod(0o755)
    (config / 'quickshell/shared').mkdir(parents=True)
    (config / 'quickshell/shared/foreign.txt').write_text('preserve me')
    for _ in range(2):
        for name in ['launcher', 'bar']:
            result = subprocess.run(['bwrap', '--die-with-parent', '--ro-bind', '/', '/',
                '--dev', '/dev', '--bind', str(config), str(Path.home() / '.config'), '--tmpfs', '/tmp',
                '--ro-bind', str(bin_dir), '/tmp/daevox-test-bin',
                '--setenv', 'PATH', '/tmp/daevox-test-bin:' + os.environ['PATH'],
                '--chdir', '/tmp', 'bash', str(ROOT / f'install-{name}.sh')],
                capture_output=True, text=True)
            assert result.returncode == 0, result.stdout + result.stderr
    for name in ['launcher', 'bar']:
        runtime = config / 'quickshell' / f'daevox-{name}'
        assert (runtime / 'shell.qml').is_file()
        assert (runtime / 'shared').is_symlink()
        assert (runtime / 'shared/DaevoxTheme.qml').read_bytes() == (ROOT / 'shared/DaevoxTheme.qml').read_bytes()
        assert not (runtime / 'prototype').exists()
        for source in (ROOT / name).iterdir():
            if source.suffix not in ('.qml', '.js', '.svg'):
                continue
            assert (runtime / source.name).read_bytes() == source.read_bytes()
        assert (config / f'systemd/user/daevox-{name}.service').is_file()
    assert (config / 'quickshell/shared/foreign.txt').read_text() == 'preserve me'
    assert not list(config.rglob('.install-*'))
    print('PASS installers: arbitrary cwd, repeat install, both runtimes/units, shared theme/link, foreign shared files, no prototypes')
