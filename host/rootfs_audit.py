#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Audit the delivered rootfs image and emit the debugfs evidence the committee asked for.

WHY
---
The committee's answer to "may we change the rootfs?" was: *"if you change it,
give us the corresponding debugfs information so we can assess the impact."*
This machine has no WSL, no e2fsprogs and no loop mounts, so `debugfs` itself
cannot run here.  What we can do - and what this tool does - is:

  1. read the image with the pure-Python ext4 reader (`host/ext4.py`),
  2. emit a **replayable debugfs session** that a reviewer on any Linux box can
     run against the same image to reproduce every fact below,
  3. emit a **content inventory** (path, inode, mode, size, sha256) of the whole
     tree or of a chosen subtree, so a modification can be stated as a diff
     against a recorded baseline rather than as prose.

Typical use (paths are relative to the repository root; the delivered image is
supplied separately and must never be modified):

    # 1. record the pristine baseline once
    python host/rootfs_audit.py inventory --image <image-dir>/agentos-disk.img \\
        --out evidence/reports/rootfs-baseline.tsv

    # 2. after editing a work copy, diff against it
    python host/rootfs_audit.py inventory --image work/agentos-work.img \\
        --out evidence/reports/rootfs-modified.tsv
    python host/rootfs_audit.py diff evidence/reports/rootfs-baseline.tsv \\
        evidence/reports/rootfs-modified.tsv

    # 3. emit the debugfs script a reviewer can replay
    python host/rootfs_audit.py debugfs-script --image <image-dir>/agentos-disk.img \\
        --out evidence/reports/rootfs-debugfs.txt

IMPORTANT: the delivered image is a read-only deliverable.  This tool never
writes to an image; use `rootfs_workcopy` to make an editable copy first.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from ext4 import Ext4  # noqa: E402

DEFAULT_IMAGE = os.path.join(WS, "备份文件", "agentos-disk.img")
DEFAULT_EVIDENCE = os.path.join(HERE, "evidence")

# Paths that decide whether the delivered X11 kiosk session can come up.  The
# debugfs script prints each one so a reviewer can check our claims by hand.
SESSION_FILES = [
    "/etc/inittab",
    "/etc/init.d/kiosk-boot",
    "/etc/init.d/kiosk-shutdown",
    "/usr/local/bin/x11-session",
    "/etc/kiosk/env",
    "/etc/kiosk/url",
    "/etc/chromium/chromium.conf",
    "/etc/system.jwmrc",
    "/usr/share/kiosk/index.html",
    "/usr/share/X11/xorg.conf.d/40-libinput.conf",
    "/usr/share/X11/xorg.conf.d/10-quirks.conf",
    "/etc/fstab",
    "/etc/passwd",
    "/etc/group",
]

SESSION_BINARIES = [
    "/usr/bin/Xorg",
    "/usr/libexec/Xorg",
    "/usr/libexec/Xorg.wrap",
    "/usr/bin/jwm",
    "/usr/bin/chromium",
    "/usr/lib/chromium/chromium",
    "/bin/busybox",
]


def sha256_of(fs: Ext4, path: str) -> str:
    digest = hashlib.sha256()
    digest.update(fs.read_path(path))
    return digest.hexdigest()


def human_bytes(count: int) -> str:
    for unit in ("B", "KiB", "MiB", "GiB"):
        if count < 1024 or unit == "GiB":
            return f"{count:.0f} {unit}" if unit == "B" else f"{count:.1f} {unit}"
        count /= 1024.0  # type: ignore[assignment]
    return f"{count} B"


# --------------------------------------------------------------------------- #
# subcommands
# --------------------------------------------------------------------------- #
def cmd_super(a: argparse.Namespace) -> int:
    fs = Ext4(a.image)
    print(f"image           {a.image}")
    print(f"size on disk    {os.path.getsize(a.image)} bytes "
          f"({human_bytes(os.path.getsize(a.image))})")
    print(f"superblock at   {fs.sb_offset}")
    print(fs.sb.describe())
    free = fs.sb.free_blocks_count
    print(f"free space      {free} blocks "
          f"({human_bytes(free * fs.sb.block_size)})")
    fs.close()
    return 0


