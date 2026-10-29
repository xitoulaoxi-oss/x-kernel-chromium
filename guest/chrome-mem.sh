#!/bin/sh
# Sum resident memory of Chromium PIDs listed by busybox ps.
# RSS sum is a conservative upper bound (shared pages counted per process).
ps w 2>/dev/null | grep '[c]hromium' | awk '{print $1}' | sort -u > /tmp/xk-cm-pids
echo "PIDS=$(wc -l < /tmp/xk-cm-pids) $(tr '\n' ' ' < /tmp/xk-cm-pids)"
tot=0; n=0
while read -r p; do
  [ -n "$p" ] || continue
  kb=0
  if [ -r "/proc/$p/statm" ]; then
    r=$(awk '{print $2}' "/proc/$p/statm" 2>/dev/null)
    [ -n "$r" ] || r=0
    kb=$((r * 4))
    if [ "$r" -eq 0 ] && [ -r "/proc/$p/stat" ]; then
      r=$(awk '{print $24}' "/proc/$p/stat" 2>/dev/null)
      [ -n "$r" ] || r=0
      kb=$((r * 4))
    fi
    if [ "$r" -eq 0 ] && [ -r "/proc/$p/status" ]; then
      kb=$(awk '/^VmRSS:/{print $2}' "/proc/$p/status" 2>/dev/null)
      [ -n "$kb" ] || kb=0
    fi
  elif [ -r "/proc/$p/status" ]; then
    kb=$(awk '/^VmRSS:/{print $2}' "/proc/$p/status" 2>/dev/null)
    [ -n "$kb" ] || kb=0
  else
    continue
  fi
  tot=$((tot + kb)); n=$((n + 1))
  echo "CM pid=$p rss_kb=$kb"
done < /tmp/xk-cm-pids
echo "CMEM procs=$n total_kb=$tot total_mb=$((tot / 1024))"
