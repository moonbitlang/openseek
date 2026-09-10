"""Paired real-agent TOML implementation benchmark for native Read vs builtin read.

Uses frozen OpenSeek binaries/resources, fresh independently committed Git roots,
identical prompts, alternating AB/BA order and post-run hidden CLI acceptance.
Credentials stay in the inherited environment. No model trial is silently retried.
"""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import shutil
import signal
import statistics
import subprocess
import sys
import time
import tomllib

from read_workflow_ab import digest, initialize_git, read_jsonl, save, trial_environment
from read_workflow_ab_report import pure_read_windows
from toml_read_ab_cases import INVALID, VALID

HERE = Path(__file__).resolve().parent
IGNORED = {'.git', '_build', '.mooncakes', '.openseek', 'node_modules'}
ADDENDUM = '''
For this task, integers are signed decimal integers. Implement the parser logic
in MoonBit yourself; do not reuse an existing TOML parser, use FFI, or delegate
parsing to another language. Other normal MoonBit dependencies are allowed.
Invalid TOML, invalid CLI usage, and unreadable input files must exit nonzero,
write a useful diagnostic to stderr, and emit no JSON result on stdout. For a
valid document, output one deterministic JSON value and exit zero.
Handle the task directly without delegating to child agents. Do not create
commits. You may organize the library API and implementation as you see fit.
'''


def source_digest(root):
    return {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob('*'))
            if p.is_file() and not any(part in IGNORED for part in p.relative_to(root).parts)}


