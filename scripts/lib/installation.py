#!/usr/bin/env python3
"""Transactional user installation and conservative manifest-based legacy cleanup."""
import argparse
import json
import os
import re
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HOME_DIR = Path.home()
CONFIG = HOME_DIR / '.config'
QML = CONFIG / 'quickshell'
UNITS = CONFIG / 'systemd/user'
NEW = 'daevox-shell.service'
LEGACY = ('bar', 'launcher')


def ctl(*args, check=True):
    if args[0] in ('stop', 'disable', 'daemon-reload', 'enable', 'restart', 'start'):
        print('systemctl --user ' + ' '.join(args), flush=True)
    return subprocess.run(['systemctl', '--user', *args], check=check,
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=25)


def state(unit):
    result = ctl('show', unit, '--property=LoadState,ActiveState,UnitFileState,MainPID,ControlGroup,Environment,EnvironmentFiles', check=False)
    properties = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    if result.returncode and properties.get('LoadState') != 'not-found':
        raise RuntimeError(result.stderr or f'Cannot inspect {unit}')
    if not properties.get('LoadState'):
        raise RuntimeError(f'Missing systemd state for {unit}')
    if properties.get('ActiveState') in ('activating', 'deactivating', 'reloading'):
        raise RuntimeError(f'{unit} is changing state; retry when it settles')
    return properties


def active(info):
    return info.get('ActiveState') == 'active'


def enabled(info):
    return info.get('UnitFileState') in ('enabled', 'enabled-runtime', 'linked', 'linked-runtime')


def no_symlink_parents(path):
    # Never traverse a user-controlled symlink while changing an installation.
    for parent in [path, *path.parents]:
        if parent == HOME_DIR.parent:
            break
        if parent.is_symlink():
            raise RuntimeError(f'Refusing to traverse symbolic link: {parent}')


def manual_instances(name, info):
    """Match exact config paths/names; never kill by process name."""
    config = QML / f'daevox-{name}'
    found = []
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            executable = (proc / 'exe').resolve().name
            if executable not in ('qs', 'quickshell'):
                continue
            args = (proc / 'cmdline').read_bytes().decode().split('\0')
            if any(arg in ('ipc', 'log', 'list', 'kill', 'msg') for arg in args[1:2]):
                continue
            environ = dict(entry.split('=', 1) for entry in (proc / 'environ').read_bytes().decode().split('\0') if '=' in entry)
            paths = [environ.get('QS_CONFIG_PATH', '')]
            names = [environ.get('QS_CONFIG_NAME', '')]
            for i, arg in enumerate(args):
                if arg in ('--path', '-p') and i + 1 < len(args): paths.append(args[i + 1])
                if arg.startswith('--path='): paths.append(arg.split('=', 1)[1])
                if arg in ('--config', '-c') and i + 1 < len(args): names.append(args[i + 1])
                if arg.startswith('--config='): names.append(arg.split('=', 1)[1])
                if arg.startswith('-p') and not arg.startswith('--') and len(arg) > 2: paths.append(arg[2:])
                if arg.startswith('-c') and not arg.startswith('--') and len(arg) > 2: names.append(arg[2:])
            cwd = (proc / 'cwd').resolve()
            match = f'daevox-{name}' in names
            for value in paths:
                if value:
                    target = (cwd / value).resolve()
                    match |= target in (config.resolve(), (config / 'shell.qml').resolve())
            if not match:
                continue
            group = info.get('ControlGroup', '')
            groups = [line.split(':', 2)[-1] for line in (proc / 'cgroup').read_text().splitlines()]
            managed = proc.name == info.get('MainPID') or (group and any(g == group or g.startswith(group + '/') for g in groups))
            if not managed: found.append(proc.name)
        except (FileNotFoundError, ProcessLookupError):
            continue
    return found


def check_manual(names, states):
    for name in names:
        pids = manual_instances(name, states[f'daevox-{name}.service'])
        if pids:
            raise RuntimeError(f'Manually running daevox-{name}: PID {", ".join(pids)}. Stop these instances and retry; their files were preserved.')


