#!/bin/sh
# Guest perf part 5: publish the milestones the 1 Hz monitor recorded.
# Tiny on purpose: the console heredoc is the fragile part of this path, and
# by the time this runs the 140 s frame watch has already covered the startup.
set -u
M=/tmp/perf.marks
cat "$M" 2>/dev/null
echo "log_bytes=$(wc -c < /tmp/perf.log 2>/dev/null || echo 0)"
echo "chrome_pids=$(ps w | grep -v grep | grep -c chromium)"
export DISPLAY=:0 XAUTHORITY=/run/x11/auth
echo "win=$(xprop -root _NET_CLIENT_LIST 2>&1 | head -1)"
echo HARVEST-END
