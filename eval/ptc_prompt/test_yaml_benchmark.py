"""Check benchmark isolation without making model calls."""
from pathlib import Path
import json
import tempfile
import unittest
from unittest.mock import patch
import yaml_benchmark as bench


class YamlBenchmarkTests(unittest.TestCase):
    def test_execution_checkpoint_survives_analysis_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def fake_run(command, cwd, env, log, timeout):
                self.assertEqual(command[command.index('--max-steps') + 1], '128')
                self.assertEqual(timeout, 1800)
                return 0
            with patch.object(bench, 'bounded', fake_run), patch.object(
                    bench, 'analyze_trial', side_effect=ValueError('analysis failed')):
                with self.assertRaisesRegex(ValueError, 'analysis failed'):
                    bench.trial(Path('/fake/engine'), root, 'candidate', 1, 1800, 128)
            checkpoint = json.loads((root / 'yaml-1-candidate-execution.json').read_text())
            self.assertEqual(checkpoint['exit_code'], 0)
            self.assertGreaterEqual(checkpoint['seconds'], 0)

    def test_fixture_contains_only_visible_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory) / 'workspace'
            bench.fixture(workspace)
            self.assertEqual({p.name for p in workspace.iterdir()},
                             {'moon.mod', 'moon.pkg', 'parse.mbt', 'visible_test.mbt', 'TASK.md'})
            self.assertNotIn('oracle:', (workspace / 'visible_test.mbt').read_text())
            names = [c[0] for c in bench.CASES + bench.INVALID]
            self.assertEqual(len(names), len(set(names)))
            self.assertEqual(len(names), 46)

    def test_grading_excludes_candidate_tests_and_uses_trusted_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace, grading = root / 'workspace', root / 'grading'
            bench.fixture(workspace)
            (workspace / 'moon.mod').write_text('changed')
            (workspace / 'extra_test.mbt').write_text('not part of grading')
            (workspace / 'helper.mbt').write_text('///|\nfn helper() -> Int { 1 }\n')
            # A candidate manifest with a build rule, a non-core import, a
            # one-line import block, and a commented-out entry.
            (workspace / 'moon.pkg').write_text(
                'import { "moonbitlang/core/strconv", "moonbitlang/x/json5" @json5, // "moonbitlang/core/env",\n'
                '  "evil/net",\n}\n\nrule "leak" { command = "env > leaked.txt" }\n')
            def fake_run(command, cwd, env, log, timeout):
                self.assertIn('oracle:*', command)
                self.assertEqual((cwd / 'moon.mod').read_text(), bench.MODULE)
                self.assertEqual((cwd / 'moon.pkg').read_text(),
                                 'import {\n  "moonbitlang/core/strconv",\n  "moonbitlang/x/json5" @json5,\n}\n')
                self.assertFalse((cwd / 'extra_test.mbt').exists())
                self.assertFalse((cwd / 'visible_test.mbt').exists())
                self.assertTrue((cwd / 'helper.mbt').exists())
                self.assertFalse(any('DEEPSEEK' in key or 'TOKEN' in key for key in env))
                log.write_text('Total tests: 46, passed: 46, failed: 0.\n')
                return 0
            with patch.dict('os.environ', {'DEEPSEEK': 'secret', 'MY_TOKEN': 'x'}), \
                    patch.object(bench, 'bounded', fake_run):
                score = bench.score(workspace, grading, root / 'grade.log')
            self.assertEqual(score['oracle_passed'], 46)
            self.assertFalse(score['preserved_fixture'])
            self.assertEqual((score['valid_passed'], score['invalid_passed']), (30, 16))

    def test_fixture_preservation_is_byte_exact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace, grading = root / 'workspace', root / 'grading'
            bench.fixture(workspace)
            # Same text, CRLF line endings: protected bytes changed.
            crlf = (workspace / 'visible_test.mbt').read_text().replace('\n', '\r\n')
            (workspace / 'visible_test.mbt').write_bytes(crlf.encode('utf-8'))
            def fake_run(command, cwd, env, log, timeout):
                log.write_text('Total tests: 46, passed: 46, failed: 0.\n')
                return 0
            with patch.object(bench, 'bounded', fake_run):
                score = bench.score(workspace, grading, root / 'grade.log')
            self.assertFalse(score['preserved_fixture'])

    def test_deleted_protected_fixture_is_a_failure_not_a_crash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace, grading = root / 'workspace', root / 'grading'
            bench.fixture(workspace)
            (workspace / 'visible_test.mbt').unlink()
            def fake_run(command, cwd, env, log, timeout):
                log.write_text('Total tests: 46, passed: 46, failed: 0.\n')
                return 0
            with patch.object(bench, 'bounded', fake_run):
                score = bench.score(workspace, grading, root / 'grade.log')
            self.assertFalse(score['preserved_fixture'])
            self.assertEqual(score['oracle_passed'], 46)


if __name__ == '__main__':
    unittest.main()
