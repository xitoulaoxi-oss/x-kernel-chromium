#!/usr/bin/env python3
"""Regression cases for host/observe.py (tasks 36-38).

Runs observe.py on the synthetic fixtures under tests/fixtures/observe/ and
asserts the new subject / hang-class / leak-attribution fields.  No QEMU.

    python tests/observe_cases.py
"""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OBSERVE = ROOT / "host" / "observe.py"
FIX = ROOT / "tests" / "fixtures" / "observe"
failures = 0


def run(name: str, *extra: str) -> dict:
    out = subprocess.run(
        [sys.executable, str(OBSERVE), str(FIX / name), *extra],
        capture_output=True, text=True, check=False,
    )
    if out.returncode != 0:
        raise SystemExit(f"{name}: observe.py exited {out.returncode}\n{out.stderr}")
    return json.loads(out.stdout)


def check(cond: bool, label: str, detail: object = "") -> None:
    global failures
    if cond:
        print(f"PASS {label}")
    else:
        print(f"FAIL {label} {detail}")
        failures += 1


def main() -> int:
    crash = run("crash")
    check(crash["summary"][0] == "CRASH", "crash session detected as CRASH", crash["summary"])
    subjects = crash["crash"]["subjects"]
    check(any(s["pid"] == 105 and "child" in s["role"] for s in subjects),
          "crash subject keeps child PID 105", subjects)
    check(any(s["pid"] == 87 and s["role"] == "browser" for s in subjects),
          "crash subject names the browser PID 87", subjects)

    shell = run("hang-shell")
    check(shell["hang"]["class"] == "window_shell_without_page",
          "262-colour window is window_shell_without_page", shell["hang"])
    check(shell["summary"] == ["HANG"], "shell session summarised as HANG", shell["summary"])

    desk = run("hang-desktop")
    check(desk["hang"]["class"] == "no_window_desktop_only",
          "28-colour frame is no_window_desktop_only", desk["hang"])

    leak = run("leak")
    check(leak["leak"]["detected"] is True, "rising host WS is flagged LEAK", leak["leak"])
    check(leak["leak"]["guest_chromium"]["available"] is True,
          "CMJSON per-process sample is available", leak["leak"]["guest_chromium"])
    check(leak["leak"]["guest_chromium"]["growth_kb"] == 40000,
          "per-process RSS growth is 40000 kB", leak["leak"]["guest_chromium"])
    check(leak["leak"]["attribution_limited"] is False,
          "measured CMJSON lifts attribution_limited", leak["leak"])

    clean = run("no-leak")
    check(clean["leak"]["detected"] is False, "flat host WS is not flagged", clean["leak"])
    check(clean["leak"]["attribution_limited"] is True,
          "no CMJSON keeps attribution_limited true", clean["leak"])

    control = run("control-error")
    check(control["summary"] == ["CONTROL_CHANNEL_ERROR"],
          "harness timeout is not a target CRASH", control["summary"])
    check(control["crash"]["detected"] is False, "harness error alone is not crash", control["crash"])
    check(control["diagnosis"]["control_channel_error"] is True,
          "control channel is called out", control["diagnosis"])

    nohb = run("no-heartbeat-configured", "--expected-minutes", "1")
    check(nohb["hang"]["detected"] is False,
          "missing HB in a session that did not configure HB is not HANG", nohb["hang"])
    check(nohb["diagnosis"]["observer_insufficient"] is True,
          "missing HB is an observer limitation", nohb["diagnosis"])
    check(nohb["summary"] == ["OBSERVER_INSUFFICIENT"],
          "observer limitation has its own summary", nohb["summary"])

    print("all observe cases passed" if failures == 0 else f"{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
