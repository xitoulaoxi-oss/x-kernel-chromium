#!/usr/bin/env python3
"""Assemble the harness's screendumps into an animated GIF.

Why a GIF and not a screen recorder: the task book fixes QEMU monitor
screendump as the evidence channel and calls a host screen recording a demo aid
only.  The harness already emits one screendump per step, so the "complete flow
recording" the demo item asks for can be built from exactly the frames the
functional evidence is built from -- the animation cannot show anything the
stills do not, and every frame keeps its own stats sidecar.

Each frame is labelled with its step name (the same name as the PNG), so the
animation documents the sequence it shows instead of relying on the viewer
knowing the file order.

Usage:
    python host/make_gif.py --dir evidence/sessions/REC-<timestamp> --out runs/demo.gif
"""

from __future__ import annotations

import argparse
import pathlib
import sys

from PIL import Image, ImageDraw

LABEL_BG = (0, 0, 0)


def load_frame(path: pathlib.Path, scale: float, label: bool, text: str | None = None) -> Image.Image:
    with Image.open(path) as src:
        img = src.convert("RGB")
    if scale != 1.0:
        size = (max(1, int(img.width * scale)), max(1, int(img.height * scale)))
        img = img.resize(size, Image.LANCZOS)
    if label:
        draw = ImageDraw.Draw(img)
        text = text or path.stem
        # The default bitmap font is the only one guaranteed to exist here;
        # a labelled frame that cannot be drawn is worse than an unlabelled one.
        box = draw.textbbox((0, 0), text)
        pad = 3
        draw.rectangle(
            [0, 0, box[2] - box[0] + 2 * pad, box[3] - box[1] + 2 * pad],
            fill=LABEL_BG,
        )
        draw.text((pad, pad), text, fill=(255, 255, 255))
    # GIF frames are palette images; quantising per frame keeps the status
    # colours (green/red banners in the test pages) from shifting.
    return img.convert("P", palette=Image.ADAPTIVE, colors=128)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", required=True, help="evidence directory holding the PNGs")
    ap.add_argument("--out", required=True, help="GIF to write")
    ap.add_argument("--pattern", default="*.png")
    ap.add_argument("--exclude", default="__none__")
    ap.add_argument("--scale", type=float, default=0.625)
    ap.add_argument("--delay-ms", type=int, default=700)
    ap.add_argument("--no-label", dest="label", action="store_false")
    # The harness names its frames after the step that produced them, which is
    # precise but unhelpful for fourteen identical "after-step-cmd" captures.
    # A map lets the recording say what each frame is showing.
    ap.add_argument(
        "--label-map",
        action="append",
        default=[],
        metavar="STEM=TEXT",
        help="override one frame's label; repeat per frame",
    )
    args = ap.parse_args(argv)

    labels: dict[str, str] = {}
    for entry in args.label_map:
        stem, _, text = entry.partition("=")
        labels[stem.strip()] = text.strip()

    directory = pathlib.Path(args.dir)
    if not directory.is_dir():
        print(f"no such directory: {directory}", file=sys.stderr)
        return 2
    files = sorted(p for p in directory.glob(args.pattern) if args.exclude not in p.name)
    if not files:
        print(f"no frames matching {args.pattern} in {directory}", file=sys.stderr)
        return 2

    frames = [load_frame(p, args.scale, args.label, labels.get(p.stem)) for p in files]
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        out,
        save_all=True,
        append_images=frames[1:],
        duration=args.delay_ms,
        loop=0,
        optimize=True,
        disposal=2,
    )
    print(f"frames={len(frames)} size={out.stat().st_size} bytes -> {out}")
    print("  " + "\n  ".join(p.name for p in files))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
