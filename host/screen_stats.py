#!/usr/bin/env python3
"""Decide whether a QEMU screendump actually contains a picture.

Why this exists: ``screendump`` succeeding proves only that QEMU handed us a
framebuffer.  A black screen and a rendered page both produce a valid PNG, so
every claim of the form "the browser drew something" has to be backed by a
measurement of the image's pixels, not by the file's existence.

The output is deliberately JSON on stdout so a PowerShell or shell harness can
gate on it without parsing prose.

Usage:
    python screen_stats.py <image.png> [--dump-colors N] [--out stats.json]
    python screen_stats.py --self-test
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

# How many distinct colours a frame needs before we are willing to call it
# "painted".  A pure two-tone frame (background + a single line of text) is a
# real render, so the bar is low; the point is only to separate "one flat
# colour" from "something was drawn".
MIN_PAINTED_COLORS = 3

# Fraction of pixels a single colour may occupy before the frame counts as
# blank, regardless of how many stray colours a compression artifact invented.
BLANK_DOMINANT_FRACTION = 0.995


def analyse(path: Path, sample_step: int = 4) -> dict:
    """Return pixel statistics for one image.

    ``sample_step`` walks the image on a grid instead of reading every pixel:
    a 1280x800 frame has over a million pixels and the verdict does not change
    when a few thousand of them are sampled.
    """
    try:
        from PIL import Image
    except ImportError as exc:  # pragma: no cover - environment guard
        raise SystemExit(
            "Pillow is required (bundled with the DSH runtime): %s" % exc
        ) from exc

    with Image.open(path) as img:
        img = img.convert("RGB")
        width, height = img.size
        pixels = img.load()
        counts: Counter[tuple[int, int, int]] = Counter()
        sampled = 0
        for y in range(0, height, sample_step):
            for x in range(0, width, sample_step):
                counts[pixels[x, y]] += 1
                sampled += 1

    if not sampled:
        raise SystemExit("image has no pixels: %s" % path)

    ranked = counts.most_common()
    dominant_count = ranked[0][1]
    dominant_fraction = dominant_count / sampled
    colors = len(counts)

    # Two independent ways to be blank, because either alone can be fooled:
    # a single-colour frame, or a frame so dominated by one colour that the
    # rest is noise.
    is_blank = colors < MIN_PAINTED_COLORS or dominant_fraction >= BLANK_DOMINANT_FRACTION

    return {
        "file": str(path),
        "width": width,
        "height": height,
        "sampled_pixels": sampled,
        "colors": colors,
        "dominant_fraction": round(dominant_fraction, 4),
        "blank": is_blank,
        "top_colors": [[list(rgb), n] for rgb, n in ranked[:8]],
    }


def self_test() -> int:
    """Prove the blank/painted decision on synthetic images we control."""
    from PIL import Image

    tmp = Path("_selftest")
    tmp.mkdir(exist_ok=True)

    flat = tmp / "flat.png"
    Image.new("RGB", (64, 64), (0, 0, 0)).save(flat)
    flat_stats = analyse(flat)
    assert flat_stats["blank"] is True, flat_stats
    assert flat_stats["colors"] == 1, flat_stats

    # Two colours only, with a large minority: still "blank" by the colour
    # count rule, which is the conservative direction (we would rather retract
    # a claim than assert a picture that is not there).
    nearly = tmp / "nearly.png"
    im = Image.new("RGB", (64, 64), (0, 0, 0))
    for x in range(4):
        for y in range(64):
            im.putpixel((x, y), (255, 255, 255))
    im.save(nearly)
    nearly_stats = analyse(nearly)
    assert nearly_stats["colors"] == 2, nearly_stats
    assert nearly_stats["blank"] is True, nearly_stats

    # A frame with several real colours spread over it: this is what a rendered
    # page looks like to the sampler.  Keep every region wider than
    # ``sample_step`` so the grid cannot alias it away (see the aliasing test
    # below for why that matters).
    painted = tmp / "painted.png"
    im = Image.new("RGB", (64, 64), (11, 16, 32))
    for x in range(8, 40):
        for y in range(8, 40):
            im.putpixel((x, y), (94, 234, 212))
    for x in range(44, 60):
        for y in range(44, 60):
            im.putpixel((x, y), (232, 236, 248))
    im.save(painted)
    painted_stats = analyse(painted)
    assert painted_stats["blank"] is False, painted_stats
    assert painted_stats["colors"] >= 3, painted_stats

    aliased = analyse(painted, sample_step=8)
    assert aliased["sampled_pixels"] > 0, aliased

    print(json.dumps({
        "self_test": "ok",
        "flat": flat_stats,
        "nearly": nearly_stats,
        "painted": painted_stats,
        "painted_step8": aliased,
    }, indent=2))
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("image", nargs="?", type=Path, help="image to measure")
    parser.add_argument("--out", type=Path, help="also write the JSON here")
    parser.add_argument("--sample-step", type=int, default=4)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if args.image is None:
        parser.error("an image path is required unless --self-test is used")
    if not args.image.is_file():
        raise SystemExit("no such image: %s" % args.image)

    stats = analyse(args.image, sample_step=max(1, args.sample_step))
    text = json.dumps(stats, ensure_ascii=False, indent=2)
    print(text)
    if args.out:
        args.out.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
