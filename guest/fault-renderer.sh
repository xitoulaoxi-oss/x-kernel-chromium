#!/bin/sh
# Controlled crash/freeze injection for a renderer-like Chromium child.
# usage: fault-renderer.sh crash|stop|cont
set -u
action=${1:-crash}
pidfile=/tmp/xk-fault-pid
pick() {
  for d in /proc/[0-9]*; do
    [ -r "$d/status" ] || continue
    comm=$(cat "$d/comm" 2>/dev/null) || continue
    [ "$comm" = chromium ] || continue
    ppid=$(awk '/^PPid:/{print $2}' "$d/status" 2>/dev/null)
    threads=$(awk '/^Threads:/{print $2}' "$d/status" 2>/dev/null)
    pcomm=$(cat "/proc/$ppid/comm" 2>/dev/null)
    [ "$pcomm" = chromium ] || continue
    [ "${threads:-0}" -gt 1 ] || continue
    echo "${d##*/}"; return 0
  done
  return 1
}
case "$action" in
  crash|stop)
    p=$(pick) || { echo "FAULT_NO_RENDERER"; exit 1; }
    echo "$p" > "$pidfile"
    if [ "$action" = crash ]; then kill -SEGV "$p" && echo "FAULT_CRASH pid=$p"; else kill -STOP "$p" && echo "FAULT_STOP pid=$p"; fi
    ;;
  cont)
    p=$(cat "$pidfile" 2>/dev/null || true)
    [ -n "$p" ] && kill -CONT "$p" 2>/dev/null && echo "FAULT_CONT pid=$p" || echo "FAULT_CONT_NONE"
    ;;
  *) echo "usage: $0 crash|stop|cont"; exit 2;;
esac
