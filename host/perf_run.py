#!/usr/bin/env python3
"""Run the guest performance session N times and report median + spread per metric.

Why this exists: the task book's "performance observation and quantification"
item requires each metric to be repeated at least 5 times and reported as a
median with its fluctuation range, together with the host CPU model, memory,
QEMU version and OS.  A single run cannot satisfy that, so the repetition and
the statistics are scripted here rather than done by hand.

What changed after the first submission, and why:

  * page-load latency is no longer "the browser log crossed 10 KB".  That was a
    PROXY, and a bad one: it moves when the kernel log gets chatty, and it says
    nothing about pixels.  The measurement now comes from the framebuffer --
    xkwin.ps1 -FrameWatch captures a screendump on a fixed cadence from the
    moment the launch line is dispatched, and host/frame_stats.py decides the
    first frame that carries the page.  The committee's own evidence channel is
    the QEMU monitor screendump, so the number is measured the way it will be
    reviewed.
  * renderer creation is no longer polled every 5 s.  The guest monitor now
    samples once a second and records the renderer's pid and thread count, so
    the value is not quantised to a 5 s grid.
  * two resource RATES were added, because they are named separately in the task
    book and both need a denominator: CPU usage (cpu seconds / wall seconds) and
    QEMU memory occupancy (peak working set / host physical memory).  Both
    denominators are captured by the harness during the run, not assumed here.
  * every metric now carries the sampling resolution it was measured at, so a
    reader can see that "1 s" is the floor for guest-side milestones.

Usage:
    python host/perf_run.py --repeats 5
    python host/perf_run.py --repeats 5 --kernel artifacts/kernel-procfs.bin
    python host/perf_run.py --reparse --tag pf3      # rebuild from evidence on disk

Paths are resolved against the repository root (the parent of host/), so the
defaults work from inside the checkout with no extra arguments.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import platform
import re
import statistics
import subprocess
import sys
import time

# The run is a sequence with two phases that must not be confused:
#   1) setup (pages, X, jwm, profile reset) -- cheap things that may take time;
#   2) the measured launch -- one console line, dispatched by -FrameWatchCmd at
#      t=0 of the frame watch.
GUEST_SCRIPTS = (
    "guest\\06-fetch-pages.sh;"
    "guest\\c1-perf-x.sh;"
    "guest\\c2-perf-prep.sh"
)
# Uploaded and verified before t=0 so the launch line costs one round trip.
GUEST_UPLOADS = (
    "guest\\c2-perf-launch.sh;"
    "guest\\c2-perf-monitor.sh;"
    "guest\\c1-perf-harvest.sh"
)
SERVE_MANIFEST = "guest\\serve-pages.txt"
FRAME_WATCH = "2x140"                                  # 2 s cadence, 140 s window
FRAME_WATCH_CMD = "sh /tmp/xk-c2-perf-launch.sh"
HARVEST_CMD = "cmd=sh /tmp/xk-c1-perf-harvest.sh"

# One entry per metric: which task-book class it belongs to, what it is measured
# from, and at what resolution.  This table IS the coverage claim, so it is part
# of the report rather than prose in a document that can drift from the data.
METRIC_DEFS = {
    "xorg_s": {
        "class": "startup", "unit": "s", "origin": "X server start (guest /tmp/perf.t0)",
        "method": "guest wall clock until /tmp/.X11-unix/X0 exists",
        "source": "guest console", "resolution_s": 1.0, "direction": "lower-is-better",
    },
    "jwm_s": {
        "class": "startup", "unit": "s", "origin": "X server start",
        "method": "guest wall clock until the window manager is spawned",
        "source": "guest console", "resolution_s": 1.0, "direction": "lower-is-better",
    },
    "chrome_s": {
        "class": "startup", "unit": "s", "origin": "X server start",
        "method": "guest monitor: first second a chromium main process exists",
        "source": "guest console", "resolution_s": 1.0, "direction": "lower-is-better",
    },
    "first_frame_s": {
        "class": "page-load", "unit": "s", "origin": "launch line dispatched on the console",
        "method": "QEMU screendump series; first frame whose page area carries content "
                  "(saturation>=0.06 AND >=300 colours AND not blank).  Colour count alone "
                  "was NOT enough: an empty browser window with a spinner measures 264 colours",
        "source": "host framebuffer (frame-watch.json)", "resolution_s": 2.0,
        "direction": "lower-is-better",
    },
    "renderer_s": {
        "class": "renderer-creation", "unit": "s", "origin": "X server start",
        "method": "guest monitor at 1 Hz: first process whose PPid is a --type=zygote process",
        "source": "guest console", "resolution_s": 1.0, "direction": "lower-is-better",
    },
    "peak_mem_mb": {
        "class": "peak-memory", "unit": "MB", "origin": "whole QEMU process lifetime",
        "method": "Process.PeakWorkingSet64 of qemu-system-aarch64 (OS high-water mark)",
        "source": "host process metrics", "resolution_s": None, "direction": "lower-is-better",
    },
    "cpu_pct": {
        "class": "cpu-usage", "unit": "% of one logical CPU", "origin": "whole QEMU process lifetime",
        "method": "TotalProcessorTime / wall clock x 100 (host-side, from qemu-metrics.json)",
        "source": "host process metrics", "resolution_s": None, "direction": "lower-is-better",
    },
    "cpu_pct_load": {
        "class": "cpu-usage", "unit": "% of one logical CPU",
        "origin": "launch dispatch -> first painted frame",
        "method": "QEMU CPU seconds consumed between the first and the first-frame capture, "
                  "divided by that interval (both sampled with the frames)",
        "source": "host framebuffer (frame-watch.json)", "resolution_s": 2.0,
        "direction": "lower-is-better",
    },
    "qemu_mem_pct": {
        "class": "qemu-memory-rate", "unit": "% of host physical memory",
        "origin": "whole QEMU process lifetime",
        "method": "PeakWorkingSet64 / host physical memory x 100 (GlobalMemoryStatusEx)",
        "source": "host process metrics", "resolution_s": None, "direction": "lower-is-better",
    },
}

# Counters are reported but not scored: they explain a metric without being one.
COUNTER_KEYS = ("renderer_forks", "renderer_threads", "log_bytes", "chrome_pids",
                "marks_loops", "harvest_wait")
GUEST_INT_KEYS = ("xorg_s", "jwm_s", "chrome_s", "renderer_s") + COUNTER_KEYS
DERIVED_FLOAT_KEYS = ("first_frame_s", "first_frame_lo_s", "first_frame_bracket_s",
                      "peak_mem_mb", "cpu_s", "wall_s", "cpu_pct", "cpu_pct_load", "qemu_mem_pct")


def find_powershell() -> str:
    """Locate a PowerShell to drive the harness ($XK_POWERSHELL wins)."""
    import os
    import shutil

    cands = [
        os.environ.get("XK_POWERSHELL"),
        shutil.which("pwsh"),
        shutil.which("powershell"),
        os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                     r"System32\WindowsPowerShell\v1.0\powershell.exe"),
        r"C:\Program Files\PowerShell\7\pwsh.exe",
    ]
    for c in cands:
        if c and pathlib.Path(c).is_file():
            return c
    found = shutil.which("pwsh") or shutil.which("powershell")
    if found:
        return found
    raise SystemExit(
        "PowerShell not found. Set $env:XK_POWERSHELL to a powershell.exe or pwsh.exe."
    )


def find_qemu() -> str:
    """Locate qemu-system-aarch64, for the version string in the report."""
    import os
    import shutil

    cands = [
        os.environ.get("XK_QEMU"),
        shutil.which("qemu-system-aarch64"),
        os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"),
                     r"qemu\qemu-system-aarch64.exe"),
    ]
    for c in cands:
        if c and pathlib.Path(c).is_file():
            return c
    return ""


POWERSHELL = find_powershell()


def host_memory_mb() -> "float | None":
    """Host physical memory in MB.

    Get-CimInstance is refused on this host and wmic does not exist, so the
    registry-only workaround the previous version used had to report memory as
    "unavailable".  ctypes can call GlobalMemoryStatusEx directly, and a memory
    occupancy RATE without its denominator is not a measurement.
    """
    try:
        import ctypes

        class MEMORYSTATUSEX(ctypes.Structure):
            _fields_ = [
                ("dwLength", ctypes.c_ulong),
                ("dwMemoryLoad", ctypes.c_ulong),
                ("ullTotalPhys", ctypes.c_ulonglong),
                ("ullAvailPhys", ctypes.c_ulonglong),
                ("ullTotalPageFile", ctypes.c_ulonglong),
                ("ullAvailPageFile", ctypes.c_ulonglong),
                ("ullTotalVirtual", ctypes.c_ulonglong),
                ("ullAvailVirtual", ctypes.c_ulonglong),
                ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
            ]

        m = MEMORYSTATUSEX()
        m.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
        if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m)):
            return round(m.ullTotalPhys / (1024 * 1024), 0)
    except Exception:  # noqa: BLE001 - a missing denominator is reported, not guessed
        return None
    return None


def host_facts() -> dict:
    """The host details the submission has to state."""
    facts = {
        "os": f"{platform.system()} {platform.release()} ({platform.version()})",
        "machine": platform.machine(),
        "python": platform.python_version(),
        "logical_cpus": None,
        "memory_mb": host_memory_mb(),
    }
    probe = (
        r"$cpu = (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0').ProcessorNameString;"
        r"$os = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion';"
        "Write-Output $cpu.Trim();"
        "Write-Output ($os.ProductName + ' ' + $os.DisplayVersion + ' build ' + $os.CurrentBuild);"
        "Write-Output $env:NUMBER_OF_PROCESSORS"
    )
    try:
        out = subprocess.run(
            [POWERSHELL, "-NoProfile", "-Command", probe],
            capture_output=True, text=True, timeout=60,
        )
        lines = [l.strip() for l in out.stdout.splitlines() if l.strip()]
        if lines:
            facts["cpu"] = lines[0]
        if len(lines) > 1:
            facts["os_registry"] = lines[1]
        if len(lines) > 2 and lines[2].isdigit():
            facts["logical_cpus"] = int(lines[2])
    except Exception as exc:  # noqa: BLE001 - host probing is best-effort
        facts["cpu"] = f"unavailable ({exc.__class__.__name__})"
    return facts


def qemu_version() -> str:
    exe = find_qemu()
    if not exe:
        return "unavailable (qemu-system-aarch64 not found; set $env:XK_QEMU)"
    try:
        out = subprocess.run([exe, "--version"], capture_output=True, text=True, timeout=30)
        return out.stdout.splitlines()[0].strip() if out.stdout else "unknown"
    except Exception as exc:  # noqa: BLE001
        return f"unavailable ({exc.__class__.__name__})"


def read_qemu_metrics(run_dir: "pathlib.Path | None") -> dict:
    """Everything the harness wrote about the QEMU process itself.

    The sidecar holds raw counters plus the denominators their ratios need
    (wall clock, host RAM, guest RAM, vCPU count).  Nothing here is derived:
    the report does the arithmetic, so a reviewer can redo it from this file.
    """
    empty = {"peak_mem_mb": None, "cpu_s": None, "wall_s": None,
             "cpu_pct": None, "qemu_mem_pct": None,
             "smp_cpus": None, "guest_mem_mb": None, "host_ram_mb": None}
    if run_dir is None:
        return empty
    path = run_dir / "qemu-metrics.json"
    if not path.is_file():
        return empty
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001 - a broken sidecar is "not measured"
        return empty
    peak_b = data.get("peak_working_set_b") or 0
    cpu_s = data.get("cpu_seconds")
    wall_s = data.get("wall_seconds")
    host_ram_b = data.get("host_ram_b")
    out = dict(empty)
    out["peak_mem_mb"] = round(peak_b / (1024 * 1024), 1) if peak_b else None
    out["cpu_s"] = cpu_s
    out["wall_s"] = wall_s
    out["smp_cpus"] = data.get("smp_cpus")
    out["guest_mem_mb"] = data.get("guest_mem_mb")
    out["host_ram_mb"] = round(host_ram_b / (1024 * 1024), 1) if host_ram_b else None
    if cpu_s is not None and wall_s:
        out["cpu_pct"] = round(cpu_s / wall_s * 100.0, 2)
    denominator = host_ram_b or (host_memory_mb() or 0) * 1024 * 1024
    if peak_b and denominator:
        out["qemu_mem_pct"] = round(peak_b / denominator * 100.0, 3)
    return out


# The console interleaves the guest's key=value lines with kernel log output,
# and a kernel line that lands mid-line leaves an ANSI reset in front of the
# value (observed: "\x1b[mrenderer_s=33").  Stripping the escapes is what makes
# the line start where the pattern expects it to.
ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def read_transcript(run_dir: "pathlib.Path") -> str:
    """The run's console transcript, with terminal escapes removed."""
    path = run_dir / "console.log"
    if not path.is_file():
        return ""
    return ANSI_RE.sub("", path.read_text(encoding="utf-8", errors="replace"))


