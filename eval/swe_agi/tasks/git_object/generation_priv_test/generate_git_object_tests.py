#!/usr/bin/env python3
import json
from pathlib import Path
from typing import List

ROOT = Path(__file__).resolve().parents[1]
INDEX_PATH = ROOT / "fixtures" / "index.json"
OUTPUT_VALID = ROOT / "git_object_valid_test.mbt"
OUTPUT_INVALID = ROOT / "git_object_invalid_test.mbt"


def main() -> int:
    if not INDEX_PATH.exists():
        raise SystemExit(
            "Missing fixtures/index.json; run "
            "generation_priv_test/generate_git_object_fixtures.py first."
        )

    index = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
    entries = index.get("entries", [])
    invalid_entries = index.get("invalid_entries", [])

    helper_block = [
        "///|",
        "async fn read_file_bytes(path : String) -> Bytes {",
        "  let file = @fs.open(path, mode=@fs.Mode::ReadOnly)",
        "  defer file.close()",
        "  let size = file.size()",
        "  file.read_exactly(size.to_int())",
        "}",
        "",
        "///|",
        "async fn load_expected_json(path : String) -> Json {",
        "  let bytes = read_file_bytes(path)",
        "  @json.parse(@encoding/utf8.decode(bytes))",
        "}",
        "",
        "///|",
        "async fn load_object_bytes(path : String) -> Bytes {",
        "  read_file_bytes(path)",
        "}",
        "",
    ]

    valid_lines: List[str] = []
    valid_lines.extend(helper_block)

    for entry in entries:
        source = entry.get("source")
        test_name = f"git object {entry['id']:04d} {entry['kind']} {entry['oid']}"
        if source:
            test_name = f"git object {entry['id']:04d} {source} {entry['kind']} {entry['oid']}"
        if not entry.get("sha1_ok", True):
            test_name += " sha1-mismatch"
        valid_lines.append("///|")
        valid_lines.append(f"async test {json.dumps(test_name)} {{")
        valid_lines.append(f"  let expected = load_expected_json({json.dumps(entry['expected'])})")
        valid_lines.append(f"  let payload = load_object_bytes({json.dumps(entry['fixture'])})")
        valid_lines.append(
            f"  let obj = parse_object_bytes(payload, expected_oid={json.dumps(entry['expected_oid'])})"
        )
        valid_lines.append("  json_inspect(obj.to_json(), content=expected)")
        valid_lines.append("}")

    invalid_lines: List[str] = []
    invalid_lines.extend(
        [
            "///|",
            "fn error_to_json(err : GitObjectError) -> Json {",
            "  match err {",
            "    GitObjectError::InvalidZlib(_) => { \"type\": \"InvalidZlib\" }",
            "    GitObjectError::InvalidHeader(_) => { \"type\": \"InvalidHeader\" }",
            "    GitObjectError::InvalidSize(_) => { \"type\": \"InvalidSize\" }",
            "    GitObjectError::InvalidSha1(_) => { \"type\": \"InvalidSha1\" }",
            "  }",
            "}",
            "",
            "///|",
            "fn result_to_json(res : Result[GitObject, GitObjectError]) -> Json {",
            "  match res {",
            "    Ok(obj) => { \"ok\": obj.to_json() }",
            "    Err(err) => { \"error\": error_to_json(err) }",
            "  }",
            "}",
            "",
        ]
    )

    for entry in invalid_entries:
        test_name = f"git object invalid {entry['id']:04d} {entry['name']}"
        invalid_lines.append("///|")
        invalid_lines.append(f"async test {json.dumps(test_name)} {{")
        invalid_lines.append(f"  let expected = load_expected_json({json.dumps(entry['expected'])})")
        invalid_lines.append(f"  let payload = load_object_bytes({json.dumps(entry['fixture'])})")
        invalid_lines.append("  let result : Result[GitObject, GitObjectError] = try? parse_object_bytes(payload)")
        invalid_lines.append("  json_inspect(result_to_json(result), content=expected)")
        invalid_lines.append("}")

    OUTPUT_VALID.write_text("\n".join(valid_lines) + "\n", encoding="utf-8")
    OUTPUT_INVALID.write_text("\n".join(invalid_lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT_VALID} with {len(entries)} tests.")
    print(f"Wrote {OUTPUT_INVALID} with {len(invalid_entries)} tests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
