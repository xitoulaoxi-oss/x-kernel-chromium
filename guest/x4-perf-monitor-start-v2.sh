#!/bin/sh
# Start the iteration-07 low-overhead sampler and return immediately.
set -u
setsid sh /tmp/xk-perf-monitor-v2.sh /tmp/xk-perf-marks 120 >/dev/null 2>&1 &
echo "MON-V2-START t0=$(cut -d' ' -f1 /proc/uptime)"
