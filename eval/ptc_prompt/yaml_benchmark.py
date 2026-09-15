#!/usr/bin/env python3
"""Free-choice PTC A/B on a specified YAML subset; independent withheld tests."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time
import run

MODULE = 'name = "ptc_eval/yaml_parser"\nversion = "0.1.0"\npreferred_target = "native"\n'
SPEC = '''Implement a YAML parser in MoonBit in this workspace. Public API:
  pub fn parse(source : String) -> Json raise
The root package is ptc_eval/yaml_parser. Replace the provided stub. No external
parser, subprocess delegation, network dependency, or non-core module dependency.
Keep implementation in root-package .mbt files. You may split those files,
import MoonBit core packages, and add your own tests.
Keep moon.mod and visible_test.mbt unchanged. Run tests before finishing.

Implement this explicit, JSON-compatible YAML subset:
- One document, optionally bracketed by --- and ... on their own lines; blank
  lines and # comments; LF or CRLF; an empty document is null. Reject extra documents.
- Plain scalars: null/Null/NULL/~ and empty values -> null; true/false in any case
  -> booleans; signed decimal integers and finite decimals/exponents -> numbers;
  other text -> strings (on/off/yes/no remain strings). Quoted scalars stay strings.
- Single quotes with doubled quote escapes; double quotes with JSON-style escapes
  including Unicode \\uXXXX. Reject unterminated quotes and invalid escapes.
- Indented block mappings with string keys; block sequences; nested collections;
  sequences of mappings and mappings with sequence values. Reject tabs in indentation,
  inconsistent dedentation, duplicate mapping keys, and a mapping entry without a colon.
- Flow sequences [a, b] and mappings {key: value}, nested or empty, with quoted
  strings, comments outside quotes, and an optional trailing comma. Reject missing
  closing delimiters or a missing mapping value separator.
- # begins a comment in a plain scalar only at its start or after whitespace.
  A colon inside a plain scalar is not a mapping separator unless followed by
  whitespace or end-of-line. Preserve URLs and quoted colons/hash characters.
- Literal block scalar | and strip-chomp |-; folded scalar > and >-: consecutive
  nonblank content lines fold to spaces; a blank content line creates a newline.
  Strip common indentation. Default chomping yields one final newline; '-' none.
- Reject anchors (&name), aliases (*name), and explicit tags (!tag) rather than
  silently misinterpreting them. These features, complex keys, merge keys,
  directives, multiline quoted scalars, and non-finite numbers are outside scope.

The supplied examples are smoke tests. Your final code will be scored against
independent withheld cases for all requirements above, including malformed input.
Implement the parser rather than special-casing examples. Use the host editing
tools to modify source, directly or from mbtx when available. Choose tools freely.
'''

# Expected JSON values are authored against the task contract, not the candidate.
VISIBLE = [
    ('empty', '', None),
    ('mapping', 'name: moon\ncount: 3\n', {'name': 'moon', 'count': 3}),
    ('sequence', '- red\n- blue\n', ['red', 'blue']),
    ('nested', 'outer:\n  inner: true\n', {'outer': {'inner': True}}),
    ('quoted', "a: 'it''s fine'\nb: \"line\\nnext\"\n", {'a': "it's fine", 'b': 'line\nnext'}),
    ('flow', '{a: [1, false, null], b: {}}', {'a': [1, False, None], 'b': {}}),
]
CASES = [
    ('comments_document', '# prelude\n---\na: 1 # note\n...\n# end\n', {'a': 1}),
    ('crlf', 'a:\r\n  - x\r\n  - y\r\n', {'a': ['x', 'y']}),
    ('null_forms', '[null, Null, NULL, ~]', [None] * 4),
    ('boolean_strings', '[TRUE, False, true, fAlSe, on, off, yes, no]', [True, False, True, False, 'on', 'off', 'yes', 'no']),
    ('numbers', '[0, -12, +7, 1.25, -0.5, 2e3, 3E-2]', [0, -12, 7, 1.25, -0.5, 2000, .03]),
    ('quoted_types', '["true", \'42\', "null"]', ['true', '42', 'null']),
    ('empty_values', 'a:\nb: ~\nc: null\n', {'a': None, 'b': None, 'c': None}),
    ('plain_hash', 'a: hello#world\nb: hello # gone\nc: "# kept"\n', {'a': 'hello#world', 'b': 'hello', 'c': '# kept'}),
    ('url', 'url: https://example.test/a#frag\ntime: 12:34\n', {'url': 'https://example.test/a#frag', 'time': '12:34'}),
    ('quoted_keys', '"a:b": "x:y#z"\n\' spaced key \': yes\n', {'a:b': 'x:y#z', ' spaced key ': 'yes'}),
    ('unicode_escape', 'value: "\\u4e2d\\u6587\\t!"\n', {'value': '中文\t!'}),
    ('quote_escapes', 'value: "a\\\"b\\\\c\\/d"\n', {'value': 'a"b\\c/d'}),
    ('nested_blocks', 'root:\n  items:\n    - one\n    - two\n  enabled: false\nend: done\n', {'root': {'items': ['one', 'two'], 'enabled': False}, 'end': 'done'}),
    ('sequence_maps', '- name: alpha\n  value: 1\n- name: beta\n  value: 2\n', [{'name': 'alpha', 'value': 1}, {'name': 'beta', 'value': 2}]),
    ('sequence_nested_map', '- name: a\n  child:\n    x: 2\n- name: b\n', [{'name': 'a', 'child': {'x': 2}}, {'name': 'b'}]),
    ('nested_sequences', '-\n  - a\n  - b\n-\n  - c\n', [['a', 'b'], ['c']]),
    ('flow_nested', '{a: [1, {b: [2, 3]}], c: []}', {'a': [1, {'b': [2, 3]}], 'c': []}),
    ('flow_trailing', '[one, {two: 2,},]', ['one', {'two': 2}]),
    ('flow_quoted_punctuation', '["a,b", \'[x]\', {"k:k": "v}v"}]', ['a,b', '[x]', {'k:k': 'v}v'}]),
    ('flow_comments', '[1, # comment\n 2, 3]', [1, 2, 3]),
    ('literal', 'text: |\n  alpha\n  beta\nnext: 1\n', {'text': 'alpha\nbeta\n', 'next': 1}),
    ('literal_strip', 'text: |-\n  alpha\n  beta\n', {'text': 'alpha\nbeta'}),
    ('folded', 'text: >\n  alpha\n  beta\n', {'text': 'alpha beta\n'}),
    ('folded_paragraph', 'text: >-\n  alpha\n\n  beta\n  gamma\n', {'text': 'alpha\nbeta gamma'}),
    ('literal_hash', 'text: |\n  # keep\n  a: b\n', {'text': '# keep\na: b\n'}),
    ('empty_flow', '{a: {}, b: []}', {'a': {}, 'b': []}),
    ('scalar_document', '---\nhello world\n...\n', 'hello world'),
    ('indent_four', 'a:\n    b:\n        c: 9\nd: 8\n', {'a': {'b': {'c': 9}}, 'd': 8}),
    ('plain_spaces', 'text: a  b c\n', {'text': 'a  b c'}),
    ('comments_between', 'a:\n  # note\n  b: 1\n\n# outer\nc: 2\n', {'a': {'b': 1}, 'c': 2}),
]
INVALID = [
    ('unclosed_double', 'a: "oops'), ('unclosed_single', "a: 'oops"),
    ('invalid_escape', 'a: "\\q"'), ('short_unicode', 'a: "\\u12"'),
    ('unclosed_sequence', '[1, 2'), ('unclosed_mapping', '{a: 1'),
    ('missing_flow_colon', '{a 1}'), ('duplicate_block_key', 'a: 1\na: 2\n'),
    ('duplicate_flow_key', '{a: 1, a: 2}'), ('tab_indent', 'a:\n\tb: 1\n'),
    ('bad_dedent', 'a:\n    b: 1\n  c: 2\n'),
    ('missing_block_colon', 'a: 1\nbroken line\n'),
    ('multiple_documents', '---\na: 1\n---\nb: 2\n'),
    ('anchor', 'a: &thing 1\n'), ('alias', 'a: *thing\n'), ('tag', 'a: !custom value\n'),
]


def literal(value):
    return json.dumps(value, ensure_ascii=False)


def tests(cases, invalid=(), prefix='oracle'):
    blocks = []
    for name, source, expected in cases:
        blocks.append(f'///|\ntest "{prefix}:{name}" {{\n  assert_eq(@yaml_parser.parse({literal(source)}), ({literal(expected)} : Json))\n}}\n')
    for name, source in invalid:
        blocks.append(f'///|\ntest "{prefix}:{name}" {{\n  let rejected = try {{ ignore(@yaml_parser.parse({literal(source)})); false }} catch {{ _ => true }}\n  assert_true(rejected)\n}}\n')
    return '\n'.join(blocks)


def fixture(workspace):
    workspace.mkdir(parents=True)
    (workspace / 'moon.mod').write_text(MODULE)
    (workspace / 'moon.pkg').write_text('')
    (workspace / 'parse.mbt').write_text('///|\npub fn parse(source : String) -> Json raise {\n  ignore(source)\n  fail("Parser not implemented")\n}\n')
    (workspace / 'visible_test.mbt').write_text(tests(VISIBLE, prefix='visible'))
    (workspace / 'TASK.md').write_text(SPEC)


def bounded(command, cwd, env, log, timeout):
    with log.open('w') as output:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            return None


IMPORT_BLOCK = re.compile(r'\bimport\s*\{([^}]*)\}', re.S)
CORE_IMPORT = re.compile(r'"(moonbitlang/(?:core|x)/[A-Za-z0-9_/]+)"(?:\s+@([a-z_][a-z0-9_]*))?')
SECRET_MARKERS = ('DEEPSEEK', 'OPENAI', 'ANTHROPIC', 'KEY', 'TOKEN', 'SECRET', 'PASSWORD')


def trusted_manifest(candidate):
    """Rebuild moon.pkg from the candidate's core imports only.

    A package manifest can carry build rules that run shell commands before
    `moon test`; none of that reaches the grading project. Only quoted
    moonbitlang/core or moonbitlang/x imports (optionally aliased) inside
    `import { ... }` blocks survive, however they are laid out; comments are
    stripped first so a commented-out entry is not resurrected.
    """
    uncommented = '\n'.join(line.split('//', 1)[0] for line in candidate.splitlines())
    imports = []
    for block in IMPORT_BLOCK.findall(uncommented):
        for path, alias in CORE_IMPORT.findall(block):
            entry = f'"{path}"' + (f' @{alias}' if alias else '')
            if entry not in imports:
                imports.append(entry)
    if not imports:
        return ''
    return 'import {\n' + ''.join(f'  {entry},\n' for entry in imports) + '}\n'


def preserved(path, expected):
    """Byte-exact fixture check; a deleted protected file is a failure, not a crash."""
    try:
        return path.read_bytes() == expected.encode('utf-8')
    except FileNotFoundError:
        return False


def grading_env():
    """Grading runs without any credential in its environment."""
    return {key: value for key, value in os.environ.items()
            if not any(marker in key.upper() for marker in SECRET_MARKERS)}


def score(workspace, grading, log):
    grading.mkdir()
    # Only root-package implementation and its core imports enter the trusted
    # grading project. Candidate tests, manifests and build scripts do not.
    for path in workspace.glob('*.mbt'):
        if not path.name.endswith(('_test.mbt', '_wbtest.mbt')):
            shutil.copyfile(path, grading / path.name)
    (grading / 'moon.pkg').write_text(trusted_manifest((workspace / 'moon.pkg').read_text()))
    (grading / 'moon.mod').write_text(MODULE)
    (grading / 'oracle_test.mbt').write_text(tests(CASES, INVALID))
    code = bounded(['moon', 'test', '--target', 'native', '--filter', 'oracle:*'], grading, grading_env(), log, 120)
    text = log.read_text()
    matches = re.findall(r'Total tests: (\d+), passed: (\d+), failed: (\d+)\.', text)
    passed = int(matches[-1][1]) if matches else 0
    failures = re.findall(r'\("oracle:([^"]+)"\) failed:', text)
    return {'oracle_passed': passed, 'oracle_total': len(CASES) + len(INVALID),
            'oracle_exit_code': code, 'oracle_failures': failures,
            'valid_passed': len(CASES) - sum(n in {c[0] for c in CASES} for n in failures) if matches else 0,
            'invalid_passed': len(INVALID) - sum(n in {c[0] for c in INVALID} for n in failures) if matches else 0,
            'compile_or_harness_error': not bool(matches),
            # Byte-exact: a candidate that only rewrote line endings changed protected bytes.
            'preserved_fixture': preserved(workspace / 'moon.mod', MODULE) and
                preserved(workspace / 'visible_test.mbt', tests(VISIBLE, prefix='visible'))}


def trial(engine, out, variant, repeat, timeout, max_steps=128):
    name = f'yaml-{repeat}-{variant}'
    workspace = out / 'workspaces' / name
    fixture(workspace)
    env = os.environ.copy()
    env['OPENSEEK_GLOBAL_SKILLS_DIR'] = str(workspace / '.no-global-skills')
    env['OPENSEEK_REFERENCES'] = str(run.ROOT / 'share')
    started = time.monotonic()
    log = out / f'{name}.log'
    code = bounded([str(engine), 'run', '--model', 'deepseek-v4-flash', '--max-steps', str(max_steps),
                    '--dir', str(workspace), '--session', name,
                    '--system-prompt-file', str(out / f'{variant}.md'),
                    'Read TASK.md and implement the requested YAML parser completely.'],
                   run.ROOT, env, log, timeout)
    result = {'name': name, 'variant': variant, 'repeat': repeat,
              'seconds': round(time.monotonic() - started, 2), 'exit_code': code}
    (out / f'{name}-execution.json').write_text(json.dumps(result, indent=2) + '\n')
    result = analyze_trial(out, variant, repeat, result)
    print(json.dumps(result), flush=True)
    return result


def analyze_trial(out, variant, repeat, execution=None):
    name = f'yaml-{repeat}-{variant}'
    workspace = out / 'workspaces' / name
    log = out / f'{name}.log'
    if execution is None:
        checkpoint = out / f'{name}-execution.json'
        if checkpoint.exists():
            execution = json.loads(checkpoint.read_text())
        elif (out / f'{name}.json').exists():
            previous = json.loads((out / f'{name}.json').read_text())
            execution = {k: v for k, v in previous.items() if k in
                         ('name', 'variant', 'repeat', 'exit_code', 'seconds',
                          'exit_code_unrecorded', 'seconds_source')}
        else:
            # Recovery for the original reader's child-session ambiguity. Keep
            # OS exit status unavailable and label reconstructed timing.
            stat = log.stat()
            execution = {'name': name, 'variant': variant, 'repeat': repeat,
                         'exit_code': None, 'exit_code_unrecorded': True,
                         'seconds': round(stat.st_mtime - stat.st_birthtime, 2) if hasattr(stat, 'st_birthtime') else None,
                         'seconds_source': 'log creation to last write; excludes silent waits' if hasattr(stat, 'st_birthtime') else 'unavailable without execution checkpoint'}
    result = dict(execution)
    items = run.session_items(workspace, session_name=name)
    assistants = [i['payload'] for i in items if i['kind'] == 'assistant']
    outputs = [i['payload'] for i in items if i['kind'] == 'tool_result']
    nested = [c for r in outputs for c in (r.get('data') or {}).get('ptc_calls', [])]
    terminals = [i['payload'] for i in items if i['kind'] == 'terminal']
    result.update(steps=len(assistants), outer_calls=sum(len(a.get('tool_calls', [])) for a in assistants),
                  nested_calls=len(nested), tool_errors=sum(r['is_error'] for r in outputs),
                  nested_errors=sum(c.get('result', {}).get('is_error', False) for c in nested),
                  final=terminals[-1] if terminals else None, usage=run.usage(log))
    child_sessions = list(workspace.rglob(f'openseek_session-{name}-sr-*.jsonl'))
    result['child_sessions'] = len(child_sessions)
    result['child_steps'] = sum(sum(json.loads(line).get('item', {}).get('kind') == 'assistant'
                                    for line in path.read_text().splitlines()) for path in child_sessions)
    result['usage_scope'] = 'parent only; child token usage unavailable' if child_sessions else 'parent (no children)'
    grading = out / f'{name}-grading'
    suffix = 1
    while grading.exists():
        suffix += 1
        grading = out / f'{name}-grading-{suffix}'
    result.update(score(workspace, grading, grading.with_suffix('.log')))
    result['passed'] = result['oracle_passed'] == result['oracle_total'] and result['preserved_fixture'] and result['oracle_exit_code'] == 0 and result.get('exit_code') == 0 and bool(terminals) and terminals[-1]['kind'] == 'finished'
    (out / f'{name}.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-engine', type=Path)
    parser.add_argument('--engine', type=Path)
    parser.add_argument('--analyze-only', action='store_true')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--runs', type=int, default=2)
    parser.add_argument('--concurrency', type=int, default=2)
    parser.add_argument('--timeout', type=int, default=1800)
    parser.add_argument('--max-steps', type=int, default=128)
    args = parser.parse_args()
    if args.analyze_only:
        out = args.out.resolve()
        manifest = json.loads((out / 'manifest.json').read_text())
        results = [analyze_trial(out, variant, repeat)
                   for repeat in range(1, manifest['runs'] + 1)
                   for variant in ('baseline', 'candidate')]
        (out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        return
    if args.engine is None or args.baseline_engine is None:
        parser.error('both engines are required for live trials')
    if not os.environ.get('DEEPSEEK'):
        parser.error('DEEPSEEK is required')
    if min(args.runs, args.concurrency, args.timeout, args.max_steps) <= 0:
        parser.error('runs, concurrency, timeout, and max-steps must be positive')
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    generated = (run.ROOT / 'prompt/generated_default_prompt.mbt').read_text()
    prompt = '\n'.join(line.removeprefix('    #|') for line in generated.splitlines() if line.startswith('    #|'))
    engines = {'baseline': args.baseline_engine.resolve(), 'candidate': args.engine.resolve()}
    for variant in engines:
        (out / f'{variant}.md').write_text(prompt)
    manifest = {'experiment': 'yaml-parser-capability', 'model': 'deepseek-v4-flash',
                'runs': args.runs, 'max_steps': args.max_steps, 'timeout': args.timeout, 'concurrency': args.concurrency,
                'visible_cases': len(VISIBLE), 'withheld_cases': len(CASES) + len(INVALID),
                'prompt_sha256': hashlib.sha256(prompt.encode()).hexdigest(),
                'spec_sha256': hashlib.sha256(SPEC.encode()).hexdigest(),
                'oracle_sha256': hashlib.sha256(tests(CASES, INVALID).encode()).hexdigest(),
                'engine_sha256': {k: hashlib.sha256(v.read_bytes()).hexdigest() for k, v in engines.items()},
                'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    jobs = [(variant, repeat) for repeat in range(1, args.runs + 1)
            for variant in (('baseline', 'candidate') if repeat % 2 else ('candidate', 'baseline'))]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = [pool.submit(trial, engines[v], out, v, r, args.timeout, args.max_steps) for v, r in jobs]
        results = [f.result() for f in futures]
    (out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
