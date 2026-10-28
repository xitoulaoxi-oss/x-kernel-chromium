#!/bin/sh
# Guest-side: launch Chromium WITHOUT `su`.
#
# Why: in the previous run the launcher left one process in state R with a single
# thread and 3 fds -- that is `su kiosk` itself burning CPU, and /tmp/w.log was 0
# bytes, so Chromium was never exec'd at all.  `su` is therefore not a neutral
# wrapper here; it can fail to launch anything.
#
# Running as root is acceptable for this test: /dev/dri/card0 is mode 666 and the
# session has no seat/login management, so the only thing `kiosk` provided was a
# uid.  Removing `su` also removes a variable that has been silently confounding
# every earlier attempt.
set -u
A=/run/x11/auth
P=/tmp/pr
U=/usr/share/kiosk/official/index.html
echo "R1"
rm -rf "$P"; mkdir -p "$P"
rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
echo "R2 xsock=$([ -S /tmp/.X11-unix/X0 ] && echo y || echo n) xorg=$(ps w | grep -c '[X]org')"
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export DISPLAY=:0
export XAUTHORITY=$A
setsid chromium --ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl --disable-vulkan --disable-features=Vulkan --user-data-dir=$P --enable-logging=stderr file://$U >/tmp/w.log 2>&1 &
echo "R3 started"
sleep 25
echo "R4 procs=$(ps w | grep -c '[c]hromium') rend=$(ps w | grep -c '[-]-type=renderer') gpu=$(ps w | grep -c '[-]-type=gpu') log=$(wc -c < /tmp/w.log 2>/dev/null)"
echo "R5-window"
xprop -root _NET_CLIENT_LIST 2>&1 | head -2
echo "R6"
tail -10 /tmp/w.log 2>/dev/null
echo "R7"