def owned_paths(name):
    base = QML / f'daevox-{name}'
    for entry in (ROOT / f'scripts/manifests/legacy-{name}.txt').read_text().splitlines():
        relative = Path(entry)
        if relative.is_absolute() or '..' in relative.parts:
            raise RuntimeError(f'Unsafe manifest entry: {entry}')
        path = base / relative
        # Keep everything underneath a symlinked directory, including its target.
        if any(parent.is_symlink() for parent in [base, *list(path.parents)[:len(relative.parts)-1]]):
            continue
        if path.is_symlink() or path.is_file():
            yield path


def report_preserved(names):
    for name in names:
        for base in (QML / f'daevox-{name}', UNITS / f'daevox-{name}.service.d'):
            if base.is_symlink(): print(f'Preserved: {base}')
            elif base.exists():
                for directory, dirs, files in os.walk(base, followlinks=False):
                    for entry in sorted(files + [d for d in dirs if (Path(directory)/d).is_symlink()]):
                        print(f'Preserved: {Path(directory)/entry}')
    print(f'Preserved shared theme: {QML / "shared"}')
    print('Notification history and user settings are preserved.')
    print('Update Hyprland manually: remove old daevox-bar/daevox-launcher autostarts; replace IPC paths with ~/.config/quickshell/daevox-shell/shell.qml.')


def cleanup_files(names, dry=False):
    for name in names:
        for path in [*owned_paths(name), UNITS / f'daevox-{name}.service']:
            if path.is_file() or path.is_symlink():
                print(f'Remove: {path}')
                if not dry: path.unlink()
        base = QML / f'daevox-{name}'
        if not dry and base.is_dir() and not base.is_symlink():
            directories = {base}
            for entry in (ROOT / f'scripts/manifests/legacy-{name}.txt').read_text().splitlines():
                parent = (base / entry).parent
                while parent != base:
                    directories.add(parent)
                    parent = parent.parent
            for path in sorted(directories, key=lambda p: len(p.parts), reverse=True):
                if any(parent.is_symlink() for parent in [path, *path.parents]): continue
                if path.is_dir() and not any(path.iterdir()): path.rmdir()
    report_preserved(names)


def stop_disable(unit, info, dry=False):
    if active(info):
        print(f'Stop: {unit}')
        if not dry: ctl('stop', unit)
    if enabled(info):
        print(f'Disable: {unit}')
        if not dry: ctl('disable', unit)


def uninstall(names, dry):
    for path in (QML, UNITS): no_symlink_parents(path)
    states = {f'daevox-{n}.service': state(f'daevox-{n}.service') for n in names}
    check_manual(names, states)
    for unit, info in states.items(): stop_disable(unit, info, dry)
    if not dry:
        # A process started concurrently must also block deletion.
        check_manual(names, {unit: state(unit) for unit in states})
    cleanup_files(names, dry)
    print('Reload systemd user units')
    if not dry: ctl('daemon-reload')


