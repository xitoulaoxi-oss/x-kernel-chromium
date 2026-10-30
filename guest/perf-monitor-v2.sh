#!/bin/sh
# Low-overhead guest sampler (iteration 07).
#   * time source: /proc/uptime when the kernel exposes it; otherwise wall
#     seconds with an explicit CLOCK=wall marker (this kernel has no uptime file)
#   * memory every 2 s, process scan every 6 s (not every tick)
#   * renderer candidates are direct children of a chromium zygote; the host
#     must still confirm the role for the recorded PID in the same session
set -u
OUT=${1:-/tmp/xk-perf-marks}
DURATION=${2:-120}
rm -f "$OUT"

now() {
  v=$(cut -d' ' -f1 /proc/uptime 2>/dev/null || true)
  if [ -n "$v" ]; then echo "uptime:$v"; else echo "wall:$(date +%s)"; fi
}

T0=$(now)
echo "MONO_T0=$T0" >> "$OUT"

mem_sample() {
  mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
  mf=$(awk '/^MemFree:/{print $2}' /proc/meminfo 2>/dev/null)
  if [ -n "$mt" ] && [ -n "$mf" ]; then
    echo "MONO=$(now) MEM_USED_KB=$((mt - mf))" >> "$OUT"
  fi
}

scan_renderer() {
  z=""
  for d in /proc/[0-9]*; do
    [ -r "$d/comm" ] || continue
    [ "$(cat "$d/comm" 2>/dev/null)" = chromium ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null || true)
    case "$cmd" in *--type=zygote*) z="$z ${d##*/}";; esac
  done
  [ -n "$z" ] || return 0
  for d in /proc/[0-9]*; do
    [ -r "$d/status" ] || continue
    ppid=$(awk '/^PPid:/{print $2}' "$d/status" 2>/dev/null)
    case " $z " in *" $ppid "*) ;; *) continue;; esac
    th=$(awk '/^Threads:/{print $2}' "$d/status" 2>/dev/null)
    st=$(awk '{print $22}' "$d/stat" 2>/dev/null)
    echo "MONO=$(now) RENDERER pid=${d##*/} start=${st:-na} threads=$th" >> "$OUT"
  done
}

start=$(date +%s)
i=0
while :; do
  sleep 2
  i=$((i + 1))
  mem_sample
  if [ $((i % 3)) -eq 0 ]; then scan_renderer; fi
  [ $(( $(date +%s) - start )) -ge "$DURATION" ] && break
done
echo "MONO_END=$(now)" >> "$OUT"
