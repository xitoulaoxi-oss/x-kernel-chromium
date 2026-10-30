#!/bin/sh
# Dump the browser's own target list (URL and title) through the guest-local
# CDP endpoint.  Used between the first window and the --new-window request.
set -u
echo TARGETS-BEGIN
wget -q -O - http://127.0.0.1:9222/json/list 2>/dev/null || echo TARGETS-UNAVAILABLE
echo
echo TARGETS-END
