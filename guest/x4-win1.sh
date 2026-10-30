#!/bin/sh
# Step 4: window 1, the committee's index page, launched the way the successful
# single-window session did.  --disable-dev-shm-usage is deliberately NOT added:
# it was absent from every run that painted a page.
set -u
A=/run/x11/auth; P=/tmp/pr
U=/usr/share/kiosk/official/index.html
rm -rf $P; mkdir -p $P
rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
setsid chromium ${XK_CDP_ARGS:-} --ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl --disable-vulkan --disable-features=Vulkan --user-data-dir=$P --enable-logging=stderr file://$U >/tmp/w.log 2>&1 &
echo W1 started
t=0
while [ $t -lt 150 ]; do
  sleep 15; t=$((t+15))
  w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l)
  echo "W2 t=$t procs=$(ps w | grep -c '[c]hromium') log=$(wc -c < /tmp/w.log) wins=$w"
  [ $t -ge 60 ] && [ "$w" -ge 1 ] && break
done
echo "W3 $(xprop -root _NET_CLIENT_LIST 2>&1 | head -1)"
echo "W4 active=$(xprop -root _NET_ACTIVE_WINDOW 2>&1 | head -1)"
echo W5
