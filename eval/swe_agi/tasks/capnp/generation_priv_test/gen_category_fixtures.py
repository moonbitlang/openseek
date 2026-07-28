#!/usr/bin/env python3
import pathlib
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "test" / "category_fixtures.capnp"
OUTPUT = ROOT / "test" / "generated_category_fixtures_test.mbt"


def run_convert(type_name: str, text_input: str) -> bytes:
    cmd = ["capnp", "convert", "text:binary", str(SCHEMA), type_name]
    try:
        completed = subprocess.run(
            cmd,
            input=text_input.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=ROOT,
            check=True,
        )
    except FileNotFoundError as exc:
        raise SystemExit("capnp tool not found in PATH") from exc
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.decode("utf-8", errors="replace").strip()
        raise SystemExit(f"capnp convert failed: {stderr}") from exc
    return completed.stdout


def escape_bytes(data: bytes) -> str:
    out = []
    for value in data:
        if value == 0x22:
            out.append("\\\"")
        elif value == 0x5C:
            out.append("\\\\")
        elif 0x20 <= value <= 0x7E:
            out.append(chr(value))
        else:
            out.append(f"\\x{value:02x}")
    return "".join(out)


def format_bytes_literal(data: bytes) -> str:
    if len(data) <= 32:
        return f'b"{escape_bytes(data)}"'
    hex_values = [f"0x{value:02x}" for value in data]
    lines = []
    for i in range(0, len(hex_values), 12):
        chunk = ", ".join(hex_values[i : i + 12])
        if i + 12 < len(hex_values):
            chunk = f"{chunk},"
        lines.append(f"  {chunk}")
    return "[\n" + "\n".join(lines) + "\n]"


def render_fixture(name: str, data: bytes) -> str:
    literal = format_bytes_literal(data)
    return "///|\n" f"let {name} : Bytes = {literal}\n"


def main() -> int:
    fixtures = [
        ("simple_bool_fixture", "SimpleBool", "(flag = true)"),
        ("simple_int32_fixture", "SimpleInt32", "(value = -123456)"),
        ("simple_int8_fixture", "SimpleInt8", "(value = -42)"),
        ("simple_uint64_fixture", "SimpleUInt64", "(value = 9000000000000000000)"),
        ("simple_uint16_fixture", "SimpleUInt16", "(value = 65535)"),
        ("simple_float64_fixture", "SimpleFloat64", "(value = -2.25)"),
        ("simple_float32_fixture", "SimpleFloat32", "(value = 3.5)"),
        ("simple_text_fixture", "SimpleText", '(value = "hello")'),
        (
            "simple_bytes_fixture",
            "SimpleBytes",
            "(value = [0, 1, 2, 255])",
        ),
        (
            "simple_bool_list_fixture",
            "SimpleBoolList",
            "(values = [true, false, true, true])",
        ),
        (
            "simple_text_list_fixture",
            "SimpleTextList",
            '(values = ["a", "bb", ""])',
        ),
        (
            "medium_root_fixture",
            "MediumRoot",
            '(\n'
            '  name = "medium",\n'
            "  values = [10, -20, 30],\n"
            '  child = (value = 7, label = "child"),\n'
            '  children = [(value = 1, label = "one"), (value = 2, label = "two")]\n'
            ")",
        ),
        (
            "medium_list_fixture",
            "MediumListRoot",
            '(\n'
            '  items = [(value = -1, label = "a"), (value = 5, label = "bb")],\n'
            "  flags = [true, false, true, false]\n"
            ")",
        ),
        (
            "medium_numbers_fixture",
            "MediumNumbers",
            '(\n'
            '  title = "nums",\n'
            "  numbers = [-1, 2, 300],\n"
            "  flags = [true, false, true]\n"
            ")",
        ),
        (
            "medium_mixed_fixture",
            "MediumMixed",
            '(\n'
            "  id = 42,\n"
            '  tags = ["x", "yy"],\n'
            "  payload = [9, 8],\n"
            '  child = (value = 3, label = "kid")\n'
            ")",
        ),
        (
            "difficult_nested_fixture",
            "DifficultNested",
            '(\n'
            '  title = "deep",\n'
            "  matrix = [[1, 2], [-3, 4, 5]],\n"
            '  nodes = [(id = 7, tag = "x"), (id = 9, tag = "yy")],\n'
            "  payload = [0, 1, 2, 255]\n"
            ")",
        ),
        (
            "difficult_union_fixture",
            "DifficultUnion",
            '(\n'
            "  child = (value = -9),\n"
            "  flags = [true, false, true, true],\n"
            "  groups = [[(value = 1), (value = -2)], [(value = 3)]]\n"
            ")",
        ),
        (
            "difficult_deeplist_fixture",
            "DifficultDeepList",
            '(\n'
            '  title = "deep2",\n'
            '  rows = [[(value = 1, label = "a"), (value = 2, label = "b")],\n'
            '          [(value = -3, label = "c")]],\n'
            "  masks = [[true, false], [false, true, true]]\n"
            ")",
        ),
        (
            "difficult_mixed_fixture",
            "DifficultMixed",
            '(\n'
            '  header = "mix",\n'
            "  items = [\n"
            '    (name = "m1", values = [1], child = (value = 1, label = "x"), children = []),\n'
            '    (name = "m2", values = [-1, 2], child = (value = 2, label = "y"),\n'
            '     children = [(value = 3, label = "z")])\n'
            "  ],\n"
            "  extras = [[1, 2, 3], [255]]\n"
            ")",
        ),
    ]

    contents = [
        "// Code generated by generation_priv_test/gen_category_fixtures.py; "
        "DO NOT EDIT.\n",
        "// Schema: test/category_fixtures.capnp\n",
        "\n",
    ]
    for name, type_name, text_input in fixtures:
        data = run_convert(type_name, text_input)
        contents.append(render_fixture(name, data))
        contents.append("\n")

    OUTPUT.write_text("".join(contents).rstrip() + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
