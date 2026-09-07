#!/usr/bin/env bash
# Both public CLIs use the same manifest, process detection and cleanup implementation.
daevox_installation_cli() {
    local library_dir
    library_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    python3 "$library_dir/installation.py" "$@"
}
