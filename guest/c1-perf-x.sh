#!/bin/sh
# Guest-side perf part 1: X + window manager, with a shared start timestamp.
# Writes /tmp/perf.t0 so part 2 can report every milestone relative to the same
# instant.  Whole-second timing: busybox `date` ignores %N here (measured).
set -u
A=/run/x11/auth
echo "P1-BEGIN"
pkill -x jwm 2>/dev/null; pkill -x Xorg 2>/dev/null; pkill -f chromium 2>/dev/null
sleep 2
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 /tmp/perf.log
mkdir -p /etc/X11/xorg.conf.d
printf 'Section "Device"\n Identifier "x"\n Driver "modesetting"\n Option "AccelMethod" "none"\nEndSection\n' > /etc/X11/xorg.conf.d/10-xk.conf
T0=$(date +%s)
echo "$T0" > /tmp/perf.t0
C="$(hexdump -n 16 -v -e '4/4 "%08x" 1 ""' /dev/urandom)"
xauth -q -f "$A" add :0 . "$C" 2>/dev/null
chmod 644 "$A"
Xorg :0 vt1 -nolisten tcp -auth "$A" >/tmp/xo.log 2>&1 &
w=0
while [ ! -S /tmp/.X11-unix/X0 ] && [ "$w" -lt 600 ]; do sleep 0.05; w=$((w+1)); done
echo "xorg_s=$(( $(date +%s) - T0 ))"
su kiosk -s /bin/sh -c "DISPLAY=:0 XAUTHORITY=$A exec jwm" >/tmp/jw.log 2>&1 &
sleep 1
echo "jwm_s=$(( $(date +%s) - T0 ))"
echo "P1-END"
