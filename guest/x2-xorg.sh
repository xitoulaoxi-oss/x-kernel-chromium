#!/bin/sh
# Step 2: X server.  Software modesetting with ShadowFB and a software cursor --
# the configuration the teammate's working session used, and the one every
# frame in this project's evidence was produced with.
set -u
A=/run/x11/auth
mkdir -p /etc/X11/xorg.conf.d
printf 'Section "Device"\n Identifier "x"\n Driver "modesetting"\n Option "AccelMethod" "none"\n Option "ShadowFB" "true"\n Option "SWcursor" "true"\nEndSection\n' > /etc/X11/xorg.conf.d/10-xk.conf
C=$(hexdump -n 16 -v -e '4/4 "%08x" 1 ""' /dev/urandom)
xauth -q -f $A add :0 . $C 2>/dev/null; chmod 644 $A
Xorg :0 vt1 -nolisten tcp -auth $A -logfile /tmp/xo3.log >/tmp/xo.out 2>&1 &
w=0; while [ ! -S /tmp/.X11-unix/X0 ] && [ $w -lt 120 ]; do sleep 0.5; w=$((w+1)); done
echo "X5 xsock=$([ -S /tmp/.X11-unix/X0 ] && echo yes || echo NO)"
sleep 3
echo "X6 xolog=$(wc -c < /tmp/xo3.log) libinput=$(grep -ci libinput /tmp/xo3.log)"
grep -iE 'libinput|keyboard|mouse' /tmp/xo3.log | head -8
echo X7
