"""Verify a completed TOML Read A/B run and emit a compact, portable JSON report.

Uses the frozen scorer's verdicts without changing or filtering them. Reconciles
recorded usage with CLI events, source hashes, Git roots and paired fixtures.
"""

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess

IGNORED = {'.git', '_build', '.mooncakes', '.openseek', 'node_modules'}
USAGE_KEYS = ['prompt_tokens', 'completion_tokens', 'prompt_cache_hit_tokens', 'prompt_cache_miss_tokens']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_digest(root):
    return {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob('*'))
            if p.is_file() and not any(part in IGNORED for part in p.relative_to(root).parts)}


def complete_sum(values):
    return sum(values) if all(v is not None for v in values) else None


def model_graph_usage(events, parent_usage, parent_steps):
    started = {e['id']: e for e in events if e.get('event') == 'subrun_started'}
    finished = {}
    for event in events:
        if event.get('event') == 'subrun_finished':
            previous = finished.get(event['id'])
            assert previous is None or previous == event, 'Conflicting subrun summaries'
            finished[event['id']] = event
    missing = sorted(set(started) - set(finished))
    usage = {}
    for key in USAGE_KEYS:
        values = [parent_usage.get(key)] + [e.get(key) for e in finished.values()]
        usage[key] = complete_sum(values) if not missing else None
    steps = complete_sum([parent_steps] + [e.get('steps') for e in finished.values()]) if not missing else None
    subruns = [{k: e[k] for k in ['id', 'status', 'steps', 'prompt_tokens', 'completion_tokens'] if k in e}
               | {'kind': started.get(e['id'], {}).get('kind')} for e in finished.values()]
    return {'usage': usage, 'steps': steps, 'subruns': subruns, 'unfinished_subruns': missing}


def aggregate(rows):
    usage = {key: complete_sum([r['total_model_usage'].get(key) for r in rows]) for key in USAGE_KEYS}
    medians = {key: statistics.median([r['total_model_usage'][key] for r in rows])
               if all(r['total_model_usage'].get(key) is not None for r in rows) else None for key in USAGE_KEYS}
    return {'runs': len(rows), 'passed': sum(r['passed'] for r in rows),
            'finished': sum(r['finished'] for r in rows),
            'artifact_accepted': sum(r['validation']['passed'] for r in rows),
            'delivery_passed': sum(r['finished'] and r['returncode'] == 0 and r['validation']['passed'] for r in rows),
            'usage': usage,
            'usage_medians': medians, 'parent_steps': sum(r['steps'] for r in rows),
            'steps': complete_sum([r['total_model_steps'] for r in rows]),
            'subruns': sum(len(r['subruns']) for r in rows),
            'tool_calls': sum(r['tool_calls_total'] for r in rows),
            'tool_errors': sum(r['tool_error_count'] for r in rows),
            'native_read_calls': sum(r['tool_calls'].get('read', 0) for r in rows),
            'named_read_calls': sum(r['named_read_calls'] for r in rows),
            'acceptance': {group: {'passed': sum(r['acceptance'][group]['passed'] for r in rows),
                                   'expected': sum(r['acceptance'][group]['expected'] for r in rows)}
                           for group in ['valid', 'invalid', 'usage', 'determinism']},
            'elapsed_median_s': statistics.median(r['elapsed_s'] for r in rows),
            'parent_retries': sum(r['retries'] for r in rows),
            'parent_decode_errors': sum(r['decode_errors'] for r in rows),
            'timeouts': sum(r['timed_out'] for r in rows),
            'delegated_calls': sum(len(r['delegated_calls']) for r in rows)}


