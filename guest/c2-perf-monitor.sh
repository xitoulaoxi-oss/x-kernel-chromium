#!/bin/sh
# Guest perf part 3: 1-second milestone monitor for one browser launch.
# The renderer is a direct child of a --type=zygote process: this build does
# not rewrite the child argv, so argv cannot be used (see guest/README.md).
set -u
M=/tmp/perf.marks
T0=$(cat /tmp/perf.t0 2>/dev/null || date +%s)
cs=0; rs=0; k=0; z=; memmax=0
while [ "$k" -lt 110 ]; do
  k=$((k+1)); sleep 1
  s=$(( $(date +%s) - T0 ))
  if [ -r /proc/meminfo ]; then
    mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
    mf=$(awk '/^MemFree:/{print $2}' /proc/meminfo 2>/dev/null)
    if [ -n "$mt" ] && [ -n "$mf" ]; then
      used=$((mt - mf))
      [ "$used" -gt "$memmax" ] && memmax=$used
    fi
  fi
  if [ "$cs" -eq 0 ]; then
    n=$(ps w 2>/dev/null | grep -c 'chromium --ozone')
    [ "$n" -gt 0 ] && { cs=$s; echo "chrome_s=$s" >> "$M"; }
  fi
  if [ "$rs" -eq 0 ] && [ "$cs" -ne 0 ]; then
    [ $((k % 5)) -eq 0 ] && z=
    if [ -z "$z" ]; then
      for p in /proc/[0-9]*; do
        case "$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)" in
          *--type=zygote*) z="$z $(basename "$p")";;
        esac
      done
    fi
    if [ -n "$z" ]; then
      for p in /proc/[0-9]*; do
        pp=; th=
        while read -r a b; do
          [ "$a" = "PPid:" ] && pp=$b
          [ "$a" = "Threads:" ] && th=$b
        done < "$p/status" 2>/dev/null
        [ -n "$pp" ] || continue
        case " $z " in
          *" $pp "*)
            rs=$s
            echo "renderer_s=$s" >> "$M"
            echo "renderer_pid=$(basename "$p")" >> "$M"
            echo "renderer_threads=$th" >> "$M"
            echo "zygote_pids=$z" >> "$M"
            break
            ;;
        esac
      done
    fi
  fi
  [ "$k" -ge 90 ] && break
done
echo "marks_loops=$k" >> "$M"
echo "mem_max_used_kb=$memmax" >> "$M"
echo "done=1" >> "$M"