def replace_file(path, content):
    """Do not truncate existing settings if a write fails midway."""
    descriptor, temporary = tempfile.mkstemp(prefix='.daevox-write-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, (path.stat().st_mode & 0o777) if path.exists() else 0o600)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def activation_changes():
    """Retarget only a known notification activation entry owned by the old shell."""
    data = Path(os.environ.get('XDG_DATA_HOME', HOME_DIR / '.local/share'))
    changes = []
    directory = data / 'dbus-1/services'
    if not directory.exists(): return changes
    no_symlink_parents(directory)
    for path in directory.glob('*.service'):
        if path.is_symlink(): continue
        original = path.read_bytes()
        content = original.decode()
        if re.search(r'^Name=org\.freedesktop\.Notifications\s*$', content, re.M) and re.search(r'^SystemdService=daevox-(?:launcher|shell)\.service\s*$', content, re.M):
            changes.append((path, original, content.replace('daevox-launcher.service', NEW).encode()))
    return changes


def quote_environment(value):
    # systemd unit quoting; literal percent must not become a specifier.
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%').replace('\n', '\\n').replace('\r', '\\r') + '"'


def orphan_notification_setting(unit):
    """Recover the explicit opt-in retained by uninstall-legacy after unit removal."""
    setting = None
    for path in sorted((UNITS / (unit + '.d')).glob('*.conf')):
        section = ''
        content = path.read_text().replace('\\\n', ' ')
        for raw in content.splitlines():
            line = raw.strip()
            if not line or line.startswith(('#', ';')): continue
            if line.startswith('['):
                section = line
                continue
            if section != '[Service]' or '=' not in line: continue
            key, value = line.split('=', 1)
            if key.strip() == 'Environment':
                entries = shlex.split(value)
                if not entries: setting = None
                for entry in entries:
                    if entry.startswith('DAEVOX_NOTIFICATIONS='):
                        setting = entry.split('=', 1)[1]
            elif key.strip() == 'UnsetEnvironment':
                if 'DAEVOX_NOTIFICATIONS' in shlex.split(value): setting = None
    return setting


def inherited_environment(states, manager_environment=''):
    values = {}
    # User units inherit the manager environment even without PassEnvironment.
    # Preserve a previous notification opt-in supplied there, but do not enable
    # notifications for a clean installation merely because it is set globally.
    if any(states[unit].get('LoadState') == 'loaded' for unit in ('daevox-launcher.service', NEW)):
        for entry in shlex.split(manager_environment):
            if entry.startswith('DAEVOX_NOTIFICATIONS='):
                values['DAEVOX_NOTIFICATIONS'] = entry.split('=', 1)[1]
    files = []
    for unit in ('daevox-bar.service', 'daevox-launcher.service', NEW):
        info = states[unit]
        if unit != NEW and info.get('LoadState') == 'not-found':
            previous = orphan_notification_setting(unit)
            if previous is not None: values['DAEVOX_NOTIFICATIONS'] = previous
        for entry in shlex.split(info.get('Environment', '')):
            if '=' in entry:
                key, value = entry.split('=', 1)
                if key != 'QML_IMPORT_PATH': values[key] = value
        # Preserve external EnvironmentFiles, including optional missing files.
        import re
        source = info.get('EnvironmentFiles', '')
        matches = list(re.finditer(r'(\S+) \(ignore_errors=(yes|no)\)', source))
        if source and not matches:
            raise RuntimeError('Cannot safely interpret EnvironmentFiles: ' + source)
        for match in matches:
            path, optional = match.groups()
            path = path.replace('\\x20', ' ')
            if any(str(QML / f'daevox-{n}') in path for n in LEGACY):
                raise RuntimeError(f'EnvironmentFile is inside legacy runtime; move it outside before migration: {path}')
            value = ('-' if optional == 'yes' else '') + path
            if value not in files: files.append(value)
    return values, files


def stage_runtime(destination):
    destination.mkdir()
    shutil.copy2(ROOT / 'shell.qml', destination)
    for directory in ('desktop', 'bar', 'launcher', 'launcher/audio', 'notifications', 'shared'):
        target = destination / directory
        target.mkdir(parents=True, exist_ok=True)
        for source in (ROOT / directory).iterdir():
            if source.is_file() and (source.suffix in ('.qml', '.js', '.svg') or source.name == 'qmldir'):
                shutil.copy2(source, target / source.name)
    module = destination / 'Daevox/Notifications'
    module.mkdir(parents=True)
    subprocess.run(['bash', str(ROOT / 'native/notifications/build.sh'), str(module)], check=True)
    shutil.copy2(ROOT / 'Daevox/Notifications/qmldir', module)
    shutil.copy2(ROOT / 'native/notifications/lock.xml', module / 'lock-protocol-license.xml')
    # Parse every component before touching live services. No QML is instantiated.
    qmlfiles = sorted(str(p) for p in destination.rglob('*.qml'))
    result = subprocess.run(['/usr/lib/qt6/bin/qmllint', '--ignore-settings', '-I', '/usr/lib/qt6/qml', '-I', str(destination), *qmlfiles], text=True, capture_output=True)
    if result.returncode not in (0, 255) or re.search(r'(?m)^Error:', result.stdout + result.stderr):
        raise RuntimeError('QML validation failed:\n' + result.stdout + result.stderr)


def wait_ready(destination):
    until = time.monotonic() + 10
    last = ''
    while time.monotonic() < until:
        try:
            result = subprocess.run(['qs', 'ipc', '--path', str(destination / 'shell.qml'), 'call', 'launcher', 'status'], text=True, capture_output=True, timeout=2)
        except subprocess.TimeoutExpired:
            last = 'Launcher IPC timed out'
            continue
        if result.returncode == 0:
            try:
                status = json.loads(result.stdout)
                if isinstance(status.get('visible'), bool) and 'applications' in status:
                    if status.get('notifications') is not None and not status['notifications'].get('ready'):
                        last = 'Notification endpoint is not ready'
                    else:
                        # Require the process to survive after IPC first becomes available.
                        time.sleep(.5)
                        if active(state(NEW)): return
            except (ValueError, AttributeError): pass
        last = last or result.stderr
        time.sleep(.1)
    raise RuntimeError('New shell failed readiness check: ' + last)


def install():
    for command in ('qs', '/usr/lib/qt6/bin/qmllint', 'systemctl', 'cc', 'c++', 'pkg-config', 'wayland-scanner'):
        if not shutil.which(command): raise RuntimeError('Missing dependency: ' + command)
    destination = QML / 'daevox-shell'
    unit_path = UNITS / NEW
    for path in (destination, unit_path, UNITS / (NEW + '.d')): no_symlink_parents(path)
    manager_environment = ctl('show-environment').stdout
    states = {unit: state(unit) for unit in ('daevox-bar.service', 'daevox-launcher.service', NEW)}
    check_manual((*LEGACY, 'shell'), states)
    if not active(state('graphical-session.target')):
        raise RuntimeError('Run installation in an active graphical session so activation can be verified before removing legacy files.')
    values, files = inherited_environment(states, manager_environment)
    activations = activation_changes()
    QML.mkdir(parents=True, exist_ok=True)
    UNITS.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.daevox-install-', dir=QML) as temporary:
        work = Path(temporary)
        staged = work / 'runtime'
        stage_runtime(staged)
        template = (ROOT / 'docs/examples/daevox-shell.service').read_text()
        if activations:
            # Notification ownership is optional; never gate shell startup on it.
            template = template.replace('Type=exec', 'Type=exec\nBusName=org.freedesktop.Notifications')
        settings = ''.join('Environment=' + quote_environment(k + '=' + v) + '\n' for k, v in sorted(values.items()))
        settings += ''.join('EnvironmentFile=' + quote_environment(v) + '\n' for v in files)
        template = template.replace('[Service]\n', '[Service]\n' + settings)
        # Inherited explicit notification settings must override the disabled default.
        template = template.replace('Environment=DAEVOX_NOTIFICATIONS=0\n', '') if 'DAEVOX_NOTIFICATIONS' in values else template
        old_unit = unit_path.read_bytes() if unit_path.exists() else None
        recovery = Path(tempfile.mkdtemp(prefix='daevox-shell-backup-', dir=QML))
        old_runtime = recovery / 'runtime'
        print(f'Recovery settings: {recovery}')
        (recovery / 'services.json').write_text(json.dumps(states, indent=2))
        if old_unit is not None: (recovery / NEW).write_bytes(old_unit)
        for index, (path, original, updated) in enumerate(activations):
            (recovery / f'activation-{index}.service').write_bytes(original)
        (recovery / 'activation-paths.json').write_text(json.dumps([str(p) for p, _, _ in activations]))
        changed_runtime = False
        changed_unit = False
        touched = []
        changed_activations = []
        try:
            # All expensive or fallible preparation above happens before the first stop.
            check_manual((*LEGACY, 'shell'), states)
            for unit, info in states.items():
                touched.append(unit)
                stop_disable(unit, info)
            check_manual((*LEGACY, 'shell'), {unit: state(unit) for unit in states})
            if destination.exists(): destination.rename(old_runtime)
            changed_runtime = True
            staged.rename(destination)
            replace_file(unit_path, template.encode())
            changed_unit = True
            for path, original, updated in activations:
                changed_activations.append((path, original))
                replace_file(path, updated)
            ctl('daemon-reload')
            ctl('enable', NEW)
            ctl('restart', NEW)
            print('Checking launcher IPC readiness…', flush=True)
            wait_ready(destination)
        except BaseException:
            failures = []
            def restore_call(*args):
                try: ctl(*args)
                except Exception as error: failures.append(str(error))
            if changed_runtime:
                restore_call('stop', NEW)
                if failures:
                    # A failed stop means files may still be in use. Keep both copies.
                    backup = Path(tempfile.mkdtemp(prefix='daevox-shell-recovery-', dir=QML))
                    if old_runtime.exists(): old_runtime.rename(backup / 'runtime')
                    if old_unit is not None: (backup / NEW).write_bytes(old_unit)
                    for index, (path, original) in enumerate(changed_activations):
                        (backup / f'activation-{index}.service').write_bytes(original)
                    print(f'Recovery requires attention; live files retained, previous files: {backup}', file=sys.stderr)
                    raise
                try:
                    if destination.exists(): shutil.rmtree(destination)
                    if old_runtime.exists(): old_runtime.rename(destination)
                except OSError as error:
                    backup = Path(tempfile.mkdtemp(prefix='daevox-shell-recovery-', dir=QML))
                    if old_runtime.exists(): old_runtime.rename(backup / 'runtime')
                    recovery.rename(backup / 'settings')
                    print(f'Could not restore runtime: {error}. Previous files retained: {backup}', file=sys.stderr)
                    raise
            for path, original in changed_activations:
                try: replace_file(path, original)
                except OSError as error: failures.append(str(error))
            if changed_unit:
                restore_call('disable', NEW)
                if old_unit is None: unit_path.unlink(missing_ok=True)
                else: replace_file(unit_path, old_unit)
            restore_call('daemon-reload')
            for unit in touched:
                if enabled(states[unit]):
                    runtime = states[unit].get('UnitFileState', '').endswith('-runtime')
                    restore_call('enable', *(['--runtime'] if runtime else []), unit)
                if active(states[unit]): restore_call('start', unit)
            if failures: print('Recovery requires attention: ' + '; '.join(failures), file=sys.stderr)
            raise
        # Preserve unknown files from a previous unified installation in a visible backup.
        if old_runtime.exists():
            print(f'Previous unified runtime preserved: {old_runtime}')
        check_manual(LEGACY, {unit: state(unit) for unit in states})
        for name in LEGACY:
            if active(state(f'daevox-{name}.service')):
                raise RuntimeError(f'Legacy service daevox-{name} restarted during migration; files preserved')
        cleanup_files(LEGACY)
        ctl('daemon-reload')
    print('Daevox Shell installed and verified through launcher IPC.')


def main():
    parser = argparse.ArgumentParser(description='Install unified Daevox Shell or remove legacy modules. Run as your regular user, without sudo, from any directory.')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('install', description='Build, validate, activate and migrate Daevox Shell in an active graphical session. Run without sudo, from any directory.')
    remove = commands.add_parser('uninstall', description='Remove only known legacy files; preserve history, shared theme and user files. Run without sudo, from any directory.')
    remove.add_argument('module', choices=(*LEGACY, 'all'))
    remove.add_argument('--dry-run', action='store_true', help='Show planned changes without modifying files or services.')
    args = parser.parse_args()
    if os.geteuid() == 0: raise RuntimeError('Run as your regular user, without sudo.')
    if args.command == 'install': install()
    else: uninstall(LEGACY if args.module == 'all' else [args.module], args.dry_run)


if __name__ == '__main__':
    try: main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f'Error: {error}', file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr: print(error.stderr, file=sys.stderr)
        sys.exit(1)
