"""Offline checks that the live eval cannot pass by merely claiming success."""
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
import run


class OracleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.workspace = Path(self.directory.name)

    def events(self, answer, results=()):
        items = [{'kind': 'tool_result', 'payload': r} for r in results]
        items.append({'kind': 'terminal', 'payload': {'kind': 'finished', 'message': answer}})
        (self.workspace / 'openseek_session-test.jsonl').write_text(
            '\n'.join(json.dumps({'item': item}) for item in items))

    def test_capability_comparison_holds_prompt_constant(self):
        base = 'before\n### Programmatic tool calls\ncurrent SDK guidance\n## Tool Protocol\nafter'
        variants = run.prompt_variants(base, False)
        self.assertEqual(variants, {'baseline': base, 'candidate': base})
        historical = run.prompt_variants(base, True)
        self.assertNotEqual(historical['baseline'], historical['candidate'])
        self.assertTrue(all(p.startswith('before\n') and p.endswith('## Tool Protocol\nafter')
                            for p in historical.values()))

    def test_named_parent_session_excludes_review_children(self):
        self.events('parent done')
        (self.workspace / 'openseek_session-test-sr-1.jsonl').write_text(
            json.dumps({'item': {'kind': 'terminal', 'payload': {'message': 'child done'}}}) + '\n')
        with self.assertRaises(ValueError):
            run.session_items(self.workspace)
        items = run.session_items(self.workspace, session_name='test')
        self.assertEqual(items[-1]['payload']['message'], 'parent done')

    def test_claim_without_edit_fails(self):
        _, expected = run.fixture('single_edit', self.workspace)
        self.events('Done')
        self.assertFalse(run.analyze('single_edit', self.workspace, expected, 0)['passed'])

    def test_correct_edit_passes_but_protected_file_change_fails(self):
        _, expected = run.fixture('single_edit', self.workspace)
        (self.workspace / 'note.txt').write_text(expected['note.txt'])
        self.events('Done')
        self.assertTrue(run.analyze('single_edit', self.workspace, expected, 0)['passed'])
        (self.workspace / 'keep.txt').write_text('changed')
        self.assertFalse(run.analyze('single_edit', self.workspace, expected, 0)['passed'])

    def test_computed_oracle_requires_every_file_and_summary(self):
        _, expected = run.fixture('computed_edits', self.workspace)
        for name, content in expected.items():
            (self.workspace / name).write_text(content)
        total = sum((i + 3) * (107 + 19 * i) for i in range(12))
        self.events(f'Updated 12 files; total {total}')
        self.assertTrue(run.analyze('computed_edits', self.workspace, expected, 0)['passed'])
        self.events('Updated 12 files')
        self.assertFalse(run.analyze('computed_edits', self.workspace, expected, 0)['passed'])

    def test_search_requires_observed_urls(self):
        _, expected = run.fixture('search', self.workspace)
        answer = {'python': ['https://docs.python.org/3/library/asyncio-task.html'],
                  'rust': ['https://doc.rust-lang.org/std/thread/fn.scope.html']}
        self.events(json.dumps(answer))
        self.assertFalse(run.analyze('search', self.workspace, expected, 0)['passed'])
        results = [{'tool_name': 'web_search', 'content': urls[0], 'is_error': False,
                    'data': {'sources': [{'url': urls[0]}]}}
                   for urls in answer.values()]
        self.events(json.dumps(answer), [dict(r, tool_name='mbtx') for r in results])
        self.assertFalse(run.analyze('search', self.workspace, expected, 0)['passed'])
        self.events(json.dumps(answer), results)
        self.assertTrue(run.analyze('search', self.workspace, expected, 0)['passed'])

    def test_baseline_search_bullets_have_equivalent_provenance(self):
        _, expected = run.fixture('search', self.workspace)
        answer = {'python': ['https://docs.python.org/3/library/asyncio-task.html'],
                  'rust': ['https://doc.rust-lang.org/std/thread/fn.scope.html']}
        results = [{'tool_name': 'web_search', 'content': f'Sources:\n- [Official]({urls[0]})\n',
                    'is_error': False} for urls in answer.values()]
        self.events(json.dumps(answer), results)
        self.assertTrue(run.analyze('search', self.workspace, expected, 0)['passed'])
        self.assertEqual(run.source_urls({'content': 'Unobserved https://docs.python.org/'}), set())
        self.assertEqual(run.source_urls(dict(results[0], data={'sources': []})), set())

    def test_byte_oracle_rejects_changed_line_endings(self):
        _, expected = run.fixture('single_edit', self.workspace)
        (self.workspace / 'note.txt').write_bytes(expected['note.txt'].replace('\n', '\r\n').encode())
        self.events('Done')
        self.assertFalse(run.analyze('single_edit', self.workspace, expected, 0)['passed'])

    def test_required_ptc_cannot_pass_with_only_correct_files(self):
        _, expected = run.fixture('single_edit', self.workspace)
        (self.workspace / 'note.txt').write_text(expected['note.txt'])
        self.events('Done')
        self.assertFalse(run.analyze('single_edit', self.workspace, expected, 0, True)['passed'])

    def test_nested_errors_and_interruption_are_counted(self):
        _, expected = run.fixture('single_edit', self.workspace)
        self.events('done', [{'tool_name': 'mbtx', 'content': 'failed', 'is_error': True,
                             'data': {'ptc_calls': [
                                 {'name': 'edit', 'status': 'interrupted'},
                                 {'name': 'edit', 'status': 'done', 'result': {'is_error': True}}]}}])
        result = run.analyze('single_edit', self.workspace, expected, 0)
        self.assertEqual((result['nested_calls'], result['nested_errors'], result['interrupted_calls']),
                         (2, 1, 1))



class BoundedRunnerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.workspace = Path(self.directory.name)

    def run_bounded(self, script, **limits):
        log = self.workspace / 'run.log'
        code = run.bounded([sys.executable, '-c', script], self.workspace, os.environ.copy(),
                           log, **limits)
        return code, log.read_text()

    def test_exit_code_and_output_are_returned_within_the_timeout(self):
        code, output = self.run_bounded('print("done"); raise SystemExit(3)', timeout=30)
        self.assertEqual(code, 3)
        self.assertEqual(output.strip(), 'done')

    def test_timeout_terminates_the_process_group(self):
        started = time.monotonic()
        code, output = self.run_bounded(
            'import time; print("up", flush=True); time.sleep(60)', timeout=0.5, grace=5)
        self.assertIsNone(code)
        self.assertEqual(output.strip(), 'up')
        self.assertLess(time.monotonic() - started, 5)

    def test_grace_expiry_kills_a_process_that_ignores_sigterm(self):
        started = time.monotonic()
        code, output = self.run_bounded(
            'import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); '
            'print("up", flush=True); time.sleep(60)', timeout=0.5, grace=0.5)
        self.assertIsNone(code)
        self.assertEqual(output.strip(), 'up')
        self.assertLess(time.monotonic() - started, 10)


if __name__ == '__main__':
    unittest.main()
