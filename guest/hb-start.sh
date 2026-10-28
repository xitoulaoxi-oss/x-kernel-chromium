#!/bin/sh
# Start the heartbeat in the background and return immediately.
pkill -f /tmp/xk-hb.sh 2>/dev/null
setsid sh /tmp/xk-hb.sh >/tmp/xk-hb.log 2>&1 &
echo HB_STARTED
