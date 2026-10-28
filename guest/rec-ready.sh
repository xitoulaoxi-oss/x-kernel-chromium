#!/bin/sh
# 启动守门人（演示/帧采集）：反复拉起浏览器，直到窗口标题变成页面标题（不再是 Untitled）。
#
# 为什么需要它：实测约 1/3 的会话会停在 "Loading..." —— 浏览器把 URL 填进了地址栏，
# 但 file:// 的文档没有提交（同一时刻日志里是网络服务崩溃重启后的连接风暴）。
# 与其录到一半才发现白屏，不如把"重试"做成启动阶段的一步：最多 3 次，
# 每次最多等 100 s，成功就打印 REC-READY 并退出。
set -u
A=/run/x11/auth; export DISPLAY=:0 XAUTHORITY=$A
i=0
while [ $i -lt 3 ]; do
  i=$((i+1))
  if [ $i -gt 1 ]; then
    pkill -f "chromium --ozone" 2>/dev/null; sleep 3
    sh /tmp/xk-rec-chrome.sh again
  else
    sh /tmp/xk-rec-chrome.sh
  fi
  k=0
  while [ $k -lt 100 ]; do
    sleep 2; k=$((k+2))
    w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o "0x[0-9a-f]*" | head -1)
    [ -n "$w" ] || continue
    case "$(xprop -id $w _NET_WM_NAME 2>/dev/null)" in
      *Untitled*) ;;
      *) echo "REC-READY attempt=$i wait=${k}s";
         echo "REC-READY attempt=$i wait=${k}s" >> /tmp/stab.log; exit 0;;
    esac
  done
  echo "REC-RETRY attempt=$i did not commit a page"
done
echo "REC-FAILED after 3 attempts"
exit 1
