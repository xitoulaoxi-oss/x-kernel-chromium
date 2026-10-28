#!/bin/sh
# 拉起 Chromium（kiosk 单窗口）。用于手动演示与帧采集；发起即返回，心跳写 /tmp/stab.log。
# 被 rec-ready.sh 反复调用：$1=again 时跳过清理与心跳（重试不应该多一份心跳）。
set -u
A=/run/x11/auth; P=/tmp/pr; U=/usr/share/kiosk/official/index.html
again=${1:-}
if [ "$again" != "again" ]; then
  rm -rf $P; mkdir -p $P
  rm -f /home/kiosk/.config/chromium/Singleton* 2>/dev/null
  rm -f /tmp/stab.log
fi
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe DISPLAY=:0 XAUTHORITY=$A
setsid chromium --ozone-platform=x11 --no-sandbox --use-gl=angle --use-angle=gl \
  --disable-vulkan --disable-features=Vulkan --user-data-dir=$P \
  --enable-logging=stderr file://$U >>/tmp/w.log 2>&1 &
echo "REC-C1 launch($again) at $(date +%H:%M:%S)"
if [ "$again" != "again" ]; then
(
  t=0
  while [ $t -lt 3600 ]; do
    sleep 60; t=$((t+60))
    w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o "0x[0-9a-f]*" | wc -l)
    echo "REC-HB t=${t}s x=$(ps w | grep -c '[X]org') j=$(ps w | grep -c '[j]wm') c=$(ps w | grep -c '[c]hromium') wins=$w log=$(wc -c < /tmp/w.log) wall=$(date +%H:%M:%S)"
  done
) >>/tmp/stab.log 2>&1 &
echo "REC-C2 heartbeat -> /tmp/stab.log"
fi
