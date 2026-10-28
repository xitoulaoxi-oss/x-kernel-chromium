#!/bin/sh
# One heartbeat line per minute.  Started by hb-start.sh; read by hb-dump.sh.
while :; do
  c=$(ps w 2>/dev/null | grep -c "[c]hromium")
  m=$(free -m 2>/dev/null | awk '/Mem:/{print $3}')
  echo "HB t=$(date +%s) chrome=$c mem_mb=$m"
  sleep 60
done
