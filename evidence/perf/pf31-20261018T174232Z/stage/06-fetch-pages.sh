#!/bin/sh
# Guest-side: install the committee pages and point the kiosk at one.
#
# Why this replaces the 7 KB embedded installer: tools/xkwin.ps1 now serves
# staged files over HTTP and exports XK_HTTP, and it verifies its own server
# from the guest's view before any script runs.  Pulling three files plus
# sha256 verification fits the 1.8 KB console ceiling, an embedded copy does
# not.  Every byte is checked, so a truncated download cannot pass.
set -u
D=/usr/share/kiosk/official
mkdir -p "$D"
ok=0; bad=0
for n in index interaction layout; do
  if wget -q -O "$D/$n.html" "$XK_HTTP/$n.html" 2>/dev/null; then
    b=$(wc -c < "$D/$n.html")
    s=$(sha256sum "$D/$n.html" | cut -c1-16)
    echo "P $n bytes=$b sha=$s"
    case "$n:$b:$s" in
      index:5730:831cf28f3748940b) ok=$((ok+1));;
      interaction:10991:58130daa4a2f426f) ok=$((ok+1));;
      layout:11444:a1b04f9aba81b4b7) ok=$((ok+1));;
      *) bad=$((bad+1));;
    esac
  else
    echo "P $n FETCH-FAILED"
    bad=$((bad+1))
  fi
done
echo "P1 ok=$ok bad=$bad"
echo -n file://$D/index.html > /etc/kiosk/url
echo "P2 url=$(cat /etc/kiosk/url)"
ls -l "$D"
echo P3
