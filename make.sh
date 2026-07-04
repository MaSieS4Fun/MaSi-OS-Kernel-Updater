#!/usr/bin/env bash
# Kernel_MaSi-OS — compile gaming kernel + ABL bootimg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT

exec "${ROOT}/lib/kbuild.sh" "$@"
