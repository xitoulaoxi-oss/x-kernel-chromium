# Observability

- `host/page_probe.py`: actual URL, document completion, navigation identity and JS/CSS/input results.
- `host/browser_probe.py` + `host/process_identity_check.py`: browser-reported roles joined to guest procfs. Missing evidence is a structured failure.
- `host/css_layout_probe.py`: matching page hash, browser version, viewport, finite geometry and key styles. Linux headless is a reference only.
- `host/observe.py`: crash, hang and memory-growth signals from saved session logs; attribution limits remain explicit.
- `host/acceptance/`: strict cold-start, stability/load and rehearsal aggregators.
- `host/xkwin.ps1`: bounded guest/QMP failure diagnostics before cleanup; screenshots via QEMU screendump.

Fixtures test parsing and false-positive rejection. They do not replace real QEMU fault scenarios or prove a memory leak. Current observations: [evidence](../evidence/README.md).

- `host/baseline_x4b.py` / `host/baseline_x4.py`: five-round first-frame/page-load collector; the x4 variant adds a 1 Hz monitor, which was itself found to perturb startup and is kept as a negative result.
- `guest/fault-renderer.sh`, `guest/fault-growth.sh`: controlled crash/stop/leak injections for task 09.
- `host/page_probe.py` now also returns `page_load_end_ms` and `dom_content_loaded_ms` from the Navigation Timing entry, so page load is a browser-clock interval rather than a screenshot guess.


## 2026-10-31 checkpoint clarification

监控5轮中3轮在上传前失败，不能证明监控导致5/5失败。新事件环和冻结导出见 [阶段说明](checkpoint-20261031.md)；完整故障诊断仍待验证。
