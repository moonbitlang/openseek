#!/usr/bin/env python3
"""Run the real CI monitor against a local gh fixture; no network or credentials."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def check(state, *, status="COMPLETED", name="build"):
    return {"__typename": "CheckRun", "name": name, "status": status,
            "conclusion": state, "workflowName": "CI", "detailsUrl": "https://github.com/example/repo/actions/runs/123/job/456"}


def snapshot(checks, head="a" * 40):
    return {"number": 42, "url": "https://github.com/example/repo/pull/42",
            "headRefOid": head, "statusCheckRollup": checks}


def main():
    with tempfile.TemporaryDirectory(prefix="ci-watch-") as temporary:
        temp = Path(temporary)
        source = temp / "ci-watch.mbtx"
        shutil.copyfile(ROOT / "share/workflow/ci-watch.mbtx", source)
        build = subprocess.run(["moon", "run", "--build-only", "--deny-warn", "--target", "wasm", str(source)],
                               cwd=ROOT, text=True, capture_output=True)
        assert build.returncode == 0, build.stdout + build.stderr
        artifact = json.loads(build.stdout)["artifacts_path"][0]
        fake = temp / "gh"
        fake.write_text(f"#!{sys.executable}\n" + '''import json, os, pathlib, sys
root = pathlib.Path(os.environ["CI_FIXTURE"])
counter = root / "calls.jsonl"
args = sys.argv[1:]
assert args[:2] == ["pr", "view"], args
assert "--json" in args and "--repo" in args, args
calls = counter.read_text().splitlines() if counter.exists() else []
if calls:
    assert args[2] == "https://github.com/example/repo/pull/42", args
with counter.open("a") as f: f.write(json.dumps(args) + "\\n")
fixture = json.loads((root / "fixture.json").read_text())
entry = fixture[min(len(calls), len(fixture)-1)]
print(entry.get("raw", json.dumps(entry.get("snapshot"))))
print(entry.get("stderr", ""), file=sys.stderr)
sys.exit(entry.get("exit", 0))
''')
        fake.chmod(0o755)
        env = dict(os.environ, PATH=str(temp) + os.pathsep + os.environ["PATH"], CI_FIXTURE=str(temp))
        passed = snapshot([check("SUCCESS")])
        pending = snapshot([check("", status="IN_PROGRESS")])
        context = {"__typename": "StatusContext", "context": "external", "state": "SUCCESS", "targetUrl": None}
        cases = [
            ("success", [passed], True, "CI PASSED", False),
            ("current-branch", [passed], True, "CI PASSED", False),
            ("legacy-status", [snapshot([context])], True, "CI PASSED", False),
            ("mixed-skip", [snapshot([check("SUCCESS"), check("SKIPPED", name="optional")])], True, "skip=1", False),
            ("pending", [pending], False, "CI INCOMPLETE", False),
            ("no-checks", [snapshot([])], False, "NO CHECKS", False),
            ("only-skipped", [snapshot([check("NEUTRAL")])], False, "ONLY SKIPPED", False),
            ("unknown-state", [snapshot([check("NEW_STATE")])], False, "PENDING/UNKNOWN", False),
            ("missing-conclusion", [snapshot([check(None)])], False, "UNKNOWN", False),
            ("bad-check", [snapshot([{}])], False, "Unrecognized", False),
            ("null-rollup", [dict(passed, statusCheckRollup=None)], False, "Invalid CI snapshot", False),
            ("settles", [pending, passed, passed], True, "CI PASSED", True),
            ("late-registration", [snapshot([]), passed, passed], True, "CI PASSED", True),
            ("late-failure", [passed, snapshot([check("FAILURE")])], False, "CI FAILED", True),
            ("head-changed", [passed, snapshot([check("SUCCESS")], "b"*40)], False, "SUPERSEDED", True),
        ]
        for state in ("FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"):
            cases.append((state.lower(), [snapshot([check(state)])], False, "CI FAILED", False))
        cases.extend([
            ("api-error", [{"exit": 1, "snapshot": passed, "stderr": "authentication failed"}], False, "CI query failed", False),
            ("bad-json", [{"raw": "not json"}], False, "without a verified successful result", False),
            ("timeout", [pending], False, "without a verified successful result", True),
        ])
        for name, sequence, success, expected, watch in cases:
            fixture = [x if "exit" in x or "raw" in x else {"snapshot": x} for x in sequence]
            (temp / "fixture.json").write_text(json.dumps(fixture))
            calls = temp / "calls.jsonl"
            calls.unlink(missing_ok=True)
            args = ["moonrun", artifact, "--"]
            if name != "current-branch":
                args.append("42")
            args += ["--repo", "example/repo"]
            args += ["--interval-seconds", "1", "--timeout-seconds", "1" if name == "timeout" else "10"] if watch else ["--once"]
            result = subprocess.run(args, cwd=temp, env=env, capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            assert (result.returncode == 0) == success, (name, output)
            assert expected in output, (name, output)
            rows = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{"result"')]
            for row in rows:
                assert row["url"] is None or isinstance(row["url"], str), row
                assert row["workflow"] is None or isinstance(row["workflow"], str), row
                if row["result"] == "FAIL":
                    assert row["failure_logs_argv"] == ["gh", "run", "view", "123", "--repo", "github.com/example/repo", "--log-failed"], row
            count = len(calls.read_text().splitlines())
            if name in ("settles", "late-registration"):
                assert count == 3, (name, count)
            elif name == "head-changed":
                assert count == 2, count
            elif not watch:
                assert count == 1, count
            if name == "timeout":
                assert output.count("pass=0 skip=0 pending=1 fail=0") == 1, output
            print(f"ci-watch: {name} passed")
        for args in (["--timeout-seconds", "0"], ["--interval-seconds", "9999"], ["--repo"], ["--unknown"]):
            calls.unlink(missing_ok=True)
            result = subprocess.run(["moonrun", artifact, "--", *args], cwd=temp, env=env, capture_output=True)
            assert result.returncode != 0 and not calls.exists(), args
        print("ci-watch: invalid arguments rejected before gh")


if __name__ == "__main__":
    main()
