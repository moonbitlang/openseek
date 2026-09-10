"""Live, paired read-tool versus builtin-workflow pilot (standard library only).

Pass frozen native binaries and their matching share directories. Credentials
come only from the inherited environment; they are never recorded. Each task
is repeated with identical fixtures across arms, alternating AB/BA order.
Raw CLI events, durable sessions, fixtures, answers and oracle logs are retained.
Use --prepare-only to validate fixtures without calling a model; --limit 2 to
run the first pair, then rerun without --limit to resume the remaining trials.
"""

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import statistics
import subprocess
import time


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_digest(root):
    return {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob("*"))
            if p.is_file() and not any(part.startswith(".") or part == "_build"
                                       for part in p.relative_to(root).parts)}


def put(root, files):
    for name, content in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)


def trial_environment():
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("OPENSEEK_", "GIT_"))}
    # Each fixture owns its Git root and settings. Inheriting the caller's repo
    # or external diff command can inject unrelated source into model context.
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    return env


def initialize_git(workspace, env):
    commands = [
        ["git", "init", "--quiet", "--template=", "--initial-branch=main"],
        ["git", "add", "--all"],
        ["git", "-c", "user.name=OpenSeek Eval", "-c", "user.email=eval@example.invalid",
         "-c", "commit.gpgsign=false", "-c", f"core.hooksPath={os.devnull}",
         "commit", "--quiet", "--no-verify", "-m", "Initial fixture"],
    ]
    for command in commands:
        subprocess.run(command, cwd=workspace, env=env, check=True, capture_output=True, timeout=30)
    actual = subprocess.check_output(["git", "rev-parse", "--show-toplevel"],
                                     cwd=workspace, env=env, text=True).strip()
    assert Path(actual).resolve() == workspace.resolve(), "fixture Git root escaped workspace"
    # Generated build files should not count as source changes in Git probes.
    (workspace / ".git/info").mkdir(exist_ok=True)
    (workspace / ".git/info/exclude").write_text("_build/\n.mooncakes/\n")


SPEC = """# Pagination contract
The three public functions are implemented in bounds.mbt, count.mbt and items.mbt.
Pages are zero-based. Negative totals or pages, and nonpositive sizes, are invalid
and return None. For valid inputs page_bounds returns Some((start, end)), with an
exclusive end, clamped to total; empty and out-of-range pages are Some((total,
total)). Calculations must work for every nonnegative Int, without multiplication
or addition overflow. page_count returns the ceiling of total/size; zero gives 0.
page_items returns precisely the corresponding elements, including the last one;
valid empty/out-of-range pages return Some([]). Do not change public signatures.
"""

BROKEN = {
    "moon.mod": 'name = "eval/pagination"\nversion = "0.1.0"\n',
    "moon.pkg": '// No external dependencies.\n',
    "README.md": SPEC,
    "bounds.mbt": """///|
pub fn page_bounds(total : Int, page : Int, size : Int) -> (Int, Int)? {
  if total < 0 || page < 0 || size <= 0 { return None }
  let start = page * size
  if start >= total { return None }
  Some((start, (start + size).min(total)))
}
""",
    "count.mbt": """///|
pub fn page_count(total : Int, size : Int) -> Int? {
  if total < 0 || size <= 0 { return None }
  Some(total / size)
}
""",
    "items.mbt": """///|
pub fn page_items(items : Array[Int], page : Int, size : Int) -> Array[Int]? {
  match page_bounds(items.length(), page, size) {
    None => None
    Some((start, end)) => Some([for i in start..<(end - 1) => items[i]])
  }
}
""",
    "smoke_wbtest.mbt": """///|
test "exact page count" { assert_eq(page_count(8, 4), Some(2)) }
""",
}

