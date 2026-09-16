#!/usr/bin/env python3
"""Bounded PTC capability or historical prompt A/B. Credentials are inherited, never recorded."""
import argparse
import concurrent.futures
import hashlib
import json
import os
import re
from pathlib import Path
import signal
import subprocess
import tempfile
import time
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CASES = ('single_edit', 'computed_edits', 'search')
MODEL = 'deepseek-v4-flash'
MAX_STEPS = 24


def bounded(command, cwd, env, log, timeout, grace=10):
    """Run `command` with its output in `log`; None when killed at `timeout`.

    The child gets its own session so the whole tree is signalled: SIGTERM,
    then SIGKILL after `grace` seconds.
    """
    with log.open('w') as output:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=grace)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            return None


def trial_env(workspace):
    """The engine's environment: credentials inherited and global skills disabled."""
    env = os.environ.copy()
    env['OPENSEEK_GLOBAL_SKILLS_DIR'] = str(workspace / '.no-global-skills')
    return env


def engine_command(engine, workspace, name, prompt, task, max_steps):
    return [str(engine), 'run', '--model', MODEL, '--max-steps', str(max_steps),
            '--dir', str(workspace), '--session', name,
            '--system-prompt-file', str(prompt), task]


def engine_hashes(engines):
    return {variant: hashlib.sha256(binary.read_bytes()).hexdigest()
            for variant, binary in engines.items()}


def head_commit():
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()


def fixture(case, workspace):
    files = {'keep.txt': 'preserve me\n'}
    if case == 'single_edit':
        files['note.txt'] = 'alpha\nbeta\ngamma\n'
        expected = {'note.txt': 'alpha\ndelta\ngamma\n'}
        task = 'In note.txt replace the unique word beta with delta; preserve every other byte.'
    elif case == 'computed_edits':
        rows = ['file,units,unit_price_cents']
        expected = {}
        for i in range(12):
            name = f'items/item-{i:02}.txt'
            units, price = i + 3, 107 + 19 * i
            rows.append(f'{name},{units},{price}')
            files[name] = f'item={i:02}\ntotal_cents=0\nstatus=keep\n'
            expected[name] = files[name].replace('total_cents=0', f'total_cents={units * price}')
        files['prices.csv'] = '\n'.join(rows) + '\n'
        task = ('Read prices.csv. For each row, set total_cents in the named item file to '
                'units * unit_price_cents. Preserve all other bytes and all input files. '
                'Report the number of updated files and the sum of their new totals.')
    else:
        expected = {}
        task = ('Use web_search to find official documentation for both topics: Python asyncio.TaskGroup '
                'and Rust std::thread::scope. Return a JSON object with exactly the keys python and rust, '
                'each holding one or two distinct official documentation URLs found in search results. '
                'Do not create files. No prose outside the JSON object in your final answer.')
    for name, content in files.items():
        path = workspace / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    task += ('\nUse the host editing tools for modifications. Preserve keep.txt and unrelated files. '
             'Verify the result before finishing. Workspace: ' + str(workspace))
    return task, files | expected


def session_items(workspace, session_name=None):
    pattern = f'openseek_session-{session_name}.jsonl' if session_name else 'openseek_session-*.jsonl'
    paths = list(workspace.rglob(pattern))
    if len(paths) != 1:
        raise ValueError(f'expected one session, got {len(paths)}')
    records = [json.loads(line) for line in paths[0].read_text().splitlines()]
    return [record['item'] for record in records if 'item' in record]


def source_urls(result):
    data = result.get('data')
    if isinstance(data, dict) and 'sources' in data:
        return {source['url'] for source in data['sources']
                if isinstance(source, dict) and isinstance(source.get('url'), str)}
    # The SDK-only baseline predates structured search metadata. Its source
    # bullets contain the same URLs the model sees. Normalize that format so
    # provenance scoring does not require a candidate-only feature.
    return set(re.findall(r'(?m)^- \[[^\n]*\]\((https?://[^\s]+)\)$',
                          result.get('content', '')))


def session_metrics(items):
    """Split a session into its parts and count the calls both runners report."""
    assistants = [i['payload'] for i in items if i['kind'] == 'assistant']
    results = [i['payload'] for i in items if i['kind'] == 'tool_result']
    terminals = [i['payload'] for i in items if i['kind'] == 'terminal']
    nested = [call for r in results for call in (r.get('data') or {}).get('ptc_calls', [])]
    metrics = {
        'steps': len(assistants),
        'outer_calls': sum(len(a.get('tool_calls', [])) for a in assistants),
        'nested_calls': len(nested),
        'tool_errors': sum(r['is_error'] for r in results),
        'nested_errors': sum(c.get('result', {}).get('is_error', False) for c in nested),
    }
    return metrics, results, nested, terminals


