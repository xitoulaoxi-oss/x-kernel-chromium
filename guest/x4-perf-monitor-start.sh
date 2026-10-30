#!/bin/sh
# Start the 1 Hz Chromium milestone/memory monitor for a plain x4 launch.
# Records the shared origin and returns immediately; the monitor is killed by
# the session shutdown, not by this script.
set -u
echo "$(date +%s)" > /tmp/perf.t0
rm -f /tmp/perf.marks
setsid sh /tmp/xk-c2-perf-monitor.sh >/dev/null 2>&1 &
echo "MON-START t0=$(cat /tmp/perf.t0)"
