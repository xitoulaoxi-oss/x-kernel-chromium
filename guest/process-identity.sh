#!/bin/sh
set -u
echo PROC_IDENTITY_BEGIN
for p in $(ps w | grep '[c]hromium' | awk '{print $1}' | sort -u); do
  [ -r /proc/$p/status ] || continue
  echo "PROC_IDENTITY_PID=$p"
  grep -E '^(Name|Pid|PPid|Threads|State|VmRSS|VmHWM):' /proc/$p/status || true
  if grep -q '^VmRSS:' /proc/$p/status; then echo "PROC_RSS_STATUS=$p:available"; else echo "PROC_RSS_STATUS=$p:unavailable"; fi
  if [ -r /proc/$p/statm ]; then echo "PROC_STATM_PID=$p"; cat /proc/$p/statm; else echo "PROC_STATM_PID=$p:unavailable"; fi
done
echo PROC_IDENTITY_END
