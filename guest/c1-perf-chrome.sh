#!/bin/sh
# Guest perf part 2: launch Chromium, record milestones.
# renderer_s uses the process tree: renderers are forked from the zygote and never
# rewrite argv, so a child OF a zygote is the only true signal for them.
set -u
A=/run/x11/auth; U=/usr/share/kiosk/official/index.html; L=/tmp/perf.log
echo P2-BEGIN
T0=$(cat /tmp/perf.t0 2>/dev/null || date +%s)
rm -rf /tmp/pr; mkdir -p /tmp/pr; rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
setsid chromium --ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl --disable-vulkan --disable-features=Vulkan --user-data-dir=/tmp/pr --enable-logging=stderr file://$U >"$L" 2>&1 &
foz() {
  Z=$(for p in /proc/[0-9]*; do case "$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)" in *--type=zygote*) basename "$p";; esac; done | tr '\n' ' ')
  [ -n "$Z" ] || { echo 0; return; }
  n=0
  for p in /proc/[0-9]*; do
    pp=$(sed -n 's/^PPid:[[:space:]]*//p' "$p/status" 2>/dev/null)
    case " $Z " in *" $pp "*) n=$((n+1));; esac
  done
  echo "$n"
}
s=0; p=0; r=0; n=0; lb=0
while [ "$n" -lt 240 ]; do
  n=$((n+1)); sleep 1
  [ "$s" -eq 0 ] && [ "$(ps w | grep -c 'chromium --ozone')" -gt 0 ] && { echo "chrome_s=$(( $(date +%s) - T0 ))"; s=1; }
  [ "$r" -eq 0 ] && [ "$s" -eq 1 ] && [ $((n % 5)) -eq 0 ] && [ "$(foz)" -gt 0 ] && { echo "renderer_s=$(( $(date +%s) - T0 ))"; r=1; }
  lb=$(wc -c < "$L" 2>/dev/null || echo 0)
  [ "$p" -eq 0 ] && [ "$lb" -gt 10000 ] && { echo "paint_s=$(( $(date +%s) - T0 ))"; p=1; }
  [ "$p" -eq 1 ] && [ "$r" -eq 1 ] && [ "$n" -gt 45 ] && break
done
echo "painted=$p"; echo "renderer_forks=$(foz)"; echo "log_bytes=$lb"
echo "win=$(xprop -root _NET_CLIENT_LIST 2>&1 | head -1)"
echo P2-END
