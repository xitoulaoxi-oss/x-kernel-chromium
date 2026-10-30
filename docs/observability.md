# Observability

- `host/page_probe.py`: actual URL, document completion, navigation identity and JS/CSS/input results.
- `host/browser_probe.py` + `host/process_identity_check.py`: browser-reported roles joined to guest procfs. Missing evidence is a structured failure.
- `host/css_layout_probe.py`: matching page hash, browser version, viewport, finite geometry and key styles. Linux headless is a reference only.
- `host/observe.py`: crash, hang and memory-growth signals from saved session logs; attribution limits remain explicit.
- `host/acceptance/`: strict cold-start, stability/load and rehearsal aggregators.
- `host/xkwin.ps1`: bounded guest/QMP failure diagnostics before cleanup; screenshots via QEMU screendump.

Fixtures test parsing and false-positive rejection. They do not replace real QEMU fault scenarios or prove a memory leak. Current observations: [evidence](../evidence/README.md).
