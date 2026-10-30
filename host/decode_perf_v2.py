#!/usr/bin/env python3
"""Decode the iteration-07 low-overhead guest sampler.

Guest marks use /proc/uptime (monotonic, centiseconds).  Memory is KiB in the
kernel interface and is reported here as MiB.  No host/guest epoch subtraction
is used.
"""
from __future__ import annotations
import argparse, json, pathlib, re

ANSI = re.compile(r'\x1b\[[0-9;?]*[a-zA-Z]')


def load(p):
    try:
        return json.loads(pathlib.Path(p).read_text(encoding='utf-8-sig'))
    except Exception:
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('session')
    ap.add_argument('--out')
    args = ap.parse_args()
    s = pathlib.Path(args.session)
    console = ANSI.sub('', (s / 'console.log').read_text(encoding='utf-8', errors='replace'))
    t0 = None
    clock_kind = None
    m0 = re.search(r'MONO_T0=(uptime|wall):([0-9.]+)', console)
    if m0:
        clock_kind = m0.group(1)
        t0 = float(m0.group(2))
    mem = []
    renderers = []
    for m in re.finditer(r'^MONO=(?:uptime|wall):([0-9.]+) MEM_USED_KB=(\d+)$', console, re.M):
        mem.append({'mono_s': float(m.group(1)), 'used_kib': int(m.group(2))})
    for m in re.finditer(r'^MONO=(?:uptime|wall):([0-9.]+) RENDERER pid=(\d+) start=(\S+) threads=(\d+)$', console, re.M):
        start = m.group(3)
        renderers.append({'mono_s': float(m.group(1)), 'pid': int(m.group(2)),
                          'proc_start_ticks': None if start == 'na' else int(start), 'threads': int(m.group(4))})
    browser = load(s / 'browser-processes.json') or {}
    roles = set(browser.get('renderer_pids') or [])
    confirmed = [r for r in renderers if r['pid'] in roles]
    first = confirmed[0] if confirmed else None
    fw = load(s / 'frame-watch.json') or {}
    an = fw.get('analysis') or {}
    page = load(s / 'page-check.json') or {}
    peak = max((x['used_kib'] for x in mem), default=None)
    out = {
        'session': str(s),
        'clock': {'guest': ('/proc/uptime monotonic seconds (0.01 s)' if clock_kind == 'uptime'
                             else 'wall seconds (kernel has no /proc/uptime; CLOCK=wall)'),
                  'guest_clock_kind': clock_kind,
                  'host_frame': 'frame-watch Stopwatch t0 at launch dispatch',
                  'page_load': 'browser loadEventEnd - navigationStart',
                  'cross_clock_subtraction': False},
        't0_mono_s': t0,
        'memory': {'samples': len(mem), 'unit_in_source': 'KiB',
                   'peak_used_kib': peak,
                   'peak_used_mib': round(peak / 1024.0, 2) if peak is not None else None,
                   'note': 'MemTotal-MemFree, includes cache, not per-process RSS'},
        'renderer': {'candidate_events': len(renderers), 'role_confirmed_events': len(confirmed),
                     'first_confirmed': None if not first else {
                         'pid': first['pid'],
                         'creation_mono_s': first['mono_s'],
                         'creation_after_t0_s': round(first['mono_s'] - t0, 2) if t0 else None,
                         'proc_start_ticks': first['proc_start_ticks'],
                         'threads': first['threads']}},
        'first_frame': {'found': an.get('found'), 'first_s': an.get('first_frame_s'),
                        'lo_s': an.get('first_frame_lo_s'), 'bracket_s': an.get('first_frame_bracket_s')},
        'page': {'ok': page.get('ok'), 'url': page.get('url'),
                 'load_ms_in_browser': round(page.get('page_load_end_ms', 0) - page.get('time_origin', 0), 1)
                 if page.get('page_load_end_ms') else None},
        'ok': bool(page.get('ok') and an.get('found') and first and peak is not None),
    }
    if args.out:
        pathlib.Path(args.out).write_text(json.dumps(out, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(out, indent=2))
    return 0 if out['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
