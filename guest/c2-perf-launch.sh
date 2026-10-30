#!/bin/sh
# Guest perf part 2: ONE console line that starts Chromium and returns.
# Nothing slow may happen here: the host sends this line at t=0 of its frame
# watch, so any upload / profile reset inside it would be measured as latency.
set -u
A=/run/x11/auth; U=/usr/share/kiosk/official/index.html; L=/tmp/perf.log
T0=$(cat /tmp/perf.t0 2>/dev/null || date +%s)
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
setsid chromium ${XK_CDP_ARGS:-} --ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl \
  --disable-vulkan --disable-features=Vulkan --user-data-dir=/tmp/pr \
  --enable-logging=stderr file://$U >"$L" 2>&1 &
echo "t0=$T0"
echo "launch_epoch=$(date +%s)"
setsid sh /tmp/xk-c2-perf-monitor.sh >/dev/null 2>&1 &
echo LAUNCH-END
