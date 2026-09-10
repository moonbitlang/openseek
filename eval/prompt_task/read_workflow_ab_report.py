"""Derive portable metrics from a completed read_workflow_ab.py run.

The original strict verdict is preserved. Content correctness is a separate,
post-hoc metric: read tasks may contain prose surrounding one exact JSON object;
repair tasks must pass the independent oracle. Neither metric silently retries
or drops failed trials. Output excludes full sessions and model reasoning.
"""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import statistics


def content_correct(result, expected):
    if result["returncode"] != 0 or result["answer"] is None:
        return False
    if result["task"] == "repair":
        return result["oracle_ok"]
    answer = result["answer"]
    candidates = [answer] + re.findall(r"```(?:json)?\s*(.*?)```", answer, re.S)
    for candidate in candidates:
        try:
            value, _ = json.JSONDecoder().raw_decode(candidate.lstrip())
            if value == expected:
                return True
        except json.JSONDecodeError:
            pass
    return False


def pure_read_windows(root):
    windows = []
    for path in (root / "sessions").rglob("openseek_session-*.jsonl"):
        pending = None
        for line in path.read_text().splitlines():
            event = json.loads(line)
            item = event.get("item", {})
            payload = item.get("payload", {})
            if item.get("kind") == "assistant":
                calls = payload.get("tool_calls", [])
                read_ids = set()
                for call in calls:
                    try:
                        args = json.loads(call["arguments"])
                    except (json.JSONDecodeError, TypeError):
                        args = None
                    if call["name"] == "read" or (call["name"] == "mbtx" and
                            isinstance(args, dict) and args.get("filename") == "@builtin/read.mbtx"):
                        read_ids.add(call["id"])
                pending = (event["ts"], read_ids) if read_ids and len(read_ids) == len(calls) else None
            elif item.get("kind") == "tool_result" and pending is not None:
                start, read_ids = pending
                read_ids.discard(payload["tool_call_id"])
                if not read_ids:
                    windows.append(event["ts"] - start)
                    pending = None
    return windows


def aggregate(rows):
    usage = Counter()
    tools = Counter()
    for row in rows:
        usage.update(row["usage"])
        tools.update(row["tool_calls"])
    windows = [ms for row in rows for ms in row["read_dispatch_windows_ms"]]
    pure_windows = [ms for row in rows for ms in row["pure_read_batch_windows_ms"]]
    return {
        "runs": len(rows), "strict_passes": sum(r["passed"] for r in rows),
        "content_correct": sum(r["content_correct"] for r in rows),
        "protected_files_preserved": sum(r["protected_ok"] for r in rows),
        "elapsed_median_s": statistics.median(r["elapsed_s"] for r in rows),
        "elapsed_mean_s": statistics.mean(r["elapsed_s"] for r in rows),
        "steps_total": sum(r["steps"] for r in rows),
        "tool_calls": dict(tools), "tool_calls_total": sum(tools.values()),
        "tool_errors": sum(len(r["tool_errors"]) for r in rows),
        "decode_errors": sum(r["decode_errors"] for r in rows),
        "retries": sum(r["retries"] for r in rows),
        "named_read_calls": sum(r["named_read_calls"] for r in rows),
        "named_read_runs": sum(r["named_read_calls"] > 0 for r in rows),
        "read_dispatch_windows_count": len(windows),
        "read_dispatch_window_median_ms": statistics.median(windows) if windows else None,
        "pure_read_batch_count": len(pure_windows),
        "pure_read_batch_median_ms": statistics.median(pure_windows) if pure_windows else None,
        "usage": dict(usage),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    plan = json.loads((args.input / "plan.json").read_text())
    rows = []
    for trial in plan["trials"]:
        root = args.input / trial["id"]
        result = json.loads((root / "result.json").read_text())
        expected = json.loads((root / "expected.json").read_text())
        result["content_correct"] = content_correct(result, expected)
        result["fixture_sha256"] = json.loads((root / "fixture-sha256.json").read_text())
        result["pure_read_batch_windows_ms"] = pure_read_windows(root)
        events = [json.loads(line) for line in (root / "events.jsonl").read_text().splitlines()
                  if line.startswith("{")]
        first_usage = next((e["usage"] for e in events if e.get("event") == "usage"), None)
        result["first_prompt_tokens"] = first_usage.get("prompt_tokens") if first_usage else None
        rows.append(result)
    for task in ["batch", "ranges", "repair"]:
        for repeat in sorted({r["repeat"] for r in rows}):
            pair = [r for r in rows if r["task"] == task and r["repeat"] == repeat]
            assert len(pair) == 2 and pair[0]["fixture_sha256"] == pair[1]["fixture_sha256"]
    summary = {arm: aggregate([r for r in rows if r["arm"] == arm])
               for arm in ["baseline", "candidate"]}
    by_task = {task: {arm: aggregate([r for r in rows if r["arm"] == arm and r["task"] == task])
                      for arm in ["baseline", "candidate"]}
               for task in ["batch", "ranges", "repair"]}
    result = {"model": plan["model"], "thinking": plan["thinking"],
              "fixture_git": plan.get("fixture_git"),
              "max_steps": plan["max_steps"], "timeout_seconds": plan["timeout"],
              "baseline_sha256": plan["baseline_sha256"],
              "candidate_sha256": plan["candidate_sha256"],
              "evaluator_sha256": plan["evaluator_sha256"],
              "summary": summary, "by_task": by_task, "trials": rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
