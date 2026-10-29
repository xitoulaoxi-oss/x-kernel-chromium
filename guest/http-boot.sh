#!/bin/sh
# Bootstrap: fetch all guest steps over HTTP, then run them in order.
# Keeps the serial console free of long heredocs (its transfer is unreliable).
set -u
H=$XK_HTTP
for s in 06-fetch-pages x1-input x2-xorg y3-jwm-stock x4-win1 x5c-win2 chrome-mem; do
  if wget -q -O /tmp/xk-$s.sh "$H/$s.sh"; then
    echo "HTTP $s"
    sh /tmp/xk-$s.sh
  else
    echo "HTTP-FAIL $s"
  fi
done
echo HTTP-BOOT-END
