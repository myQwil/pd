#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"

# Staging
DESTDIR=install zig build -p "$PREFIX" "$@"

# Generate manifest (in case you want to uninstall later)
find install -type f -printf '/%P\n' > install_manifest.txt

# Copy to prefix path. Invoke sudo if current user doesn't own prefix.
my_uid=$(id -u)
check_dir=$( [[ -d "$PREFIX" ]] && echo "$PREFIX" || dirname "$PREFIX" )
if [[ $(stat -c '%u' "$check_dir") -ne $my_uid ]]; then
    sudo rsync -a --chown=root:root "install/$PREFIX/" "$PREFIX"
else
    rsync -a "install/$PREFIX/" "$PREFIX"
fi
