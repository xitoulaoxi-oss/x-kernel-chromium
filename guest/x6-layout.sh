#!/bin/sh
# Single window on the CSS layout page.
#
# Same launch line as x4-win1.sh (the one that painted every frame in this project's
# evidence), only the URL differs -- x4-win1.sh loads index.html, this loads
# layout.html.  The window list is read during the stable period, which is the lesson
# recorded in docs/ENGINEERING-NOTES.md: reading _NET_CLIENT_LIST 25 s after start
# shows nothing even on a healthy session.
set -u
A=/run/x11/auth; P=/tmp/prl
U=/usr/share/kiosk/official/layout.html
rm -rf $P; mkdir -p $P
rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
echo "L0 $(ls -l $U 2>&1)"
setsid chromium --ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl --disable-vulkan --disable-features=Vulkan --user-data-dir=$P --enable-logging=stderr file://$U >/tmp/lay.log 2>&1 &
echo L1 started
t=0
while [ $t -lt 150 ]; do
  sleep 15; t=$((t+15))
  w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l)
  echo "L2 t=$t procs=$(ps w | grep -c '[c]hromium') log=$(wc -c < /tmp/lay.log) wins=$w"
  [ $t -ge 60 ] && [ "$w" -ge 1 ] && break
done
echo "L3 $(xprop -root _NET_CLIENT_LIST 2>&1 | head -1)"
echo L4
