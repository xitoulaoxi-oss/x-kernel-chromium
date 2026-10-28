#!/bin/sh
# Second window for the recording.
#
# The harness UPLOADS every -Script file and then RUNS it, so this script has to
# be uploaded early and fire late.  Without the argument it does nothing; the
# recording calls it with "go" at the point in the timeline where the second
# window should appear.
if [ $# -eq 0 ]; then
  echo "R2 idle (pass 'go' to open the window)"
  exit 0
fi
if [ "$1" != "go" ]; then
  echo "R2 idle (pass 'go' to open the window)"
  exit 0
fi
set -u
A=/run/x11/auth; P=/tmp/pr
U=/usr/share/kiosk/official/interaction.html
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
setsid chromium --user-data-dir=$P --no-sandbox --ozone-platform=x11 --use-gl=angle \
  --use-angle=gl --disable-vulkan --disable-features=Vulkan --new-window file://$U \
  >/tmp/w2.log 2>&1 &
echo "R2 second window requested"