def analyze(case, workspace, expected, exit_code, require_ptc=False, session_name=None):
    # The parent session by name: a review child leaves a second journal.
    items = session_items(workspace, session_name=session_name)
    metrics, results, nested, terminals = session_metrics(items)
    failures = []
    if require_ptc and not any(c['name'] in ('edit', 'multi_edit', 'web_search') for c in nested):
        failures.append('requested PTC was not used')
    if exit_code != 0 or not terminals or terminals[-1]['kind'] != 'finished':
        failures.append('run did not finish successfully')
    for name, content in expected.items():
        path = workspace / name
        if not path.exists() or path.read_bytes() != content.encode('utf-8'):
            failures.append(f'byte oracle failed: {name}')
    final = terminals[-1]['message'] if terminals else None
    if case == 'search':
        # A provenance/format oracle, not a semantic judge of documentation quality.
        search_results = [r for r in results if r['tool_name'] == 'web_search']
        search_results += [c['result'] for c in nested
                           if c['name'] == 'web_search' and c.get('result') is not None]
        observed_urls = {url for result in search_results for url in source_urls(result)}
        try:
            answer = json.loads(final)
            if not isinstance(answer, dict) or set(answer) != {'python', 'rust'}:
                raise ValueError('expected python and rust keys')
            for key, host in [('python', 'docs.python.org'), ('rust', 'doc.rust-lang.org')]:
                urls = answer[key]
                if not isinstance(urls, list) or not 1 <= len(urls) <= 2:
                    raise ValueError('expected one or two URLs')
                if not all(isinstance(url, str) for url in urls) or len(set(urls)) != len(urls):
                    raise ValueError('expected distinct URL strings')
                for url in urls:
                    if urlparse(url).hostname != host or url not in observed_urls:
                        raise ValueError('URL is not an observed official source')
            search_calls = sum(r['tool_name'] == 'web_search' for r in results)
            search_calls += sum(c['name'] == 'web_search' for c in nested)
            if search_calls < 2:
                raise ValueError('expected searches for both topics')
        except (ValueError, TypeError, KeyError):
            failures.append('search format/source provenance oracle failed')
    if case == 'computed_edits':
        total = sum((i + 3) * (107 + 19 * i) for i in range(12))
        if final is None or '12' not in final or str(total) not in final.replace(',', ''):
            failures.append('computed summary count/sum missing')
    return {
        'passed': not failures, 'failures': failures, **metrics,
        'interrupted_calls': sum(c['status'] != 'done' for c in nested),
        'model_tool_output_chars': sum(len(r['content']) for r in results),
        'final': final,
    }


