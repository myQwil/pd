#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"

# Staging
DESTDIR=build zig build -p "$PREFIX" "$@"

# Generate manifest (in case you want to uninstall later)
find build -type f -printf '/%P\n' > install_manifest.txt

# Copy to prefix path. Invoke sudo if current user doesn't own prefix.
my_uid=$(id -u)
check_dir=$( [[ -d "$PREFIX" ]] && echo "$PREFIX" || dirname "$PREFIX" )
if [[ $(stat -c '%u' "$check_dir") -ne $my_uid ]]; then
    sudo rsync -a --chown=root:root "build/$PREFIX/" "$PREFIX"
else
    rsync -a "build/$PREFIX/" "$PREFIX"
fi