def percentage(a, b):
    return 100 * (b - a) / a if a is not None and b is not None and a != 0 else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=lambda p: Path(p).resolve())
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    root = args.run
    plan = json.loads((root / 'plan.json').read_text())
    manifest = json.loads((root / 'manifest.json').read_text())
    preflight = json.loads((root / 'preflight.json').read_text())
    audit_path = root / 'source-audit.json'
    audits = json.loads(audit_path.read_text()) if audit_path.is_file() else {}
    cleanup_path = root / 'cleanup-events.jsonl'
    cleanup_events = [json.loads(line) for line in cleanup_path.read_text().splitlines()] if cleanup_path.is_file() else []
    transport_path = root / 'transport-audit.json'
    transport_audit = json.loads(transport_path.read_text()) if transport_path.is_file() else None
    library_path = root / 'library-probe.json'
    library_probe = json.loads(library_path.read_text()) if library_path.is_file() else None
    library_rows = {r['id']: r for r in library_probe['trials']} if library_probe is not None else {}
    if library_probe is not None:
        assert library_probe['post_hoc'] and not library_probe['frozen_cli_scores_changed']
        assert set(library_rows) == {t['id'] for t in plan['trials']}
    if 'transport' in manifest:
        assert digest(root / 'deepseek_eval_relay.py') == manifest['transport']['relay_sha256']
    for name, expected in plan['evaluator_sha256'].items():
        assert digest(root / name) == expected, name
    for arm, label in [('baseline', 'a'), ('candidate', 'b')]:
        assert digest(root / 'bin' / label) == plan[arm + '_sha256']
        assert source_digest(root / ('share-' + label)) == plan[arm + '_share_sha256']
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
    rows = []
    for trial in plan['trials']:
        path = root / trial['id']
        result = json.loads((path / 'result.json').read_text())
        assert all(result[k] == v for k, v in trial.items())
        assert (path / 'prompt.txt').read_text() == plan['prompt']
        assert source_digest(path / 'workspace') == result['source_sha256']
        actual = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'],
                                         cwd=path / 'workspace', env=env, text=True).strip()
        assert Path(actual).resolve() == (path / 'workspace').resolve()
        events = [json.loads(line) for line in (path / 'events.jsonl').read_text().splitlines()
                  if line.startswith('{')]
        usage = Counter()
        for event in events:
            if event.get('event') == 'usage':
                usage.update({k: v for k, v in event['usage'].items() if type(v) is int})
        assert dict(usage) == result['usage'], trial['id']
        assert sum(e.get('event') == 'usage' for e in events) == result['usage_events']
        assert sum(e.get('event') == 'agent_step' for e in events) == result['steps']
        calls = json.loads((path / 'calls.json').read_text())
        assert len(calls) == result['tool_calls_total']
        assert dict(Counter(c['name'] for c in calls)) == result['tool_calls']
        probes = json.loads((path / 'probes.json').read_text())
        assert sum(p['passed'] for p in probes) == result['validation']['probes_passed']
        selectors = {
            'valid': (lambda p: p['valid'] and p['name'] != 'deterministic-output', preflight['valid_documents'] * 2),
            'invalid': (lambda p: not p['valid'] and p['mode'] != 'usage', preflight['invalid_documents'] * 2),
            'usage': (lambda p: p['mode'] == 'usage', 3),
            'determinism': (lambda p: p['name'] == 'deterministic-output', 1),
        }
        acceptance = {name: {'passed': sum(p['passed'] for p in probes if select(p)),
                              'expected': expected} for name, (select, expected) in selectors.items()}
        row = {key: result[key] for key in [
            'id', 'repeat', 'arm', 'passed', 'finished', 'returncode', 'timed_out',
            'elapsed_s', 'usage', 'usage_events', 'first_prompt_tokens', 'steps', 'model_stderr',
            'tool_calls', 'tool_calls_total', 'named_read_calls', 'pure_read_batch_windows_ms',
            'decode_errors', 'retries', 'event_counts', 'delegated_calls', 'terminal_errors',
            'fixture_sha256', 'source_sha256', 'validation', 'answer',
        ]}
        graph = model_graph_usage(events, result['usage'], result['steps'])
        row['total_model_usage'] = graph['usage']
        row['total_model_steps'] = graph['steps']
        row['subruns'] = graph['subruns']
        row['unfinished_subruns'] = graph['unfinished_subruns']
        row['acceptance'] = acceptance
        all_errors = []
        for session in (path / 'sessions').rglob('openseek_session-*.jsonl'):
            for line in session.read_text().splitlines():
                item = json.loads(line).get('item', {})
                payload = item.get('payload', {})
                if item.get('kind') == 'tool_result' and payload.get('is_error'):
                    all_errors.append(payload['tool_name'])
        row['parent_tool_error_count'] = len(result['tool_errors'])
        row['tool_error_count'] = len(all_errors)
        row['tool_error_tools'] = dict(Counter(all_errors))
        row['git_commit_count'] = int(subprocess.check_output(
            ['git', 'rev-list', '--count', 'HEAD'], cwd=path / 'workspace', env=env, text=True))
        audit = audits.get(trial['id'])
        if audit is not None:
            assert audit['source_sha256'] == result['source_sha256'], 'Source audit is stale'
            row['source_audit'] = {k: v for k, v in audit.items() if k != 'source_sha256'}
        else:
            row['source_audit'] = None
        probe = library_rows.get(trial['id'])
        if probe is not None:
            assert probe['source_sha256'] == result['source_sha256'], 'Library probe is stale'
            row['posthoc_library_probe'] = {k: v for k, v in probe.items() if k not in {'source_sha256', 'id', 'arm'}}
        else:
            row['posthoc_library_probe'] = None
        rows.append(row)
    pairs = []
    for repeat in sorted({r['repeat'] for r in rows}):
        group = {r['arm']: r for r in rows if r['repeat'] == repeat}
        assert len(group) == 2 and group['baseline']['fixture_sha256'] == group['candidate']['fixture_sha256']
        a, b = group['baseline'], group['candidate']
        pairs.append({'repeat': repeat, 'baseline_passed': a['passed'], 'candidate_passed': b['passed'],
                      'input_change_pct': percentage(a['total_model_usage'].get('prompt_tokens'), b['total_model_usage'].get('prompt_tokens')),
                      'output_change_pct': percentage(a['total_model_usage'].get('completion_tokens'), b['total_model_usage'].get('completion_tokens'))})
    summary = {arm: aggregate([r for r in rows if r['arm'] == arm]) for arm in ['baseline', 'candidate']}
    output = {'model': plan['model'], 'thinking': plan['thinking'], 'max_steps': plan['max_steps'],
              'api_url': plan.get('api_url'), 'web_search_available': plan.get('web_search_available'),
              'timeout_seconds': plan['timeout_seconds'], 'manifest': manifest,
              'reporter_sha256': digest(Path(__file__)),
              'environment_cleanup': cleanup_events, 'transport_audit': transport_audit,
              'posthoc_library_probe': {k: v for k, v in library_probe.items() if k != 'trials'} if library_probe is not None else None,
              'evaluator_sha256': plan['evaluator_sha256'], 'preflight': preflight,
              'primary_metric': plan['primary_metric'], 'policy': plan['policy'],
              'summary': summary, 'pairs': pairs, 'trials': rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
