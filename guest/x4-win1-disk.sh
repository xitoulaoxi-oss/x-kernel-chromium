#!/bin/sh
# E004a: only the profile moves from tmpfs (/tmp) to disk-backed /root.
set -u
A=/run/x11/auth; P=/root/pr
U=/usr/share/kiosk/official/index.html
rm -rf $P; mkdir -p $P
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
GL="--ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl --disable-vulkan --disable-features=Vulkan"
setsid chromium $GL --user-data-dir=$P --enable-logging=stderr file://$U >/tmp/w.log 2>&1 &
echo W1D started
t=0
while [ $t -lt 150 ]; do
  sleep 15; t=$((t+15))
  w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l)
  echo "W2D t=$t procs=$(ps w | grep -c '[c]hromium') wins=$w"
  [ $t -ge 60 ] && [ "$w" -ge 1 ] && break
done
echo W3D
