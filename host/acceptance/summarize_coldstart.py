#!/usr/bin/env python3
"""Summarise cold-start run directories for tasks 09-12.

Usage:
    python summarize_coldstart.py <run-dir> [<run-dir> ...] [--csv out.csv]

Reads only files the harness wrote:
  startup-ready.json, zz-final.stats.json, console.log, timing.txt.
Never edits a run directory.  Missing fields become null, not guesses.
"""
from __future__ import annotations

import argparse
import csv
import json
import pathlib
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
TITLE = re.compile(r'WM_NAME\(UTF8_STRING\) = "([^"]+)"')


def load(path: pathlib.Path):
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception:
        return None


def row(run: pathlib.Path) -> dict:
    ready = load(run / "startup-ready.json") or {}
    final = load(run / "zz-final.stats.json") or {}
    console = ""
    if (run / "console.log").is_file():
        console = ANSI.sub("", (run / "console.log").read_text(encoding="utf-8", errors="replace"))
    titles = TITLE.findall(console)
    timing = ""
    if (run / "timing.txt").is_file():
        timing = (run / "timing.txt").read_text(encoding="utf-8", errors="replace").strip()
    dur = None
    m = re.search(r"duration_s=([\d.]+)", timing)
    if m:
        dur = float(m.group(1))
    actions = ready.get("actions") or []
    attempts = ready.get("attempts") or []
    first_fail = ready.get("first_failure") or {}
    return {
        "run": run.name,
        "ready": ready.get("ready"),
        "total_gate_s": ready.get("total_s"),
        "attempts": max([a.get("attempt", 0) for a in attempts], default=0),
        "reloads": sum(1 for a in actions if a.get("action") == "reload"),
        "restarts": sum(1 for a in actions if a.get("action") == "restart"),
        "first_fail_colors": first_fail.get("colors"),
        "final_colors": final.get("colors"),
        "final_blank": final.get("blank"),
        "title": titles[-1] if titles else None,
        "duration_s": dur,
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--csv")
    ap.add_argument("--g1", action="store_true", help="also write a G1 pass/fail markdown")
    ap.add_argument("--md")
    args = ap.parse_args(argv)
    rows = [row(pathlib.Path(p)) for p in args.runs]
    cols = ["run", "ready", "title", "final_colors", "final_blank", "attempts",
            "reloads", "restarts", "first_fail_colors", "total_gate_s", "duration_s"]
    for r in rows:
        print(" | ".join(str(r[c]) for c in cols))
    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=cols)
            w.writeheader()
            w.writerows(rows)
        print("wrote", args.csv)
    exit_code = 0
    if args.g1:
        ok = 0
        lines = ["# G1 - consecutive cold starts", "",
                 "| # | run | ready | attempts | actions | first fail | final colours | title | duration s | verdict |",
                 "|---|---|---|---|---|---|---|---|---|---|"]
        for i, r in enumerate(rows, 1):
            good = r["attempts"] == 1 and r["reloads"] == 0 and r["restarts"] == 0 and bool(r["ready"]) and (r["final_colors"] or 0) >= 300 and not r["final_blank"] \
                and (r["title"] or "") and "初赛指定测试页" in (r["title"] or "")
            ok += 1 if good else 0
            actions = f"reload={r['reloads']} restart={r['restarts']}"
            lines.append(
                f"| {i} | {r['run']} | {r['ready']} | {r['attempts']} | {actions} | "
                f"{r['first_fail_colors']} | {r['final_colors']} | {r['title']} | {r['duration_s']} | "
                f"{'PASS' if good else 'FAIL'} |"
            )
        unique = len({str(pathlib.Path(p).resolve()) for p in args.runs}) == len(rows)
        verdict = "PASS" if ok == len(rows) == 20 and unique else "FAIL"
        exit_code = 0 if verdict == "PASS" else 1
        lines += ["", f"**{ok}/{len(rows)} passed -> G1 {verdict}**"]
        text = "\n".join(lines) + "\n"
        print(text)
        if args.md:
            open(args.md, "w", encoding="utf-8").write(text)
            print("wrote", args.md)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
