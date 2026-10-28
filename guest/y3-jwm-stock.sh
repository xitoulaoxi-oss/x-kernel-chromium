#!/bin/sh
# Step 3 (vendor-config variant): start the image's OWN window manager with the
# image's OWN /etc/system.jwmrc -- no private config file at all.
#
# Why this variant exists: the stock config already binds Alt+Tab:
#     <Key mask="A" key="Tab">nextstacked</Key>
# so window switching is a capability of the DELIVERED session, not something
# this project added.  The grep below prints that line from the running image so
# the claim is checked against the file, not against memory.
set -u
A=/run/x11/auth
echo Y1
grep -n 'mask="A"' /etc/system.jwmrc | head -12
su kiosk -s /bin/sh -c "DISPLAY=:0 XAUTHORITY=$A exec jwm" >/tmp/jw.log 2>&1 &
sleep 5
echo "Y2 jwm=$(ps w | grep -c '[j]wm') jwlog=$(wc -c < /tmp/jw.log)"
echo "Y3 wm=$(su kiosk -s /bin/sh -c "DISPLAY=:0 XAUTHORITY=$A xprop -root _NET_SUPPORTING_WM_CHECK" 2>&1 | head -1)"
head -5 /tmp/jw.log 2>/dev/null
echo Y4
