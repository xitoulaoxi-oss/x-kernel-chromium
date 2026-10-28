#!/bin/sh
# 10-minute stability sample, final kernel, two windows already up.
# One line per minute: are Xorg/jwm/chromium alive, how many windows does the WM
# report, which one is active, and is the browser log still growing.  Kept short
# on purpose: every extra line is another chance for the serial console to garble
# the heredoc that carries it.
set -u
export DISPLAY=:0 XAUTHORITY=/run/x11/auth
echo T1
t=0
while [ $t -lt 600 ]; do
  sleep 60; t=$((t+60))
  w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l)
  a=$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | tail -c 9)
  echo "T2 t=$t x=$(ps w | grep -c '[X]org') j=$(ps w | grep -c '[j]wm') c=$(ps w | grep -c '[c]hromium') w=$w a=$a l1=$(wc -c < /tmp/w.log) l2=$(wc -c < /tmp/w2.log 2>/dev/null)"
done
echo "T3 $(xrandr --current 2>&1 | head -1)"
echo "T4 $(xprop -root _NET_CLIENT_LIST 2>&1 | head -1)"
echo "T5 $(xprop -root _NET_SUPPORTING_WM_CHECK 2>&1 | head -1)"
echo T6
