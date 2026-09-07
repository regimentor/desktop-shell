#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# An isolated bus cannot activate or replace the user's notification daemon.
test_runtime=$(mktemp -d /tmp/daevox-shell-bus.XXXXXX)
cat > "$test_runtime/bus.conf" <<CONF
<busconfig><type>session</type><listen>unix:tmpdir=$test_runtime</listen>
<policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy>
</busconfig>
CONF
export DAEVOX_TEST_WAYLAND=${WAYLAND_DISPLAY:?Run in a graphical session}
if [[ "$DAEVOX_TEST_WAYLAND" != /* ]]; then export DAEVOX_TEST_WAYLAND="$XDG_RUNTIME_DIR/$DAEVOX_TEST_WAYLAND"; fi
export DAEVOX_TEST_HYPR_DIR="$XDG_RUNTIME_DIR/hypr"
exec env XDG_RUNTIME_DIR="$test_runtime" dbus-run-session --config-file "$test_runtime/bus.conf" -- env DAEVOX_ISOLATED_TEST=1 python3 "$project_dir/tests/shell/integration.py" "$@"
