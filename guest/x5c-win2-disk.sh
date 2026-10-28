#!/bin/sh
# E004a second window: same disk profile and original flags as x4-win1-disk.
set -u
A=/run/x11/auth; P=/root/pr; Q=/root/pr2
U=/usr/share/kiosk/official/interaction.html
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
GL="--ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl --disable-vulkan --disable-features=Vulkan"
cnt() { xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l; }
setsid chromium --user-data-dir=$P $GL --new-window file://$U >/tmp/w2.log 2>&1 &
t=0
while [ $t -lt 90 ]; do sleep 10; t=$((t+10)); echo "N2D t=$t wins=$(cnt)"; [ "$(cnt)" -ge 2 ] && break; done
if [ "$(cnt)" -lt 2 ]; then
  rm -rf $Q; mkdir -p $Q
  setsid chromium $GL --user-data-dir=$Q file://$U >/tmp/w3.log 2>&1 &
  t=0; while [ $t -lt 120 ]; do sleep 15; t=$((t+15)); echo "N5D t=$t wins=$(cnt)"; [ "$(cnt)" -ge 2 ] && break; done
fi
echo N6D
