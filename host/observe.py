#!/usr/bin/env python3
"""Summarise crash / hang / leak signals from one harness session.

Usage:
    python host/observe.py experiments/E000-baseline/run3
    python host/observe.py <session> --expected-minutes 30 --out observe.json
    python host/observe.py <session> --strict

The tool reads only files the harness already writes:
  console.log, *.stats.json, qemu-metrics.json, harness-error.txt,
  qemu.stderr.log, and optionally observe.jsonl from host/monitor-qemu.ps1.

It does not run QEMU and does not modify the session.
"""
from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import sys
from typing import Any

ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
HB = re.compile(r"\bHB\s+t=(\d+).*?chrome=(\d+).*?mem_mb=(\d+)")
CRASH_PATTERNS = [
    ("kernel panic", re.compile(r"kernel panic|panic:", re.I)),
    ("SIGSEGV", re.compile(r"SIGSEGV|segmentation fault|segfault", re.I)),
    ("SIGILL", re.compile(r"SIGILL|illegal instruction", re.I)),
    ("SIGABRT", re.compile(r"SIGABRT|abort\(\)", re.I)),
    ("Aw Snap", re.compile(r"Aw,\s*Snap", re.I)),
    ("OOM", re.compile(r"out of memory|oom-kill|killed process|Cannot allocate memory", re.I)),
    ("QEMU fatal", re.compile(r"qemu: fatal|qemu-system.*fatal", re.I)),
]


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


def trend(session: pathlib.Path) -> dict[str, Any]:
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
                samples.append({"t": float(row["elapsed_s"]), "ws": float(row["ws_mb"])})
    if len(samples) < 3:
        return {"samples": len(samples), "insufficient_data": True}
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
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("session", type=pathlib.Path)
    ap.add_argument("--expected-minutes", type=int, default=0)
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

    crash_matches: list[dict[str, Any]] = []
    for name, pat in CRASH_PATTERNS:
        for m in pat.finditer(console):
            line = console.count("\n", 0, m.start()) + 1
            crash_matches.append({"kind": name, "line": line, "text": m.group(0)[:120]})
            break
    crash = {
        "detected": bool(crash_matches) or bool(harness_err.strip()),
        "signals": crash_matches,
        "harness_error": bool(harness_err.strip()),
        "harness_error_tail": harness_err.strip()[-500:],
        "qemu_stderr_tail": qemu_err.strip()[-500:],
    }

    hang_reasons: list[str] = []
    final_blank = bool(stats and stats.get("blank"))
    final_colors = stats.get("colors") if stats else None
    if stats is None:
        hang_reasons.append("no final screenshot stats")
    elif final_blank:
        hang_reasons.append("final frame is blank")
    elif isinstance(final_colors, (int, float)) and final_colors < 300:
        hang_reasons.append(f"final frame has only {final_colors} colours")
    if args.expected_minutes and not hb:
        hang_reasons.append("no heartbeat lines for a timed session")
    if hb:
        if args.expected_minutes and len(hb) < max(1, args.expected_minutes - 2):
            hang_reasons.append(f"heartbeat count {len(hb)} < expected ~{args.expected_minutes}")
        if hb[-1]["chrome"] == 0:
            hang_reasons.append("last heartbeat reports chrome=0")
    hang = {
        "detected": bool(hang_reasons),
        "reasons": hang_reasons,
        "heartbeats": len(hb),
        "last_heartbeat": hb[-1] if hb else None,
        "final_stats": stats_name,
    }

    tr = trend(session)
    leak_detected = False
    if not tr.get("insufficient_data"):
        leak_detected = tr["growth_mb"] >= args.leak_mb and tr["slope_mb_per_min"] >= args.leak_slope
    leak = {"detected": leak_detected, **tr, "threshold_mb": args.leak_mb, "threshold_slope": args.leak_slope}

    summary = []
    if crash["detected"]:
        summary.append("CRASH")
    if hang["detected"]:
        summary.append("HANG")
    if leak["detected"]:
        summary.append("LEAK")
    if not summary:
        summary.append("NO_CRASH_HANG_LEAK")

    report = {
        "session": str(session),
        "summary": summary,
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
