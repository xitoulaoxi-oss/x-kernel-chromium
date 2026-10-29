#!/bin/sh
# Sum resident memory of every Chromium process from /proc/<pid>/statm.
# This is the guest-side metric the user clarified as the 1.5G qualification.
# RSS is conservative: shared pages are counted once per process, so the sum is
# an upper bound, not PSS.  Page size on this guest is 4 KiB.
tot=0; n=0
for d in /proc/[0-9]*; do
  [ -r "$d/cmdline" ] || continue
  case "$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)" in
    *chromium*) ;;
    *) continue ;;
  esac
  [ -r "$d/statm" ] || continue
  set -- $(cat "$d/statm" 2>/dev/null)
  r=$2
  [ -n "$r" ] || r=0
  kb=$((r * 4))
  tot=$((tot + kb)); n=$((n + 1))
  echo "CM pid=$(basename "$d") rss_kb=$kb"
done
echo "CMEM procs=$n total_kb=$tot total_mb=$((tot / 1024))"
