#!/bin/sh

# Verify that a running release build and its WebKit extension come from the
# same installation prefix. Mixing these produces unhandled user-message
# errors when their private protocol changes.

set -eu

install_prefix=${1:-"$HOME/.local"}
expected_executable="$install_prefix/bin/geary"
expected_extension="$install_prefix/lib/geary/web-extensions/libgeary-web-process.so"

geary_pid=$(pgrep -x geary | sed -n '1p')
if test -z "$geary_pid"; then
    echo "Geary is not running" >&2
    exit 1
fi

running_executable=$(readlink -f "/proc/$geary_pid/exe")
if test "$running_executable" != "$expected_executable"; then
    echo "Unexpected Geary executable: $running_executable" >&2
    echo "Expected: $expected_executable" >&2
    exit 1
fi

if ! test -f "$expected_extension"; then
    echo "WebKit extension is not installed: $expected_extension" >&2
    exit 1
fi

extension_loaded=false
for process_maps in /proc/[0-9]*/maps; do
    if test -r "$process_maps" &&
       grep -Fq "$expected_extension" "$process_maps" 2>/dev/null; then
        extension_loaded=true
        break
    fi
done

if test "$extension_loaded" != true; then
    echo "No WebKit process has loaded: $expected_extension" >&2
    echo "Open a message in Geary, then run this check again." >&2
    exit 1
fi

echo "Geary executable and WebKit extension use $install_prefix"
