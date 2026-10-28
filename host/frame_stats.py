#!/usr/bin/env python3
"""Turn a QEMU frame-watch series into a page-load (first-frame) measurement.

Why this exists: the task book names "page load latency" as a scored metric, and
the committee's own evidence channel is the QEMU monitor screendump.  Measuring
the moment the page becomes visible therefore cannot be done from a browser log
line -- that only says the process was alive -- it has to be read off the
framebuffer.  host/xkwin.ps1 -FrameWatch takes a screendump every N seconds
while the browser starts and records when each capture was requested and when
the PNG landed; this script measures those PNGs and decides which frame is the
first one that actually carries the page.

What "first frame" means here (this definition was forced by the data):

  An empty browser window is NOT a painted page.  A first attempt used colour
  count alone (>= 100 distinct colours), and it counted a blank white page with
  a "Loading..." spinner: that frame has 264 colours from the tab bar, the
  toolbar and the window frame, versus 91 for the bare window and 835 for the
  rendered committee page.  Colour count cannot tell chrome from content.

  The page itself can: index.html paints a dark banner and four saturated
  colour blocks.  So a frame counts as painted when

      saturation_frac >= SAT_FLOOR   (fraction of pixels with chroma > 60)
      and colors >= COLOUR_FLOOR     (sanity floor, default 300)
      and not blank                  (screen_stats.py rules)

  Measured separation on real frames (session evidence/perf/pf31-...):
      bare window            91 colours, saturation 0.040
      empty page + spinner  264 colours, saturation 0.040
      page appears                      saturation 0.107
      page fully painted    835 colours, saturation 0.156
  and on the run that never loaded (pf34-...): 265 colours, saturation 0.040
  for the whole 140 s window -- correctly reported as "not found" instead of
  as a 66 s page load.

  The reported latency is the capture COMPLETION time (an upper bound), and the
  previous frame's completion time is published beside it as the lower bound.
  Sampling is 2 s, so the bracket width is one interval and it is stated rather
  than hidden.

Nothing is tuned to a good-looking number: every frame's colour count and
saturation are written back into the JSON, and the first-frame instant is
recomputed at several thresholds, so a reader can disagree with 0.06 and see
the consequence without re-running anything.

Usage:
    python host/frame_stats.py <session-dir> [--sat 0.06] [--threshold 300] [--out FILE]
    python host/frame_stats.py --self-test
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from screen_stats import BLANK_DOMINANT_FRACTION, MIN_PAINTED_COLORS  # same rules as the screenshots

SAT_FLOOR = 0.06
COLOUR_FLOOR = 300
SAMPLE_STEP = 4


def measure(png: Path) -> dict:
    """Colour count, dominant fraction, blank verdict and saturation fraction.

    One pass over a 4-pixel grid, the same grid screen_stats.py uses, so "blank"
    keeps a single definition across the package.
    """
    from PIL import Image

    with Image.open(png) as img:
        img = img.convert("RGB")
        width, height = img.size
        pixels = img.load()
        counts: Counter = Counter()
        saturated = 0
        sampled = 0
        for y in range(0, height, SAMPLE_STEP):
            for x in range(0, width, SAMPLE_STEP):
                r, g, b = pixels[x, y]
                counts[(r, g, b)] += 1
                sampled += 1
                if max(r, g, b) - min(r, g, b) > 60 and max(r, g, b) > 60:
                    saturated += 1
    if not sampled:
        raise SystemExit("image has no pixels: %s" % png)
    dominant_count = counts.most_common(1)[0][1]
    dominant_fraction = dominant_count / sampled
    colors = len(counts)
    blank = colors < MIN_PAINTED_COLORS or dominant_fraction >= BLANK_DOMINANT_FRACTION
    return {
        "colors": colors,
        "dominant_fraction": round(dominant_fraction, 4),
        "saturation_frac": round(saturated / sampled, 4),
        "blank": blank,
        "sampled_pixels": sampled,
    }


def is_painted(frame: dict, sat: float = SAT_FLOOR, colours: int = COLOUR_FLOOR) -> bool:
    if frame.get("colors") is None:
        return False
    return (
        frame["colors"] >= colours
        and not frame.get("blank", True)
        and (frame.get("saturation_frac") or 0.0) >= sat
    )


def first_paint(frames: list, sat: float = SAT_FLOOR, colours: int = COLOUR_FLOOR) -> dict:
    """First frame that carries the page, with its uncertainty bracket."""
    hit = [f for f in frames if is_painted(f, sat, colours)]
    if not hit:
        return {
            "found": False,
            "sat_floor": sat,
            "colour_floor": colours,
            "reason": "no captured frame carried page content (saturation %.3f, %d colours)" % (sat, colours),
        }
    k = frames.index(hit[0])
    hi = float(frames[k]["t_done_s"])
    lo = float(frames[k - 1]["t_done_s"]) if k > 0 else 0.0
    cpu_load = None
    try:
        c0 = frames[0].get("cpu_s")
        ck = frames[k].get("cpu_s")
        t0 = float(frames[0]["t_done_s"])
        if c0 is not None and ck is not None and hi > t0:
            cpu_load = round((ck - c0) / (hi - t0) * 100.0, 2)
    except Exception:  # noqa: BLE001 - a missing CPU sample is "not measured"
        cpu_load = None
    return {
        "found": True,
        "sat_floor": sat,
        "colour_floor": colours,
        "frame_index": frames[k]["n"],
        "first_frame_s": round(hi, 3),
        "first_frame_lo_s": round(lo, 3),
        "first_frame_bracket_s": round(hi - lo, 3),
        "colors_at_first_frame": frames[k]["colors"],
        "saturation_at_first_frame": frames[k].get("saturation_frac"),
        "colors_before": frames[k - 1]["colors"] if k > 0 else None,
        "saturation_before": frames[k - 1].get("saturation_frac") if k > 0 else None,
        "cpu_pct_to_first_frame": cpu_load,
    }


def enrich(session: Path, sat: float, colours: int, out) -> dict:
    meta_path = session / "frame-watch.json"
    if not meta_path.is_file():
        raise SystemExit("no frame-watch.json in %s (was the run made with -FrameWatch?)" % session)
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    frames = meta.get("frames", [])
    # PowerShell's ConvertTo-Json collapses a one-element collection into an
    # object, so a single-frame run would otherwise be iterated as its keys.
    if isinstance(frames, dict):
        frames = [frames]

    for frame in frames:
        png = session / frame["png"]
        if not png.is_file():
            frame["colors"] = None
            continue
        m = measure(png)
        frame.update(m)

    # Drop keys written by an earlier version of this tool, so a re-analysed
    # session cannot carry two contradictory thresholds at once.
    for stale in ("threshold_colors", "analysis_v1", "colour_floor_sensitivity_old"):
        meta.pop(stale, None)

    measured = [f for f in frames if f.get("colors") is not None]
    page_like = [f["colors"] for f in measured if f.get("saturation_frac", 0) >= sat]
    meta["sat_floor"] = sat
    meta["colour_floor"] = colours
    meta["frames_measured"] = len(measured)
    meta["baseline_colors_median"] = (
        statistics.median([f["colors"] for f in measured if not is_painted(f, sat, colours)])
        if any(not is_painted(f, sat, colours) for f in measured) else None
    )
    meta["analysis"] = first_paint(frames, sat, colours)

    # Threshold sensitivity on BOTH axes, so the verdict is not a number that
    # only exists at one arbitrary cut-off.
    meta["threshold_sensitivity"] = []
    for s in (0.02, 0.04, 0.06, 0.08, 0.12):
        res = first_paint(frames, s, colours)
        meta["threshold_sensitivity"].append({
            "sat_floor": s,
            "first_frame_s": res.get("first_frame_s"),
            "found": res.get("found", False),
        })
    meta["colour_floor_sensitivity"] = []
    for c in (100, 200, 300, 500):
        res = first_paint(frames, sat, c)
        meta["colour_floor_sensitivity"].append({
            "colour_floor": c,
            "first_frame_s": res.get("first_frame_s"),
            "found": res.get("found", False),
        })
    meta["series"] = [
        {
            "n": f["n"],
            "t_req_s": f.get("t_req_s"),
            "t_done_s": f.get("t_done_s"),
            "colors": f.get("colors"),
            "saturation_frac": f.get("saturation_frac"),
            "blank": f.get("blank"),
        }
        for f in frames
    ]

    target = out or meta_path
    target.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    return meta


def self_test() -> int:
    """Decide the verdict on synthetic frames, not on captured ones."""
    base = [
        {"n": 1, "t_done_s": 1.0, "colors": 2, "blank": True, "saturation_frac": 0.0},
        {"n": 2, "t_done_s": 3.0, "colors": 91, "blank": False, "saturation_frac": 0.04},
        # an empty browser window: lots of colours, no page content
        {"n": 3, "t_done_s": 5.0, "colors": 264, "blank": False, "saturation_frac": 0.04},
        # the page appears
        {"n": 4, "t_done_s": 7.0, "colors": 526, "blank": False, "saturation_frac": 0.107},
        {"n": 5, "t_done_s": 9.0, "colors": 835, "blank": False, "saturation_frac": 0.156},
    ]
    got = first_paint(base)
    assert got["found"] is True, got
    assert got["first_frame_s"] == 7.0, got
    assert got["first_frame_lo_s"] == 5.0, got
    assert got["first_frame_bracket_s"] == 2.0, got

    # A run that never loads the page must be "not found", never a number.
    stuck = [f for f in base if f["n"] <= 3]
    assert first_paint(stuck)["found"] is False, first_paint(stuck)

    # Colour count alone must NOT be enough (this is the bug that was found).
    assert is_painted({"colors": 264, "blank": False, "saturation_frac": 0.04}) is False
    assert is_painted({"colors": 835, "blank": False, "saturation_frac": 0.156}) is True
    print(json.dumps({"self_test": "ok", "bracket": got,
                      "empty_page_rejected": True, "colour_only_rejected": True}, indent=2))
    return 0


def main(argv: list) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("session", nargs="?", type=Path, help="evidence session directory")
    ap.add_argument("--sat", type=float, default=SAT_FLOOR,
                    help="saturation fraction the page area needs before it counts as painted")
    ap.add_argument("--threshold", type=int, default=COLOUR_FLOOR,
                    help="colour-count sanity floor (default 300)")
    ap.add_argument("--out", type=Path, help="write the enriched JSON here instead of in place")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    if args.session is None:
        ap.error("a session directory is required unless --self-test is used")
    meta = enrich(args.session, args.sat, args.threshold, args.out)
    a = meta["analysis"]
    print("frames=%s threshold=sat>=%s and colours>=%s" % (
        meta["frames_measured"], meta["sat_floor"], meta["colour_floor"]))
    if a.get("found"):
        print("first_frame_s=%s (bracket %s..%s, saturation %s -> %s, colours %s -> %s)" % (
            a["first_frame_s"], a["first_frame_lo_s"], a["first_frame_s"],
            a["saturation_before"], a["saturation_at_first_frame"],
            a["colors_before"], a["colors_at_first_frame"]))
    else:
        print("first frame: NOT FOUND -- " + a.get("reason", ""))
    for row in meta.get("threshold_sensitivity", []):
        print("  sat >= %.2f -> %s" % (row["sat_floor"], row["first_frame_s"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
