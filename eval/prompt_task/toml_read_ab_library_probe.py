"""Post-hoc typed-JSON check, separate from the frozen TOML CLI acceptance score.

Run only after every planned model trial has ended. Uses fresh source copies and
the same positive/negative numeric payload assertions for every submission.
"""

import argparse
import json
from pathlib import Path
import re
import shutil

from read_workflow_ab import digest, initialize_git, save, trial_environment
from toml_read_ab import command_run, IGNORED, source_digest


def parse_expression(interface, literal):
    # Only adapt the public String versus StringView argument, never behavior.
    if re.search(r'^pub fn parse_string\(String\)', interface, re.M):
        return f'parse_string({literal})'
    if re.search(r'^pub fn parse\(String\)', interface, re.M):
        return f'parse({literal})'
    if re.search(r'^pub fn parse\(StringView\)', interface, re.M):
        return f'parse({literal}[:])'
    raise ValueError('No recognized public parse API; inspect and record an adapter')


def locate_library(workspace):
    candidates = []
    for interface in workspace.rglob('pkg.generated.mbti'):
        if any(part in IGNORED for part in interface.relative_to(workspace).parts):
            continue
        try:
            parse_expression(interface.read_text(), '""')
        except ValueError:
            continue
        candidates.append(interface)
    if len(candidates) != 1:
        raise ValueError(f'Inspect ambiguous or unsupported library API: {candidates}')
    return candidates[0].parent.relative_to(workspace), candidates[0].read_text()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    plan = json.loads((args.run / 'plan.json').read_text())
    assert all((args.run / trial['id'] / 'result.json').is_file() for trial in plan['trials']), 'Wait for all model trials'
    env = trial_environment()
    for key in ['DEEPSEEK', 'KIMI', 'GLM', 'OPENAI_API_KEY']:
        env.pop(key, None)
    rows = []
    for trial in plan['trials']:
        trial_root = args.run / trial['id']
        workspace = trial_root / 'workspace'
        original = json.loads((trial_root / 'result.json').read_text())['source_sha256']
        assert source_digest(workspace) == original
        library_dir, interface = locate_library(workspace)
        tests = []
        for label, number in [('positive', 7), ('negative', -7)]:
            expression = parse_expression(interface, json.dumps(f'value = {number}\n'))
            tests.append(f'''///|
test "posthoc typed JSON {label} integer" {{
  let value = {expression}
  guard value is Json::Object(fields) else {{ fail("expected object") }}
  guard fields.get("value") is Some(Json::Number(number, ..)) else {{
    fail("expected numeric payload")
  }}
  assert_eq(number, {number}.0)
}}
''')
        root = trial_root / 'library-probe'
        shutil.copytree(workspace, root,
                        ignore=lambda _, names: [n for n in names if n in IGNORED])
        initialize_git(root, env)
        test_path = root / library_dir / 'posthoc_payload_test.mbt'
        assert not test_path.exists()
        source = '\n'.join(tests)
        test_path.write_text(source)
        run = command_run(['moon', 'test', '--target', 'native',
                           str(test_path.relative_to(root))], root, env)
        summary = re.search(r'Total tests: (\d+), passed: (\d+), failed: (\d+)',
                            run['stdout'] + run['stderr'])
        row = {'id': trial['id'], 'arm': trial['arm'], 'test_source': source,
               'library_dir': str(library_dir),
               'source_sha256': original, 'command_result': run,
               'tests': int(summary[1]) if summary else None,
               'passed': int(summary[2]) if summary else None,
               'failed': int(summary[3]) if summary else None}
        assert source_digest(workspace) == original, 'Probe modified model source'
        save(trial_root / 'library-probe.json', row)
        rows.append(row)
        print(trial['id'], 'tests:', row['tests'], 'passed:', row['passed'], flush=True)
    save(args.run / 'library-probe.json', {
        'post_hoc': True, 'frozen_cli_scores_changed': False,
        'purpose': 'Check the numeric payload, not just its serialized repr',
        'script_sha256': digest(Path(__file__)), 'trials': rows,
    })


if __name__ == '__main__':
    main()
