#!/usr/bin/env python3
import argparse
from pathlib import Path
import re
import subprocess
import sys
from typing import List, Optional, Tuple


LUA_RUNNER = r"""
local chunk = io.read("*a")
local f, err = load(chunk, "chunk", "t", _ENV)
if not f then
  io.stderr:write("syntax:", err, "\n")
  os.exit(2)
end
local ok, runtime_err = pcall(f)
if not ok then
  io.stderr:write("runtime:", runtime_err, "\n")
  os.exit(3)
end
"""


def extract_cases(path: Path) -> List[Tuple[str, str, str, Path]]:
  cases: List[Tuple[str, str, str, Path]] = []
  current_test: Optional[str] = None
  current_expect: Optional[str] = None
  blocks: List[str] = []
  collecting = False
  buf: List[str] = []

  with path.open("r", encoding="utf-8") as handle:
    for line in handle:
      stripped = line.lstrip()

      if collecting:
        if stripped.startswith("#|"):
          buf.append(stripped.split("#|", 1)[1].rstrip("\n"))
          continue
        code = "\n".join(buf) + "\n"
        blocks.append(code)
        collecting = False
        buf = []

      match = re.match(r'^\s*test\s+"([^"]+)"', line)
      if match:
        current_test = match.group(1)
        current_expect = None
        blocks = []

      if "exec_ok(" in line:
        current_expect = "ok"
      if "exec_syntax_error(" in line:
        current_expect = "syntax"
      if "exec_runtime_error(" in line:
        current_expect = "runtime"

      if stripped.startswith("#|"):
        collecting = True
        buf = [stripped.split("#|", 1)[1].rstrip("\n")]

      if current_test and line.strip() == "}":
        if collecting:
          code = "\n".join(buf) + "\n"
          blocks.append(code)
          collecting = False
          buf = []
        if current_expect is None:
          raise ValueError(f"Missing expectation in {path}")
        if not blocks:
          raise ValueError(f"Missing Lua source in {path}")
        for index, code in enumerate(blocks, start=1):
          name = current_test if len(blocks) == 1 else f"{current_test}#{index}"
          cases.append((name, current_expect, code, path))
        current_test = None
        current_expect = None
        blocks = []

  return cases


def run_case(lua_cmd: str, code: str) -> Tuple[int, str, str]:
  result = subprocess.run(
    [lua_cmd, "-e", LUA_RUNNER],
    input=code,
    text=True,
    capture_output=True,
  )
  return result.returncode, result.stdout, result.stderr


def main() -> int:
  parser = argparse.ArgumentParser(
    description="Verify Lua snippets in MoonBit tests using system lua.",
  )
  parser.add_argument(
    "--lua",
    default="lua",
    help="Lua executable to use (default: lua).",
  )
  parser.add_argument(
    "--suite",
    default=Path(__file__).resolve().parents[1],
    type=Path,
    help="Path to the lua suite directory.",
  )
  parser.add_argument(
    "--verbose",
    action="store_true",
    help="Print each test case name as it runs.",
  )
  args = parser.parse_args()

  suite_dir = args.suite.resolve()
  test_files = sorted(suite_dir.glob("lua_*_test.mbt"))
  if not test_files:
    print(f"No test files found under {suite_dir}", file=sys.stderr)
    return 1

  cases: List[Tuple[str, str, str, Path]] = []
  for path in test_files:
    cases.extend(extract_cases(path))

  expected_rc = {"ok": 0, "syntax": 2, "runtime": 3}
  failures = []

  for name, expect, code, path in cases:
    if args.verbose:
      print(f"run {name}")
    rc, out, err = run_case(args.lua, code)
    if rc != expected_rc[expect]:
      failures.append((name, expect, rc, path, out, err))

  if failures:
    print(f"{len(failures)} failures:", file=sys.stderr)
    for name, expect, rc, path, out, err in failures:
      print(
        f"- {name} ({path}): expected {expect}, got rc={rc}",
        file=sys.stderr,
      )
      if out:
        print("  stdout:", out.strip(), file=sys.stderr)
      if err:
        print("  stderr:", err.strip(), file=sys.stderr)
    return 1

  print(f"Verified {len(cases)} cases with {args.lua}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
