#!/usr/bin/env python3
"""Summarise crash / hang / leak signals from one harness session.

Usage:
    python host/observe.py experiments/E000-baseline/run3
    python host/observe.py <session> --expected-minutes 30 --out observe.json
    python host/observe.py <session> --strict

The tool reads only files the harness already writes:
  console.log, *.stats.json, qemu-metrics.json, harness-error.txt,
  qemu.stderr.log, observe.jsonl (host monitor), and CMJSON lines written by
  guest/chrome-mem.sh.

It does not run QEMU and does not modify the session.

Task 36-38 additions:
  * crash subjects: Chromium log lines carry "[pid:tid:time:LEVEL:file]"; the
    report now names the PID and whether it is the browser (from _NET_WM_PID)
    instead of printing a bare string hit;
  * hang classification: desktop-only / window-shell-without-page / heartbeat
    loss / browser gone are separate states, not one "colors < 300" rule;
  * leak attribution: per-process Chromium RSS samples (CMJSON) are reported
    separately from the host QEMU working set, and "unavailable" stays
    unavailable instead of becoming zero.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Any

ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
HB = re.compile(r"\bHB\s+t=(\d+).*?chrome=(\d+).*?mem_mb=(\d+)")
CHROME_LINE = re.compile(
    r"^\[(\d+):(\d+):\d+/\d+\.\d+:(INFO|WARNING|ERROR|FATAL):([^\]]*)\]\s*(.*)$"
)
WM_PID = re.compile(r"_NET_WM_PID\(CARDINAL\)\s*=\s*(\d+)")
CMJSON = re.compile(r"^CMJSON\s+(\{.*\})\s*$", re.M)
CRASH_PATTERNS = [
    ("kernel panic", re.compile(r"kernel panic|panic:", re.I)),
    ("SIGSEGV", re.compile(r"SIGSEGV|segmentation fault|segfault", re.I)),
    ("SIGILL", re.compile(r"SIGILL|illegal instruction", re.I)),
    ("SIGABRT", re.compile(r"SIGABRT|abort\(\)", re.I)),
    ("Aw Snap", re.compile(r"Aw,\s*Snap", re.I)),
    ("OOM", re.compile(r"out of memory|oom-kill|killed process|Cannot allocate memory", re.I)),
    ("QEMU fatal", re.compile(r"qemu: fatal|qemu-system.*fatal", re.I)),
]

SCHEMA = 2


def read_text(path: pathlib.Path) -> str:
    if not path.is_file():
        return ""
    return ANSI.sub("", path.read_text(encoding="utf-8", errors="replace"))


def load_json(path: pathlib.Path) -> Any:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def final_stats(session: pathlib.Path) -> tuple[dict[str, Any] | None, str | None]:
    exact = session / "zz-final.stats.json"
    if exact.is_file():
        return load_json(exact), exact.name
    candidates = sorted(session.glob("*.stats.json"))
    if not candidates:
        return None, None
    return load_json(candidates[-1]), candidates[-1].name


def heartbeat_lines(console: str) -> list[dict[str, int]]:
    rows: list[dict[str, int]] = []
    for m in HB.finditer(console):
        rows.append({"t": int(m.group(1)), "chrome": int(m.group(2)), "mem_mb": int(m.group(3))})
    return rows


def chromium_log_lines(console: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for n, line in enumerate(console.splitlines(), 1):
        m = CHROME_LINE.match(line.strip())
        if not m:
            continue
        rows.append({
            "line": n,
            "pid": int(m.group(1)),
            "tid": int(m.group(2)),
            "level": m.group(3),
            "source": m.group(4).split(":")[0],
            "text": m.group(5)[:200],
        })
    return rows


def crash_subjects(console: str, chrome_lines: list[dict[str, Any]]) -> list[dict[str, Any]]:
    browser_pid = None
    m = WM_PID.search(console)
    if m:
        browser_pid = int(m.group(1))
    by_line = {row["line"]: row for row in chrome_lines}
    subjects: list[dict[str, Any]] = []
    seen: set[tuple[str, int | None]] = set()
    for name, pat in CRASH_PATTERNS:
        for match in pat.finditer(console):
            line_no = console.count("\n", 0, match.start()) + 1
            subject = by_line.get(line_no)
            pid = subject["pid"] if subject else None
            key = (name, pid)
            if key in seen:
                break
            seen.add(key)
            if pid is None:
                role = "kernel-or-session"
            elif browser_pid is not None and pid == browser_pid:
                role = "browser"
            else:
                role = "chromium-child(role-from-argv-unavailable)"
            subjects.append({
                "kind": name,
                "line": line_no,
                "pid": pid,
                "role": role,
                "log_level": subject["level"] if subject else None,
                "log_source": subject["source"] if subject else None,
                "text": match.group(0)[:120],
            })
            break
    return subjects


def trend(session: pathlib.Path, warmup_s: float = 0.0) -> dict[str, Any]:
    path = session / "observe.jsonl"
    samples: list[dict[str, float]] = []
    if path.is_file():
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if "elapsed_s" in row and "ws_mb" in row:
                t = float(row["elapsed_s"])
                if t >= warmup_s:
                    samples.append({"t": t, "ws": float(row["ws_mb"])})
    if len(samples) < 3:
        return {"samples": len(samples), "insufficient_data": True, "warmup_minutes": round(warmup_s / 60.0, 1)}
    xs = [p["t"] for p in samples]
    ys = [p["ws"] for p in samples]
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    den = sum((x - mx) ** 2 for x in xs)
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den if den else 0.0
    return {
        "samples": n,
        "first_mb": round(ys[0], 1),
        "last_mb": round(ys[-1], 1),
        "peak_mb": round(max(ys), 1),
        "growth_mb": round(ys[-1] - ys[0], 1),
        "slope_mb_per_min": round(slope * 60.0, 2),
        "insufficient_data": False,
        "warmup_minutes": round(warmup_s / 60.0, 1),
    }


def guest_process_memory(console: str) -> dict[str, Any]:
    """Per-process Chromium RSS samples emitted by guest/chrome-mem.sh (CMJSON)."""
    rows: list[dict[str, Any]] = []
    for m in CMJSON.finditer(console):
        try:
            rows.append(json.loads(m.group(1)))
        except Exception:
            continue
    if not rows:
        return {
            "available": False,
            "reason": "no CMJSON sample in console (chrome-mem.sh not run or interface missing)",
            "samples": 0,
        }
    last = rows[-1]
    state = last.get("state")
    series = [row.get("rss_kb_sum") for row in rows if row.get("rss_kb_sum") is not None]
    growth = None
    if len(series) >= 2:
        growth = series[-1] - series[0]
    return {
        "available": state == "measured",
        "state": state,
        "samples": len(rows),
        "last": last,
        "series_kb": series,
        "growth_kb": growth,
        "shared_double_count": last.get("shared_double_count"),
        "note": "RSS sum double-counts shared pages; PSS is unavailable on this kernel",
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("session", type=pathlib.Path)
    ap.add_argument("--expected-minutes", type=int, default=0)
    ap.add_argument("--heartbeat-configured", action="store_true",
                    help="the session was configured to emit HB lines; only then may a missing HB be a hang")
    ap.add_argument("--warmup-minutes", type=float, default=5.0,
                    help="ignore startup growth before this many minutes (default 5)")
    ap.add_argument("--leak-mb", type=float, default=256.0)
    ap.add_argument("--leak-slope", type=float, default=2.0)
    ap.add_argument("--out", type=pathlib.Path)
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args(argv)

    session = args.session
    if not session.is_dir():
        raise SystemExit(f"not a session directory: {session}")

    console = read_text(session / "console.log")
    stats, stats_name = final_stats(session)
    hb = heartbeat_lines(console)
    metrics = load_json(session / "qemu-metrics.json") or {}
    harness_err = read_text(session / "harness-error.txt") if (session / "harness-error.txt").is_file() else ""
    qemu_err = read_text(session / "qemu.stderr.log") if (session / "qemu.stderr.log").is_file() else ""

    chrome_lines = chromium_log_lines(console)
    subjects = crash_subjects(console, chrome_lines)
    crash = {
        "detected": bool(subjects),
        "subjects": subjects,
        "signals": [{"kind": s["kind"], "pid": s["pid"], "role": s["role"], "text": s["text"]} for s in subjects],
        "harness_error": bool(harness_err.strip()),
        "harness_error_tail": harness_err.strip()[-500:],
        "qemu_stderr_tail": qemu_err.strip()[-500:],
        "chromium_log_lines": len(chrome_lines),
    }

    final_blank = bool(stats and stats.get("blank"))
    final_colors = stats.get("colors") if stats else None
    hang_class = None
    reasons: list[str] = []
    observer_reasons: list[str] = []
    heartbeat_configured = bool(args.heartbeat_configured or hb)
    if stats is None:
        # A missing screenshot is missing evidence, not proof that the target
        # hung.  Keep it in the observer bucket so summary cannot print HANG.
        observer_reasons.append("no final screenshot stats")
    elif isinstance(final_colors, (int, float)) and final_colors < 60:
        hang_class = "no_window_desktop_only"
        reasons.append(f"final frame is the desktop only ({final_colors} colours)")
    elif final_blank or (isinstance(final_colors, (int, float)) and final_colors < 300):
        hang_class = "window_shell_without_page"
        reasons.append(f"window shell without page ({final_colors} colours, blank={final_blank})")
    if args.expected_minutes and not hb:
        if heartbeat_configured:
            hang_class = hang_class or "heartbeat_missing"
            reasons.append("no heartbeat lines for a timed session that configured heartbeats")
        else:
            observer_reasons.append("no heartbeat lines and heartbeat was not configured")
    if hb:
        if args.expected_minutes and len(hb) < max(1, args.expected_minutes - 2):
            hang_class = hang_class or "heartbeat_missing"
            reasons.append(f"heartbeat count {len(hb)} < expected ~{args.expected_minutes}")
        if hb[-1]["chrome"] == 0:
            hang_class = "browser_gone"
            reasons.append("last heartbeat reports chrome=0")

    # A page that paints has colours >= 300; if it painted but a timed session
    # lost its heartbeat, that is still a hang and must not be hidden.
    hang = {
        "detected": hang_class is not None,
        "class": hang_class,
        "reasons": reasons,
        "heartbeats": len(hb),
        "heartbeat_configured": heartbeat_configured,
        "last_heartbeat": hb[-1] if hb else None,
        "final_stats": stats_name,
        "final_colors": final_colors,
        "final_blank": final_blank,
    }

    tr = trend(session, args.warmup_minutes * 60.0)
    leak_detected = False
    if not tr.get("insufficient_data"):
        leak_detected = tr["growth_mb"] >= args.leak_mb and tr["slope_mb_per_min"] >= args.leak_slope
    guest_mem = guest_process_memory(console)
    leak = {
        "detected": leak_detected,
        "host_qemu_ws": tr,
        "guest_chromium": guest_mem,
        "threshold_mb": args.leak_mb,
        "threshold_slope": args.leak_slope,
        "attribution_limited": bool(guest_mem.get("state") not in ("measured",)),
        "note": "host QEMU working set is a lead only; guest per-process RSS is a separate quantity",
    }

    control_channel_error = bool(harness_err.strip() or qemu_err.strip())
    observer_insufficient = bool(observer_reasons)
    summary = []
    if crash["detected"]:
        summary.append("CRASH")
    if hang["detected"]:
        summary.append("HANG")
    if leak["detected"]:
        summary.append("LEAK")
    if control_channel_error and not (crash["detected"] or hang["detected"] or leak["detected"]):
        summary.append("CONTROL_CHANNEL_ERROR")
    if observer_insufficient and not summary:
        summary.append("OBSERVER_INSUFFICIENT")
    if not summary:
        summary.append("NO_CRASH_HANG_LEAK")

    diagnosis = {
        "target_fault": ("crash" if crash["detected"] else
                         "hang" if hang["detected"] else
                         "leak" if leak["detected"] else None),
        "control_channel_error": control_channel_error,
        "control_channel_detail": (harness_err.strip() or qemu_err.strip())[-500:] if control_channel_error else "",
        "observer_insufficient": observer_insufficient,
        "observer_reasons": observer_reasons,
        "heartbeat_configured": heartbeat_configured,
    }

    report = {
        "schema_version": SCHEMA,
        "session": str(session),
        "summary": summary,
        "diagnosis": diagnosis,
        "crash": crash,
        "hang": hang,
        "leak": leak,
        "qemu_metrics": metrics,
    }
    text = json.dumps(report, ensure_ascii=False, indent=2)
    print(text)
    if args.out:
        args.out.write_text(text + "\n", encoding="utf-8", newline="\n")
    if args.strict and (crash["detected"] or hang["detected"] or leak["detected"]):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
