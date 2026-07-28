#!/usr/bin/env python3
"""Capture zipinfo output for the maintainer-only ZIP corpus."""

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES_DIR = ROOT / "generation_priv_test" / "fixtures"
SOURCES_DIR = FIXTURES_DIR / "sources"
MANIFEST_PATH = FIXTURES_DIR / "manifest.json"
RAW_DIR = FIXTURES_DIR / "zipinfo_raw"
INDEX_PATH = RAW_DIR / "index.json"

ZIPINFO_BIN = "/usr/bin/zipinfo"

ZIP_EXTS = {".zip", ".jar", ".ZIP", ".JAR"}


def discover_fixtures() -> list[Path]:
  if MANIFEST_PATH.exists():
    data = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    return [ROOT / entry["path"] for entry in data.get("entries", [])]
  fixtures = []
  for path in SOURCES_DIR.rglob("*"):
    if path.is_file() and path.suffix in ZIP_EXTS:
      fixtures.append(path)
  return fixtures


def main() -> int:
  RAW_DIR.mkdir(parents=True, exist_ok=True)
  fixtures = discover_fixtures()
  entries = []
  for fixture in fixtures:
    rel = fixture.relative_to(ROOT)
    raw_path = RAW_DIR / rel
    raw_path = raw_path.with_suffix(raw_path.suffix + ".txt")
    raw_path.parent.mkdir(parents=True, exist_ok=True)

    result = subprocess.run(
      [ZIPINFO_BIN, "-l", str(rel)],
      cwd=ROOT,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      text=True,
      encoding="utf-8",
      errors="replace",
    )
    output = result.stdout
    if result.stderr:
      output = output + ("\n" if output and not output.endswith("\n") else "") + result.stderr
    raw_path.write_text(output, encoding="utf-8")

    entries.append({
      "fixture": str(rel),
      "raw": str(raw_path.relative_to(ROOT)),
      "exit_code": result.returncode,
    })

  INDEX_PATH.write_text(json.dumps({"entries": entries}, indent=2), encoding="utf-8")
  print(f"Wrote zipinfo output for {len(entries)} fixtures.")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
