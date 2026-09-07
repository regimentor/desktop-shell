#!/usr/bin/env bash
set -euo pipefail
# Run inside dbus-run-session. No hardware monitors, user state, or live audio.
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_dir=$(mktemp -d /tmp/daevox-audio-test.XXXXXX)
export PIPEWIRE_RUNTIME_DIR="$test_dir"
export XDG_CONFIG_HOME="$test_dir/config"
export XDG_STATE_HOME="$test_dir/state"
export XDG_CACHE_HOME="$test_dir/cache"
export PIPEWIRE_CONFIG_DIR="$test_dir/pipewire"
export DAEVOX_AUDIO_TEST_DIR="$test_dir"
mkdir -p "$PIPEWIRE_CONFIG_DIR/pipewire.conf.d" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
cp /usr/share/pipewire/*.conf "$PIPEWIRE_CONFIG_DIR/"
cat > "$PIPEWIRE_CONFIG_DIR/pipewire.conf.d/test.conf" <<'CONF'
context.objects = [
 { factory = adapter args = { factory.name = support.null-audio-sink node.name = test-a node.description = "Test Speakers" media.class = Audio/Sink audio.position = [ FL FR ] } }
 { factory = adapter args = { factory.name = support.null-audio-sink node.name = test-b node.description = "Test Headphones" media.class = Audio/Sink audio.position = [ FL FR ] } }
]
CONF
pids=()
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    wait || true
    printf 'Test logs: %s\n' "$test_dir"
}
trap cleanup EXIT
pipewire >"$test_dir/pipewire.log" 2>&1 &
pids+=("$!")
for ((i=0; i<50; i++)); do [[ -S "$test_dir/pipewire-0" ]] && break; sleep 0.1; done
wireplumber --profile policy >"$test_dir/wireplumber.log" 2>&1 &
pids+=("$!")
for ((i=0; i<50; i++)); do
    if pw-metadata -l 2>/dev/null | grep -q 'Found "default" metadata'; then break; fi
    sleep 0.1
done
pw-play --raw --rate 48000 --channels 2 --target test-a -P '{ application.id = "daevox.test" application.name = "Audio Test" media.name = "First stream" }' /dev/zero >"$test_dir/stream-a.log" 2>&1 &
pids+=("$!")
pw-play --raw --rate 48000 --channels 2 --target test-a -P '{ application.id = "daevox.test" application.name = "Audio Test" media.name = "Second stream" }' /dev/zero >"$test_dir/stream-b.log" 2>&1 &
pids+=("$!")
# Model tests work offscreen; the ui argument tests the real Wayland window.
test_source=shell.qml
if [[ ${1:-} == ui ]]; then test_source=ui.qml; else export QT_QPA_PLATFORM=offscreen; fi
mkdir -p "$test_dir/qml"
for module in shared launcher desktop notifications; do
    cp -r "$project_dir/$module" "$test_dir/qml/$module"
done
sed 's|"../../|"|g' "$project_dir/tests/audio/$test_source" > "$test_dir/qml/shell.qml"
result=0
timeout 35 qs --path "$test_dir/qml/shell.qml" --no-color >"$test_dir/test.log" 2>&1 || result=$?
cat "$test_dir/test.log"
(( result == 0 )) || exit "$result"
grep -Eq 'AUDIO (INTEGRATION|UI) PASS' "$test_dir/test.log"
if grep -E 'TypeError|ReferenceError|Binding loop|FAIL' "$test_dir/test.log"; then exit 1; fi
