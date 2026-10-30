#!/bin/sh
# Task 08 candidate A: keep the network service inside the browser process.
# If the first navigation is lost because the out-of-process network service
# crashes and restarts, this removes that process boundary entirely.
set -u
A=/run/x11/auth; P=/tmp/pr
U=/usr/share/kiosk/official/index.html
rm -rf $P; mkdir -p $P
rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
GL="--ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl --disable-vulkan --disable-features=Vulkan --enable-features=NetworkServiceInProcess"
setsid chromium $GL --user-data-dir=$P --enable-logging=stderr file://$U >/tmp/w.log 2>&1 &
echo W1N started
t=0
while [ $t -lt 120 ]; do
  sleep 15; t=$((t+15))
  w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l)
  title=""
  for id in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*'); do
    title=$(xprop -id $id WM_NAME 2>/dev/null | head -1)
    break
  done
  echo "W2N t=$t procs=$(ps w | grep -c '[c]hromium') log=$(wc -c < /tmp/w.log) wins=$w title=$title"
  [ $t -ge 60 ] && [ "$w" -ge 1 ] && break
done
echo "W3N $(xprop -root _NET_CLIENT_LIST 2>&1 | head -1)"
echo W4N
