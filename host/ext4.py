#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Minimal read-only ext4 reader written from scratch (pure Python, no deps).

Why: the delivered `agentos-disk.img` is a raw ext3/4 filesystem with a private
1024-byte header, and this Windows session has no WSL, no e2fsprogs and no 7-Zip.
Rather than fight the host, we read the filesystem directly.

Only what we need is implemented:
  * superblock + group descriptors (64-bit aware)
  * inode table lookup by inode number
  * extent-tree file data (ext4 `EXTENTS` feature)
  * classic direct/indirect block maps (fallback)
  * directory listing / recursive walk / file extraction
"""
from __future__ import annotations

import struct
import sys
from dataclasses import dataclass, field

SUPER_MAGIC = 0xEF53
SUPER_OFFSET = 1024  # ext* superblock is always at byte 1024

# inode mode bits
S_IFMT = 0o170000
S_IFDIR = 0o040000
S_IFREG = 0o100000
S_IFLNK = 0o120000

INCOMPAT_64BIT = 0x80
INCOMPAT_EXTENTS = 0x40
INCOMPAT_FILETYPE = 0x2
RO_COMPAT_HUGE_FILE = 0x8
RO_COMPAT_EXTRA_ISIZE = 0x20


@dataclass
class SuperBlock:
    raw: bytes
    inodes_count: int
    blocks_count: int
    r_blocks_count: int
    free_blocks_count: int
    free_inodes_count: int
    first_data_block: int
    log_block_size: int
    log_cluster_size: int
    blocks_per_group: int
    clusters_per_group: int
    inodes_per_group: int
    mtime: int
    wtime: int
    mnt_count: int
    max_mnt_count: int
    magic: int
    state: int
    errors: int
    minor_rev_level: int
    lastcheck: int
    checkinterval: int
    creator_os: int
    rev_level: int
    def_resuid: int
    def_resgid: int
    first_ino: int
    inode_size: int
    block_group_nr: int
    feature_compat: int
    feature_incompat: int
    feature_ro_compat: int
    uuid: bytes
    volume_name: str
    last_mounted: str
    desc_size: int
    blocks_count_hi: int
    free_blocks_hi: int

    @property
    def block_size(self) -> int:
        return 1024 << self.log_block_size

    @property
    def inode_count_total(self) -> int:
        return self.inodes_count

    @property
    def total_blocks(self) -> int:
        if self.feature_incompat & INCOMPAT_64BIT:
            return self.blocks_count | (self.blocks_count_hi << 32)
        return self.blocks_count

    @property
    def has_extents(self) -> bool:
        return bool(self.feature_incompat & INCOMPAT_EXTENTS)

    @property
    def groups(self) -> int:
        return (self.total_blocks - self.first_data_block + self.blocks_per_group - 1) // self.blocks_per_group

    def describe(self) -> str:
        return (
            f"block_size      = {self.block_size}\n"
            f"inode_size      = {self.inode_size}\n"
            f"inodes          = {self.inodes_count}  (free {self.free_inodes_count})\n"
            f"blocks          = {self.total_blocks}  (free {self.free_blocks_count})\n"
            f"blocks/group    = {self.blocks_per_group}\n"
            f"inodes/group    = {self.inodes_per_group}\n"
            f"groups          = {self.groups}\n"
            f"first_data_blk  = {self.first_data_block}\n"
            f"rev_level       = {self.rev_level}  minor={self.minor_rev_level}\n"
            f"feature_compat  = {self.feature_compat:#x}\n"
            f"feature_incompat= {self.feature_incompat:#x}"
            f"{'  [64BIT]' if self.feature_incompat & INCOMPAT_64BIT else ''}"
            f"{'  [EXTENTS]' if self.has_extents else ''}\n"
            f"feature_ro_compat={self.feature_ro_compat:#x}\n"
            f"desc_size       = {self.desc_size}\n"
            f"uuid            = {self.uuid.hex()}\n"
            f"volume_name     = {self.volume_name!r}\n"
            f"last_mounted    = {self.last_mounted!r}\n"
            f"state           = {self.state:#x}   errors={self.errors}\n"
            f"mtime/wtime     = {self.mtime}/{self.wtime}\n"
            f"creator_os      = {self.creator_os}\n"
        )


@dataclass
class Inode:
    number: int
    mode: int
    uid: int
    size: int
    atime: int
    ctime: int
    mtime: int
    dtime: int
    gid: int
    links_count: int
    blocks: int
    flags: int
    i_block: bytes = b""
    file_acl: int = 0
    extra: bytes = b""

    @property
    def is_dir(self) -> bool:
        return (self.mode & S_IFMT) == S_IFDIR

    @property
    def is_reg(self) -> bool:
        return (self.mode & S_IFMT) == S_IFREG

    @property
    def is_symlink(self) -> bool:
        return (self.mode & S_IFMT) == S_IFLNK

    @property
    def type_char(self) -> str:
        return {S_IFDIR: "d", S_IFREG: "-", S_IFLNK: "l"}.get(self.mode & S_IFMT, "?")

    @property
    def perm(self) -> str:
        m = self.mode & 0o7777
        out = []
        for shift, ch in ((8, "r"), (7, "w"), (6, "x"), (5, "r"), (4, "w"), (3, "x"), (2, "r"), (1, "w"), (0, "x")):
            out.append(ch if m & (1 << shift) else "-")
        return "".join(out)


class Ext4:
    def __init__(self, path: str, super_offset: int = SUPER_OFFSET):
        self.path = path
        self._f = open(path, "rb")
        self._f.seek(super_offset)
        sb_raw = self._f.read(1024)
        if len(sb_raw) < 1024:
            raise ValueError("short read for superblock")
        magic = struct.unpack_from("<H", sb_raw, 56)[0]
        if magic != SUPER_MAGIC:
            raise ValueError(f"bad ext magic {magic:#x} at offset {super_offset}")
        self.sb_offset = super_offset
        self.sb = self._parse_sb(sb_raw)
        self._desc_cache: list[tuple[int, int]] | None = None

    def _parse_sb(self, b: bytes) -> SuperBlock:
        u16 = lambda o: struct.unpack_from("<H", b, o)[0]
        u32 = lambda o: struct.unpack_from("<I", b, o)[0]
        sb = SuperBlock(
            raw=b,
            inodes_count=u32(0),
            blocks_count=u32(4),
            r_blocks_count=u32(8),
            free_blocks_count=u32(12),
            free_inodes_count=u32(16),
            first_data_block=u32(20),
            log_block_size=u32(24),
            log_cluster_size=u32(28),
            blocks_per_group=u32(32),
            clusters_per_group=u32(36),
            inodes_per_group=u32(40),
            mtime=u32(44),
            wtime=u32(48),
            mnt_count=u16(52),
            max_mnt_count=u16(54),
            magic=u16(56),
            state=u16(58),
            errors=u16(60),
            minor_rev_level=u16(62),
            lastcheck=u32(64),
            checkinterval=u32(68),
            creator_os=u32(72),
            rev_level=u32(76),
            def_resuid=u16(80),
            def_resgid=u16(82),
            first_ino=u32(84),
            inode_size=u16(88),
            block_group_nr=u16(90),
            feature_compat=u32(92),
            feature_incompat=u32(96),
            feature_ro_compat=u32(100),
            uuid=b[104:120],
            volume_name=b[120:136].split(b"\0")[0].decode("utf-8", "replace"),
            last_mounted=b[136:200].split(b"\0")[0].decode("utf-8", "replace"),
            desc_size=0,
            blocks_count_hi=0,
            free_blocks_hi=0,
        )
        if sb.rev_level >= 1:
            sb.desc_size = u16(254)
        else:
            sb.desc_size = 32
        if sb.desc_size < 32:
            sb.desc_size = 32
        if sb.feature_incompat & INCOMPAT_64BIT:
            sb.blocks_count_hi = u32(0x150)
            sb.free_blocks_hi = u32(0x158)
        if sb.inode_size == 0:
            sb.inode_size = 128
        return sb

    # ---------------------------------------------------------------- reading
    def _read_at(self, offset: int, length: int) -> bytes:
        self._f.seek(offset)
        data = self._f.read(length)
        if len(data) != length:
            raise IOError(f"short read at {offset}: wanted {length} got {len(data)} (EOF?)")
        return data

    def read_block(self, blk: int, count: int = 1) -> bytes:
        bs = self.sb.block_size
        return self._read_at(blk * bs, bs * count)

    def block_iter(self, blk: int, count: int = 1):
        bs = self.sb.block_size
        for i in range(count):
            yield self.read_block(blk + i)

    # ------------------------------------------------------- group descriptors
    def group_descriptors(self) -> list[tuple[int, int]]:
        """Return (block_bitmap, inode_bitmap) per group; only what we need."""
        if self._desc_cache is not None:
            return self._desc_cache
        sb = self.sb
        bs = sb.block_size
        gdt_block = sb.first_data_block + 1
        need = sb.groups * sb.desc_size
        nblocks = (need + bs - 1) // bs
        # GDT is duplicated in every group when SPARSE_SUPER, but group 0's copy is enough.
        raw = b"".join(self.block_iter(gdt_block, nblocks))
        out = []
        for g in range(sb.groups):
            o = g * sb.desc_size
            block_bitmap = struct.unpack_from("<I", raw, o)[0]
            inode_bitmap = struct.unpack_from("<I", raw, o + 4)[0]
            out.append((block_bitmap, inode_bitmap))
        self._desc_cache = out
        return out

    def inode_table_block(self, group: int) -> int:
        sb = self.sb
        bs = sb.block_size
        gdt_block = sb.first_data_block + 1
        need = sb.groups * sb.desc_size
        nblocks = (need + bs - 1) // bs
        raw = b"".join(self.block_iter(gdt_block, nblocks))
        o = group * sb.desc_size + 8  # inode_table is the 3rd u32
        return struct.unpack_from("<I", raw, o)[0]

    # ------------------------------------------------------------------ inodes
    def inode(self, number: int) -> Inode:
        sb = self.sb
        if number < 1 or number > sb.inodes_count:
            raise ValueError(f"inode {number} out of range 1..{sb.inodes_count}")
        group = (number - 1) // sb.inodes_per_group
        index = (number - 1) % sb.inodes_per_group
        table = self.inode_table_block(group)
        off = table * sb.block_size + index * sb.inode_size
        raw = self._read_at(off, sb.inode_size)
        u16 = lambda o: struct.unpack_from("<H", raw, o)[0]
        u32 = lambda o: struct.unpack_from("<I", raw, o)[0]
        ino = Inode(
            number=number,
            mode=u16(0),
            uid=u16(2),
            size=u32(4),
            atime=u32(8),
            ctime=u32(12),
            mtime=u32(16),
            dtime=u32(20),
            gid=u16(24),
            links_count=u16(26),
            blocks=u32(28),
            flags=u32(32),
            i_block=raw[40:100],
            file_acl=u32(104),
            extra=raw[128:],
        )
        if self.sb.feature_ro_compat & RO_COMPAT_HUGE_FILE and ino.flags & 0x8:
            ino.size = ino.size | (u32(108) << 32)
        return ino

    # ------------------------------------------------------------ block mapping
    def _extent_blocks(self, i_block: bytes) -> list[int]:
        """Walk an ext4 extent tree rooted in i_block (60 bytes).

        ON-DISK LAYOUT. The two entry kinds are 12 bytes each but are NOT the
        same field order -- mixing them up silently yields absurd block numbers:

            struct ext4_extent_header {          // 12 bytes
                __le16 eh_magic;                 // 0xF30A
                __le16 eh_entries;
                __le16 eh_max;
                __le16 eh_depth;                 // 0 = node holds leaf extents
                __le32 eh_generation;
            };

            struct ext4_extent {                 // 12 bytes, only at depth 0
                __le32 ee_block;
                __le16 ee_len;                   // 0x8000 = unwritten
                __le16 ee_start_hi;              // hi BEFORE lo
                __le32 ee_start_lo;
            };                                   //  -> struct "<IHHI"

            struct ext4_extent_idx {             // 12 bytes, only at depth > 0
                __le32 ei_block;
                __le32 ei_leaf_lo;               // lo BEFORE hi  (!)
                __le16 ei_leaf_hi;
                __le16 ei_unused;
            };                                   //  -> struct "<IIHH"
        """
        out: list[int] = []

        def walk(node: bytes, depth: int):
            magic, entries, _max_entries, node_depth, _gen = struct.unpack_from("<HHHHI", node, 0)
            if magic != 0xF30A:
                raise ValueError(f"bad extent magic {magic:#x} (expected 0xf30a)")
            if node_depth != depth:
                raise ValueError(f"extent depth mismatch: header {node_depth}, caller {depth}")
            for i in range(entries):
                o = 12 + i * 12
                if o + 12 > len(node):
                    break
                if depth == 0:
                    _ee_block, ee_len, ee_start_hi, ee_start_lo = struct.unpack_from("<IHHI", node, o)
                    length = ee_len & 0x7FFF
                    if length == 0:
                        continue
                    start = (ee_start_hi << 32) | ee_start_lo
                    out.extend(range(start, start + length))
                else:
                    _ei_block, leaf_lo, leaf_hi, _unused = struct.unpack_from("<IIHH", node, o)
                    child = (leaf_hi << 32) | leaf_lo
                    if child == 0:
                        continue
                    walk(self.read_block(child), depth - 1)

        walk(i_block, struct.unpack_from("<H", i_block, 6)[0])
        return out

    def _classic_blocks(self, i_block: bytes, size: int) -> list[int]:
        bs = self.sb.block_size
        ptrs = list(struct.unpack_from("<15I", i_block, 0))
        per = bs // 4
        out = list(ptrs[:12])
        need = (size + bs - 1) // bs
        if len(out) >= need:
            return out[:need]
        # single indirect
        if ptrs[12]:
            raw = self.read_block(ptrs[12])
            out.extend(struct.unpack_from(f"<{per}I", raw, 0))
        if len(out) >= need:
            return out[:need]
        if ptrs[13]:
            raw = self.read_block(ptrs[13])
            for p in struct.unpack_from(f"<{per}I", raw, 0):
                if len(out) >= need:
                    break
                if p:
                    out.extend(struct.unpack_from(f"<{per}I", self.read_block(p), 0))
        if len(out) >= need:
            return out[:need]
        if ptrs[14]:
            raw = self.read_block(ptrs[14])
            for p in struct.unpack_from(f"<{per}I", raw, 0):
                if len(out) >= need:
                    break
                if not p:
                    continue
                raw2 = self.read_block(p)
                for q in struct.unpack_from(f"<{per}I", raw2, 0):
                    if len(out) >= need:
                        break
                    if q:
                        out.extend(struct.unpack_from(f"<{per}I", self.read_block(q), 0))
        return out[:need]

    def file_blocks(self, ino: Inode) -> list[int]:
        if ino.flags & 0x80000 or (self.sb.has_extents and ino.i_block[:2] == b"\x0a\xf3"):
            return self._extent_blocks(ino.i_block)
        return self._classic_blocks(ino.i_block, ino.size)

    # ------------------------------------------------------------------- data
    def read_file(self, ino: Inode) -> bytes:
        if ino.is_symlink and ino.size <= 60:
            return ino.i_block[: ino.size]
        bs = self.sb.block_size
        if ino.is_symlink and ino.size < bs:
            # fast symlink stored in i_block already handled; slow symlink below
            pass
        chunks = []
        remaining = ino.size
        for blk in self.file_blocks(ino):
            if remaining <= 0:
                break
            if blk == 0:
                take = min(bs, remaining)
                chunks.append(b"\0" * take)
            else:
                chunks.append(self.read_block(blk))
            remaining -= bs
        data = b"".join(chunks)
        return data[: ino.size]

    def read_path(self, path: str, cwd: int = 2) -> bytes:
        ino = self.resolve(path, cwd)
        return self.read_file(ino)

    # ------------------------------------------------------------ directories
    def list_dir(self, ino: Inode) -> list[tuple[int, str, int, int]]:
        """Return (inode, name, file_type, rec_len) entries."""
        if not ino.is_dir:
            raise ValueError(f"inode {ino.number} is not a directory")
        sb = self.sb
        data_blocks = self.file_blocks(ino)
        # directories can be large; read lazily block by block
        entries: list[tuple[int, str, int, int]] = []
        seen = 0
        for blk in data_blocks:
            if blk == 0:
                continue
            raw = self.read_block(blk)
            off = 0
            while off + 8 <= len(raw):
                inode_num, rec_len, name_len, file_type = struct.unpack_from("<IHBB", raw, off)
                if rec_len < 8 or off + rec_len > len(raw):
                    break
                if inode_num != 0 and name_len > 0:
                    name = raw[off + 8 : off + 8 + name_len].decode("utf-8", "replace")
                    entries.append((inode_num, name, file_type, rec_len))
                off += rec_len
            seen += 1
        return entries

    def resolve(self, path: str, cwd: int = 2) -> Inode:
        if path.startswith("/"):
            ino = self.inode(2)
            parts = [p for p in path.split("/") if p]
        else:
            ino = self.inode(cwd)
            parts = [p for p in path.split("/") if p]
        for p in parts:
            if p == ".":
                continue
            if p == "..":
                ino = self.inode(2)
                continue
            found = None
            for num, name, _ft, _rl in self.list_dir(ino):
                if name == p:
                    found = num
                    break
            if found is None:
                raise FileNotFoundError(f"{p!r} not found in {path!r} (dir inode {ino.number})")
            ino = self.inode(found)
        return ino

    def walk(self, path: str = "/", follow_symlinks: bool = False):
        """Yield (path, Inode) depth-first."""
        root = self.resolve(path)
        stack = [(path.rstrip("/") or "", root)]
        while stack:
            p, ino = stack.pop()
            yield p or "/", ino
            if ino.is_dir:
                try:
                    kids = self.list_dir(ino)
                except Exception:
                    continue
                for num, name, _ft, _rl in kids:
                    if name in (".", ".."):
                        continue
                    cp = f"{p}/{name}"
                    try:
                        child = self.inode(num)
                    except Exception:
                        continue
                    if child.is_dir:
                        stack.append((cp, child))
                    else:
                        yield cp, child

    def close(self):
        self._f.close()


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        print("usage: ext4.py <image> super")
        print("       ext4.py <image> ls <path>")
        print("       ext4.py <image> cat <path>")
        print("       ext4.py <image> tree <path> [maxdepth]")
        print("       ext4.py <image> find <path> <substring>")
        return 2
    fs = Ext4(argv[1])
    cmd = argv[2] if len(argv) > 2 else "super"
    if cmd == "super":
        print(fs.sb.describe())
    elif cmd == "ls":
        ino = fs.resolve(argv[3])
        print(f"# {argv[3]}  inode={ino.number} size={ino.size} mode={ino.type_char}{ino.perm}")
        for num, name, ft, _rl in sorted(fs.list_dir(ino), key=lambda e: e[1]):
            if name in (".", ".."):
                continue
            try:
                c = fs.inode(num)
                print(f"{c.type_char}{c.perm} {c.size:>10} {num:>8}  {name}")
            except Exception as e:
                print(f"?          ?          {num:>8}  {name}   ({e})")
    elif cmd == "cat":
        ino = fs.resolve(argv[3])
        sys.stdout.write(fs.read_file(ino).decode("utf-8", "replace"))
    elif cmd == "tree":
        maxdepth = int(argv[4]) if len(argv) > 4 else 2
        base = argv[3].rstrip("/")
        for p, ino in sorted(fs.walk(argv[3])):
            depth = p.count("/") - base.count("/")
            if depth > maxdepth:
                continue
            print(f"{ino.type_char}{ino.perm} {ino.size:>10}  {p}")
    elif cmd == "find":
        needle = argv[4].lower()
        for p, ino in sorted(fs.walk(argv[3])):
            if needle in p.lower():
                print(f"{ino.type_char}{ino.perm} {ino.size:>10}  {p}")
    else:
        print(f"unknown command {cmd}", file=sys.stderr)
        return 2
    fs.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