def parse_output(text: str) -> dict:
    """Guest-side integers.

    Anchored to a whole line on purpose: the harness echoes every script's
    source into the transcript, so a looser pattern would happily match the
    script that prints the value instead of the value.
    """
    vals = {}
    for key in GUEST_INT_KEYS:
        m = re.search(rf"(?m)^{key}=(\d+)\s*$", text)
        if m:
            vals[key] = int(m.group(1))
    return vals


def read_frame_watch(run_dir: "pathlib.Path") -> dict:
    """The framebuffer measurement of the first painted frame.

    Returns an empty dict when the run has no frame-watch file (older sessions,
    or a build of the harness without -FrameWatch): a missing measurement must
    show up as a smaller n, never as a zero that silently averages in.
    """
    path = run_dir / "frame-watch.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return {}
    analysis = data.get("analysis") or {}
    out = {
        "frame_watch_interval_s": data.get("interval_s"),
        "frames_measured": data.get("frames_measured"),
        "baseline_colors": data.get("baseline_colors_median"),
        "sat_floor": data.get("sat_floor"),
        "colour_floor": data.get("colour_floor"),
    }
    if analysis.get("found"):
        out["first_frame_s"] = analysis.get("first_frame_s")
        out["first_frame_lo_s"] = analysis.get("first_frame_lo_s")
        out["first_frame_bracket_s"] = analysis.get("first_frame_bracket_s")
        out["cpu_pct_load"] = analysis.get("cpu_pct_to_first_frame")
    return out


