#!/usr/bin/env python3
"""Five-round baseline collector for the four finals metrics (task 05).

Definition (fixed before the first run, see --defs):
  1. startup_first_frame_s: launch dispatch -> first screendump whose page area
     has content (frame_stats thresholds).  Sampling upper bound.
  2. page_load_s: launch -> DOM loadEventEnd, read through CDP; exact to the
     browser clock, but depends on guest epoch == guest launch epoch.
  3. renderer_creation_s: X server start -> first child of a zygote (1 Hz guest
     monitor), accepted only if that PID is reported as a renderer by Chromium
     SystemInfo.getProcessInfo in the same session.
  4. peak_guest_used_mb: max of (MemTotal - MemFree) sampled at 1 Hz in the
     guest; whole-guest upper bound, not per-process RSS.

Usage:
    python host/baseline_run.py --kernel artifacts/kernel-idlefix.bin \
        --repeats 5 --tag base1 --out evidence/baseline/base1.json
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import statistics
import subprocess
import sys
import time

WS = pathlib.Path(__file__).resolve().parent.parent
PY = sys.executable
POWERSHELL = "powershell"
ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")

DEFS = {
    "startup_first_frame_s": {
        "unit": "s", "origin": "launch line dispatched", "resolution_s": 5.0,
        "method": "QEMU screendump; first frame with saturation>=0.06, >=300 colours, not blank",
        "type": "sampled upper bound",
    },
    "page_load_s": {
        "unit": "s", "origin": "launch line dispatched", "resolution_s": 0.001,
        "method": "CDP DOM: performance.timeOrigin + navigation.loadEventEnd, minus guest launch_epoch",
        "type": "browser-clock exact (same guest epoch)",
    },
    "renderer_creation_s": {
        "unit": "s", "origin": "X server start (/tmp/perf.t0)", "resolution_s": 1.0,
        "method": "1 Hz guest monitor first zygote child + Chromium SystemInfo renderer PID confirmation",
        "type": "sampled, role-confirmed",
    },
    "peak_guest_used_mb": {
        "unit": "MB", "origin": "launch -> harvest", "resolution_s": 1.0,
        "method": "max(MemTotal-MemFree) over 1 Hz guest samples; whole-guest upper bound",
        "type": "sampled upper bound (not per-process RSS)",
    },
}


def load(p):
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8-sig"))
    except Exception:
        return None


def transcript(d):
    p = d / "console.log"
    if not p.is_file():
        return ""
    return ANSI.sub("", p.read_text(encoding="utf-8", errors="replace"))


def kv(text, key):
    m = re.findall(rf"^{re.escape(key)}=([0-9.]+)\s*$", text, re.M)
    return float(m[-1]) if m else None


def run_one(kernel, disk, outdir, n):
    d = outdir / f"run{n:02d}"
    d.mkdir(parents=True, exist_ok=True)
    cmd = [
        POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", str(WS / "host" / "xkwin.ps1"),
        "-Kernel", kernel, "-Disk", disk,
        "-ServeManifest", "guest\\serve-pages.txt",
        "-Script", "guest\\06-fetch-pages.sh;guest\\x1-input.sh;guest\\x2-xorg.sh;guest\\y3-jwm-stock.sh;guest\\c2-perf-prep.sh",
        "-Upload", "guest\\c2-perf-launch.sh;guest\\c2-perf-monitor.sh;guest\\c1-perf-harvest.sh",
        "-FrameWatch", "10x150", "-FrameWatchCmd", "sh /tmp/xk-c2-perf-launch.sh",
        "-Key", "cmd=sh /tmp/xk-c1-perf-harvest.sh",
        "-EnableGuestCdp", "-PageProbeMode", "page",
        "-ExpectedPageUrl", "file:///usr/share/kiosk/official/index.html",
        "-CollectBrowserProcesses",
        "-Tag", f"BASE{n:02d}", "-OutDir", str(d),
        "-CommandTimeoutSec", "400", "-BootTimeoutSec", "420", "-AfterScriptWait", "15",
    ]
    t0 = time.time()
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    (d / "harness.out.txt").write_text(proc.stdout or "", encoding="utf-8")
    (d / "harness.err.txt").write_text(proc.stderr or "", encoding="utf-8")
    (d / "harness-result.json").write_text(json.dumps({"exit_code": proc.returncode}), encoding="utf-8")
    text = transcript(d)
    page = load(d / "page-check.json") or {}
    fw = load(d / "frame-watch.json") or {}
    bp = load(d / "browser-processes.json") or {}
    qm = load(d / "qemu-metrics.json") or {}
    launch = kv(text, "launch_epoch")
    renderer_s = kv(text, "renderer_s")
    renderer_pid = None
    m = re.findall(r"^renderer_pid=(\d+)\s*$", text, re.M)
    if m:
        renderer_pid = int(m[-1])
    renderer_confirmed = bool(renderer_pid and renderer_pid in (bp.get("renderer_pids") or []))
    first_frame = (fw.get("analysis") or {}).get("first_frame_s")
    page_load = None
    if launch and page.get("page_load_end_ms") and page.get("ok") and page.get("url") == "file:///usr/share/kiosk/official/index.html":
        page_load = round(page["page_load_end_ms"] / 1000.0 - launch, 3)
    peak_used = kv(text, "mem_max_used_kb")
    return {
        "run": n,
        "wall_s": round(time.time() - t0, 1),
        "harness_rc": proc.returncode,
        "url": page.get("url"), "title": page.get("title"), "page_ok": page.get("ok"),
        "launch_epoch": launch,
        "startup_first_frame_s": first_frame,
        "page_load_s": page_load,
        "renderer_creation_s": renderer_s if renderer_confirmed else None,
        "renderer_s_raw": renderer_s,
        "renderer_pid": renderer_pid,
        "renderer_role_confirmed": renderer_confirmed,
        "peak_guest_used_mb": round(peak_used / 1024.0, 1) if peak_used else None,
        "peak_host_qemu_mb": round((qm.get("peak_working_set_b") or 0) / (1024 * 1024), 1) if qm else None,
        "evidence_dir": str(d),
    }


def summarise(samples, key):
    vals = [s[key] for s in samples if isinstance(s.get(key), (int, float))]
    if not vals:
        return {"n": 0, "median": None}
    return {"n": len(vals), "median": round(statistics.median(vals), 3),
            "min": min(vals), "max": max(vals),
            "spread": round(max(vals) - min(vals), 3),
            "all": vals}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel", default="artifacts/kernel-idlefix.bin")
    ap.add_argument("--disk", default=r"D:\x-kernel-dsh-bridge\delivered\agentos-disk.img")
    ap.add_argument("--repeats", type=int, default=5)
    ap.add_argument("--tag", default="base1")
    ap.add_argument("--out", default="evidence/baseline/baseline.json")
    args = ap.parse_args()
    out = WS / args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    outdir = out.parent / args.tag
    outdir.mkdir(parents=True, exist_ok=True)
    samples = []
    for n in range(1, args.repeats + 1):
        print(f"--- baseline run {n}/{args.repeats} ---", flush=True)
        s = run_one(args.kernel, args.disk, outdir, n)
        samples.append(s)
        print("   ", {k: s[k] for k in ("harness_rc", "page_ok", "startup_first_frame_s",
                                        "page_load_s", "renderer_creation_s", "renderer_role_confirmed",
                                        "peak_guest_used_mb")}, flush=True)
    doc = {
        "schema": "xk-baseline/1",
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "kernel": args.kernel,
        "repeats": args.repeats,
        "definitions": DEFS,
        "samples": samples,
        "summary": {k: summarise(samples, k) for k in DEFS},
        "failure_rate": round(sum(1 for s in samples if s["harness_rc"] != 0 or not s["page_ok"]) / len(samples), 3),
        "notes": [
            "No value is treated as PASS if the session failed or the DOM check failed.",
            "first_frame and peak memory are sampled upper bounds; page load is a browser-clock interval.",
            "renderer_s is only reported when Chromium's own process list confirms the PID role.",
        ],
    }
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(doc["summary"], ensure_ascii=False, indent=2))
    print("wrote", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
