#!/usr/bin/env python3
"""Generate unsplit MoonBit tests from the maintainer-only ZIP corpus."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATION_DIR = ROOT / "generation_priv_test"
EXPECTED_INDEX = GENERATION_DIR / "fixtures" / "expected" / "index.json"


def main() -> int:
  if not EXPECTED_INDEX.exists():
    raise SystemExit(
      "Missing generation_priv_test/fixtures/expected/index.json; "
      "run parse_zipinfo.py first."
    )
  expected_index = json.loads(EXPECTED_INDEX.read_text(encoding="utf-8"))
  entries = expected_index.get("entries", [])
  valid_entries: list[dict] = []
  invalid_entries: list[dict] = []
  for item in entries:
    expected_path = ROOT / item["expected"]
    expected = json.loads(expected_path.read_text(encoding="utf-8"))
    if expected.get("invalid", False):
      invalid_entries.append(item)
    else:
      valid_entries.append(item)

  helper_block = [
    "///|",
    "async fn load_expected_json(path : String) -> Json raise {",
    "  let data = @fs.read_file(path)",
    "  @json.parse(data.text())",
    "}",
    "",
    "///|",
    "async fn parse_seekable_fixture(path : String) -> ZipReport raise {",
    "  let file = @fs.open(path, mode=@fs.Mode::ReadOnly)",
    "  defer file.close()",
    "  // The fixture split is a test-harness detail. The API receives the stable",
    "  // archive name recorded in the generated oracle.",
    '  let archive_name = path.replace(old="_pub_test", new="").replace(old="_priv_test", new="")',
    "  parse_file(file, name=archive_name)",
    "}",
    "",
    "///|",
    "async fn parse_stream_fixture(path : String) -> ZipReport raise {",
    "  // Keep seekable and streaming reports independent of the fixture split.",
    '  let archive_name = path.replace(old="_pub_test", new="").replace(old="_priv_test", new="")',
    "  @async.with_task_group(fn(group) {",
    "    let (reader, writer) = @io.pipe()",
    "    defer reader.close()",
    "    group.spawn_bg(fn() {",
    "      defer writer.close()",
    "      let file = @fs.open(path, mode=@fs.Mode::ReadOnly)",
    "      defer file.close()",
    "      // A parser may finish after the ZIP records it needs. Closing the reader",
    "      // then is normal and must not turn the producer task into a test failure.",
    "      writer.write_reader(file) catch {",
    "        @io.PipeClosed => ()",
    "        error => raise error",
    "      }",
    "    })",
    "    parse_stream(reader, name=archive_name)",
    "  })",
    "}",
    "",
  ]

  def emit_tests(path: Path, label: str, items: list[dict], include_helpers: bool) -> None:
    lines: list[str] = []
    if include_helpers:
      lines.extend(helper_block)
    for idx, item in enumerate(items):
      fixture = item["fixture"]
      expected = item["expected"]
      test_name = f"zip {label} {idx:04d} {Path(fixture).name}"
      lines.append("///|")
      lines.append(f"async test {json.dumps(test_name)} {{")
      lines.append(f"  let expected = load_expected_json({json.dumps(expected)})")
      lines.append(f"  let report_seek = parse_seekable_fixture({json.dumps(fixture)})")
      lines.append("  assert_eq(report_seek.to_json(), expected)")
      lines.append(f"  let report_stream = parse_stream_fixture({json.dumps(fixture)})")
      lines.append("  assert_eq(report_stream.to_json(), expected)")
      lines.append("}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {path} with {len(items)} tests.")

  # These are staging outputs. The checked-in benchmark deliberately splits the
  # resulting corpus into public and private files with stable global indices.
  emit_tests(GENERATION_DIR / "zip_valid_generated.mbt", "valid", valid_entries, True)
  emit_tests(
    GENERATION_DIR / "zip_invalid_generated.mbt",
    "invalid",
    invalid_entries,
    False,
  )
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