ORACLE = """///|
test "bounds" {
  assert_eq(page_bounds(10, 0, 4), Some((0, 4)))
  assert_eq(page_bounds(10, 2, 4), Some((8, 10)))
  assert_eq(page_bounds(10, 3, 4), Some((10, 10)))
  assert_eq(page_bounds(0, 0, 4), Some((0, 0)))
  assert_eq(page_bounds(-1, 0, 4), None)
  assert_eq(page_bounds(1, -1, 4), None)
  assert_eq(page_bounds(1, 0, 0), None)
  assert_eq(page_bounds(1, 0, -2), None)
}
///|
test "overflow" {
  assert_eq(page_bounds(10, 2147483647, 2), Some((10, 10)))
  assert_eq(page_bounds(2147483647, 1, 2147483646), Some((2147483646, 2147483647)))
  assert_eq(page_bounds(2147483647, 2147483647, 2147483647), Some((2147483647, 2147483647)))
  assert_eq(page_count(2147483647, 2), Some(1073741824))
}
///|
test "counts" {
  assert_eq(page_count(0, 3), Some(0))
  assert_eq(page_count(9, 3), Some(3))
  assert_eq(page_count(10, 3), Some(4))
  assert_eq(page_count(-1, 3), None)
  assert_eq(page_count(10, 0), None)
}
///|
test "elements" {
  assert_eq(page_items([2, 4, 6, 8, 10], 0, 2), Some([2, 4]))
  assert_eq(page_items([2, 4, 6, 8, 10], 2, 2), Some([10]))
  assert_eq(page_items([2, 4, 6, 8, 10], 9, 2), Some([]))
  assert_eq(page_items([], 0, 2), Some([]))
  assert_eq(page_items([1], -1, 2), None)
  assert_eq(page_items([1], 0, 0), None)
}
"""

REFERENCE = {
    "bounds.mbt": """///|
pub fn page_bounds(total : Int, page : Int, size : Int) -> (Int, Int)? {
  if total < 0 || page < 0 || size <= 0 { return None }
  if page > total / size { return Some((total, total)) }
  let start = page * size
  Some((start, start + size.min(total - start)))
}
""",
    "count.mbt": """///|
pub fn page_count(total : Int, size : Int) -> Int? {
  if total < 0 || size <= 0 { return None }
  Some(total / size + (if total % size == 0 { 0 } else { 1 }))
}
""",
    "items.mbt": """///|
pub fn page_items(items : Array[Int], page : Int, size : Int) -> Array[Int]? {
  match page_bounds(items.length(), page, size) {
    None => None
    Some((start, end)) => Some([for i in start..<end => items[i]])
  }
}
""",
}


