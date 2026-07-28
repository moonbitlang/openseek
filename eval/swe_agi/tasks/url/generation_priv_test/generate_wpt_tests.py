#!/usr/bin/env python3
"""Generate MoonBit tests from WPT urltestdata.json for spec/url package."""

import json
import sys
from pathlib import Path

DEFAULT_DATA_PATH = (
    Path(__file__).resolve().parents[1]
    / "specs"
    / "wpt"
    / "resources"
    / "urltestdata.json"
)


def escape_moonbit_string(s):
    """Escape special characters for MoonBit string literals."""
    if s is None:
        return None
    result = []
    for c in s:
        code = ord(c)
        if c == '\\':
            result.append('\\\\')
        elif c == '"':
            result.append('\\"')
        elif c == '\n':
            result.append('\\n')
        elif c == '\r':
            result.append('\\r')
        elif c == '\t':
            result.append('\\t')
        elif code < 32 or code == 127:
            # Control characters - use unicode escape format
            result.append(f'\\u{{{code:04X}}}')
        else:
            result.append(c)
    return ''.join(result)


def generate_single_test(index, test):
    """Generate a test block for a single test case."""
    input_val = escape_moonbit_string(test.get('input', ''))
    base_val = test.get('base')
    is_failure = test.get('failure', False)

    lines = []
    lines.append('///|')
    lines.append(f'test "WPT #{index}" {{')

    if base_val is None:
        # No base URL
        if is_failure:
            # Case B: No base, expects failure
            lines.append(f'  let result = @url.Url::parse("{input_val}")')
            lines.append('  guard result is None else {')
            lines.append('    fail("Expected failure but got: \\{result.unwrap().to_string().escape()}")')
            lines.append('  }')
        else:
            # Case A: No base, expects success
            href = escape_moonbit_string(test.get('href', ''))
            lines.append(f'  let result = @url.Url::parse("{input_val}")')
            lines.append('  guard result is Some(url) else { fail("Expected success but parsing failed") }')
            lines.append(f'  assert_eq(url.to_string(), "{href}")')
    else:
        # With base URL
        base_escaped = escape_moonbit_string(base_val)
        lines.append(f'  let base_url = @url.Url::parse("{base_escaped}")')
        lines.append(
            '  guard base_url is Some(base_url) else { fail("base URL must parse") }'
        )
        lines.append(f'  let result = @url.Url::parse("{input_val}", base=base_url)')

        if is_failure:
            # Case D: With base, expects failure
            lines.append('  guard result is None else {')
            lines.append('    fail("Expected failure but got: \\{result.unwrap().to_string().escape()}")')
            lines.append('  }')
        else:
            # Case C: With base, expects success
            href = escape_moonbit_string(test.get('href', ''))
            lines.append('  guard result is Some(url) else { fail("Expected success but parsing failed") }')
            lines.append(f'  assert_eq(url.to_string(), "{href}")')

    lines.append('}')
    return '\n'.join(lines)


def main():
    if len(sys.argv) > 2:
        raise SystemExit(f"usage: {sys.argv[0]} [urltestdata.json]")

    # Use the checked-in fixture by default so repeated generation uses the
    # exact benchmark data instead of whichever WPT revision is current.
    data_path = Path(sys.argv[1]) if len(sys.argv) == 2 else DEFAULT_DATA_PATH
    print(f"Loading test data from {data_path}...", file=sys.stderr)
    with data_path.open(encoding="utf-8") as response:
        data = json.load(response)

    print(f"Loaded {len(data)} entries", file=sys.stderr)

    # Generate test file
    output = []
    output.append("// Auto-generated from the checked-in WPT URL fixture")
    output.append("// See generation_priv_test/README.md")
    output.append("// Do not edit manually")
    output.append("//")
    output.append(
        "// To regenerate: python3 "
        "generation_priv_test/generate_wpt_tests.py > url_wpt_test.mbt"
    )
    output.append("")

    test_count = 0

    for item in data:
        if isinstance(item, str):
            # Comment - skip (we use index-based naming now)
            continue
        else:
            # Test case
            output.append(generate_single_test(test_count, item))
            output.append("")
            test_count += 1

    print(f"Generated {test_count} individual test cases", file=sys.stderr)
    print('\n'.join(output))


if __name__ == "__main__":
    main()
