#!/bin/sh
# Combined candidate: no separate GPU process, and the official page is opened
# as the first real navigation only after the browser's DevTools endpoint is
# ready.  No reload/restart of a failed navigation.
set -u
A=/run/x11/auth; P=/tmp/pr; U=/usr/share/kiosk/official/index.html
rm -rf $P; mkdir -p $P
rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
GL="--ozone-platform=x11 --no-sandbox --disable-gpu"
setsid chromium ${XK_CDP_ARGS:-} $GL --user-data-dir=$P --no-startup-window --enable-logging=stderr >/tmp/w.log 2>&1 &
echo W1C started
i=0; ready=0
while [ $i -lt 60 ]; do
  sleep 1; i=$((i+1))
  if wget -q -O /dev/null http://127.0.0.1:9222/json/version 2>/dev/null; then ready=1; break; fi
done
echo "W2C cdp_ready=$ready after=${i}s"
if [ "$ready" -eq 1 ]; then
  setsid chromium $GL --user-data-dir=$P --new-window file://$U >/tmp/w2.log 2>&1 &
  echo W3C new_window_sent
else
  setsid chromium ${XK_CDP_ARGS:-} $GL --user-data-dir=$P file://$U >/tmp/w2.log 2>&1 &
  echo W3C fallback_direct
fi
t=0
while [ $t -lt 120 ]; do
  sleep 10; t=$((t+10))
  w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l)
  echo "W4C t=$t procs=$(ps w | grep -c '[c]hromium') log1=$(wc -c < /tmp/w.log) log2=$(wc -c < /tmp/w2.log) wins=$w"
  [ "$w" -ge 1 ] && [ $t -ge 20 ] && break
done
echo "W5C $(xprop -root _NET_CLIENT_LIST 2>&1 | head -1)"
echo W6C
