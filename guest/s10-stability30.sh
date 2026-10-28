#!/bin/sh
# 30-minute stability sample; two windows must already be up.
# One HB line per minute is parsed by host/observe.py; T2 adds window details.
set -u
export DISPLAY=:0 XAUTHORITY=/run/x11/auth
echo T1
t=0
while [ $t -lt 1800 ]; do
  sleep 60; t=$((t+60))
  w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l)
  a=$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | tail -c 9)
  c=$(ps w 2>/dev/null | grep -c '[c]hromium')
  m=$(free -m 2>/dev/null | awk '/Mem:/{print $3}')
  echo "HB t=$t chrome=$c mem_mb=$m"
  echo "T2 t=$t x=$(ps w 2>/dev/null | grep -c '[X]org') j=$(ps w 2>/dev/null | grep -c '[j]wm') c=$c w=$w a=$a"
done
echo "T3 $(xrandr --current 2>&1 | head -1)"
echo "T4 $(xprop -root _NET_CLIENT_LIST 2>&1 | head -1)"
echo "T5 $(xprop -root _NET_SUPPORTING_WM_CHECK 2>&1 | head -1)"
echo T6