def summarise(samples: list, key: str) -> "dict | None":
    """median / min / max / spread plus the relative dispersion a reviewer asks for."""
    vals = [s[key] for s in samples if isinstance(s.get(key), (int, float))]
    if not vals:
        return None
    vals_sorted = sorted(vals)
    med = statistics.median(vals_sorted)
    spread = vals_sorted[-1] - vals_sorted[0]
    cv = None
    mean = statistics.fmean(vals_sorted)
    if len(vals_sorted) > 1 and mean:
        cv = round(statistics.stdev(vals_sorted) / mean * 100.0, 2)
    d = METRIC_DEFS.get(key, {})
    return {
        "class": d.get("class", "counter"),
        "unit": d.get("unit"),
        "n": len(vals_sorted),
        "median": med,
        "min": vals_sorted[0],
        "max": vals_sorted[-1],
        "spread": round(spread, 3),
        "spread_pct_of_median": round(spread / med * 100.0, 2) if med else None,
        "cv_pct": cv,
        "resolution_s": d.get("resolution_s"),
        "raw": vals_sorted if key not in ("first_frame_s",) else [s.get(key) for s in samples if s.get(key) is not None],
    }


def class_coverage(summary: dict) -> list:
    """Which classes are backed by >= 5 complete samples, stated explicitly.

    The scoring rule is a step function (2 classes = 1 point, 3 = 2, >= 4 = 4),
    so the report computes the step instead of leaving it to a reading of the
    summary table.
    """
    classes = {}
    for key, s in summary.items():
        if s["class"] == "counter":
            continue
        c = classes.setdefault(s["class"], {"class": s["class"], "metrics": [], "n_min": None})
        c["metrics"].append(key)
        c["n_min"] = s["n"] if c["n_min"] is None else min(c["n_min"], s["n"])
    rows = []
    for c in classes.values():
        rows.append({
            "class": c["class"],
            "metrics": sorted(c["metrics"]),
            "complete_samples": c["n_min"],
            "meets_5_repeats": (c["n_min"] or 0) >= 5,
        })
    rows.sort(key=lambda r: r["class"])
    return rows


