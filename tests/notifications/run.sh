#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
if [[ ${1:-} == --wayland ]]; then
    display_path=${WAYLAND_DISPLAY:?WAYLAND_DISPLAY is required}
    if [[ "$display_path" != /* ]]; then display_path="${XDG_RUNTIME_DIR:?}/$display_path"; fi
    export DAEVOX_UI_WAYLAND="$display_path"
fi
test_runtime=$(mktemp -d /tmp/daevox-notification-bus.XXXXXX)
# No service directories: even a readiness query cannot auto-activate mako.
cat > "$test_runtime/bus.conf" <<CONF
<busconfig><type>session</type><listen>unix:tmpdir=$test_runtime</listen>
<policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy>
</busconfig>
CONF
exec env XDG_RUNTIME_DIR="$test_runtime" dbus-run-session --config-file "$test_runtime/bus.conf" -- env DAEVOX_ISOLATED_TEST=1 python3 "$project_dir/tests/notifications/integration.py"
