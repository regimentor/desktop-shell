#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_dir=$(mktemp -d /tmp/daevox-launcher-motion.XXXXXX)
for module in launcher shared notifications; do cp -r "$project_dir/$module" "$test_dir/$module"; done
sed 's|"../../launcher"|"launcher"|' "$project_dir/tests/launcher/motion.qml" > "$test_dir/shell.qml"
result=0
timeout 10 qs --no-color --log-rules quickshell.io.socket.warning=false --path "$test_dir/shell.qml" > "$test_dir/motion.log" 2>&1 || result=$?
cat "$test_dir/motion.log"
if (( result != 0 )); then exit "$result"; fi
if rg 'FAIL|TypeError|ReferenceError|Binding loop|Unable to assign|Error:' "$test_dir/motion.log"; then exit 1; fi
rg -q 'MOTION_PASS' "$test_dir/motion.log"
