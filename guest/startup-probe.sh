#!/bin/sh
# Diagnostic launch only: same browser flags as x4-win1.sh, no restart/reload.
set -u
A=/run/x11/auth; P=/tmp/pr; U=/usr/share/kiosk/official/index.html
rm -rf "$P"; mkdir -p "$P"
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
setsid chromium ${XK_CDP_ARGS:-} --ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl --disable-vulkan --disable-features=Vulkan --user-data-dir=$P --enable-logging=stderr file://$U >/tmp/w.log 2>&1 &
echo "STARTUP_PROBE_BEGIN browser_pid=$! epoch=$(date +%s)"
i=0
while [ "$i" -lt 18 ]; do
  sleep 5; i=$((i+1))
  echo "STARTUP_TICK sample=$i epoch=$(date +%s) log_bytes=$(wc -c </tmp/w.log)"
  ps w | grep '[c]hromium' || true
  echo STARTUP_BROWSER_LOG
  tail -n 8 /tmp/w.log
  echo STARTUP_MEMORY
  head -n 6 /proc/meminfo
done
echo STARTUP_FINAL_LOG
cat /tmp/w.log
echo STARTUP_FINAL_WINDOWS
xprop -root _NET_CLIENT_LIST _NET_ACTIVE_WINDOW 2>/dev/null || true
echo STARTUP_PROBE_END
