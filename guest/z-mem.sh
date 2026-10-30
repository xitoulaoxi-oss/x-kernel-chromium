#!/bin/sh
# Sample guest memory for task 16: /proc/meminfo (allocator view) + chrome-mem.sh
# (per-process RSS, expected unavailable on this kernel).
#   sh /tmp/xk-z-mem.sh [samples] [gap_seconds]
set -u
n=${1:-6}
gap=${2:-10}
echo ZMSTART samples=$n gap=$gap
i=0
while [ $i -lt $n ]; do
    echo "ZSAMPLE i=$i t=$(date +%s)"
    head -3 /proc/meminfo 2>/dev/null
    sh /tmp/xk-chrome-mem.sh 2>/dev/null | grep -E '^CMEM|^CMJSON'
    i=$((i + 1))
    [ $i -lt $n ] && sleep $gap
done
echo ZMEND
