#!/bin/sh
# Probe TCP keep-alive sockopts (numeric optnames 4/5/6, so no interpreter
# constants are needed). Neither perl nor python3 exists in the delivered rootfs,
# so python3-minimal is installed here first -- the image banner advertises apt,
# and -snapshot means the install is discarded when QEMU exits.
# Before the pr-c patch these answer ENOPROTOOPT (92); after it they round-trip.
echo "=== keepalive probe start ==="
if ! command -v python3 >/dev/null 2>&1; then
    echo "installing python3-minimal"
    DEBIAN_FRONTEND=noninteractive apt-get update >/tmp/apt.log 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends python3-minimal >>/tmp/apt.log 2>&1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 still missing; apt log tail:"
    tail -12 /tmp/apt.log
    echo "=== keepalive probe end ==="
    exit 1
fi
echo "python3: $(command -v python3)"
python3 - <<'PYEOF'
import socket
for name, opt in (("TCP_KEEPIDLE", 4), ("TCP_KEEPINTVL", 5), ("TCP_KEEPCNT", 6)):
    sock = socket.socket()
    try:
        sock.setsockopt(socket.IPPROTO_TCP, opt, 30)
        print(name, "set ok, read back", sock.getsockopt(socket.IPPROTO_TCP, opt))
    except OSError as err:
        print(name, "FAILED:", err)
    finally:
        sock.close()
PYEOF
echo "=== keepalive probe end ==="
