#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$project_dir/scripts/lib/legacy-installation.sh"
daevox_installation_cli install "$@"
