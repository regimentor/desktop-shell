#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    cat <<'HELP'
Usage: ./install-launcher.sh

Install or update the launcher in ~/.config/quickshell/daevox-launcher.
Enable its systemd user service and restart it if the graphical session is active.
Run as your regular user, without sudo. May be run from any directory.
Stop any manually launched copy of the installed configuration first.
HELP
    exit 0
fi
if (( $# > 0 )); then
    printf 'Unknown argument: %s\nUse --help for usage.\n' "$1" >&2
    exit 2
fi
if (( EUID == 0 )); then
    printf 'Run this script as your regular user, without sudo.\n' >&2
    exit 1
fi

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
launcher_dir="$HOME/.config/quickshell/daevox-launcher"
unit_dir="$HOME/.config/systemd/user"
unit=daevox-launcher.service
shared_dir="$HOME/.config/quickshell/shared"
# Install every runtime component, including newly added local QML types.
shopt -s nullglob
sources=("$project_dir"/launcher/*.qml "$project_dir"/launcher/*.js)
files=()
for source in "${sources[@]}"; do files+=("${source##*/}"); done

for dependency in qs uwsm systemctl install mktemp mv ln; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        printf 'Missing dependency: %s\n' "$dependency" >&2
        printf 'On Arch: sudo pacman -Syu --needed quickshell qt6-declarative qt6-svg uwsm ghostty\n' >&2
        exit 1
    fi
done
for file in DaevoxTheme.qml qmldir; do
    [[ -r "$project_dir/shared/$file" ]] || { printf "Missing shared source: %s\n" "$file" >&2; exit 1; }
done
if [[ -e "$launcher_dir/shared" && ! -L "$launcher_dir/shared" ]]; then
    printf "Refusing to replace existing directory: %s/shared\n" "$launcher_dir" >&2
    exit 1
fi
for file in "${files[@]}"; do
    [[ -r "$project_dir/launcher/$file" ]] || {
        printf 'Missing source: %s\n' "$project_dir/launcher/$file" >&2
        exit 1
    }
done
[[ -r "$project_dir/docs/examples/$unit" ]] || {
    printf 'Missing service template: %s\n' "$project_dir/docs/examples/$unit" >&2
    exit 1
}

# Check the user manager before changing the installed configuration.
systemctl --user show-environment >/dev/null
install -d -- "$launcher_dir" "$unit_dir" "$shared_dir"
stage_dir=$(mktemp -d "$launcher_dir/.install-XXXXXX")
trap 'rm -rf -- "$stage_dir"' EXIT

for file in "${files[@]}"; do
    install -m644 -- "$project_dir/launcher/$file" "$stage_dir/$file"
done
# Quickshell replaces the source .qmlls.ini with a runtime symlink. Generate a
# portable copy so installation also works when that runtime tree is gone.
cat > "$stage_dir/.qmlls.ini" <<'INI'
[General]
buildDir=/usr/lib/qt6/qml
importPaths=/usr/lib/qt6/qml
INI
chmod 644 "$stage_dir/.qmlls.ini"

# Avoid a running service reloading a partially updated set of QML files.
if systemctl --user is-active --quiet "$unit"; then
    systemctl --user stop "$unit"
fi
for file in DaevoxTheme.qml qmldir; do
    shared_stage=$(mktemp "$shared_dir/.install-XXXXXX")
    install -m644 -- "$project_dir/shared/$file" "$shared_stage"
    mv -fT -- "$shared_stage" "$shared_dir/$file"
done
ln -sfnT -- ../shared "$launcher_dir/shared"
for file in "${files[@]}" .qmlls.ini; do
    mv -fT -- "$stage_dir/$file" "$launcher_dir/$file"
done
install -m644 -- "$project_dir/docs/examples/$unit" "$unit_dir/$unit"
systemctl --user daemon-reload
systemctl --user enable "$unit"

if systemctl --user is-active --quiet graphical-session.target; then
    systemctl --user reset-failed "$unit"
    systemctl --user restart "$unit"
    systemctl --user is-active --quiet "$unit" || {
        printf 'Service did not stay active. Check: journalctl --user -u %s -b\n' "$unit" >&2
        exit 1
    }
    printf 'Launcher installed and started (hidden).\n'
else
    printf 'Launcher installed. It will start with the next graphical session.\n'
fi

cat <<'NEXT'

Add this bind to your Hyprland Lua config, then run hyprctl reload:

hl.bind("SUPER + Space", hl.dsp.exec_cmd(
    'qs ipc --path "$HOME/.config/quickshell/daevox-launcher/shell.qml" call launcher toggle'
))

Toggle manually:
  qs ipc --path "$HOME/.config/quickshell/daevox-launcher/shell.qml" call launcher toggle

For Terminal=true entries, put com.mitchellh.ghostty.desktop first in
~/.config/xdg-terminals.list. The interface uses the system Monoid font.
NEXT