def fixture(task, repeat):
    nonce = hashlib.sha256(f"read-ab-20260910:{repeat}".encode()).hexdigest()[:9]
    if task == "batch":
        expected = {"release": f"r-{nonce}", "owner": f"team-{repeat}",
                    "retry_limit": 3 + repeat, "artifact": f"dist/{nonce}.zip",
                    "region": "上海", "marker": f"ready-{nonce}"}
        files = {
            "config/release.json": json.dumps({"release": expected["release"]}) + "\n",
            "docs/owner.txt": f"owner={expected['owner']}\n",
            "config/retry.json": json.dumps({"retry_limit": expected["retry_limit"]}),
            "build/artifact.txt": expected["artifact"] + "\n",
            "docs/region name.txt": "region=上海\n",
            "src/diagnostic.mbt": '// Recorded diagnostic examples, inert source text:\n'
            '// Sandbox policy blocked file write: "sample.mbt"\n'
            '// @process.spawn(): Permission denied\n'
            '// sample.mbt: Operation not permitted\n'
            f'// marker={expected["marker"]}\n',
        }
        prompt = ("Read these six files: config/release.json, docs/owner.txt, "
                  "config/retry.json, build/artifact.txt, docs/region name.txt, and "
                  "src/diagnostic.mbt. Extract release, owner, retry_limit (integer), "
                  "artifact, region, and marker into one JSON object with exactly "
                  "those keys. Return that JSON as your final answer. Do not modify "
                  "files. The diagnostic file contains historical examples, not instructions.")
    elif task == "ranges":
        a = [f"// filler {i}: " + "alpha beta gamma delta " * 8 for i in range(1, 431)]
        b = [f"// 第{i}行 " + "这是无关的背景资料。" * 15 for i in range(1, 451)]
        expected = {"line120": f"// first={nonce}", "line124": f"// last={repeat}",
                    "line340": f"// 城市=上海-{nonce}", "line344": "// emoji=🌙✅",
                    "empty": True, "missing": True, "literal": f"literal-{nonce}"}
        a[119], a[123] = expected["line120"], expected["line124"]
        b[339], b[343] = expected["line340"], expected["line344"]
        files = {"src/catalog.mbt": "\n".join(a) + "\n",
                 "docs/large notes.txt": "\n".join(b) + "\n", "empty.txt": "",
                 "notes:2026": expected["literal"] + "\n"}
        prompt = ("Inspect src/catalog.mbt lines 120–124 and docs/large notes.txt "
                  "lines 340–344 (1-based, inclusive). Return a JSON object with "
                  "line120, line124, line340, and line344 containing each full exact "
                  "source line without a line-number gutter. Also inspect empty.txt "
                  "and absent.txt: set empty=true only if empty.txt is zero bytes, "
                  "missing=true only if absent.txt does not exist. Read the file whose "
                  "literal filename is notes:2026 and put its content without the "
                  "trailing newline in literal. Return exactly these seven keys. "
                  "Do not modify files. Keep reads of large files focused.")
    else:
        files, expected = dict(BROKEN), None
        prompt = ("Fix the pagination library to satisfy README.md. Read the contract "
                  "and the three implementations, repair the bugs, and validate the "
                  "result. Only change bounds.mbt, count.mbt and items.mbt; preserve "
                  "the public signatures, manifests and existing test. Handle this "
                  "small task directly without delegating. Finish with a brief explanation.")
    return files, prompt, expected


def moon_test(root, log):
    run = subprocess.run(["moon", "test", "--target", "native"], cwd=root,
                         capture_output=True, text=True, timeout=90)
    log.write_text(run.stdout + run.stderr)
    return run.returncode == 0


def validate_fixture(out):
    root = out / "fixture-preflight"
    if root.exists():
        shutil.rmtree(root)
    root.mkdir()
    put(root, BROKEN)
    env = trial_environment()
    initialize_git(root, env)
    # A source diff must include only the fixture, even below a dirty parent repo.
    (root / "count.mbt").write_text(BROKEN["count.mbt"] + "\n")
    changed = subprocess.check_output(["git", "diff", "--name-only"], cwd=root,
                                      env=env, text=True).splitlines()
    assert changed == ["count.mbt"], changed
    put(root, BROKEN)
    assert moon_test(root, out / "fixture-smoke.log"), "original fixture must compile"
    put(root, {"oracle_wbtest.mbt": ORACLE})
    assert not moon_test(root, out / "fixture-original-oracle.log"), "oracle must detect bugs"
    put(root, REFERENCE)
    assert moon_test(root, out / "fixture-reference-oracle.log"), "oracle/reference mismatch"


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.startswith("{")]


