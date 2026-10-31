import json, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'host'))
from page_probe import assess

ROOT = pathlib.Path(__file__).resolve().parents[1]
HASHES = {p.name: __import__('hashlib').sha256(p.read_bytes()).hexdigest()
          for p in [ROOT / 'pages/index.html', ROOT / 'pages/interaction.html', ROOT / 'pages/layout.html']}


def value(url, title='t', h1='h', rows=None, verdict=False):
    return {'url': url, 'title': title, 'h1': h1, 'ready_state': 'complete',
            'time_origin': 123.0, 'body_text': 'body', 'rows': rows or {},
            'verdict_pass': verdict}


def main():
    failures = []
    def check(name, cond, detail=''):
        print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else f' {detail}'))
        if not cond: failures.append(name)

    index_url = 'file:///pages/index.html'
    v = assess(value(index_url), 'id1', index_url, 'page')
    check('static index not_applicable, not false',
          v['ok'] and v['rows']['T1'] == 'not_applicable' and v['verdict'] == 'not_applicable', v)
    v = assess(value(index_url), 'id1', index_url, 'js')
    check('static index as js page fails', not v['ok'], v)
    v = assess({'url': index_url, 'ready_state': 'complete', 'time_origin': 1.0, 'body_text': 'body',
                'title': '', 'h1': '', 'rows': {}, 'verdict_pass': False}, 'id1', index_url, 'page')
    check('empty document fails', not v['ok'], v)
    v = assess(value(index_url), 'id1', index_url, 'page', expected_body_sha256='0' * 64)
    check('official/hash mismatch fails', not v['ok'], v)

    interaction = 'file:///pages/interaction.html'
    t_rows = {f'T{i}': {'pass': True, 'text': 'pass'} for i in range(1, 7)}
    v = assess(value(interaction, rows=t_rows, verdict=False), 'id2', interaction, 'page')
    check('interaction page requires T1-T6 only',
          v['ok'] and v['rows']['C1'] == 'not_applicable' and v['verdict'] == 'not_applicable', v)
    t_bad = dict(t_rows); t_bad['T4'] = {'pass': False, 'text': 'wait'}
    v = assess(value(interaction, rows=t_bad), 'id2', interaction, 'page')
    check('interaction T failure is a real failure', not v['ok'], v)

    layout = 'file:///pages/layout.html'
    c_rows = {f'C{i}': {'pass': True, 'text': 'pass'} for i in range(1, 7)}
    v = assess(value(layout, rows=c_rows, verdict=False), 'id3', layout, 'page')
    check('layout page requires C1-C6 only', v['ok'] and v['rows']['T1'] == 'not_applicable', v)

    # Browser EXPRESSION returns verdict_pass at the top level, not in rows.
    for mode, url, rows in [('js', interaction, t_rows), ('css', layout, c_rows)]:
        v = assess(value(url, rows=rows, verdict=True), 'valid-'+mode, url, mode)
        check(mode+' real top-level verdict passes', v['ok'] and v['verdict'] is True, v)
        v = assess(value(url, rows=rows, verdict=False), 'invalid-'+mode, url, mode)
        check(mode+' failed top-level verdict is rejected', not v['ok'], v)

    unknown = 'file:///pages/about:blank'
    v = assess(value(unknown), 'id4', unknown, 'page')
    check('unknown document does not pass', not v['ok'], v)

    print('PAGE-VERDICT-TESTS-PASS' if not failures else f'{len(failures)} FAILURES')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
