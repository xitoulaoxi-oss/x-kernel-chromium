#!/bin/sh
# Candidate B fix: skip the separate GPU process/ANGLE initialization.  The
# first navigation never starts when the GPU channel stalls; software
# compositing still has to prove the page through CDP, not colour count.
set -u
A=/run/x11/auth; P=/tmp/pr; U=/usr/share/kiosk/official/index.html
rm -rf $P; mkdir -p $P
rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
setsid chromium ${XK_CDP_ARGS:-} --ozone-platform=x11 --no-sandbox --disable-gpu \
  --user-data-dir=$P --enable-logging=stderr file://$U >/tmp/w.log 2>&1 &
echo W1NG started
t=0
while [ $t -lt 150 ]; do
  sleep 15; t=$((t+15))
  w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l)
  echo "W2NG t=$t procs=$(ps w | grep -c '[c]hromium') log=$(wc -c < /tmp/w.log) wins=$w"
  [ $t -ge 45 ] && [ "$w" -ge 1 ] && break
done
echo "W3NG $(xprop -root _NET_CLIENT_LIST 2>&1 | head -1)"
echo W4NG
