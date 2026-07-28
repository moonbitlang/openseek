#!/usr/bin/env python3.10
"""Generate MoonBit tests from yaml-test-suite/data.

This script scans the YAML Test Suite cases and produces MoonBit `test {}` blocks
similar to `yaml_generated_test.mbt`.

By default it generates tests for cases that have both `in.yaml` and `in.json`.
Cases with `error` can be optionally included as negative tests.

Usage:
  python generation_priv_test/generate_yaml_tests.py \
    --data-dir yaml-test-suite/data \
    --out yaml_generated_test.mbt

Then you can review and copy/merge into `yaml_generated_test.mbt`.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


CASE_ID_RE = re.compile(r"^[0-9A-Z]{4}$")


@dataclass(frozen=True)
class CasePaths:
    case_id: str
    case_dir: Path
    in_yaml: Path
    in_json: Path | None
    error: Path | None


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="strict")


def _normalize_newlines(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _decode_yaml_test_suite_special_chars(text: str) -> str:
    """Decode yaml-test-suite visual markers into real characters.

    See `yaml-test-suite/ReadMe.md` -> "Special Characters".

    Notes:
    - `␣` becomes a literal space.
    - Tab markers (various `—` + `»` forms) become a literal tab (`\t`).
    - `↵` is a trailing newline marker; we remove it (real newlines are already
      present as line separators).
    - `∎` indicates no final newline; we remove it and ensure the overall text
      has no trailing newline.
    - `←` becomes a carriage return (`\r`).
    - `⇔` becomes a BOM (`\ufeff`).
    """

    text = _normalize_newlines(text)

    # Common replacements that can appear anywhere.
    text = text.replace("␣", " ")
    text = text.replace("←", "\r")
    text = text.replace("⇔", "\ufeff")

    out_lines: list[str] = []
    lines = text.split("\n")

    no_final_newline = False
    for i, line in enumerate(lines):
        # Drop the synthetic trailing line produced by split if file ends with \n.
        if i == len(lines) - 1 and line == "":
            continue

        # Hard tab markers are shown as one of: » —» ——» ———»
        # Replace any run of em dashes followed by a single right guillemet.
        line = re.sub(r"—*»", "\t", line)

        # Remove explicit trailing newline marker.
        if line.endswith("↵"):
            line = line[:-1]

        # Detect 'no final newline' marker at end of the last logical line.
        if line.endswith("∎"):
            line = line[:-1]
            no_final_newline = True

        out_lines.append(line)

    decoded = "\n".join(out_lines)
    if not no_final_newline:
        decoded += "\n"
    return decoded


def _yaml_to_moon_multiline_string(yaml_text: str) -> str:
    """Render YAML as an exact MoonBit string literal.

    A `#|` multiline literal always contributes line separators, so it cannot
    preserve yaml-test-suite cases with a carriage return or no final newline.
    JSON string escaping is compatible with MoonBit and preserves both.
    """

    yaml_text = _decode_yaml_test_suite_special_chars(yaml_text)
    return "  let in_yaml = " + json.dumps(yaml_text, ensure_ascii=False)


def _indent(text: str, spaces: int) -> str:
    prefix = " " * spaces
    return "\n".join(prefix + line if line else prefix.rstrip() for line in text.split("\n"))


def _json_file_to_moon_source(path: Path) -> str:
    """Embed JSON source directly into MoonBit.

    JSON is a proper subset of MoonBit, so we keep the file contents "as is"
    (normalized to LF newlines) and indent it under the `let` binding.

    If a suite file contains multiple concatenated JSON documents, we keep only
    the first document so `in_json` is a single `Json` value.
    """

    raw = _normalize_newlines(_read_text(path))
    if raw.strip() == "":
        raise ValueError("empty in.json")

    decoder = json.JSONDecoder()
    first_value, end = decoder.raw_decode(raw.lstrip())
    # Re-serialize the first value to JSON to preserve JSON syntax (not MoonBit
    # tuples/maps) while still being valid MoonBit.
    json_text = json.dumps(first_value, ensure_ascii=False, indent=2)
    # If the file had a single JSON value, prefer its original formatting.
    remainder = raw.lstrip()[end:].strip()
    if remainder == "":
        json_text = raw.strip("\n")

    return _indent(json_text, 2)


def _discover_cases(data_dir: Path) -> list[CasePaths]:
    cases: list[CasePaths] = []
    for case_dir in sorted([p for p in data_dir.iterdir() if p.is_dir()], key=lambda p: p.name):
        case_id = case_dir.name
        if not CASE_ID_RE.match(case_id):
            continue

        in_yaml = case_dir / "in.yaml"
        if not in_yaml.exists():
            continue

        in_json = case_dir / "in.json"
        error = case_dir / "error"
        cases.append(
            CasePaths(
                case_id=case_id,
                case_dir=case_dir,
                in_yaml=in_yaml,
                in_json=in_json if in_json.exists() else None,
                error=error if error.exists() else None,
            )
        )
    return cases


def _render_positive_test(case_id: str, yaml_text: str, json_source: str) -> str:
    yaml_block = _yaml_to_moon_multiline_string(yaml_text)

    return "\n".join(
        [
            "///|",
            f'test "{case_id}" {{',
            yaml_block.rstrip("\n"),
            "  let in_json : Json =",
            json_source,
            "  let yaml = @yaml.parse(in_yaml)",
            "  match yaml {",
            "    Ok(yaml) => assert_eq(yaml.to_json(), in_json)",
            '    Err(error) => fail("Unexpected parse error: " + error.to_string())',
            "  }",
            "}",
            "",
        ]
    )


def _render_negative_test(case_id: str, yaml_text: str) -> str:
    yaml_block = _yaml_to_moon_multiline_string(yaml_text)

    return "\n".join(
        [
            "///|",
            f'test "{case_id}" {{',
            yaml_block.rstrip("\n"),
            "  let yaml = parse(in_yaml)",
            "  match yaml {",
            '    Ok(_) => fail("Expected parse error")',
            "    Err(_) => ()",
            "  }",
            "}",
            "",
        ]
    )


def generate(
    data_dir: Path,
    include_error_cases: bool,
    include_missing_expected: bool,
) -> tuple[str, dict[str, int]]:
    cases = _discover_cases(data_dir)

    rendered: list[str] = []
    stats = {
        "total_cases": len(cases),
        "positive": 0,
        "negative": 0,
        "skipped_missing_expected": 0,
        "skipped_no_expected_no_error": 0,
    }

    for case in cases:
        yaml_text = _read_text(case.in_yaml)

        if case.in_json is not None:
            if case.in_json.stat().st_size == 0:
                stats["skipped_missing_expected"] += 1
                continue
            json_source = _json_file_to_moon_source(case.in_json)
            rendered.append(_render_positive_test(case.case_id, yaml_text, json_source))
            stats["positive"] += 1
            continue

        if case.error is not None:
            if include_error_cases:
                rendered.append(_render_negative_test(case.case_id, yaml_text))
                stats["negative"] += 1
            else:
                stats["skipped_missing_expected"] += 1
            continue

        if include_missing_expected:
            # Still generate a negative test: suite case exists but we don't have json/error.
            rendered.append(_render_negative_test(case.case_id, yaml_text))
            stats["negative"] += 1
        else:
            stats["skipped_no_expected_no_error"] += 1

    header = "\n".join(
        [
            "// AUTO-GENERATED FILE. DO NOT EDIT.",
            "// Generated by generation_priv_test/generate_yaml_tests.py",
            f"// Source: {data_dir.as_posix()}",
            "",
        ]
    )
    return header + "".join(rendered), stats


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path("yaml-test-suite/data"),
        help="Path to yaml-test-suite/data directory",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("yaml_generated_test.mbt"),
        help="Output MoonBit test file path",
    )
    parser.add_argument(
        "--include-error-cases",
        action="store_true",
        help="Also generate tests for cases with an `error` file (expects parse error)",
    )
    parser.add_argument(
        "--include-missing-expected",
        action="store_true",
        help="Generate negative tests for cases with no in.json and no error",
    )

    args = parser.parse_args(list(argv) if argv is not None else None)

    if not args.data_dir.exists():
        raise SystemExit(f"data dir not found: {args.data_dir}")

    content, stats = generate(
        data_dir=args.data_dir,
        include_error_cases=args.include_error_cases,
        include_missing_expected=args.include_missing_expected,
    )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(content, encoding="utf-8")

    print(
        "generated",
        str(args.out),
        "positive=",stats["positive"],
        "negative=",stats["negative"],
        "skipped_missing_expected=",stats["skipped_missing_expected"],
        "skipped_no_expected_no_error=",stats["skipped_no_expected_no_error"],
        "total=",stats["total_cases"],
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
