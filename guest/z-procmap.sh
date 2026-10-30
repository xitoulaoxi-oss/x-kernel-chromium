#!/bin/sh
# Dump the Chromium process tree for task 17.  The build does not rewrite child
# argv, so roles are inferred only from PPid/threads; this script prints the raw
# /proc facts and lets the host build process-map.json without guessing roles.
#   sh /tmp/xk-z-procmap.sh
set -u
export DISPLAY=:0 XAUTHORITY=/run/x11/auth
echo PMSTART
echo "PM windows: $(xprop -root _NET_CLIENT_LIST 2>/dev/null | head -1)"
for id in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*'); do
    echo "PM window=$id"
    xprop -id $id WM_NAME _NET_WM_PID WM_CLASS 2>&1 | head -4
done
for d in /proc/[0-9]*; do
    [ -d "$d" ] || continue
    p=${d##*/}
    comm=$(cat "$d/comm" 2>/dev/null) || comm=""
    case "$comm" in
        *chromium*|*chrome*) ;;
        *) continue ;;
    esac
    ppid=$(awk '{print $4}' "$d/stat" 2>/dev/null)
    threads=$(awk '/^Threads:/{print $2}' "$d/status" 2>/dev/null)
    state=$(awk '/^State:/{print $2}' "$d/status" 2>/dev/null)
    echo "PM pid=$p ppid=${ppid:-?} threads=${threads:-?} state=${state:-?} comm=$comm"
done
echo "PMEND"
