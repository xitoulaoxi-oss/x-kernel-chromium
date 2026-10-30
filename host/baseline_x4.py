#!/usr/bin/env python3
"""Five-round baseline for the plain x4 (real startup) chain.

Differences from baseline_run.py: the launch is the same x4 script used by the
20-start test, and the frame-watch t0 is the launch-dispatch origin.  Renderer
creation is a 1 Hz guest monitor; the PID must also appear in Chromium's own
SystemInfo renderer list in the same session.

Usage:
    python host/baseline_x4.py --kernel artifacts/kernel-final.bin \
        --repeats 5 --tag x4final --out evidence/baseline/x4final.json
"""
from __future__ import annotations
import argparse, datetime, json, pathlib, re, statistics, subprocess, sys, time

WS = pathlib.Path(__file__).resolve().parent.parent
POWERSHELL = "powershell"
ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
EXPECTED = "file:///usr/share/kiosk/official/index.html"

DEFS = {
    "startup_first_frame_s": {
        "unit": "s", "origin": "frame-watch t0 = launch dispatch", "resolution_s": 10.0,
        "method": "QEMU screendump; first frame with saturation>=0.06, >=300 colours, not blank",
        "type": "sampled upper bound",
    },
    "page_load_s": {
        "unit": "s", "origin": "frame-watch t0 (host UTC)", "resolution_s": 0.001,
        "method": "page performance.timeOrigin + navigation.loadEventEnd minus frame-watch t0",
        "type": "browser-clock exact, requires guest/host epoch agreement",
    },
    "renderer_creation_s": {
        "unit": "s", "origin": "/tmp/perf.t0 just before launch", "resolution_s": 1.0,
        "method": "1 Hz guest monitor first zygote child; accepted only if Chromium SystemInfo lists that PID",
        "type": "sampled, role-confirmed",
    },
    "peak_guest_used_mb": {
        "unit": "MB", "origin": "launch -> harvest", "resolution_s": 1.0,
        "method": "max(MemTotal-MemFree) over 1 Hz guest samples; whole-guest upper bound",
        "type": "sampled upper bound",
    },
}


def load(p):
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8-sig"))
    except Exception:
        return None


def text_of(d):
    p = d / "console.log"
    return "" if not p.is_file() else ANSI.sub("", p.read_text(encoding="utf-8", errors="replace"))


