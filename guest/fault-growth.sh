#!/bin/sh
# Controlled guest memory growth (tmpfs file); not attributed to Chromium.
set -u
N=${1:-256}
dd if=/dev/zero of=/dev/shm/xk-fault-leak bs=1M count="$N" 2>/dev/null || { echo "FAULT_LEAK_FAIL"; exit 1; }
sync
echo "FAULT_LEAK mb=$N file=/dev/shm/xk-fault-leak"