def scoring(n_classes: int) -> int:
    """The task book's step function for metric coverage."""
    if n_classes >= 4:
        return 4
    if n_classes == 3:
        return 2
    if n_classes == 2:
        return 1
    return 0


def main(argv: list) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repeats", type=int, default=5)
    ap.add_argument("--kernel", default=r"artifacts\kernel-procfs.bin")
    ap.add_argument("--disk", default=None, help="delivered agentos-disk.img (default: ../delivered/agentos-disk.img if present)")
    ap.add_argument("--tag", default="perf")
    ap.add_argument(
        "--append",
        action="store_true",
        help="add this batch's samples to the existing --out report instead of overwriting it",
    )
    ap.add_argument("--out", default=None,
                    help="report path (default evidence/reports/perf-report.json)")
    ap.add_argument("--reparse", action="store_true",
                    help="rebuild the report from the evidence directories already on disk")
    ap.add_argument("--reparse-dir", action="append", default=[], metavar="NAME",
                    help="with --reparse: use exactly these evidence directory names, in order")
    args = ap.parse_args(argv)

    ws = pathlib.Path(__file__).resolve().parent.parent
    if args.disk:
        disk = pathlib.Path(args.disk)
        if not disk.is_file():
            raise SystemExit(f"disk not found: {disk}")
    else:
        candidate = ws.parent.parent / "delivered" / "agentos-disk.img"
        disk = candidate if candidate.is_file() else None
    run_root = ws / "evidence" / "perf"
    session_root = ws / "evidence" / "sessions"
    run_root.mkdir(parents=True, exist_ok=True)
    out_path = pathlib.Path(args.out) if args.out else (ws / "evidence" / "reports" / "perf-report.json")
    if not out_path.is_absolute():
        out_path = ws / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)

    def sample_from(run_dir: pathlib.Path, run_idx: int) -> dict:
        vals = parse_output(read_transcript(run_dir))
        vals.update(read_qemu_metrics(run_dir))
        vals.update(read_frame_watch(run_dir))
        vals["run"] = run_idx
        vals["evidence_dir"] = run_dir.name
        return vals

    samples = []
    if args.reparse:
        # Rebuild the report from evidence that already exists.  The runs are the
        # expensive part and the transcripts are the raw data, so a parser fix must
        # not require re-running QEMU -- and re-running to make a number look better
        # is exactly what this mode makes unnecessary.
        if args.reparse_dir:
            runs = []
            for name in args.reparse_dir:
                for candidate in (run_root / name, session_root / name, ws / "evidence" / name):
                    if candidate.is_dir():
                        runs.append(candidate)
                        break
        else:
            runs = sorted(run_root.glob(f"{args.tag}*-*")) or \
                sorted(session_root.glob(f"{args.tag}*-*")) or \
                sorted((ws / "evidence").glob(f"{args.tag}*-*"))
        runs = [r for r in runs if r.is_dir()]
        if not runs:
            names = sorted({p.name for p in run_root.iterdir() if p.is_dir()} |
                           {p.name for p in session_root.iterdir() if p.is_dir()})
            print(f"no session matched tag {args.tag!r} under {run_root} or {session_root}", file=sys.stderr)
            print("pass --reparse-dir <name> (repeatable), or --tag <prefix>.", file=sys.stderr)
            print("sessions present:", file=sys.stderr)
            for n in names:
                print(f"    {n}", file=sys.stderr)
            return 2
        for idx, run in enumerate(runs, start=1):
            vals = sample_from(run, idx)
            samples.append(vals)
            print(f"    {vals}", flush=True)

    for i in range(1, 0 if args.reparse else args.repeats + 1):
        stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
        session = f"{args.tag}{i}-{stamp}"
        session_dir = run_root / session
        print(f"--- run {i}/{args.repeats}  ({session}) ---", flush=True)
        cmd = [
            POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(ws / "host" / "xkwin.ps1"),
            "-Kernel", args.kernel,
            *(["-Disk", str(disk)] if disk else []),
            "-ServeManifest", SERVE_MANIFEST,
            "-Script", GUEST_SCRIPTS,
            "-Upload", GUEST_UPLOADS,
            "-FrameWatch", FRAME_WATCH,
            "-FrameWatchCmd", FRAME_WATCH_CMD,
            "-Key", HARVEST_CMD,
            "-Tag", session,
            "-OutDir", str(session_dir),
            "-CommandTimeoutSec", "700",
            "-BootTimeoutSec", "400",
            "-AfterScriptWait", "20",
        ]
        started = time.time()
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=2400)
        # Keep the harness's own stdout next to the evidence.  Without it a run
        # that dies early leaves only a transcript and no reason, which is how a
        # single KeyError in a stats pass once looked like "the measurement
        # produced nothing".
        try:
            (session_dir / "harness.out.txt").write_text(proc.stdout or "", encoding="utf-8")
        except Exception:  # noqa: BLE001 - evidence sidecar is best-effort
            pass
        wall_s = round(time.time() - started, 1)
        text = read_transcript(session_dir)
        vals = sample_from(session_dir, i)
        vals["harness_wall_s"] = wall_s
        samples.append(vals)
        print(f"    {vals}", flush=True)

    if args.append and out_path.is_file():
        prev = json.loads(out_path.read_text(encoding="utf-8"))
        merged = list(prev.get("samples", []))
        offset = len(merged)
        for j, s in enumerate(samples, start=1):
            s = dict(s)
            s["run"] = offset + j
            merged.append(s)
        samples = merged
        print(f"appended {len(merged) - offset} sample(s) to {out_path.name} "
              f"(now {len(merged)})", flush=True)

    summary = {}
    for key in GUEST_INT_KEYS + DERIVED_FLOAT_KEYS:
        s = summarise(samples, key)
        if s:
            summary[key] = s
    coverage = class_coverage(summary)
    scored_classes = [c for c in coverage if c["meets_5_repeats"]]

    report = {
        "schema": "xkwin-perf/2 (framebuffer first-frame + resource rates)",
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "host": host_facts(),
        "qemu": qemu_version(),
        "qemu_config": {
            "machine": "virt",
            "cpu_model": "cortex-a72",
            "accelerator": "tcg (pure software emulation, no KVM/HVF)",
            "smp_cpus": samples[0].get("smp_cpus") if samples else None,
            "guest_ram_mb": samples[0].get("guest_mem_mb") if samples else None,
        },
        "guest_kernel": args.kernel,
        "measurement_protocol": {
            "repeats_per_metric": "each metric is measured once per run; the report requires n>=5",
            "statistic": "median with min/max/spread, plus spread as % of median and the CV",
            "first_frame": "QEMU screendump cadence from the instant the launch line is dispatched; "
                           "painted = saturation>=0.06 in the page area, >=300 colours, not blank "
                           "(colour count alone counts an empty browser window as a result); the "
                           "reported value is the capture completion time (upper bound), bracketed "
                           "by the previous frame",
            "renderer": "guest monitor at 1 Hz, direct child of a --type=zygote process "
                        "(this build does not rewrite the child argv)",
            "resource_rates": "cpu_pct = cpu seconds / wall seconds; "
                              "qemu_mem_pct = QEMU peak working set / host physical memory",
        },
        "metric_definitions": METRIC_DEFS,
        "metric_classes": sorted({d["class"] for d in METRIC_DEFS.values()}),
        "samples": samples,
        "summary": summary,
        "class_coverage": coverage,
        "coverage_scoring": {
            "classes_with_5_or_more_samples": len(scored_classes),
            "points_per_task_book": scoring(len(scored_classes)),
            "rule": "2 classes = 1 point, 3 classes = 2 points, >= 4 classes = 4 points",
        },
    }
    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print("\n=== summary (median / min / max / spread) ===")
    for key, s in summary.items():
        if s["class"] == "counter":
            continue
        print(f"  {key:18s} class={s['class']:<18} n={s['n']} median={s['median']:<10} "
              f"min={s['min']:<10} max={s['max']:<10} spread={s['spread']}"
              + (f" (res {s['resolution_s']}s)" if s["resolution_s"] else ""))
    print("\n=== metric classes (need n>=5 each) ===")
    for c in coverage:
        mark = "OK " if c["meets_5_repeats"] else "LOW"
        print(f"  [{mark}] {c['class']:<18} n={c['complete_samples']:<3} metrics={', '.join(c['metrics'])}")
    print(f"\nclasses with >=5 samples: {len(scored_classes)} -> "
          f"{len(scored_classes)} class coverage = {report['coverage_scoring']['points_per_task_book']} point(s)")
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    # sys.argv[1:], not sys.argv: argparse would otherwise treat the script path
    # itself as an unrecognised positional argument.
    raise SystemExit(main(sys.argv[1:]))