def num(text, key):
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
        "-Script", "guest\\06-fetch-pages.sh;guest\\x1-input.sh;guest\\x2-xorg.sh;guest\\y3-jwm-stock.sh;guest\\x4-perf-monitor-start.sh",
        "-Upload", "guest\\x4-win1.sh;guest\\c2-perf-monitor.sh;guest\\x4-perf-monitor-start.sh;guest\\chrome-mem.sh",
        "-FrameWatch", "10x150", "-FrameWatchCmd", "sh /tmp/xk-x4-win1.sh",
        "-EnableGuestCdp", "-PageProbeMode", "page", "-ExpectedPageUrl", EXPECTED,
        "-CollectBrowserProcesses",
        "-Key", "cmd=cat /tmp/perf.marks;cmd=sh /tmp/xk-chrome-mem.sh",
        "-Tag", f"X4B{n:02d}", "-OutDir", str(d),
        "-CommandTimeoutSec", "400", "-BootTimeoutSec", "420", "-AfterScriptWait", "10",
    ]
    t0 = time.time()
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    (d / "harness.out.txt").write_text(proc.stdout or "", encoding="utf-8")
    (d / "harness.err.txt").write_text(proc.stderr or "", encoding="utf-8")
    (d / "harness-result.json").write_text(json.dumps({"exit_code": proc.returncode}), encoding="utf-8")
    text = text_of(d)
    page = load(d / "page-check.json") or {}
    fw = load(d / "frame-watch.json") or {}
    bp = load(d / "browser-processes.json") or {}
    qm = load(d / "qemu-metrics.json") or {}
    t0_epoch = None
    if fw.get("t0_utc"):
        t0_epoch = datetime.datetime.fromisoformat(fw["t0_utc"].replace("Z", "+00:00")).timestamp()
    nav = None; page_load = None; epoch_delta = None
    if t0_epoch and page.get("time_origin"):
        epoch_delta = round(page["time_origin"] / 1000.0 - t0_epoch, 3)
        nav = epoch_delta
        if page.get("page_load_end_ms") and page.get("ok") and page.get("url") == EXPECTED:
            page_load = round(page["page_load_end_ms"] / 1000.0 - t0_epoch, 3)
    renderer_raw = num(text, "renderer_s")
    pid = None
    m = re.findall(r"^renderer_pid=(\d+)\s*$", text, re.M)
    if m:
        pid = int(m[-1])
    confirmed = bool(pid and pid in (bp.get("renderer_pids") or []))
    peak = num(text, "mem_max_used_kb")
    return {
        "run": n, "wall_s": round(time.time() - t0, 1), "harness_rc": proc.returncode,
        "url": page.get("url"), "page_ok": page.get("ok"),
        "t0_utc": fw.get("t0_utc"),
        "startup_first_frame_s": (fw.get("analysis") or {}).get("first_frame_s"),
        "navigation_start_s": nav,
        "page_load_s": page_load,
        "epoch_delta_s": epoch_delta,
        "renderer_creation_s": renderer_raw if confirmed else None,
        "renderer_s_raw": renderer_raw,
        "renderer_pid": pid, "renderer_role_confirmed": confirmed,
        "peak_guest_used_mb": round(peak / 1024.0, 1) if peak else None,
        "peak_host_qemu_mb": round((qm.get("peak_working_set_b") or 0) / (1024 * 1024), 1) if qm else None,
        "evidence_dir": str(d),
    }


def summary(samples, key):
    vals = [s[key] for s in samples if isinstance(s.get(key), (int, float))]
    if not vals:
        return {"n": 0, "median": None}
    return {"n": len(vals), "median": round(statistics.median(vals), 3),
            "min": min(vals), "max": max(vals), "spread": round(max(vals) - min(vals), 3),
            "all": vals}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel", default="artifacts/kernel-final.bin")
    ap.add_argument("--disk", default=r"D:\x-kernel-dsh-bridge\delivered\agentos-disk.img")
    ap.add_argument("--repeats", type=int, default=5)
    ap.add_argument("--tag", default="x4final")
    ap.add_argument("--out", default="evidence/baseline/x4final.json")
    args = ap.parse_args()
    out = WS / args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    outdir = out.parent / args.tag
    outdir.mkdir(parents=True, exist_ok=True)
    samples = []
    for n in range(1, args.repeats + 1):
        print(f"--- x4 baseline {n}/{args.repeats} ---", flush=True)
        s = run_one(args.kernel, args.disk, outdir, n)
        samples.append(s)
        print("   ", {k: s[k] for k in ("harness_rc", "page_ok", "startup_first_frame_s",
                                        "navigation_start_s", "page_load_s", "renderer_creation_s",
                                        "renderer_role_confirmed", "peak_guest_used_mb")}, flush=True)
    doc = {
        "schema": "xk-baseline-x4/1",
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "kernel": args.kernel, "repeats": args.repeats,
        "definitions": DEFS, "samples": samples,
        "summary": {k: summary(samples, k) for k in DEFS},
        "failure_rate": round(sum(1 for s in samples if s["harness_rc"] != 0 or not s["page_ok"]) / len(samples), 3),
        "notes": [
            "first_frame and peak memory are sampled upper bounds; page load is a browser-clock interval.",
            "renderer_creation_s is reported only when Chromium's process list confirms the PID role.",
            "A run whose DOM check failed is not used for page_load or renderer_creation.",
        ],
    }
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(doc["summary"], ensure_ascii=False, indent=2))
    print("wrote", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
