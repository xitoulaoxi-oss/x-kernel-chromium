#!/bin/sh
# Task 07 diagnostic: normal launch, then dump the state that distinguishes
# "page never committed" from "page committed but not painted".
# Fixed 75 s wait so the same point is sampled in every run.
set -u
A=/run/x11/auth; P=/tmp/pr
U=/usr/share/kiosk/official/index.html
rm -rf $P; mkdir -p $P
rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
GL="--ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl --disable-vulkan --disable-features=Vulkan"
setsid chromium $GL --user-data-dir=$P --enable-logging=stderr file://$U >/tmp/w.log 2>&1 &
echo "D0 started pid=$!"
sleep 75

echo D1-WINDOWS
xprop -root _NET_CLIENT_LIST
for id in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*'); do
  echo "D1 win=$id"
  xprop -id $id WM_NAME _NET_WM_PID 2>&1 | head -3
done

echo D2-PROCS
echo "D2 total=$(ps w | grep -c '[c]hromium') renderer=$(ps w | grep -c '[-]-type=renderer') gpu=$(ps w | grep -c '[-]-type=gpu') utility=$(ps w | grep -c '[-]-type=utility') zygote=$(ps w | grep -c '[-]-type=zygote')"
ps w | grep '[c]hromium' | head -25

echo D3-LOG
echo "D3 bytes=$(wc -c < /tmp/w.log)"
echo "D3 network_crash=$(grep -c 'Network service crashed' /tmp/w.log)"
grep -E 'ERROR|FATAL|crash|Network service|renderer' /tmp/w.log | tail -30
echo D3-TAIL
tail -12 /tmp/w.log

echo D4-SHM
ls -l /dev/shm 2>&1 | head -10
df -h /dev/shm /tmp 2>&1
echo "D4 meminfo:"; head -3 /proc/meminfo

echo D5-KERNEL
dmesg 2>/dev/null | tail -15
echo D6-DONE
