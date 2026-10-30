#!/usr/bin/env python3
"""Aggregate the three rehearsal scenes (task 42) into G6.md.

Usage:
    python summarize_scenes.py <scene1> <scene2> <scene3> [--md G6.md]
"""
from __future__ import annotations

import argparse
import json
import pathlib


def load(p: pathlib.Path):
    try:
        return json.loads(p.read_text(encoding="utf-8-sig"))
    except Exception:
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("scenes", nargs="+")
    ap.add_argument("--md")
    args = ap.parse_args()
    rows = []
    for s in map(pathlib.Path, args.scenes):
        doc = load(s / "scene.json") or {}
        f = load(s / "functional" / "run" / "functional.json") or {}
        rows.append({
            "scene": doc.get("scene", s.name),
            "root": doc.get("root"),
            "functional_rc": doc.get("functional_rc"),
            "functional_passed": f.get("passed"),
            "functional_total": f.get("total"),
            "stability_verdict": doc.get("stability_verdict"),
            "loads": doc.get("loads"),
            "heartbeats": doc.get("heartbeats"),
            "final_colors": doc.get("final_colors"),
            "duration_s": doc.get("duration_s"),
            "scene_path": str(s.resolve()),
            "stability_rc": doc.get("stability_rc"),
            "watchdog": doc.get("watchdog"),
            "full_acceptance": doc.get("full_acceptance") is True,
            "perf_pass": doc.get("perf_pass") is True,
            "kernel_sha256": doc.get("kernel_sha256"),
        })
    ok = all(
        r["functional_rc"] == 0 and r["functional_passed"] == r["functional_total"]
        and r["functional_total"] is not None and r["functional_total"] >= 3
        and r["stability_verdict"] == "PASS" and r['stability_rc'] == 0
        and not r['watchdog'] and r['full_acceptance'] and r['perf_pass']
        for r in rows
    )
    kernels = {r['kernel_sha256'] for r in rows}
    ok = (ok and len({r['scene_path'] for r in rows}) == 3
          and len({r['scene'] for r in rows}) == 3 and len(kernels) == 1 and None not in kernels)
    lines = ["# G6 - three rehearsal scenes", "",
             "| scene | root | functional | loads | HB | final colours | duration s | stability |",
             "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(
            f"| {r['scene']} | {r['root']} | {r['functional_passed']}/{r['functional_total']} "
            f"(rc {r['functional_rc']}) | {r['loads']} | {r['heartbeats']} | {r['final_colors']} | "
            f"{r['duration_s']} | {r['stability_verdict']} |"
        )
    lines += ["", f"**{len(rows)} scenes -> G6 {'PASS' if ok and len(rows) == 3 else 'FAIL'}**"]
    text = "\n".join(lines) + "\n"
    print(text)
    if args.md:
        open(args.md, "w", encoding="utf-8").write(text)
        print("wrote", args.md)
    return 0 if ok and len(rows) == 3 else 1


if __name__ == "__main__":
    raise SystemExit(main())
