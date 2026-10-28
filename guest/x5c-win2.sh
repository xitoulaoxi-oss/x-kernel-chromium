#!/bin/sh
# Step 5: a SECOND window, by two routes.
#  (a) --new-window into the RUNNING instance: the profile is owned by the
#      browser already rendering, so the request travels over the unix-socket /
#      Mojo channel this project had to fix.  An earlier attempt omitted
#      --no-sandbox and died before handing anything over: a test bug, and N3
#      prints the log so it stays on record.
#  (b) fallback: a second instance with its OWN profile, no hand-off at all, so
#      "two windows" does not depend on one IPC path working.
set -u
A=/run/x11/auth; P=/tmp/pr; Q=/tmp/pr2
U=/usr/share/kiosk/official/interaction.html
GL="--ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl --disable-vulkan --disable-features=Vulkan"
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
cnt() { xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l; }
echo "N1 before=$(xprop -root _NET_CLIENT_LIST 2>&1 | head -1) wins=$(cnt)"
setsid chromium --user-data-dir=$P $GL --new-window file://$U >/tmp/w2.log 2>&1 &
t=0
while [ $t -lt 60 ]; do
  sleep 10; t=$((t+10))
  echo "N2 t=$t wins=$(cnt) log2=$(wc -c < /tmp/w2.log)"
  [ "$(cnt)" -ge 2 ] && break
done
if [ "$(cnt)" -lt 2 ]; then
  echo "N3 no window from hand-off; w2.log follows"
  cat /tmp/w2.log
  echo "N4 fallback: second instance, own profile"
  rm -rf $Q; mkdir -p $Q
  setsid chromium $GL --user-data-dir=$Q file://$U >/tmp/w3.log 2>&1 &
  t=0
  while [ $t -lt 120 ]; do
    sleep 15; t=$((t+15))
    echo "N5 t=$t wins=$(cnt) log3=$(wc -c < /tmp/w3.log)"
    [ "$(cnt)" -ge 2 ] && break
  done
fi
echo "N6 $(xprop -root _NET_CLIENT_LIST 2>&1 | head -1)"
echo "N7 active=$(xprop -root _NET_ACTIVE_WINDOW 2>&1 | head -1) wins=$(cnt) log1=$(wc -c </tmp/w.log)"
echo N8
