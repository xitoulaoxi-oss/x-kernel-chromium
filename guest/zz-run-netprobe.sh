#!/bin/sh
# Fetch the keep-alive probe from the host upload server and run it.
#
# The delivered rootfs has wget, so the 388 KB binary arrives over HTTP
# (http://10.0.2.2:<port>, exported as XK_HTTP by the harness) instead of the
# serial console -- a chunked serial transfer that size floods the console and
# corrupts the payload.
echo "=== probe runner start ==="
if [ -z "$XK_HTTP" ]; then
    echo "XK_HTTP is not set; cannot fetch the probe"
    echo "=== probe runner end ==="
    exit 1
fi

DEST=/tmp/net_keepalive_probe
echo "fetching $XK_HTTP/net_keepalive_probe"
if ! wget -q -O "$DEST" "$XK_HTTP/net_keepalive_probe"; then
    wget -O "$DEST" "$XK_HTTP/net_keepalive_probe"
fi
if [ ! -s "$DEST" ]; then
    echo "fetch produced no file"
    echo "=== probe runner end ==="
    exit 1
fi
echo "received $(wc -c < "$DEST") bytes"
chmod +x "$DEST"

"$DEST"
echo "probe exit=$?"
echo "=== probe runner end ==="
