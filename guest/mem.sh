#!/bin/sh
# Print the guest memory budget in one block.  "used" alone hides page cache,
# which is exactly what the host QEMU working set also counts.
echo MEMSTART
free -m 2>/dev/null || true
echo MEMINFO
head -5 /proc/meminfo 2>/dev/null || true
echo MEMEND
