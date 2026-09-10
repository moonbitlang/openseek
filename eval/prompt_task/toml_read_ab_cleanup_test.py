"""Regression coverage for descendants that outlive an evaluation command."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from read_workflow_ab import trial_environment
from toml_read_ab import command_run


class ProcessCleanupTest(unittest.TestCase):
    def check_descendant_cleanup(self, parent_sleep, timeout):
        script = '''import subprocess, sys, time
child = subprocess.Popen(
    [sys.executable, '-c', 'import time; time.sleep(60)'],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(child.pid, flush=True)
time.sleep(PARENT_SLEEP)
'''.replace('PARENT_SLEEP', str(parent_sleep))
        with tempfile.TemporaryDirectory(prefix='toml-process-cleanup-') as directory:
            result = command_run([sys.executable, '-c', script], Path(directory),
                                 trial_environment(), timeout=timeout)
        pid = int(result['stdout'].strip())
        try:
            self.assertEqual(result['timed_out'], parent_sleep > timeout)
            if not result['timed_out']:
                self.assertEqual(result['returncode'], 0)
            deadline = time.monotonic() + 2
            while True:
                state = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='],
                                       capture_output=True, text=True).stdout.strip()
                if not state or state.startswith('Z'):
                    break
                if time.monotonic() >= deadline:
                    self.fail(f'Child {pid} remained running after its parent ended')
                time.sleep(0.1)
        finally:
            # The regression must not leave its own child behind when it fails.
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    def test_successful_parent_cleans_up_descendant(self):
        self.check_descendant_cleanup(parent_sleep=0, timeout=5)

    def test_timed_out_parent_cleans_up_descendant(self):
        self.check_descendant_cleanup(parent_sleep=60, timeout=1)


if __name__ == '__main__':
    unittest.main()
