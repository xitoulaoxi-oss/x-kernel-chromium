#!/bin/sh
# Late process census + role separation, in ONE script.
#
# Two questions, one pass, because each script transfer is a chance for the
# serial console to garble a heredoc:
#   1. is the page painted by now?  (log size is the proxy this project uses)
#   2. of the processes whose cmdline says --type=zygote, which are actually
#      forked renderer children?  Chromium forks renderers out of the zygote and
#      this build never rewrites their argv, so cmdline cannot tell them apart --
#      parent pid, thread count and RSS can.
set -u
export DISPLAY=:0 XAUTHORITY=/run/x11/auth
echo Q1
sleep 150
echo "Q2 log=$(wc -c < /tmp/w.log) wins=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l)"
for p in /proc/[0-9]*; do
  [ -d "$p" ] || continue
  c=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)
  id=$(basename "$p")
  ppid=$(awk '{print $4}' "$p/stat" 2>/dev/null)
  th=$(grep -i '^Threads:' "$p/status" 2>/dev/null | awk '{print $2}')
  rss=$(grep -i '^VmRSS:' "$p/status" 2>/dev/null | awk '{print $2}')
  case "$c" in
    *--type=*) ty=$(printf %s "$c" | grep -o -- '--type=[a-z-]*' | head -1) ;;
    *)         ty=$(printf %s "$c" | cut -c1-24) ;;
  esac
  echo "Q3 pid=$id ppid=$ppid threads=$th rss_kb=$rss [$ty]"
done
echo "Q4 procdirs=$(ls -d /proc/[0-9]* 2>/dev/null | wc -l)"
echo Q5
