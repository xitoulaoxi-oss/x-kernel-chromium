#!/bin/sh
# Guest-side A: X server + window manager.  Under 1.8 KB (console ceiling).
set -u
A=/run/x11/auth
echo "A1"
pkill -x jwm 2>/dev/null; pkill -x Xorg 2>/dev/null; sleep 2
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 /tmp/xo.log
mkdir -p /etc/X11/xorg.conf.d
printf 'Section "Device"\n Identifier "x"\n Driver "modesetting"\n Option "AccelMethod" "none"\nEndSection\n' > /etc/X11/xorg.conf.d/10-xk.conf
C="$(hexdump -n 16 -v -e '4/4 "%08x" 1 ""' /dev/urandom)"
xauth -q -f "$A" add :0 . "$C" 2>/dev/null; chmod 644 "$A"
Xorg :0 vt1 -nolisten tcp -auth "$A" -logfile /tmp/xo2.log -verbose 6 >/tmp/xo.out 2>&1 &
w=0; while [ ! -S /tmp/.X11-unix/X0 ] && [ "$w" -lt 120 ]; do sleep 0.5; w=$((w+1)); done
echo "A2 xsock=$([ -S /tmp/.X11-unix/X0 ] && echo yes || echo NO)"
su kiosk -s /bin/sh -c "DISPLAY=:0 XAUTHORITY=$A exec jwm" >/tmp/jw.log 2>&1 &
sleep 3
echo "A3 jwm=$(ps w | grep -c '[j]wm') reach=$(su kiosk -s /bin/sh -c "DISPLAY=:0 XAUTHORITY=$A xrandr --current 2>&1 | head -1")"
echo "A4"
