#!/bin/sh
# Structured read-out: which windows exist, what each is called, which one jwm
# considers active, and WHICH PROCESS owns it.
#
# _NET_WM_PID is the part that separates the two possible stories: two windows
# of one browser (the hand-off worked over the Mojo/unix-socket path) versus two
# independent browsers (each with its own process).  Both give two windows; only
# the PID says which one happened.
set -u
export DISPLAY=:0 XAUTHORITY=/run/x11/auth
echo E1
xprop -root _NET_CLIENT_LIST
xprop -root _NET_ACTIVE_WINDOW
xprop -root _NET_CLIENT_LIST_STACKING
i=0
for id in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*'); do
  i=$((i+1))
  echo "E2 win$i=$id"
  xprop -id $id WM_NAME 2>&1 | head -2
  xprop -id $id _NET_WM_PID WM_CLASS 2>&1 | head -2
done
echo "E3 chrome=$(ps w | grep -c '[c]hromium') log1=$(wc -c < /tmp/w.log) log2=$(wc -c < /tmp/w2.log) log3=$(wc -c < /tmp/w3.log 2>/dev/null)"
echo "E4 devinput=$(ls /dev/input 2>/dev/null | tr '\n' ' ') xolog=$(wc -c < /tmp/xo3.log)"
grep -iE 'libinput|keyboard|mouse|event[0-9]' /tmp/xo3.log | head -10
echo E5