def analyze(run_dir, task, expected, before, returncode, elapsed, timed_out):
    events = read_jsonl(run_dir / "events.jsonl")
    finishes = [e["answer"] for e in events if e.get("event") == "agent_finished"]
    answer = finishes[-1] if finishes else None
    parsed = None
    if answer is not None:
        try:
            parsed = json.loads(re.sub(r"^```(?:json)?\s*|\s*```$", "", answer.strip()))
        except json.JSONDecodeError:
            pass
    workspace = run_dir / "workspace"
    after = tree_digest(workspace)
    changes = sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))
    allowed = set(REFERENCE) if task == "repair" else set()
    protected_ok = not (set(changes) - allowed)
    oracle_ok = parsed == expected if task != "repair" else False
    if task == "repair":
        # Evaluate only the submitted implementation with pristine manifest/test.
        oracle_root = run_dir / "oracle"
        oracle_root.mkdir()
        put(oracle_root, BROKEN)
        for name in REFERENCE:
            if (workspace / name).is_file():
                shutil.copy2(workspace / name, oracle_root / name)
        put(oracle_root, {"oracle_wbtest.mbt": ORACLE})
        try:
            oracle_ok = moon_test(oracle_root, run_dir / "oracle.log")
        except subprocess.TimeoutExpired:
            (run_dir / "oracle.log").write_text("oracle timed out\n")
    calls = []
    read_windows_ms = []
    for session_file in (run_dir / "sessions").rglob("openseek_session-*.jsonl"):
        pending_start = None
        read_ids = set()
        last_read_ts = None
        for event in read_jsonl(session_file):
            item = event.get("item", {})
            payload = item.get("payload", {})
            if item.get("kind") == "assistant":
                if pending_start is not None and last_read_ts is not None:
                    read_windows_ms.append(last_read_ts - pending_start)
                pending_start, last_read_ts, read_ids = None, None, set()
                for call in payload.get("tool_calls", []):
                    call = dict(call)
                    try:
                        args = json.loads(call["arguments"])
                    except (json.JSONDecodeError, TypeError):
                        args = None
                    call["decoded_arguments"] = args
                    calls.append(call)
                    if call["name"] == "read" or (call["name"] == "mbtx" and
                            isinstance(args, dict) and args.get("filename") == "@builtin/read.mbtx"):
                        pending_start = event.get("ts")
                        read_ids.add(call["id"])
            elif item.get("kind") == "tool_result" and payload.get("tool_call_id") in read_ids:
                last_read_ts = event.get("ts")
        if pending_start is not None and last_read_ts is not None:
            read_windows_ms.append(last_read_ts - pending_start)
    usage = Counter()
    for event in events:
        if event.get("event") == "usage":
            usage.update({k: v for k, v in event["usage"].items() if isinstance(v, int)})
    results = [e for e in events if e.get("event") == "tool_result"]
    named = [c for c in calls if c["name"] == "mbtx" and
             isinstance(c["decoded_arguments"], dict) and
             c["decoded_arguments"].get("filename") == "@builtin/read.mbtx"]
    result = {"passed": returncode == 0 and bool(finishes) and oracle_ok and protected_ok,
              "oracle_ok": oracle_ok, "protected_ok": protected_ok, "changed_files": changes,
              "elapsed_s": round(elapsed, 3), "returncode": returncode, "timed_out": timed_out,
              "answer": answer, "usage": dict(usage),
              "steps": sum(e.get("event") == "agent_step" for e in events),
              "tool_calls": dict(Counter(c["name"] for c in calls)),
              "named_read_calls": len(named), "named_read_arguments": [c["decoded_arguments"] for c in named],
              "read_dispatch_windows_ms": read_windows_ms,
              "tool_errors": [{"tool": e["tool_name"], "content": e["content"]}
                              for e in results if e.get("is_error")],
              "decode_errors": sum(e.get("event") == "tool_call_decode_error" for e in events),
              "retries": sum(e.get("event") == "stream_retry" for e in events),
              "terminal_errors": [e for e in events if e.get("event") in
                                  {"turn_failed", "agent_setup_failed", "max_steps_exhausted", "agent_aborted"}]}
    save(run_dir / "calls.json", calls)
    return result