def trial(engine, out, variant, case, repeat, timeout, require_ptc):
    name = f'{case}-{repeat}-{variant}'
    workspace = out / 'workspaces' / name
    workspace.mkdir(parents=True)
    task, expected = fixture(case, workspace)
    if require_ptc:
        task += '\nUse mbtx with ptc: true and the bundled tools client for the requested edits or searches.'
    (workspace / '.eval-task.txt').write_text(task)
    command = engine_command(engine, workspace, name, out / f'{variant}.md', task, MAX_STEPS)
    env = trial_env(workspace)
    started = time.monotonic()
    exit_code = bounded(command, ROOT, env, out / f'{name}.log', timeout)
    result = {'name': name, 'variant': variant, 'case': case, 'repeat': repeat,
              'seconds': round(time.monotonic() - started, 2), 'exit_code': exit_code}
    try:
        result.update(analyze(case, workspace, expected, exit_code, require_ptc, session_name=name))
    except (OSError, ValueError, KeyError) as error:
        result.update(passed=False, failures=[str(error)])
    result['usage'] = usage(out / f'{name}.log')
    (out / f'{name}.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)
    return result


def usage(log_path):
    totals = None
    for line in log_path.read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get('event') == 'usage':
            if totals is None:
                totals = {}
            for key, value in event['usage'].items():
                totals[key] = totals.get(key, 0) + value
    return totals


def reanalyze(out):
    results = []
    manifest = json.loads((out / 'manifest.json').read_text())
    for path in sorted(out.glob('*-*-*.json')):
        result = json.loads(path.read_text())
        if 'name' not in result:
            continue
        workspace = out / 'workspaces' / result['name']
        # Compute expectations in a separate temporary fixture, never reset a trial.
        with tempfile.TemporaryDirectory() as directory:
            _, expected = fixture(result['case'], Path(directory))
        result.update(analyze(result['case'], workspace, expected, result['exit_code'],
                              manifest.get('require_ptc', False), session_name=result['name']))
        result['usage'] = usage(out / f"{result['name']}.log")
        path.write_text(json.dumps(result, indent=2) + '\n')
        results.append(result)
    (out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')


PTC_HEADING = '### Programmatic tool calls\n'


def prompt_variants(base, prompt_ab):
    if not prompt_ab:
        return {variant: base for variant in ('baseline', 'candidate')}
    if PTC_HEADING not in base:
        raise ValueError('the base prompt has no "### Programmatic tool calls" section; '
                         'pass --base-prompt with the historical prompt that had one')
    start = base.index(PTC_HEADING)
    end = base.index('## Tool Protocol', start)
    return {variant: base[:start] + (HERE / f'{variant}.md').read_text().rstrip()
            + '\n\n' + base[end:] for variant in ('baseline', 'candidate')}


def generated_prompt(path):
    """Decode the generated literal, including its expanded references tree."""
    generated = path.read_text()
    return '\n'.join(line.removeprefix('    #|') for line in generated.splitlines()
                     if line.startswith('    #|'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path)
    parser.add_argument('--baseline-engine', type=Path)
    parser.add_argument('--prompt-ab', action='store_true', help='Reproduce the historical prompt-only comparison')
    parser.add_argument('--base-prompt', type=Path,
                        help='Base system prompt as plain text (default: decode prompt/generated_default_prompt.mbt '
                             'from this checkout); --prompt-ab needs one with a PTC section')
    parser.add_argument('--analyze-only', action='store_true')
    parser.add_argument('--require-ptc', action='store_true')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--concurrency', type=int, default=3)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--cases', nargs='+', choices=CASES, default=CASES)
    args = parser.parse_args()
    if args.analyze_only:
        reanalyze(args.out.resolve())
        return
    if args.engine is None:
        parser.error('--engine is required for live trials')
    if args.prompt_ab == (args.baseline_engine is not None):
        parser.error('choose --baseline-engine for capability A/B, or --prompt-ab for historical prompt A/B')
    if args.baseline_engine is not None and args.require_ptc:
        parser.error('capability A/B must leave tool choice free; do not require PTC from the baseline')
    if not os.environ.get('DEEPSEEK'):
        parser.error('export DEEPSEEK before running this live evaluation')
    if min(args.runs, args.concurrency, args.timeout) <= 0:
        parser.error('runs, concurrency, and timeout must be positive')
    base = (args.base_prompt.read_text() if args.base_prompt
            else generated_prompt(ROOT / 'prompt/generated_default_prompt.mbt'))
    try:
        variants = prompt_variants(base, args.prompt_ab)
    except ValueError as error:
        parser.error(str(error))
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    hashes = {}
    for variant, prompt in variants.items():
        (out / f'{variant}.md').write_text(prompt)
        hashes[variant] = hashlib.sha256(prompt.encode()).hexdigest()
    engine = args.engine.resolve()
    engines = {'candidate': engine, 'baseline': args.baseline_engine.resolve()
               if args.baseline_engine is not None else engine}
    manifest = {'model': MODEL,
                'experiment': 'prompt' if args.prompt_ab else 'capability',
                'runs': args.runs, 'max_steps': MAX_STEPS,
                'concurrency': args.concurrency, 'timeout': args.timeout,
                'require_ptc': args.require_ptc,
                'cases': args.cases, 'prompt_sha256': hashes,
                'engine_sha256': engine_hashes(engines),
                'commit': head_commit()}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    # Interleave paired variants and alternate which launches first per repeat.
    jobs = [(variant, case, repeat) for repeat in range(1, args.runs + 1)
            for case in args.cases
            for variant in (('baseline', 'candidate') if repeat % 2 else ('candidate', 'baseline'))]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = [pool.submit(trial, engines[job[0]], out, *job, args.timeout, args.require_ptc) for job in jobs]
        results = [future.result() for future in futures]
    (out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
