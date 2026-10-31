import json, pathlib, os, sys, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'host'))
from attempt_runner import classify

failures = []
def check(name, cond, detail=''):
    print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else f' {detail}'))
    if not cond: failures.append(name)

def mk(files):
    d = pathlib.Path(tempfile.mkdtemp(prefix='attempt-', dir=ROOT / 'experiments/REVIEW-FIX'))
    for name, content in files.items():
        (d / name).write_text(content, encoding='utf-8')
    return d

d = mk({})
check('no error but no terminal is not success', classify(d, 0, False)['status'] == 'INCOMPLETE')
d = mk({'qemu-metrics.json': '{}'})
check('fake metrics alone is not success', classify(d, 0, False)['status'] == 'INCOMPLETE')
d = mk({'qemu-metrics.json': '{}', 'zz-final.stats.json': '{}'})
check('terminal files without owned QEMU are not success', classify(d, 0, False)['status'] == 'INCOMPLETE')
d = mk({'qemu-metrics.json': '{}', 'zz-final.stats.json': '{}', 'qemu-owner.json': json.dumps({'pid': os.getpid()})})
check('non-QEMU owner PID is not success', classify(d, 0, False)['status'] == 'INCOMPLETE')
d = mk({'qemu-metrics.json': '{}', 'zz-final.stats.json': '{}', 'qemu-owner.json': json.dumps({'pid': 999999})})
check('dead owner PID is not success', classify(d, 0, False)['status'] == 'INCOMPLETE')
d = mk({'qemu-metrics.json': '{}', 'zz-final.stats.json': '{}', 'qemu-owner.json': json.dumps({'pid': 999999})})
check('deadline with no terminal is TIMEOUT', classify(d, 1, True)['status'] == 'TIMEOUT')
d = mk({'harness-error.txt': 'timeout'})
check('harness error is ERROR', classify(d, 0, False)['status'] == 'ERROR')

print('ATTEMPT-TERMINAL-TESTS-PASS' if not failures else f'{len(failures)} FAILURES')
raise SystemExit(1 if failures else 0)
