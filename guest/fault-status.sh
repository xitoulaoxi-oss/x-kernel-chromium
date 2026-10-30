#!/bin/sh
# Read-only status for the process a previous fault-renderer.sh stop/crash
# selected.  Kept as a short uploaded script so a -Key step needs no quoted
# semicolons and can always return its own completion marker.
set -u
p=$(cat /tmp/xk-fault-pid 2>/dev/null || true)
echo "FAULT_PID=${p:-none}"
if [ -n "$p" ] && [ -r "/proc/$p/status" ]; then
  grep -E '^(Name|State|Threads|PPid):' "/proc/$p/status" 2>/dev/null || true
fi
if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo ALIVE; else echo GONE; fi
echo FAULT-STATUS-END