def cmd_inventory(a: argparse.Namespace) -> int:
    fs = Ext4(a.image)
    rows: list[str] = []
    rows.append("path\tinode\ttype\tmode\tsize\tsha256")
    root = fs.resolve(a.path)
    for path, inode in fs.walk(a.path):
        rel = path.rstrip("/") or "/"
        if inode.is_reg:
            try:
                digest = sha256_of(fs, rel)
            except Exception as exc:  # noqa: BLE001
                digest = f"ERROR:{exc}"
            size = inode.size
        else:
            digest = "-"
            size = inode.size
        rows.append(
            f"{rel}\t{inode.number}\t{inode.type_char}\t{inode.mode & 0o7777:04o}"
            f"\t{size}\t{digest}"
        )
    fs.close()

    text = "\n".join(sorted(rows[1:]))
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        with open(a.out, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("path\tinode\ttype\tmode\tsize\tsha256\n")
            fh.write(text)
            fh.write("\n")
        print(f"wrote {len(rows) - 1} entries to {a.out}")
    else:
        print("path\tinode\ttype\tmode\tsize\tsha256")
        print(text)
    return 0


def cmd_diff(a: argparse.Namespace) -> int:
    def load(path: str) -> dict[str, tuple[str, str, str, str]]:
        out: dict[str, tuple[str, str, str, str]] = {}
        with open(path, encoding="utf-8") as fh:
            next(fh, None)
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 6:
                    continue
                name, _inode, kind, mode, size, digest = parts
                out[name] = (kind, mode, size, digest)
        return out

    before, after = load(a.baseline), load(a.modified)
    added = sorted(set(after) - set(before))
    removed = sorted(set(before) - set(after))
    changed = sorted(
        name for name in set(before) & set(after) if before[name] != after[name]
    )

    print(f"# rootfs change manifest")
    print(f"baseline : {a.baseline}  ({len(before)} entries)")
    print(f"modified : {a.modified}  ({len(after)} entries)")
    print(f"added={len(added)} removed={len(removed)} changed={len(changed)}")
    for label, names in (("ADDED", added), ("REMOVED", removed), ("CHANGED", changed)):
        if not names:
            continue
        print(f"\n## {label}")
        for name in names:
            if label == "CHANGED":
                old, new = before[name], after[name]
                detail = []
                if old[1] != new[1]:
                    detail.append(f"mode {old[1]} -> {new[1]}")
                if old[2] != new[2]:
                    detail.append(f"size {old[2]} -> {new[2]}")
                if old[3] != new[3]:
                    detail.append("hash " f"{old[3][:12]}.. -> {new[3][:12]}..")
                print(f"  {name}   ({'; '.join(detail)})")
            else:
                entry = (after if label == "ADDED" else before)[name]
                print(f"  {name}   ({entry[0]}{entry[1]} {entry[2]} bytes)")
    return 0


def cmd_debugfs_script(a: argparse.Namespace) -> int:
    fs = Ext4(a.image)
    lines: list[str] = []
    add = lines.append

    add("# Replayable debugfs session for the delivered rootfs image.")
    add("#")
    add("# The committee asked for the debugfs information behind any rootfs change.")
    add("# Run this on a Linux host with e2fsprogs:")
    add("#")
    add(f"#     debugfs -f rootfs-debugfs-new.txt {os.path.basename(a.image)}")
    add("#")
    add("# Every line below is read-only; nothing here mutates the image.")
    add("")
    add("stats")
    add("show_super_stats")
    add("")
    add("# ---- delivered X11 kiosk session: configuration ----")
    for path in SESSION_FILES:
        add(f"cat {path}")
    add("")
    add("# ---- delivered X11 kiosk session: binaries (inode + block map) ----")
    for path in SESSION_BINARIES:
        add(f"stat {path}")
    add("")
    add("# ---- the whole kiosk tree ----")
    for directory in ("/etc/kiosk", "/usr/share/kiosk", "/usr/local/bin", "/usr/share/jwm"):
        add(f"ls -l {directory}")
    add("")
    add("# ---- device nodes the session needs ----")
    for node in ("/dev", "/dev/dri", "/dev/input"):
        add(f"ls -l {node}")
    add("")

    # Record the exact identity of every file we might touch, so a reviewer can
    # tell whether the submitted image is the delivered one.
    add("# ---- recorded identity of files the session depends on ----")
    for path in SESSION_FILES + SESSION_BINARIES:
        try:
            inode = fs.resolve(path)
        except FileNotFoundError:
            add(f"# MISSING: {path}")
            continue
        kind = inode.type_char
        add(
            f"# {path}  inode={inode.number} type={kind} "
            f"mode={inode.mode & 0o7777:04o} size={inode.size} "
            f"blocks={inode.blocks}"
        )
        if inode.is_reg and a.hashes:
            add(f"#   sha256={sha256_of(fs, path)}")
    add("")
    add("quit")
    fs.close()

    text = "\n".join(lines) + "\n"
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        with open(a.out, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        print(f"wrote {len(lines)} debugfs commands to {a.out}")
    else:
        sys.stdout.write(text)
    return 0


def cmd_workcopy(a: argparse.Namespace) -> int:
    if not os.path.isfile(a.image):
        print(f"no such image: {a.image}", file=sys.stderr)
        return 2
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    if os.path.exists(a.out) and not a.force:
        print(f"refusing to overwrite {a.out} (pass --force)", file=sys.stderr)
        return 2
    size = os.path.getsize(a.image)
    print(f"copying {human_bytes(size)} ...")
    shutil.copyfile(a.image, a.out)
    src = hashlib.sha256(open(a.image, "rb").read()).hexdigest()
    dst = hashlib.sha256(open(a.out, "rb").read()).hexdigest()
    print(f"source sha256 {src}")
    print(f"copy   sha256 {dst}")
    if src != dst:
        print("COPY MISMATCH - do not use this copy", file=sys.stderr)
        return 1
    print("copy verified byte-for-byte")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--image", default=DEFAULT_IMAGE)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("super", help="superblock summary and free space")
    p.set_defaults(func=cmd_super)

    p = sub.add_parser("inventory", help="path/inode/mode/size/sha256 listing")
    p.add_argument("--path", default="/")
    p.add_argument("--out")
    p.set_defaults(func=cmd_inventory)

    p = sub.add_parser("diff", help="diff two inventories")
    p.add_argument("baseline")
    p.add_argument("modified")
    p.set_defaults(func=cmd_diff)

    p = sub.add_parser("debugfs-script", help="emit a replayable debugfs session")
    p.add_argument("--out")
    p.add_argument("--hashes", action="store_true", default=True)
    p.set_defaults(func=cmd_debugfs_script)

    p = sub.add_parser("workcopy", help="verified byte-for-byte editable copy")
    p.add_argument("--out", default=os.path.join(WS, "new", "work", "agentos-work.img"))
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_workcopy)

    a = ap.parse_args()
    return a.func(a)


if __name__ == "__main__":
    raise SystemExit(main())
