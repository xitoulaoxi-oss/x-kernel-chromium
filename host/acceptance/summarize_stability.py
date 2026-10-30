#!/usr/bin/env python3
"""Summarise a 30-minute stability + load session (task 22).

Usage:
    python summarize_stability.py <session-dir> --expect-minutes 30

Reads load-schedule.json, console.log (HB lines), zz-final.stats.json and
observe.json (if present).  Writes stability-load.json next to the session and
prints a G2 verdict.  A missing heartbeat/log is reported as missing, not zero.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re

ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
HB = re.compile(r"\bHB\s+t=(\d+).*?chrome=(\d+).*?mem_mb=(\d+)")
CRASH = re.compile(r"out of memory|Cannot allocate memory|QEMU fatal|kernel panic|SIGSEGV|SIGILL|SIGABRT|Aw,\s*Snap|oom-kill|killed process", re.I)


def load_json(p: pathlib.Path):
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8-sig"))
    except Exception:
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("session", type=pathlib.Path)
    ap.add_argument("--expect-minutes", type=int, default=30)
    ap.add_argument("--out", type=pathlib.Path)
    args = ap.parse_args()
    s = args.session

    doc = {}
    schedule = load_json(s / "load-schedule.json") or {}
    rows = schedule.get("rows") or []
    doc["loads"] = {
        "scheduled": schedule.get("count"),
        "completed": sum(1 for r in rows if r.get("ok")),
        "max_abs_drift_s": max([abs(r.get("drift_s") or 0) for r in rows], default=None),
        "completion_s": [r.get("completed_s") for r in rows],
        "colors": [r.get("colors") for r in rows],
        "total_s": schedule.get("total_s"),
        "rows": rows,
    }

    console = ""
    p = s / "console.log"
    if p.is_file():
        console = ANSI.sub("", p.read_text(encoding="utf-8", errors="replace"))
    hb = [{"t": int(m.group(1)), "chrome": int(m.group(2)), "mem_mb": int(m.group(3))}
          for m in HB.finditer(console)]
    crashes = sorted({m.group(0) for m in CRASH.finditer(console)})
    doc["heartbeats"] = {
        "count": len(hb),
        "first": hb[0] if hb else None,
        "last": hb[-1] if hb else None,
        "min_chrome": min([h["chrome"] for h in hb], default=None),
    }
    doc["crashes"] = crashes
    final = load_json(s / "zz-final.stats.json") or {}
    doc["final"] = {"colors": final.get("colors"), "blank": final.get("blank")}
    doc["observe"] = load_json(s / "observe.json")

    reasons = []
    if not rows:
        reasons.append("no load-schedule.json")
    elif doc["loads"]["completed"] != schedule.get("count"):
        reasons.append(f"loads {doc['loads']['completed']}/{schedule.get('count')}")
    if args.expect_minutes < 30:
        reasons.append('required stability window cannot be lowered below 30 minutes')
    if schedule.get('count') != 10 or schedule.get('interval_s') != 120 or len(rows) != 10:
        reasons.append('requires exactly ten loads at 120-second intervals')
    if (schedule.get('total_s') or 0) < 1800:
        reasons.append('verified stability window is shorter than 1800 seconds')
    navs = [r.get('navigation_id') for r in rows]
    if len(set(navs)) != 10 or any(not n for n in navs):
        reasons.append('missing or repeated navigation identities')
    for i, r in enumerate(rows):
        if (r.get('semantic_ok') is not True or not r.get('before_navigation_id')
                or r.get('before_navigation_id') == r.get('navigation_id')):
            reasons.append(f'load {i + 1}: no new completed navigation')
        if abs((r.get('planned_s') or 0) - ((schedule.get('start_s') or 0) + i * 120)) > 0.01:
            reasons.append(f'load {i + 1}: invalid absolute schedule')
        if abs(r.get('drift_s') or 0) > 1:
            reasons.append(f'load {i + 1}: trigger drift exceeds one second')
        if r.get('round') != i + 1 or r.get('completed_s') is None or r.get('completed_s', 0) < r.get('sent_s', 0):
            reasons.append(f'load {i + 1}: invalid round/timing')
    times = [h['t'] for h in hb]
    if any(b <= a or b - a > 90 for a, b in zip(times, times[1:])):
        reasons.append('heartbeats are duplicated, out of order, or have long gaps')
    if any(h['chrome'] <= 0 for h in hb):
        reasons.append('browser missing during a heartbeat')
    if (s / 'harness-error.txt').is_file() and (s / 'harness-error.txt').read_text(errors='replace').strip():
        reasons.append('harness reported an error')
    observation = doc.get('observe') or {}
    if any(observation.get(k, {}).get('detected') is True for k in ('crash', 'hang', 'leak')):
        reasons.append('observer reported a fault')
    if len(hb) < max(30, args.expect_minutes):
        reasons.append(f"heartbeats {len(hb)} < {args.expect_minutes}")
    if hb and hb[-1]["chrome"] == 0:
        reasons.append("last heartbeat chrome=0")
    if crashes:
        reasons.append("crash markers: " + ", ".join(crashes))
    if not final or (final.get("colors") or 0) < 300 or final.get("blank"):
        reasons.append("final frame has no page")
    doc["verdict"] = "PASS" if not reasons else "FAIL"
    doc["reasons"] = reasons
    out = args.out or (s / "stability-load.json")
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(doc, ensure_ascii=False, indent=2))
    print("VERDICT", doc["verdict"], "->", out)
    return 0 if doc["verdict"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
