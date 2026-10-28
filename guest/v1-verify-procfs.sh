#!/bin/sh
# Proof that the new /proc fields exist, and that they say something usable.
#
# Before this change /proc/<pid>/status carried only Name/Tgid/Pid/Uid/Gid/
# Cpus_allowed/Mems_allowed, and /proc/<pid>/stat left vsize (field 23) and rss
# (field 24) at 0 -- so no tool inside the guest could report either memory or
# thread count, which is why an earlier perf run recorded peak_rss_kb=0 for
# every sample and printed it as if it were a result.
#
# Idle unless called with "go": the harness uploads every -Script file and then
# runs it, and this probe is wanted at the END of a session, not at the start.
if [ $# -eq 0 ]; then
  echo "V1 idle (pass 'go' to probe)"
  exit 0
fi
if [ "$1" != "go" ]; then
  echo "V1 idle (pass 'go' to probe)"
  exit 0
fi
set -u
echo "V2 self-status follows"
cat /proc/self/status
echo "V3 self-stat (comm stripped so the numbering is Linux's)"
sed 's/^[0-9]* ([^)]*) //' /proc/self/stat | awk '{print "state="$1" ppid="$2" threads="$18" vsize="$21" rss="$22}'
echo "V4 chromium processes:"
for p in /proc/[0-9]*; do
  [ -d "$p" ] || continue
  c=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)
  case "$c" in
    *--type=*) id=$(basename "$p")
      t=$(sed -n 's/^Threads:[[:space:]]*//p' "$p/status" 2>/dev/null)
      v=$(sed -n 's/^VmSize:[[:space:]]*//p' "$p/status" 2>/dev/null)
      pp=$(sed -n 's/^PPid:[[:space:]]*//p' "$p/status" 2>/dev/null)
      ty=$(printf %s "$c" | grep -o -- '--type=[a-z-]*' | head -1)
      echo "V5 pid=$id ppid=$pp threads=$t vmsize=$v $ty" ;;
  esac
done
echo V6
