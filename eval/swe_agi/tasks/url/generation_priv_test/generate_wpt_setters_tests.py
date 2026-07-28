#!/usr/bin/env python3
"""Generate MoonBit tests from WPT setters_tests.json for url package."""

import json
import sys
from pathlib import Path

DEFAULT_DATA_PATH = (
    Path(__file__).resolve().parents[1]
    / "specs"
    / "wpt"
    / "resources"
    / "setters_tests.json"
)


def escape_moonbit_string(value):
    if value is None:
        return None
    result = []
    for c in value:
        code = ord(c)
        if c == "\\":
            result.append("\\\\")
        elif c == '"':
            result.append('\\"')
        elif c == "\n":
            result.append("\\n")
        elif c == "\r":
            result.append("\\r")
        elif c == "\t":
            result.append("\\t")
        elif code < 32 or code == 127 or code > 126:
            result.append(f"\\u{{{code:X}}}")
        else:
            result.append(c)
    return "".join(result)


FIELD_ORDER = [
    "href",
    "protocol",
    "username",
    "password",
    "host",
    "hostname",
    "port",
    "pathname",
    "search",
    "hash",
]


def setter_method(name):
    if name == "href":
        return "set_href"
    return f"set_{name}"


def getter_method(name):
    if name == "href":
        return "href"
    return name


def generate_single_test(setter, index, item):
    href = escape_moonbit_string(item["href"])
    new_value = escape_moonbit_string(item["new_value"])
    expected = item["expected"]

    lines = []
    lines.append("///|")
    lines.append(f'test "WPT setters {setter} #{index}" {{')
    lines.append(f'  let url = @url.Url::parse("{href}")')
    lines.append('  guard url is Some(url) else { fail("parse failed") }')
    lines.append(f'  url.{setter_method(setter)}("{new_value}")')

    for field in FIELD_ORDER:
        if field not in expected:
            continue
        expected_value = escape_moonbit_string(expected[field])
        lines.append(
            f'  assert_eq(url.{getter_method(field)}(), "{expected_value}")'
        )

    lines.append("}")
    return "\n".join(lines)


def main():
    if len(sys.argv) > 2:
        raise SystemExit(f"usage: {sys.argv[0]} [setters_tests.json]")

    # Use the checked-in fixture by default so repeated generation uses the
    # exact benchmark data instead of whichever WPT revision is current.
    data_path = Path(sys.argv[1]) if len(sys.argv) == 2 else DEFAULT_DATA_PATH
    print(f"Loading WPT setters data from {data_path}...", file=sys.stderr)
    with data_path.open(encoding="utf-8") as response:
        data = json.load(response)

    output = []
    output.append("// Auto-generated from the checked-in WPT URL setters fixture")
    output.append("// See generation_priv_test/README.md")
    output.append("// Do not edit manually")
    output.append("//")
    output.append(
        "// To regenerate: python3 "
        "generation_priv_test/generate_wpt_setters_tests.py "
        "> url_wpt_setters_test.mbt"
    )
    output.append("")

    for setter in FIELD_ORDER:
        if setter not in data:
            continue
        tests = data[setter]
        for index, item in enumerate(tests):
            output.append(generate_single_test(setter, index, item))
            output.append("")

    print("\n".join(output))


if __name__ == "__main__":
    main()
