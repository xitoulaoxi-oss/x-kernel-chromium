#!/bin/sh
# Guest perf part 1b: everything expensive that must NOT be inside the
# measured window.  Runs as a normal -Script step, minutes before t=0.
set -u
L=/tmp/perf.log; M=/tmp/perf.marks
rm -f "$L" "$M"
rm -rf /tmp/pr
mkdir -p /tmp/pr
rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
rm -f /home/kiosk/.config/chromium/Default/Singleton* 2>/dev/null
echo "prep_dir=$(ls -d /tmp/pr 2>/dev/null)"
echo PREP-END
