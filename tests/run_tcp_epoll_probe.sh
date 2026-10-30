#!/bin/sh
set -u
wget -q -O /tmp/tcp-epoll-probe "$XK_HTTP/tcp-epoll-aarch64" || exit 2
sha256sum /tmp/tcp-epoll-probe
chmod +x /tmp/tcp-epoll-probe || exit 2
/tmp/tcp-epoll-probe in
echo "TCP_EPOLL_IN_RC=$?"
/tmp/tcp-epoll-probe inout
echo "TCP_EPOLL_INOUT_RC=$?"
echo TCP_EPOLL_DIAGNOSTIC_DONE
