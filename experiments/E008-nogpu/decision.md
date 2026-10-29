# E008 决策（软件合成）

## 单次

- x4-win1-nogpu：first_frame=70.064，colors=835，final=835；
- 看起来可行。

## 5 次

- E008-nogpu5/run1..5：**5/5 found=false**，final 分别为 265/262/261/262/262；
- 软件合成没有解决随机 blank，不能作为稳定方案；
- 单次成功不能作为 5 次基线。

## 结论

- 随机 blank 不是（或不只是）GL/llvmpipe；--disable-gpu 无效。
- 需要抓取 blank 会话的 Chromium stderr / Xorg 日志；本轮诊断脚本未返回，未完成。