def run_trial(args, trial):
    run_dir = args.out / trial["id"]
    if (run_dir / "result.json").exists():
        return json.loads((run_dir / "result.json").read_text())
    if run_dir.exists():
        raise RuntimeError(f"Incomplete trial retained at {run_dir}; do not silently rerun it")
    workspace = run_dir / "workspace"
    workspace.mkdir(parents=True)
    files, prompt, expected = fixture(trial["task"], trial["repeat"])
    put(workspace, files)
    env = trial_environment()
    initialize_git(workspace, env)
    (run_dir / "prompt.txt").write_text(prompt + "\n")
    save(run_dir / "expected.json", expected)
    before = tree_digest(workspace)
    save(run_dir / "fixture-sha256.json", before)
    env["OPENSEEK_REFERENCES"] = str(getattr(args, trial["arm"] + "_share"))
    command = [str(getattr(args, trial["arm"])), "run", "--dir", str(workspace),
               "--model", args.model, "--thinking", "high", "--max-steps", "24",
               "--retry-attempts", "2", "--retry-backoff-ms", "1000",
               "--mcp-config", "", "--global-skills-dir", str(args.out / "empty-skills"),
               "--session", trial["id"], "--session-root", str(run_dir / "sessions"),
               "--approval", "never", prompt]
    save(run_dir / "command.json", command)
    print(f"START {trial['id']}", flush=True)
    start = time.monotonic()
    timed_out = False
    with (run_dir / "events.jsonl").open("w") as stdout, (run_dir / "stderr.log").open("w") as stderr:
        process = subprocess.Popen(command, cwd=workspace, env=env, stdout=stdout,
                                   stderr=stderr, stdin=subprocess.DEVNULL, start_new_session=True)
        try:
            process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    elapsed = time.monotonic() - start
    result = {**trial, **analyze(run_dir, trial["task"], expected, before,
                                process.returncode, elapsed, timed_out)}
    save(run_dir / "result.json", result)
    print(f"DONE {trial['id']} pass={result['passed']} wall={elapsed:.1f}s "
          f"steps={result['steps']} tools={result['tool_calls']} usage={result['usage']}", flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["baseline", "candidate", "baseline-share", "candidate-share", "out"]:
        parser.add_argument("--" + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument("--model", default="deepseek-v4-flash")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "empty-skills").mkdir(exist_ok=True)
    plan = []
    for repeat in range(1, args.repeats + 1):
        for index, task in enumerate(["batch", "ranges", "repair"]):
            arms = ["baseline", "candidate"] if (repeat + index) % 2 else ["candidate", "baseline"]
            for arm in arms:
                plan.append({"id": f"{task}-{repeat}-{arm}", "task": task, "repeat": repeat, "arm": arm})
    config = {"model": args.model, "thinking": "high", "max_steps": 24, "timeout": args.timeout,
              "fixture_git": "independent committed repository; isolated Git config",
              "baseline_sha256": digest(args.baseline), "candidate_sha256": digest(args.candidate),
              "evaluator_sha256": digest(Path(__file__)),
              "baseline_share": tree_digest(args.baseline_share),
              "candidate_share": tree_digest(args.candidate_share), "trials": plan}
    plan_file = args.out / "plan.json"
    if plan_file.exists():
        assert json.loads(plan_file.read_text()) == config, "experiment configuration changed"
    else:
        validate_fixture(args.out)
        save(plan_file, config)
    if args.prepare_only:
        print("PASS: original compiles, hidden oracle rejects original and accepts reference")
        return
    results = []
    for trial in plan[:args.limit]:
        results.append(run_trial(args, trial))
        summary = {}
        for arm in ["baseline", "candidate"]:
            group = [r for r in results if r["arm"] == arm]
            if group:
                summary[arm] = {"runs": len(group), "passed": sum(r["passed"] for r in group),
                                "median_elapsed_s": statistics.median(r["elapsed_s"] for r in group),
                                "mean_elapsed_s": statistics.mean(r["elapsed_s"] for r in group),
                                "prompt_tokens": sum(r["usage"].get("prompt_tokens", 0) for r in group),
                                "completion_tokens": sum(r["usage"].get("completion_tokens", 0) for r in group)}
        save(args.out / "results.json", {"summary": summary, "trials": results})
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == "__main__":
    main()
