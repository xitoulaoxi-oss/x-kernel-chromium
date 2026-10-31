#!/usr/bin/env python3
"""Run one xkwin attempt with an explicit terminal state and owned-PID checks."""
from __future__ import annotations
import argparse, ctypes, json, os, pathlib, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parent.parent


def pid_alive(pid: int) -> bool:
    if os.name != 'nt':
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    k32 = ctypes.windll.kernel32
    h = k32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return False
    code = ctypes.c_ulong()
    ok = k32.GetExitCodeProcess(h, ctypes.byref(code))
    k32.CloseHandle(h)
    return bool(ok) and code.value == 259  # STILL_ACTIVE


def pid_is_qemu(pid: int) -> bool:
    if os.name != 'nt':
        return pid_alive(pid)
    k32 = ctypes.windll.kernel32
    h = k32.OpenProcess(0x1000, False, pid)
    if not h:
        return False
    try:
        buf = ctypes.create_unicode_buffer(1024)
        size = ctypes.c_ulong(len(buf))
        if not k32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size)):
            return False
        return 'qemu-system-aarch64' in buf.value.lower()
    finally:
        k32.CloseHandle(h)


def classify(directory: pathlib.Path, exit_code: int, timed_out: bool) -> dict:
    d = pathlib.Path(directory)
    err_file = d / 'harness-error.txt'
    metrics = d / 'qemu-metrics.json'
    final = d / 'zz-final.stats.json'
    owner_file = d / 'qemu-owner.json'
    error = err_file.read_text(encoding='utf-8', errors='replace').strip() if err_file.exists() else ''
    owner = None
    owner_alive = False
    try:
        owner = json.loads(owner_file.read_text(encoding='utf-8-sig'))
        owner_alive = pid_is_qemu(int(owner.get('pid', -1)))
    except (OSError, ValueError, TypeError):
        pass
    metrics_ok = metrics.exists() and metrics.stat().st_size > 0
    final_ok = final.exists()
    base = {'directory': str(d), 'exit_code': exit_code, 'timed_out': timed_out,
            'error': error, 'owner_pid': owner.get('pid') if owner else None,
            'owner_alive': owner_alive, 'metrics': metrics_ok, 'zz_final': final_ok}
    if timed_out:
        status = 'TIMEOUT'
    elif error:
        status = 'ERROR'
    elif exit_code == 0 and metrics_ok and final_ok and owner_alive:
        status = 'SUCCESS'
    else:
        status = 'INCOMPLETE'
    base['status'] = status
    base['success'] = status == 'SUCCESS'
    return base


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--outdir', required=True)
    ap.add_argument('--kernel', default='artifacts/kernel-final.bin')
    ap.add_argument('--script', default='guest\\06-fetch-pages.sh;guest\\x1-input.sh;guest\\x2-xorg.sh;guest\\y3-jwm-stock.sh;guest\\x4-win1.sh')
    ap.add_argument('--timeout', type=int, default=320)
    ap.add_argument('--tag', default='CONV')
    ap.add_argument('--page-probe', action='store_true')
    ap.add_argument('--keep', action='store_true', default=True)
    ap.add_argument('--no-keep', dest='keep', action='store_false')
    args = ap.parse_args()
    d = pathlib.Path(args.outdir)
    d.mkdir(parents=True, exist_ok=True)
    cmd = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'host\\xkwin.ps1',
           '-Tag', args.tag, '-Disk', 'D:\\x-kernel-dsh-bridge\\delivered\\agentos-disk.img',
           '-Kernel', args.kernel, '-ServeManifest', 'guest\\serve-pages.txt',
           '-Script', args.script, '-CommandTimeoutSec', '200', '-BootTimeoutSec', '420',
           '-AfterScriptWait', '5', '-OutDir', str(d)]
    if args.keep:
        cmd.append('-Keep')
    if args.page_probe:
        cmd += ['-EnableGuestCdp', '-PageProbeMode', 'page', '-ExpectedPageUrl',
                'file:///usr/share/kiosk/official/index.html']
    out = open(d / 'driver.out.log', 'wb')
    err = open(d / 'driver.err.log', 'wb')
    p = subprocess.Popen(cmd, cwd=ROOT, stdout=out, stderr=err)
    deadline = time.time() + args.timeout
    while time.time() < deadline:
        if (d / 'harness-error.txt').exists() or (d / 'qemu-metrics.json').exists():
            break
        if p.poll() is not None:
            break
        time.sleep(1)
    time.sleep(2)
    timed_out = not ((d / 'harness-error.txt').exists() or (d / 'qemu-metrics.json').exists())
    # Give the outer xkwin process time to return its own exit code after the
    # terminal evidence exists; only then terminate it (and never the guest).
    deadline_exit = time.time() + 20
    while time.time() < deadline_exit and p.poll() is None:
        time.sleep(0.5)
    outer_terminated = False
    if p.poll() is None:
        outer_terminated = True
        p.terminate()
        try:
            p.wait(timeout=8)
        except subprocess.TimeoutExpired:
            p.kill()
    exit_code = p.returncode if p.returncode is not None else -1
    result = classify(d, exit_code, timed_out)
    result['outer_terminated'] = outer_terminated
    (d / 'attempt.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if result['success'] else (2 if timed_out else 1)


if __name__ == '__main__':
    raise SystemExit(main())
