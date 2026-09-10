#!/usr/bin/env python3
"""Exercise the bundled hosted scripts without credentials or a model."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    with tempfile.TemporaryDirectory(prefix="openseek-workflows-") as temporary:
        temp = Path(temporary)
        repo = temp / "repository"
        repo.mkdir()
        (repo / "justfile").write_text("check:\n    moon check\n")
        (repo / "README.md").write_text("orientation fixture\n" + "x" * 5000 + "excluded tail")
        (repo / "sample").mkdir()
        (repo / "sample/moon.pkg").write_text("")
        (repo / "sample/real_implementation.mbt").write_text("")
        (repo / "sample/pkg.generated.mbti").write_text("package \"sample\"\n")
        (repo / "cmd/main").mkdir(parents=True)
        (repo / "cmd/main/moon.pkg").write_text("")
        (repo / "cmd/main/main.mbt").write_text("fn main {}\n")
        (temp / "outside.md").write_text("outside\n")
        (repo / "escape.md").symlink_to(temp / "outside.md")
        child = temp / "child.py"
        child.write_text('''import json, os, sys
request = json.loads(sys.stdin.readline())
assert request["kind"] == "explore", request
assert request["max_steps"] == int(os.environ["EXPECTED_STEPS"]), request
if os.environ["EXPECTED_STEPS"] == "12":
    query = request["input"]["query"]
    assert "1 | orientation fixture" in query, query
    assert "[Excerpt truncated; read the file for the remainder.]" in query, query
    assert "excluded tail" not in query, query
    assert "sample/:" in query and "real_implementation.mbt" in query, query
    assert "pkg.generated.mbti" in query and "moon.pkg" in query, query
    assert "cmd/main/:" in query and "main.mbt" in query, query
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps(request) + "\\n")
if os.environ.get("FAIL_CHILD") == sys.argv[1]:
    sys.exit(1)
mode = os.environ.get("CITATION_MODE")
citation = {"file": "cmd/main/main.mbt", "line": 1}
if mode == "bad-line": citation["line"] = 2
if mode == "fractional-line": citation["line"] = 1.5
if mode == "missing-file": citation["file"] = "absent.mbt"
if mode == "directory": citation["file"] = "sample"
if mode == "escape": citation["file"] = "escape.md"
if mode == "traversal": citation["file"] = "../outside.md"
citations = [] if mode == "no-citations" else [citation]
print(json.dumps({"subrun_report": {"answer": "" if os.environ.get("EMPTY_CHILD") == sys.argv[1] else "offline evidence " + sys.argv[1], "citations": citations}}), flush=True)
''')
        for name in ("change-review", "repo-map"):
            source = temp / (name + ".mbtx")
            shutil.copyfile(ROOT / "share/workflow" / source.name, source)
            # Script builds share an output name, so build and exercise each
            # artifact before building the next script.
            build = subprocess.run(
                ["moon", "run", "--build-only", "--deny-warn", "--target", "wasm", str(source)],
                cwd=ROOT, text=True, capture_output=True,
            )
            assert build.returncode == 0, build.stdout + build.stderr
            artifact = json.loads(build.stdout)["artifacts_path"][0]
            expected_calls = 2 if name == "repo-map" else 3
            modes = ["success", "partial", "missing", "capacity"]
            if name == "repo-map":
                modes.extend(["empty", "bad-line", "fractional-line", "missing-file", "directory", "escape", "traversal", "no-citations", "no-recipes"])
            for mode in modes:
                if mode == "no-recipes":
                    (repo / "justfile").unlink()
                calls = temp / (name + "-" + mode + ".jsonl")
                env = dict(os.environ, CALLS=str(calls), EXPECTED_STEPS="12" if name == "repo-map" else "16")
                env.pop("EMPTY_CHILD", None)
                env["CITATION_MODE"] = mode
                env.pop("WORKFLOW_HOST", None)
                env.pop("FAIL_CHILD", None)
                if mode != "missing":
                    env["WORKFLOW_HOST"] = json.dumps({
                        "v": 1, "exe": sys.executable,
                        "child_args": [str(child), "{child}"],
                        "child_id": "test-{n}", "ids": [1, expected_calls - 1 if mode == "capacity" else expected_calls],
                        "cwd": str(repo), "deadline_ms": 10000,
                    })
                if mode == "partial":
                    env["FAIL_CHILD"] = "test-2"
                if mode == "empty":
                    env["EMPTY_CHILD"] = "test-2"
                result = subprocess.run(["moonrun", artifact], cwd=repo, env=env,
                                        text=True, capture_output=True, timeout=60)
                output = result.stdout + result.stderr
                launched = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
                assert (result.returncode == 0) == (mode in ("success", "no-recipes")), output
                assert len(launched) == (0 if mode in ("missing", "capacity") else expected_calls), output
                if mode not in ("missing", "capacity"):
                    assert len({call["id"] for call in launched}) == expected_calls, launched
                    assert f"scouts={expected_calls}" in output, output
                    if name == "repo-map":
                        assert "Validation recipes (not executed)" in output, output
                        if mode == "no-recipes":
                            assert "No root justfile found" in output, output
                        else:
                            assert "check:\n    moon check" in output, output
                    assert output.count("offline evidence") == (expected_calls - 1 if mode in ("partial", "empty") else expected_calls), output
                if mode in ("partial", "empty"):
                    assert "INCOMPLETE:" in output, output
                elif mode == "missing":
                    assert "subrun=true" in output, output
                elif mode == "capacity":
                    assert "no scouts were launched" in output, output
                if mode in ("bad-line", "fractional-line", "missing-file", "directory", "escape", "traversal"):
                    assert "UNVERIFIED:" in output, output
                if mode == "success" and name == "repo-map":
                    assert output.count("CHECKED:") == 2, output
                print(f"{name}: {mode} passed")


if __name__ == "__main__":
    main()
