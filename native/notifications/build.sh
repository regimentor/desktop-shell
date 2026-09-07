#!/usr/bin/env bash
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
output_dir=${1:?Usage: build.sh OUTPUT_DIRECTORY}
mkdir -p -- "$output_dir"
output_dir=$(cd -- "$output_dir" && pwd)
build_dir=$(mktemp -d /tmp/daevox-notifications-build.XXXXXX)
trap 'rm -rf -- "$build_dir"' EXIT
wayland-scanner client-header "$source_dir/lock.xml" "$build_dir/lock-client.h"
wayland-scanner private-code "$source_dir/lock.xml" "$build_dir/lock-protocol.c"
moc_path=$(pkg-config --variable=libexecdir Qt6Core)/moc
"$moc_path" $(pkg-config --cflags Qt6Qml Qt6Quick Qt6DBus) "$source_dir/plugin.cpp" -o "$build_dir/plugin.moc"
cc -fPIC -c "$build_dir/lock-protocol.c" -o "$build_dir/lock.o" $(pkg-config --cflags wayland-client)
c++ -std=c++17 -Wall -Wextra -Werror -fPIC -shared -I"$build_dir" \
    "$source_dir/plugin.cpp" "$build_dir/lock.o" \
    $(pkg-config --cflags --libs Qt6Quick Qt6Qml Qt6DBus wayland-client) \
    -o "$output_dir/libdaevoxnotifications.so"
