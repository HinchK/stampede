#!/usr/bin/env bash
# Exercise real queue writers in separate processes and read their JSONL.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export STAMPEDE_TEST_ROOT="$ROOT"
PYTHON_BIN=$(/bin/bash "$ROOT/lib/pyenv.sh")
"$PYTHON_BIN" - <<'PY'
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(os.environ['STAMPEDE_TEST_ROOT'])
with tempfile.TemporaryDirectory(prefix='stampede-queue-') as tmp:
    state = Path(tmp) / '.herdr-swarm'
    state.mkdir()
    queue = state / 'integration.jsonl'
    env = {**os.environ, 'REPO_DIR': tmp, 'STATE_DIR': str(state), 'PROJECT_SLUG': 'test'}
    def run(code, check=True, extra=None):
        return subprocess.run(['/bin/bash', '-c', 'source "$1/lib/arbiter.sh"\n' + code,
                               'queue-test', str(root)], env={**env, **(extra or {})},
                              text=True, capture_output=True, check=check, timeout=20)
    def rows():
        return [json.loads(line) for line in queue.read_text().splitlines() if line.strip()]

    run('arbiter_enqueue A a aaaaaaa; arbiter_enqueue B b bbbbbbb; '
        '_arb_set_status A aaaaaaa integrated')
    records = rows()
    assert [r['status'] for r in records] == ['integrated', 'queued'], records
    print('PASS: status replacement preserves one object per line and queued neighbors')

    queue.unlink()
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda _: run('arbiter_enqueue DUP worker abcdef0'), range(8)))
    assert len(rows()) == 1, rows()
    print('PASS: concurrent duplicate enqueue commits exactly one record')

    # Hold the replacement at rename. With a writer lock, arrivals wait;
    # without one, force the old append-before-rename interleaving.
    queue.write_text(json.dumps({'ts': 1, 'ticket': 'A', 'sha': 'aaaaaaa',
                                 'seat': 'a', 'status': 'queued'}) + '\n')
    entered, release = Path(tmp) / 'entered', Path(tmp) / 'release'
    os.mkfifo(entered)
    os.mkfifo(release)
    code = '''
mv() {
  printf 'ready\\n' > "$TEST_ENTERED"
  read -r _ < "$TEST_RELEASE"
  command mv "$@"
}
_arb_set_status A aaaaaaa integrated
'''
    writer = subprocess.Popen(['/bin/bash', '-c', 'source "$1/lib/arbiter.sh"\n' + code,
                               'queue-test', str(root)], env={**env, 'TEST_ENTERED': str(entered),
                                                             'TEST_RELEASE': str(release)},
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    with entered.open() as handle:
        assert handle.readline().strip() == 'ready'
    with concurrent.futures.ThreadPoolExecutor() as pool:
        arrival = pool.submit(run, 'arbiter_enqueue B b bbbbbbb')
        if not (state / 'queue.lock').exists():
            arrival.result(timeout=10)
        with release.open('w') as handle:
            handle.write('continue\n')
        stdout, stderr = writer.communicate(timeout=15)
        assert writer.returncode == 0, (stdout, stderr)
        arrival.result(timeout=15)
    assert {r['ticket'] for r in rows()} == {'A', 'B'}, rows()
    print('PASS: an arrival during replacement survives')

    queue.write_text('{broken\n')
    original = queue.read_bytes()
    result = run('arbiter_enqueue BAD worker abcdef0', check=False)
    assert result.returncode != 0 and queue.read_bytes() == original
    assert not (state / 'queue.lock').exists()
    print('PASS: corrupt queue is preserved and writer ownership released')

    queue.write_text(json.dumps({'ts': 1, 'ticket': 'OLD', 'seat': 'a', 'sha': 'aaaaaaa',
                                 'status': 'queued', 'custom': {'keep': True}}, indent=2))
    run('arbiter_enqueue OLD a bbbbbbb')
    records = rows()
    assert records[0]['status'] == 'superseded' and records[0]['custom'] == {'keep': True}
    assert records[1]['sha'] == 'bbbbbbb'
    print('PASS: legacy formatted rows compact without losing fields')

    before = queue.read_bytes()
    result = run('mv() { return 1; }; _arb_set_status OLD bbbbbbb integrated', check=False)
    assert result.returncode != 0 and queue.read_bytes() == before
    assert not (state / 'queue.lock').exists()
    print('PASS: failed replacement preserves the queue and releases its lock')

    repo = Path(tmp) / 'repo'
    repo.mkdir()
    def git(*args):
        return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()
    git('init', '-q', '-b', 'main')
    (repo/'.gitignore').write_text('.herdr-swarm/\n')
    (repo/'value.txt').write_text('base\n')
    git('add', '-A')
    git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'base')
    base = git('rev-parse', 'HEAD')
    (repo/'value.txt').write_text('worker\n')
    git('add', '-A')
    git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'worker')
    old = git('rev-parse', 'HEAD')
    state = repo/'.herdr-swarm'
    state.mkdir()
    queue = state/'integration.jsonl'
    env.update(REPO_DIR=str(repo), STATE_DIR=str(state), BASE=base, OLD=old)
    run('arbiter_init_ref "$BASE"; arbiter_enqueue A worker "$OLD"')
    gate_entered, gate_release = Path(tmp)/'gate-entered', Path(tmp)/'gate-release'
    os.mkfifo(gate_entered)
    os.mkfifo(gate_release)
    drain = subprocess.Popen(['/bin/bash', str(root/'lib/arbiter.sh'), 'drain'],
        env={**env, 'GATE_ENTERED': str(gate_entered), 'GATE_RELEASE': str(gate_release),
             'TEST_CMD': 'printf ready > "$GATE_ENTERED"; read -r token < "$GATE_RELEASE"'},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    with gate_entered.open() as handle:
        assert handle.read() == 'ready'
    try:
        run('arbiter_enqueue B other "$BASE"')
        (repo/'value.txt').write_text('new worker\n')
        git('add', '-A')
        git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'new worker')
        new = git('rev-parse', 'HEAD')
        run('arbiter_enqueue A worker "$NEW"', extra={'NEW': new})
    finally:
        with gate_release.open('w') as handle:
            handle.write('continue\n')
        stdout, stderr = drain.communicate(timeout=20)
    assert drain.returncode == 0, (stdout, stderr)
    assert git('rev-parse', 'refs/heads/swarm/test/integration') == base
    assert {(r['ticket'], r['sha']) for r in rows() if r['status'] == 'queued'} == {('A', new), ('B', base)}
    assert next(r for r in rows() if r['sha'] == old)['status'] == 'superseded'
    print('PASS: arrivals proceed during slow tests; superseded candidates cannot advance integration')

    run('''_arb_set_status A "$NEW" integrated "{merge_sha: \\\"$NEW\\\"}"
_arb_set_status B "$BASE" integrated "{merge_sha: \\\"$BASE\\\"}"
_arb_queue_write promote "$BASE"
''', extra={'NEW': new})
    records = rows()
    assert next(r for r in records if r['sha'] == new)['status'] == 'integrated'
    assert next(r for r in records if r['ticket'] == 'B')['status'] == 'promoted'
    print('PASS: promotion records only the commits actually covered by the promoted tip')
PY
