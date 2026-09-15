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
            def fake_run(command, cwd, env, log, timeout):
                self.assertIn('oracle:*', command)
                self.assertEqual((cwd / 'moon.mod').read_text(), bench.MODULE)
                self.assertFalse((cwd / 'extra_test.mbt').exists())
                self.assertFalse((cwd / 'visible_test.mbt').exists())
                self.assertTrue((cwd / 'helper.mbt').exists())
                log.write_text('Total tests: 46, passed: 46, failed: 0.\n')
                return 0
            with patch.object(bench, 'bounded', fake_run):
                score = bench.score(workspace, grading, root / 'grade.log')
            self.assertEqual(score['oracle_passed'], 46)
            self.assertFalse(score['preserved_fixture'])
            self.assertEqual((score['valid_passed'], score['invalid_passed']), (30, 16))


if __name__ == '__main__':
    unittest.main()
