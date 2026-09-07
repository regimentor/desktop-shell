#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_dir=$(mktemp -d /tmp/daevox-bar-ui.XXXXXX)
for module in bar desktop shared; do cp -r "$project_dir/$module" "$test_dir/$module"; done
for name in "${@:-ui dense interaction}"; do
    for test_name in $name; do
        case "$test_name" in ui|dense|interaction|commands) ;; *) exit 2;; esac
        sed -e 's|"runtime/StateModel.js"|"desktop/StateModel.js"|' -e 's|"runtime"|"bar"|' "$project_dir/tests/bar/$test_name.qml" > "$test_dir/shell.qml"
        timeout 10 qs --no-color --log-rules quickshell.io.socket.warning=false --path "$test_dir/shell.qml" > "$test_dir/$test_name.log" 2>&1
        cat "$test_dir/$test_name.log"
        if grep -E 'FAIL|TypeError|ReferenceError|Binding loop|Unable to assign' "$test_dir/$test_name.log"; then exit 1; fi
        grep -Eq 'PASS|UI_READY' "$test_dir/$test_name.log"
    done
done
printf 'Bar UI logs: %s\n' "$test_dir"
