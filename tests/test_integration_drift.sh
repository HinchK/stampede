#!/usr/bin/env bash
# Successful test exits must still describe the integrated commit's tree.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export STAMPEDE_TEST_ROOT="$ROOT"
PYTHON_BIN=$(/bin/bash "$ROOT/lib/pyenv.sh")
"$PYTHON_BIN" - <<'PY'
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ['STAMPEDE_TEST_ROOT'])

class IntegrationDrift(unittest.TestCase):
    def test_gate_tree(self):
        cases = {
            'tracked': 'printf changed > value.txt',
            'untracked': 'printf stray > stray.txt',
            'head': 'git -c user.name=t -c user.email=t@t commit -q --allow-empty -m drift',
            'clean': 'test -f value.txt',
        }
        for kind, command in cases.items():
            with self.subTest(kind=kind), tempfile.TemporaryDirectory(prefix='stampede-drift-') as tmp:
                repo = Path(tmp)
                def git(*args):
                    return subprocess.check_output(['git', '-C', tmp, *args], text=True).strip()
                git('init', '-q', '-b', 'main')
                (repo/'.gitignore').write_text('.herdr-swarm/\n')
                (repo/'value.txt').write_text('baseline\n')
                git('add', '-A')
                git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'base')
                base = git('rev-parse', 'HEAD')
                (repo/'value.txt').write_text('candidate\n')
                git('add', '-A')
                git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'candidate')
                sha = git('rev-parse', 'HEAD')
                state = repo/'.herdr-swarm'
                state.mkdir()
                env = {**os.environ, 'REPO_DIR': tmp, 'STATE_DIR': str(state),
                       'PROJECT_SLUG': 'drift', 'BASE_BRANCH': 'main', 'TEST_CMD': command}
                subprocess.run(['/bin/bash', '-c', '''source "$1/lib/arbiter.sh"
arbiter_init_ref "$2" >/dev/null
arbiter_enqueue DRIFT worker "$3"
arbiter_drain
''', 'drift-test', str(ROOT), base, sha], env=env, capture_output=True, text=True, check=True)
                rows = json.loads(subprocess.check_output(['jq', '-sc', '.', str(state/'integration.jsonl')], text=True))
                if kind == 'clean':
                    self.assertEqual(rows[-1]['status'], 'integrated')
                    self.assertEqual(git('rev-parse', 'refs/heads/swarm/drift/integration'), sha)
                else:
                    self.assertEqual(rows[-1]['status'], 'integration_red')
                    self.assertIn('drift', rows[-1]['gate']['reason'])
                    self.assertEqual(git('rev-parse', 'refs/heads/swarm/drift/integration'), base)
                    self.assertFalse((state/'session-verdicts.jsonl').exists())

unittest.main()
PY