def json_equal(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(json_equal(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(json_equal(x, y) for x, y in zip(a, b))
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a == b
    return type(a) is type(b) and a == b


def stop_process_group(pgid):
    # Every caller created this group with start_new_session=True. A successful
    # parent can still leave a child running; terminate those before the next trial.
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def command_run(command, cwd, env, *, stdin=None, timeout=120):
    started = time.monotonic()
    proc = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = proc.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        stop_process_group(proc.pid)
        stdout, stderr = proc.communicate()
    finally:
        stop_process_group(proc.pid)
        proc.wait()
    return {'command': [str(v) for v in command], 'returncode': proc.returncode,
            'timed_out': timed_out, 'elapsed_s': round(time.monotonic() - started, 3),
            'stdout': stdout, 'stderr': stderr}


def is_clean_failure(run):
    combined = run['stdout'] + run['stderr']
    stack = re.search(r'(?im)(RUNTIME ERROR|\bpanic\b|stack trace|traceback|^\s+at \S+)', combined)
    return (not run['timed_out'] and run['returncode'] > 0 and
            not run['stdout'].strip() and bool(run['stderr'].strip()) and not stack)


def cli_probes(command, root, env):
    root.mkdir(parents=True, exist_ok=True)
    probes = []
    outputs = {}
    for mode in ['stdin', 'file']:
        for valid, cases in [(True, VALID), (False, INVALID)]:
            for case in cases:
                name, text = case[:2]
                if mode == 'stdin':
                    argv, stdin = command + ['--stdin'], text
                else:
                    path = root / f'{name} input.toml'
                    path.write_text(text, newline='')
                    argv, stdin = command + [str(path)], None
                run = command_run(argv, root, env, stdin=stdin, timeout=5)
                if valid:
                    try:
                        actual = json.loads(run['stdout'])
                        correct = json_equal(actual, case[2])
                    except (ValueError, TypeError):
                        correct = False
                    passed = (run['returncode'] == 0 and not run['timed_out'] and correct)
                    outputs[(mode, name)] = run['stdout']
                else:
                    passed = bool(is_clean_failure(run))
                probes.append({'name': name, 'mode': mode, 'valid': valid,
                               'passed': passed, **run})
    for name, extra in [('missing-file', [str(root / 'absent-input.toml')]),
                        ('missing-argument', []), ('extra-argument', ['--stdin', 'extra'])]:
        run = command_run(command + extra, root, env, stdin='', timeout=5)
        probes.append({'name': name, 'mode': 'usage', 'valid': False,
                       'passed': bool(is_clean_failure(run)), **run})
    name, text, _ = VALID[-1]
    repeat = command_run(command + ['--stdin'], root, env, stdin=text, timeout=5)
    probes.append({'name': 'deterministic-output', 'mode': 'stdin', 'valid': True,
                   'passed': repeat['returncode'] == 0 and
                   repeat['stdout'] == outputs[('stdin', name)] == outputs[('file', name)],
                   **repeat})
    return probes


def preflight(out):
    for _, text, expected in VALID:
        assert json_equal(tomllib.loads(text), expected)
    for name, text in INVALID:
        try:
            tomllib.loads(text)
        except tomllib.TOMLDecodeError:
            continue
        raise AssertionError(f'Invalid case is accepted by tomllib: {name}')
    assert not json_equal(True, 1)
    assert json_equal({'x': [1, False]}, {'x': [1.0, False]})
    root = out / 'preflight'
    root.mkdir(exist_ok=True)
    good = root / 'reference.py'
    good.write_text('''import json, pathlib, sys, tomllib
try:
    if len(sys.argv) != 2:
        raise ValueError("expected one file or --stdin")
    text = sys.stdin.read() if sys.argv[1] == "--stdin" else pathlib.Path(sys.argv[1]).read_text()
    print(json.dumps(tomllib.loads(text), ensure_ascii=False, sort_keys=True))
except Exception as error:
    print("duplicate or invalid input: " + str(error), file=sys.stderr)
    sys.exit(2)
''')
    env = trial_environment()
    positive = cli_probes([sys.executable, str(good)], root / 'good', env)
    assert all(p['passed'] for p in positive), [p['name'] for p in positive if not p['passed']]
    bad = root / 'bad.py'
    bad.write_text('print("{}")\n')
    negative = cli_probes([sys.executable, str(bad)], root / 'bad', env)
    assert sum(p['passed'] for p in negative) < 10
    assert not is_clean_failure({'stdout': '', 'stderr': 'panic: parser failed',
                                 'returncode': 1, 'timed_out': False})
    git_root = root / 'git-fixture'
    git_root.mkdir(exist_ok=True)
    (git_root / 'only.txt').write_text('original\n')
    initialize_git(git_root, env)
    (git_root / 'only.txt').write_text('changed\n')
    changed = subprocess.check_output(['git', 'diff', '--name-only'], cwd=git_root,
                                      env=env, text=True).splitlines()
    assert changed == ['only.txt']
    save(out / 'preflight.json', {'valid_documents': len(VALID),
         'invalid_documents': len(INVALID), 'probes_per_submission': len(positive),
         'reference_passed': sum(p['passed'] for p in positive),
         'empty_parser_passed': sum(p['passed'] for p in negative), 'git_isolated': True})


def validate_submission(run_dir):
    root = run_dir / 'oracle'
    shutil.copytree(run_dir / 'workspace', root,
                    ignore=lambda _, names: [n for n in names if n in IGNORED], symlinks=False)
    if not (root / 'moon.mod').is_file():
        save(run_dir / 'validation-commands.json', [])
        save(run_dir / 'probes.json', [])
        return {'passed': False, 'moon_check': None, 'moon_test': None,
                'moon_build_cli': None, 'own_tests': None, 'blackbox_files': [],
                'modern_manifest': False, 'probes_total': 0, 'probes_passed': 0,
                'failed_probes': [], 'validation_error': 'No root moon.mod; commands were not run in an ancestor project.'}
    env = trial_environment()
    for key in ['DEEPSEEK', 'KIMI', 'GLM', 'OPENAI_API_KEY']:
        env.pop(key, None)
    # The oracle copy is also a Git root, so submitted build commands never see
    # the enclosing checkout through an upward Git search.
    initialize_git(root, env)
    commands = [command_run(['moon', 'check', '--target', 'native'], root, env),
                command_run(['moon', 'test', '--target', 'native'], root, env),
                command_run(['moon', 'build', '--target', 'native', 'cmd/tomljson'], root, env)]
    save(run_dir / 'validation-commands.json', commands)
    cli = list((root / '_build/native/debug/build').glob('**/cmd/tomljson/tomljson.exe'))
    probes = cli_probes([str(cli[0])], run_dir / 'probes', env) if len(cli) == 1 and commands[2]['returncode'] == 0 else []
    save(run_dir / 'probes.json', probes)
    blackbox = [str(p.relative_to(root)) for p in root.rglob('*_test.mbt')
                if '_build' not in p.parts and '.mooncakes' not in p.parts and
                re.search(r'\b(?:async\s+)?test\b', p.read_text())]
    total_tests = re.search(r'Total tests: (\d+), passed: (\d+), failed: (\d+)',
                            commands[1]['stdout'] + commands[1]['stderr'])
    own_tests = int(total_tests[1]) if total_tests else None
    modern_manifest = (root / 'moon.mod').is_file() and not (root / 'moon.mod.json').exists()
    validations_ok = all(c['returncode'] == 0 and not c['timed_out'] for c in commands)
    acceptance_ok = len(probes) == 2 * (len(VALID) + len(INVALID)) + 4 and all(p['passed'] for p in probes)
    return {'passed': validations_ok and acceptance_ok and bool(blackbox) and
            own_tests is not None and own_tests > 0 and modern_manifest,
            'moon_check': commands[0]['returncode'] == 0,
            'moon_test': commands[1]['returncode'] == 0,
            'moon_build_cli': commands[2]['returncode'] == 0,
            'own_tests': own_tests, 'blackbox_files': blackbox,
            'modern_manifest': modern_manifest, 'probes_total': len(probes),
            'probes_passed': sum(p['passed'] for p in probes),
            'failed_probes': [{'name': p['name'], 'mode': p['mode'],
                              'stdout': p['stdout'], 'stderr': p['stderr'],
                              'returncode': p['returncode']} for p in probes if not p['passed']]}


def metrics(run_dir):
    events = read_jsonl(run_dir / 'events.jsonl')
    usage = Counter()
    for event in events:
        if event.get('event') == 'usage':
            usage.update({k: v for k, v in event['usage'].items() if type(v) is int})
    calls = []
    for session in (run_dir / 'sessions').rglob('openseek_session-*.jsonl'):
        for event in read_jsonl(session):
            item = event.get('item', {})
            if item.get('kind') == 'assistant':
                for call in item.get('payload', {}).get('tool_calls', []):
                    try:
                        decoded = json.loads(call['arguments'])
                    except (ValueError, TypeError):
                        decoded = None
                    calls.append({**call, 'decoded_arguments': decoded})
    save(run_dir / 'calls.json', calls)
    named = [c for c in calls if c['name'] == 'mbtx' and
             isinstance(c['decoded_arguments'], dict) and
             c['decoded_arguments'].get('filename') == '@builtin/read.mbtx']
    delegated = [c['name'] for c in calls if c['name'] in {'worker', 'explore', 'review'} or
                 (isinstance(c['decoded_arguments'], dict) and c['decoded_arguments'].get('subrun'))]
    answers = [e['answer'] for e in events if e.get('event') == 'agent_finished']
    first_usage = next((e['usage'] for e in events if e.get('event') == 'usage'), None)
    return {'usage': dict(usage), 'usage_events': sum(e.get('event') == 'usage' for e in events),
            'first_prompt_tokens': first_usage.get('prompt_tokens') if first_usage else None,
            'steps': sum(e.get('event') == 'agent_step' for e in events),
            'tool_calls': dict(Counter(c['name'] for c in calls)), 'tool_calls_total': len(calls),
            'named_read_calls': len(named), 'named_read_arguments': [c['decoded_arguments'] for c in named],
            'pure_read_batch_windows_ms': pure_read_windows(run_dir),
            'tool_errors': [{'tool': e['tool_name'], 'content': e['content']}
                            for e in events if e.get('event') == 'tool_result' and e.get('is_error')],
            'decode_errors': sum(e.get('event') == 'tool_call_decode_error' for e in events),
            'retries': sum(e.get('event') == 'stream_retry' for e in events),
            'event_counts': dict(Counter(e.get('event') for e in events if e.get('event'))),
            'finished': bool(answers), 'answer': answers[-1] if answers else None,
            'delegated_calls': delegated,
            'terminal_errors': [e for e in events if e.get('event') in
                                {'turn_failed', 'agent_setup_failed', 'max_steps_exhausted', 'agent_aborted'}]}


def run_trial(args, trial, prompt):
    root = args.out / trial['id']
    if (root / 'result.json').is_file():
        return json.loads((root / 'result.json').read_text())
    if root.exists():
        raise RuntimeError(f'Incomplete trial retained: {root}; inspect rather than retry')
    workspace = root / 'workspace'
    workspace.mkdir(parents=True)
    (workspace / '.gitignore').write_text('_build/\n.mooncakes/\n')
    env = trial_environment()
    initialize_git(workspace, env)
    before = source_digest(workspace)
    save(root / 'fixture-sha256.json', before)
    (root / 'prompt.txt').write_text(prompt)
    env['OPENSEEK_REFERENCES'] = str(getattr(args, trial['arm'] + '_share'))
    command = [str(getattr(args, trial['arm'])), 'run', '--dir', str(workspace),
               '--model', args.model, '--thinking', 'high', '--max-steps', str(args.max_steps),
               '--retry-attempts', '2', '--retry-backoff-ms', '1000', '--mcp-config', '',
               '--global-skills-dir', str(args.out / 'empty-skills'), '--session', trial['id'],
               '--session-root', str(root / 'sessions'), '--approval', 'never']
    if args.api_url is not None:
        command.extend(['--api-url', args.api_url])
    command.append(prompt)
    save(root / 'command.json', command)
    print(f"START {trial['id']} arm={trial['arm']}", flush=True)
    start = time.monotonic()
    with (root / 'events.jsonl').open('w') as stdout, (root / 'stderr.log').open('w') as stderr:
        process = subprocess.Popen(command, cwd=workspace, env=env, stdin=subprocess.DEVNULL,
                                   stdout=stdout, stderr=stderr, start_new_session=True)
        timed_out = False
        try:
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            stop_process_group(process.pid)
        finally:
            stop_process_group(process.pid)
            process.wait()
    elapsed = time.monotonic() - start
    measured = metrics(root)
    after = source_digest(workspace)
    actual_git = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], cwd=workspace,
                                         env=env, text=True).strip()
    assert Path(actual_git).resolve() == workspace.resolve()
    validation = validate_submission(root)
    assert after == source_digest(workspace), 'oracle changed the submitted workspace'
    stderr_text = (root / 'stderr.log').read_text().strip()
    result = {**trial, **measured, 'returncode': process.returncode, 'timed_out': timed_out,
              'model_stderr': stderr_text if stderr_text else None,
              'elapsed_s': round(elapsed, 3), 'validation': validation,
              'fixture_sha256': before, 'source_sha256': after, 'git_isolated': True,
              'passed': process.returncode == 0 and measured['finished'] and
              not measured['delegated_calls'] and validation['passed']}
    save(root / 'result.json', result)
    print(f"DONE {trial['id']} passed={result['passed']} steps={result['steps']} "
          f"probes={validation['probes_passed']}/{validation['probes_total']} "
          f"usage={result['usage']}", flush=True)
    return result


def aggregate(rows):
    usage = Counter()
    for row in rows:
        usage.update(row['usage'])
    return {'runs': len(rows), 'passed': sum(r['passed'] for r in rows),
            'finished': sum(r['finished'] for r in rows), 'usage': dict(usage),
            'steps': sum(r['steps'] for r in rows),
            'tool_calls': sum(r['tool_calls_total'] for r in rows),
            'named_read_calls': sum(r['named_read_calls'] for r in rows),
            'native_read_calls': sum(r['tool_calls'].get('read', 0) for r in rows),
            'tool_errors': sum(len(r['tool_errors']) for r in rows),
            'probes_passed': sum(r['validation']['probes_passed'] for r in rows),
            'probes_total': sum(r['validation']['probes_total'] for r in rows),
            'elapsed_median_s': statistics.median(r['elapsed_s'] for r in rows) if rows else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['baseline', 'candidate', 'baseline-share', 'candidate-share', 'out']:
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--task', type=lambda p: Path(p).resolve(), default=HERE.parent / 'prompt_tasks/toml_parser_cli.md')
    parser.add_argument('--model', default='deepseek-v4-flash')
    parser.add_argument('--api-url', help='Optional common endpoint; the CLI disables web_search for custom endpoints')
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--max-steps', type=int, default=160)
    parser.add_argument('--timeout', type=int, default=1800)
    parser.add_argument('--limit', type=int)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / 'empty-skills').mkdir(exist_ok=True)
    prompt = args.task.read_text() + ADDENDUM
    plan = []
    for repeat in range(1, args.repeats + 1):
        arms = ['baseline', 'candidate'] if repeat % 2 else ['candidate', 'baseline']
        for arm in arms:
            plan.append({'id': f"toml-{repeat:02d}-{'a' if arm == 'baseline' else 'b'}",
                         'repeat': repeat, 'arm': arm})
    dependencies = ['toml_read_ab.py', 'toml_read_ab_cases.py', 'read_workflow_ab.py', 'read_workflow_ab_report.py']
    config = {'model': args.model, 'thinking': 'high', 'max_steps': args.max_steps,
              'api_url': args.api_url, 'web_search_available': args.api_url is None,
              'timeout_seconds': args.timeout, 'prompt': prompt, 'task_sha256': digest(args.task),
              'evaluator_sha256': {name: digest(HERE / name) for name in dependencies},
              'baseline_sha256': digest(args.baseline), 'candidate_sha256': digest(args.candidate),
              'baseline_share_sha256': source_digest(args.baseline_share),
              'candidate_share_sha256': source_digest(args.candidate_share),
              'trials': plan, 'primary_metric': 'cumulative input tokens, including cache hits',
              'secondary_metrics': ['output tokens', 'cache miss input', 'steps', 'hidden acceptance'],
              'policy': 'fixed trials, no dropped failures, no feedback or product tuning between trials'}
    plan_file = args.out / 'plan.json'
    if plan_file.exists():
        assert json.loads(plan_file.read_text()) == config, 'experiment configuration changed'
    else:
        preflight(args.out)
        save(plan_file, config)
    if args.prepare_only:
        print((args.out / 'preflight.json').read_text())
        return
    rows = []
    for trial in plan[:args.limit]:
        rows.append(run_trial(args, trial, prompt))
        summary = {arm: aggregate([r for r in rows if r['arm'] == arm])
                   for arm in ['baseline', 'candidate']}
        save(args.out / 'results.json', {'summary': summary, 'trials': rows})
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == '__main__':
    main()
