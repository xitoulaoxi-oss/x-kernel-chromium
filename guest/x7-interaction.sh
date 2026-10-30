#!/bin/sh
# Single window on the JavaScript interaction page.
#
# Same launch line as x4-win1.sh (index.html) and x6-layout.sh (layout.html); only the
# URL differs, so all three pages are rendered by the same invocation and the three
# screenshots are comparable.
set -u
A=/run/x11/auth; P=/tmp/pri
U=/usr/share/kiosk/official/interaction.html
rm -rf $P; mkdir -p $P
rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
echo "I0 $(ls -l $U 2>&1)"
setsid chromium ${XK_CDP_ARGS:-} --ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl --disable-vulkan --disable-features=Vulkan --user-data-dir=$P --enable-logging=stderr file://$U >/tmp/int.log 2>&1 &
echo I1 started
t=0
while [ $t -lt 150 ]; do
  sleep 15; t=$((t+15))
  w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l)
  echo "I2 t=$t procs=$(ps w | grep -c '[c]hromium') log=$(wc -c < /tmp/int.log) wins=$w"
  [ $t -ge 60 ] && [ "$w" -ge 1 ] && break
done
echo "I3 $(xprop -root _NET_CLIENT_LIST 2>&1 | head -1)"
echo I4
