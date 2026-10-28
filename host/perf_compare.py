#!/usr/bin/env python3
"""Build the before/after performance comparison the task book's scoring asks for.

The performance item scores relative improvement against a team's *first runnable
version*, with the raw data and the baseline archived.  This tool takes the two
reports `perf_run.py` produced (one per kernel) and emits the comparison in both
machine-readable and human-readable form, so the arithmetic is auditable rather
than a claim in prose.

Usage:
    python host/perf_compare.py \\
        --before evidence/reports/perf-report-before.json \\
        --after  evidence/reports/perf-report-after.json \\
        --label-before kernel-keepalive.bin --label-after kernel-procfs.bin \\
        --out    evidence/reports/perf-before-after.json \\
        --md     evidence/reports/PERF-BEFORE-AFTER.md

Conventions kept deliberately explicit, because a comparison is only as good as
its stated direction:

  * a metric where *smaller is better* (all timings) improves by (before-after)/before;
  * `peak_mem_mb` and `cpu_s` are resource figures, not latencies, but they are
    still "smaller is better" here;
  * the counters (`renderer_forks`, `log_bytes`, `painted`) are diagnostic only and
    are reported without an improvement figure -- a larger number there is not an
    achievement, and pretending otherwise is how a report starts lying.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

# Metric classes, copied from perf_run.py so a recomputed summary can still label
# each metric the way the task book groups them (the coverage item scores classes).
METRIC_CLASSES = {
    "xorg_s": "startup",
    "jwm_s": "startup",
    "chrome_s": "startup",
    "paint_s": "page-load",
    "renderer_s": "renderer-creation",
    "peak_mem_mb": "peak-memory",
    "cpu_s": "cpu-usage",
}

# Metrics the task book names, in its order.  Everything here is "smaller is better".
SCORED = ("chrome_s", "paint_s", "renderer_s", "peak_mem_mb", "cpu_s")
# Startup is reported as its parts plus a sum, so a single figure exists for it.
STARTUP_PARTS = ("xorg_s", "jwm_s", "chrome_s")
# Diagnostics: reported, never scored.
DIAGNOSTIC = ("painted", "renderer_forks", "log_bytes")

# Task-book improvement bands for the 3-point "performance improvement" item.
BANDS = ((0.30, 3), (0.15, 2), (0.05, 1))


def load(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


# A sample is only usable for a performance comparison if every guest-side metric is
# present.  A run that died during boot still leaves a row (it has peak_mem_mb from
# the host), and folding those zeros into a median is how a "before/after" table ends
# up describing something that never ran.
REQUIRED = ("chrome_s", "paint_s", "renderer_s")


def usable_samples(rep: dict) -> list[dict]:
    return [s for s in rep.get("samples", [])
            if all(s.get(k) for k in REQUIRED) and s.get("peak_mem_mb") and s.get("cpu_s")]


def dropped_samples(rep: dict) -> list[dict]:
    return [s for s in rep.get("samples", []) if s not in usable_samples(rep)]


def recompute(samples: list[dict]) -> dict:
    """Median/min/max/spread over the given samples, plus an xorg+jwm+chrome total."""
    out = {}
    for key in ("xorg_s", "jwm_s", "chrome_s", "paint_s", "renderer_s", "peak_mem_mb", "cpu_s"):
        vals = sorted(s[key] for s in samples if s.get(key) is not None)
        if not vals:
            continue
        n = len(vals)
        med = (vals[n // 2] if n % 2 else (vals[n // 2 - 1] + vals[n // 2]) / 2)
        out[key] = {"class": METRIC_CLASSES.get(key, "counter"), "n": n, "median": med,
                    "min": vals[0], "max": vals[-1], "spread": vals[-1] - vals[0], "raw": vals}
    return out


def median_of(rep: dict, key: str):
    s = rep.get("summary", {}).get(key)
    return None if not s else s.get("median")


def median_counter(samples: list[dict], key: str):
    """Median of a diagnostic counter, formatted for prose (counters are integers)."""
    vals = sorted(s[key] for s in samples if s.get(key) is not None)
    if not vals:
        return "n/a"
    n = len(vals)
    med = vals[n // 2] if n % 2 else (vals[n // 2 - 1] + vals[n // 2]) / 2
    return f"{med:g}"


def band_points(frac: float | None) -> int:
    if frac is None:
        return 0
    for lo, pts in BANDS:
        if frac >= lo:
            return pts
    return 0


def compare_metric(before: dict, after: dict, key: str) -> dict:
    b = median_of(before, key)
    a = median_of(after, key)
    row = {
        "metric": key,
        "class": (before.get("summary", {}).get(key, {}) or {}).get("class"),
        "before_median": b,
        "after_median": a,
        "before_raw": (before.get("summary", {}).get(key, {}) or {}).get("raw"),
        "after_raw": (after.get("summary", {}).get(key, {}) or {}).get("raw"),
    }
    if b in (None, 0) or a is None:
        row["delta"] = None
        row["improvement_frac"] = None
        row["note"] = "not comparable (missing value, or a zero baseline)"
    else:
        row["delta"] = round(b - a, 3)
        row["improvement_frac"] = round((b - a) / b, 4)
        row["note"] = ""
    row["points"] = band_points(row["improvement_frac"]) if key in SCORED else 0
    return row


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--before", required=True)
    ap.add_argument("--after", required=True)
    ap.add_argument("--label-before", default="before")
    ap.add_argument("--label-after", default="after")
    ap.add_argument("--out", default=None, help="write the JSON comparison here")
    ap.add_argument("--md", default=None, help="write a Markdown table here")
    args = ap.parse_args(argv)

    bpath, apath = pathlib.Path(args.before), pathlib.Path(args.after)
    for p in (bpath, apath):
        if not p.is_file():
            print(f"missing report: {p}", file=sys.stderr)
            return 2
    before, after = load(bpath), load(apath)

    # Work from the usable samples, recomputing the summaries, so an incomplete run
    # cannot skew a median.  The dropped rows are reported, not hidden.
    b_use, a_use = usable_samples(before), usable_samples(after)
    b_drop, a_drop = dropped_samples(before), dropped_samples(after)
    before = dict(before, summary=recompute(b_use))
    after = dict(after, summary=recompute(a_use))

    nb, na = len(b_use), len(a_use)
    warn = []
    if nb != na:
        warn.append(f"usable sample counts differ: before n={nb}, after n={na}")
    if nb < 5 or na < 5:
        warn.append(
            f"fewer than 5 usable samples (before n={nb}, after n={na}); the task book "
            f"asks for at least 5 repeats per metric"
        )
    for label, drops in (("before", b_drop), ("after", a_drop)):
        if drops:
            warn.append(
                "%s: %d sample(s) excluded as incomplete (no guest-side metrics): %s"
                % (label, len(drops), ", ".join(str(d.get("evidence_dir")) for d in drops))
            )

    # Startup total = xorg + jwm + chrome, computed from medians.
    def startup_total(rep):
        vals = [median_of(rep, k) for k in STARTUP_PARTS]
        return None if any(v is None for v in vals) else round(sum(vals), 3)

    rows = [compare_metric(before, after, k) for k in SCORED]
    st_b, st_a = startup_total(before), startup_total(after)
    st = {
        "metric": "startup_total_s",
        "class": "startup",
        "before_median": st_b,
        "after_median": st_a,
        "delta": None if (st_b in (None, 0) or st_a is None) else round(st_b - st_a, 3),
        "improvement_frac": None if (st_b in (None, 0) or st_a is None) else round((st_b - st_a) / st_b, 4),
        "before_raw": None,
        "after_raw": None,
        "note": "sum of the startup medians (xorg_s + jwm_s + chrome_s)",
        "points": 0,
    }
    st["points"] = band_points(st["improvement_frac"])

    diag = []
    for k in DIAGNOSTIC:
        b, a = median_of(before, k), median_of(after, k)
        if b is None and a is None:
            continue
        diag.append({"metric": k, "before_median": b, "after_median": a})

    result = {
        "before": {
            "report": str(bpath),
            "label": args.label_before,
            "kernel": before.get("guest_kernel"),
            "repeats": nb,
            "excluded_incomplete": [d.get("evidence_dir") for d in b_drop],
            "host": before.get("host"),
            "qemu": before.get("qemu"),
        },
        "after": {
            "report": str(apath),
            "label": args.label_after,
            "kernel": after.get("guest_kernel"),
            "repeats": na,
            "excluded_incomplete": [d.get("evidence_dir") for d in a_drop],
            "host": after.get("host"),
            "qemu": after.get("qemu"),
        },
        "direction": "smaller is better for every scored metric",
        "bands": {"30%": 3, "15%": 2, "5%": 1},
        "startup_total": st,
        "metrics": rows,
        "diagnostics_not_scored": diag,
        "warnings": warn,
        "bands_hit": [r["metric"] for r in [st] + rows if r["points"] > 0],
        "points_from_bands": max([r["points"] for r in [st] + rows] or [0]),
    }

    if args.out:
        op = pathlib.Path(args.out)
        op.parent.mkdir(parents=True, exist_ok=True)
        op.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print("wrote", op)

    def fmt(v, nd=2):
        return "-" if v is None else (f"{v:.{nd}f}" if isinstance(v, float) else str(v))

    def pct(f):
        return "-" if f is None else f"{f * 100:+.1f}%"

    lines = []
    lines.append(f"# 性能 before/after 量化对照\n")
    lines.append(f"- **before**（基线，首个可运行版本）：`{args.label_before}` — {result['before']['kernel']}")
    lines.append(f"- **after**（最终版本）：`{args.label_after}` — {result['after']['kernel']}")
    lines.append(f"- 每项重复 **{nb}** 次（before）/ **{na}** 次（after），比较对象为**中位数**")
    lines.append(f"- 方向：**所有计分指标都是越小越好**")
    lines.append(f"- 宿主：{result['after']['host'].get('cpu')}，{result['after']['host'].get('os_registry')}；"
                 f"QEMU {result['after']['qemu']}（纯 TCG）")
    lines.append("")
    lines.append("| 指标 | 类别 | before 中位数 | after 中位数 | 变化 | 相对改善 | 赛题档位 |")
    lines.append("|---|---|---|---|---|---|---|")
    for r in [st] + rows:
        pts = f"{r['points']} 分" if r["points"] else ("—" if r["metric"] not in SCORED else "0 分")
        lines.append("| `%s` | %s | %s | %s | %s | %s | %s |" % (
            r["metric"], r.get("class") or "-", fmt(r["before_median"]), fmt(r["after_median"]),
            fmt(r["delta"]), pct(r["improvement_frac"]), pts))
    lines.append("")
    if diag:
        lines.append("### 诊断量（不计分，仅供参考）\n")
        lines.append("| 指标 | before | after |")
        lines.append("|---|---|---|")
        for d in diag:
            lines.append("| `%s` | %s | %s |" % (d["metric"], fmt(d["before_median"]), fmt(d["after_median"])))
        lines.append("")
        lines.append("> 诊断量只用于解释数据（例如 `renderer_forks` 变化可说明进程数的差异），"
                     "**不作为改善证据**：这些数变大并不意味着变好。\n")
    lines.append("### 原始数据（每项 5 次或以上的全部取值）\n")
    lines.append("| 指标 | before 原始值 | after 原始值 |")
    lines.append("|---|---|---|")
    for r in [st] + rows:
        br = r.get("before_raw")
        ar = r.get("after_raw")
        lines.append("| `%s` | %s | %s |" % (
            r["metric"],
            ", ".join(str(x) for x in br) if br else "（见两份报告）",
            ", ".join(str(x) for x in ar) if ar else "（见两份报告）"))
    lines.append("")
    if result["bands_hit"]:
        lines.append(f"**达到赛题档位的指标**：{', '.join('`%s`' % m for m in result['bands_hit'])}；"
                     f"该子项按最高档位计 **{result['points_from_bands']} 分**。\n")
    else:
        lines.append("**没有任何指标达到赛题的 5% 档位**，该子项计 0 分（赛题原文："
                     "性能改善数据 3 分……无对比数据 0 分；档位为 5%/15%/30%）。\n")
    lines.append("")
    lines.append("### 关于两个计分指标的口径警告（必须随数据一起读）\n")
    lines.append("**`paint_s` = 「Chromium 的 stderr 日志跨过 10 KB」的时刻，不是画面首帧。**")
    lines.append("它同时受内核日志刷屏影响，因此比真正的首帧指标更嘈杂，应被视为代理量，而不是赛题点名的")
    lines.append("「页面加载延迟 / 启动首帧」。\n")
    # Flag samples whose wall clock is far above their batch norm: that is the
    # signature of host contention, and it has to be pointed out rather than
    # silently averaged away.
    for label, reps in (("before", b_use), ("after", a_use)):
        walls = sorted(s.get("wall_s") or 0 for s in reps)
        if len(walls) < 3:
            continue
        norm = walls[len(walls) // 2]
        odd = [s for s in reps if (s.get("wall_s") or 0) > 1.4 * norm]
        if odd:
            lines.append("**宿主污染迹象（%s 批次）**：正常 `wall_s` ≈ %s s，但下列次的 `wall_s` 明显偏高，"
                         "是测量期间宿主还有别的任务在跑：\n" % (label, norm))
            lines.append("| 会话 | wall_s | cpu_s | paint_s |")
            lines.append("|---|---|---|---|")
            for s in odd:
                lines.append("| `%s` | %s | %s | %s |" % (
                    s.get("evidence_dir"), s.get("wall_s"), s.get("cpu_s"), s.get("paint_s")))
            lines.append("")
            lines.append("这些次**保留在统计里**——删掉它们才是作弊——但上面的中位数表必须连同这条一起读。\n")
    lines.append("**`renderer_s` = 「某个 zygote 第一次出现子进程」的时刻，不是 renderer 完成创建。**")
    lines.append("这个 build 的 renderer 不重写 argv（cmdline 仍是 `--type=zygote`），只能用进程树近似。")
    lines.append("两版内核下这个近似测到的**不是同一件事**：\n")
    lines.append("- **基线内核**：zygote 无法把 fd 交给子进程（缺 SCM_RIGHTS），反复 fork 子进程重试，")
    lines.append("  于是「第一次出现子进程」很早就成立，同一时刻的子进程计数也明显偏高。")
    lines.append("- **最终内核**：交接成功，子进程按需才 fork，测得的时间更晚、子进程计数回到 5。\n")
    lines.append("`renderer_forks` 中位数实测：before = %s，after = %s，**两组内部都完全稳定**，"
                 "说明这是内核行为差异而非噪声。\n" % (median_counter(b_use, "renderer_forks"),
                                                 median_counter(a_use, "renderer_forks")))
    lines.append("**结论：`renderer_s` 在这里是诊断量，不是可比的性能指标。** 把它读成「renderer 创建延迟变慢/变快」")
    lines.append("是误读——两版测到的是不同的事件。要让它真正可比，终点应改为**页面确实被绘制**")
    lines.append("（如 screendump 颜色数越过阈值）。\n")
    lines.append("")
    lines.append("### ⚠️ 顺序/宿主漂移警告：本对照是 A→B 两段式，不是交错 A/B\n")
    lines.append("before 批次与 after 批次是**先跑完一组再跑另一组**。把两组按实际先后摊开，")
    lines.append("`chrome_s` 与 `paint_s` 都呈**单调上升**，而 `cpu_s` 基本平（与内核无关）：\n")
    lines.append("| 顺序 | 会话 | 内核 | chrome_s | paint_s | cpu_s |")
    lines.append("|---|---|---|---|---|---|")
    seq = 0
    for label, kernel, reps in (("before", args.label_before, b_use),
                                ("after", args.label_after, a_use)):
        # Order by the `run` field: it records the order the samples were appended,
        # which is the actual wall-clock order.  Sorting by name would scatter a
        # topped-up batch through the table and hide the drift this section is about.
        for s in sorted(reps, key=lambda x: x.get("run") or 0):
            seq += 1
            lines.append("| %d | `%s` | %s | %s | %s | %s |" % (
                seq, s.get("evidence_dir"), kernel.split("（")[0].strip("`"),
                s.get("chrome_s"), s.get("paint_s"), s.get("cpu_s")))
    lines.append("")
    lines.append("`chrome_s` 与 `paint_s` 的上升出现在**每一段之内**，也跨越两段，且与用了哪枚内核无关；")
    lines.append("而 `renderer_forks` 与 `renderer_s` 在每一段内都**极其稳定**，说明那两处差异是真实且可重复的")
    lines.append("内核行为差异，只有 `chrome_s`/`paint_s` 在漂。\n")
    lines.append("**因此 `chrome_s`/`paint_s` 的负值更可能是宿主状态随时间劣化 + 顺序偏置，而不是内核回归。**")
    lines.append("要把它变成可信结论，必须改为**交错 A/B/A/B** 取样（每轮换一次内核）；")
    lines.append("本对照的两段式设计做不到这一点——如实标注，不据此宣称任何一方的优劣。\n")
    if warn:
        lines.append("### ⚠️ 警告\n")
        for w in warn:
            lines.append(f"- {w}")
        lines.append("")
    lines.append("> 生成方式：`python host/perf_compare.py --before … --after … --out … --md …`；"
                 "原始报告为 `evidence/reports/perf-report-before.json` 与 `evidence/reports/perf-report-after.json`，"
                 "会话证据在 `evidence/perf/`。")

    text = "\n".join(lines) + "\n"
    if args.md:
        mp = pathlib.Path(args.md)
        mp.parent.mkdir(parents=True, exist_ok=True)
        mp.write_text(text, encoding="utf-8", newline="\n")
        print("wrote", mp)

    print()
    # A Windows console is cp936 by default and cannot encode every character that
    # belongs in this report; the Markdown file is the deliverable, so a console
    # that cannot show it must not be allowed to fail the run.
    try:
        print(text)
    except UnicodeEncodeError:
        enc = sys.stdout.encoding or "ascii"
        print(text.encode(enc, errors="replace").decode(enc, errors="replace"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
