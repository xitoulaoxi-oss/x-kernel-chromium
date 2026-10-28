#!/bin/sh
# Start the browser and RETURN, so the host can keep taking frames while the
# page loads.  Every other script in this project waits for a milestone; a
# recording needs the opposite, because what is worth recording is what happens
# during the wait.
set -u
A=/run/x11/auth; P=/tmp/pr
U=/usr/share/kiosk/official/index.html
rm -rf $P; mkdir -p $P
rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
setsid chromium --ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl \
  --disable-vulkan --disable-features=Vulkan --user-data-dir=$P \
  --enable-logging=stderr file://$U >/tmp/w.log 2>&1 &
echo "R1 launched"
