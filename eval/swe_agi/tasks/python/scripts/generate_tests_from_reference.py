#!/usr/bin/env python3.10
"""
Generate MoonBit tests from `reference_pub_test/` (CPython regression tests).

Design goal:
- Walk *all* `reference_pub_test/test_*.py` files (no manual subset picking).
- Extract only assertions we can translate safely and deterministically.
- Emit MoonBit tests into `generated_test.mbt`.
- Write a report `generated_test.report.json` for skipped assertions.

Supported extraction (best-effort):
- `self.assertEqual(<expr>, <literal>)`
- `self.assertTrue(<expr>)`, `self.assertFalse(<expr>)`
- `self.assertRaises(<Exc>, eval, "<expr>")`
- `self.assertRaises(<Exc>, compile, "<src>", "<filename>", "<mode>")`
- `self.assertRaises(<Exc>, int, <args...>)` (converted to `int(...)` expression)

Limitations:
- No execution of CPython test modules (avoids side effects).
- Only literal expected values are converted to JSON expectations.
"""

from __future__ import annotations

import ast
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional


ROOT = Path(__file__).resolve().parents[1]  # python/
REFERENCE_DIR = ROOT / "reference_pub_test"
OUT_MBT = ROOT / "generated_test.mbt"
OUT_REPORT = ROOT / "generated_test.report.json"

ALLOWED_GLOBAL_NAMES = {
    # Constants
    "True",
    "False",
    "None",
    "Ellipsis",
    # Builtins (subset; extend as your interpreter grows)
    "int",
    "bool",
    "str",
    "repr",
}

SAFE_EVAL_BUILTINS = {
    "int": int,
    "bool": bool,
    "str": str,
    "repr": repr,
    "Ellipsis": Ellipsis,
}


@dataclass(frozen=True)
class Location:
    path: str
    line: int


@dataclass(frozen=True)
class Skipped:
    location: Location
    reason: str
    snippet: str


def is_test_file(path: Path) -> bool:
    return path.name.startswith("test_") and path.suffix == ".py"


def ast_unparse(node: ast.AST) -> str:
    # Python 3.9+ has ast.unparse
    try:
        return ast.unparse(node)
    except Exception:
        return "<unparse-failed>"


def source_text(src: str, node: ast.AST) -> str:
    """
    Prefer original source spelling over AST pretty-printing.

    This is crucial for numeric literals: AST stores `0x10` as `Constant(16)` and
    `ast.unparse` will output `16`, losing the base/underscores/case.
    """
    seg = ast.get_source_segment(src, node)
    if seg is None:
        return ast_unparse(node)
    return seg.strip()


def interestingness_score(expr_src: str) -> int:
    """
    Heuristic: higher score means "more worth testing" as source text.
    """
    s = expr_src
    score = 0
    if any(token in s for token in ("0x", "0X", "0o", "0O", "0b", "0B")):
        score += 10
    if "_" in s:
        score += 4
    if any(ch.isalpha() for ch in s):
        score += 3
    if any(ch in s for ch in ("(", ")", "[", "]", "{", "}", "~", "+", "-", "*", "/", "%", "|", "&", "^", "<", ">", "=", ":", ",")):
        score += 2
    if any(ch.isspace() for ch in s):
        score += 1
    return score

def is_context_free_expr(node: ast.AST) -> bool:
    """
    Returns true iff `node` can be evaluated without any surrounding module/test
    context: only literals, operators, and a small whitelist of builtins.

    This prevents generating unusable tests like `int(cid)` where `cid` is a
    variable defined inside CPython's unittest logic.
    """

    def ok(n: ast.AST) -> bool:
        match n:
            case ast.Constant():
                return True
            case ast.Name(id=name):
                return name in ALLOWED_GLOBAL_NAMES
            case ast.UnaryOp(operand=operand):
                return ok(operand)
            case ast.BinOp(left=left, right=right):
                return ok(left) and ok(right)
            case ast.BoolOp(values=values):
                return all(ok(v) for v in values)
            case ast.Compare(left=left, comparators=comparators):
                return ok(left) and all(ok(c) for c in comparators)
            case ast.IfExp(test=test, body=body, orelse=orelse):
                return ok(test) and ok(body) and ok(orelse)
            case ast.Tuple(elts=elts) | ast.List(elts=elts) | ast.Set(elts=elts):
                return all(ok(e) for e in elts)
            case ast.Dict(keys=keys, values=values):
                return all(k is None or ok(k) for k in keys) and all(ok(v) for v in values)
            case ast.Subscript(value=value, slice=slice_):
                return ok(value) and ok(slice_)
            case ast.Slice(lower=lower, upper=upper, step=step):
                return (lower is None or ok(lower)) and (upper is None or ok(upper)) and (step is None or ok(step))
            case ast.Call(func=func, args=args, keywords=keywords):
                if not isinstance(func, ast.Name) or func.id not in ALLOWED_GLOBAL_NAMES:
                    return False
                if not all(ok(a) for a in args):
                    return False
                return all(kw.arg is not None and ok(kw.value) for kw in keywords)
            case _:
                return False

    return ok(node)


def moonbit_escape_string(s: str) -> str:
    # MoonBit string literal uses `"` with backslash escapes.
    # NOTE: `reference_pub_test/` contains tests that use surrogate code points
    # (e.g. "\udc80"). We must not write raw surrogates into UTF-8 output, so we
    # escape them using Python's `unicode_escape` when needed.
    try:
        s.encode("utf-8")
        safe = s
    except UnicodeEncodeError:
        safe = s.encode("unicode_escape").decode("ascii")

    return (
        safe.replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
        .replace('"', '\\"')
    )


def py_literal_to_test_json(value: Any) -> Optional[str]:
    """
    Convert a Python literal into a MoonBit Json literal expression string.

    Matches the contract described in `python/python_spec.mbt`:
    - ints encoded as strings
    - dict preserves insertion order; JSON encodes as list of [k,v] pairs
    """
    if value is None:
        return '{ "type": "none" }'
    if value is Ellipsis:
        return '{ "type": "ellipsis" }'
    if isinstance(value, bool):
        return f'{{ "type": "bool", "value": {"true" if value else "false"} }}'
    if isinstance(value, int):
        return f'{{ "type": "int", "value": "{value}" }}'
    if isinstance(value, str):
        # Encode strings using `unicode_escape` to support CPython tests that use
        # surrogate code points (not valid UTF-8).
        escaped = value.encode("unicode_escape").decode("ascii")
        return (
            '{ "type": "str", "escape": "'
            + moonbit_escape_string(escaped)
            + '" }'
        )
    if isinstance(value, list):
        items = [py_literal_to_test_json(v) for v in value]
        if any(x is None for x in items):
            return None
        return '{ "type": "list", "items": [' + ", ".join(items) + "] }"
    if isinstance(value, tuple):
        items = [py_literal_to_test_json(v) for v in value]
        if any(x is None for x in items):
            return None
        return '{ "type": "tuple", "items": [' + ", ".join(items) + "] }"
    if isinstance(value, dict):
        items = []
        for k, v in value.items():
            kj = py_literal_to_test_json(k)
            vj = py_literal_to_test_json(v)
            if kj is None or vj is None:
                return None
            items.append("[" + kj + ", " + vj + "]")
        return '{ "type": "dict", "items": [' + ", ".join(items) + "] }"
    return None


def extract_literal(node: ast.AST) -> Optional[Any]:
    try:
        return ast.literal_eval(node)
    except Exception:
        return None


def safe_eval(expr: str) -> tuple[bool, str, str]:
    """
    Evaluate a context-free expression in a restricted CPython environment.

    Returns: (ok, repr(value), error_string)
    """
    try:
        value = eval(expr, {"__builtins__": SAFE_EVAL_BUILTINS}, {})
        return True, repr(value), ""
    except Exception as e:
        return False, "", f"{type(e).__name__}: {e}"


def safe_exec_eval(preamble_src: str, expr: str) -> tuple[bool, str, str]:
    """
    Execute a preamble then evaluate an expression in a restricted environment.

    Returns: (ok, repr(value), error_string)
    """
    try:
        globals_ = {"__builtins__": SAFE_EVAL_BUILTINS}
        locals_: dict[str, Any] = {}
        if preamble_src.strip():
            exec(preamble_src, globals_, locals_)
        value = eval(expr, globals_, locals_)
        return True, repr(value), ""
    except Exception as e:
        return False, "", f"{type(e).__name__}: {e}"


def is_self_assert_call(node: ast.AST, name: str) -> bool:
    if not isinstance(node, ast.Call):
        return False
    func = node.func
    return (
        isinstance(func, ast.Attribute)
        and isinstance(func.value, ast.Name)
        and func.value.id == "self"
        and func.attr == name
    )


def exc_name(node: ast.AST) -> Optional[str]:
    # SyntaxError / ValueError / NameError / TypeError / ZeroDivisionError / ...
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        # e.g. module.SyntaxError
        return node.attr
    return None


def build_error_pattern(exc: str) -> Optional[str]:
    mapping = {
        "SyntaxError": "@python.PyError::SyntaxError(_)",
        "NameError": "@python.PyError::NameError(_)",
        "TypeError": "@python.PyError::TypeError(_)",
        "ValueError": "@python.PyError::ValueError(_)",
        "ZeroDivisionError": "@python.PyError::ZeroDivisionError",
        "IndexError": "@python.PyError::IndexError(_)",
        "KeyError": "@python.PyError::KeyError(_)",
        "AttributeError": "@python.PyError::AttributeError(_)",
    }
    return mapping.get(exc)


def test_name_for(location: Location, kind: str) -> str:
    # Use slash-separated names like the rest of this repo.
    rel = location.path.replace(os.sep, "/")
    return f"python/ref/{rel}:{location.line}/{kind}"


def is_context_free_stmt(stmt: ast.stmt) -> bool:
    """
    Conservative "safe prelude" statement classifier.

    Only statements that are expected to be supported early by a Python subset,
    and which are safe to re-execute in isolation, are allowed.
    """
    match stmt:
        case ast.Assign(targets=targets, value=value):
            if not is_context_free_expr(value):
                return False
            return all(isinstance(t, ast.Name) for t in targets)
        case ast.AnnAssign(target=target, value=value):
            if not isinstance(target, ast.Name):
                return False
            return value is None or is_context_free_expr(value)
        case ast.AugAssign(target=target, value=value):
            if not isinstance(target, ast.Name):
                return False
            return is_context_free_expr(value)
        case ast.Expr(value=ast.Constant()):
            return True
        case ast.Pass():
            return True
        case _:
            return False


def generate() -> None:
    skipped: list[Skipped] = []
    emitted_tests: list[str] = []
    emitted_keys: set[tuple[str, str, str]] = set()

    test_files = sorted(p for p in REFERENCE_DIR.rglob("*.py") if is_test_file(p))

    # 1) File-level syntax tests (module mode)
    #
    # These are meaningful even before runtime semantics are implemented.
    for path in test_files:
        rel_path = str(path.relative_to(REFERENCE_DIR)).replace(os.sep, "/")
        name = f"python/ref/syntax/{rel_path}"
        emitted_tests.append(
            "\n".join(
                [
                    "///|",
                    f'test "{moonbit_escape_string(name)}" {{',
                    f'  @python.check_syntax_file("reference_pub_test/{moonbit_escape_string(rel_path)}")',
                    "}",
                ]
            )
        )

    # 1b) File-level load tests using `Vm::run_file`.
    #
    # Executing the entire CPython test suite is not a realistic early target
    # (stdlib, IO, platform features, etc.). Instead, start with modules that
    # only import `unittest` and otherwise mainly define classes/functions.
    for path in test_files:
        rel_path = str(path.relative_to(REFERENCE_DIR)).replace(os.sep, "/")
        src = path.read_text(encoding="utf-8", errors="replace")
        try:
            tree = ast.parse(src, filename=str(path))
        except SyntaxError:
            continue

        top_imports: set[str] = set()
        for node in tree.body:
            if isinstance(node, ast.Import):
                for alias in node.names:
                    top_imports.add(alias.name)
            elif isinstance(node, ast.ImportFrom):
                if node.module is not None and node.level == 0:
                    top_imports.add(node.module)

        if top_imports == {"unittest"}:
            name = f"python/ref/run_file/{rel_path}"
            key = ("run_file", f"reference_pub_test/{rel_path}", "")
            if key in emitted_keys:
                continue
            emitted_keys.add(key)
            emitted_tests.append(
                "\n".join(
                    [
                        "///|",
                        f'test "{moonbit_escape_string(name)}" {{',
                        "  let vm = @python.Vm::new()",
                        f'  try! vm.run_file("reference_pub_test/{moonbit_escape_string(rel_path)}")',
                        "}",
                    ]
                )
            )

    for path in test_files:
        rel_path = str(path.relative_to(REFERENCE_DIR))
        src = path.read_text(encoding="utf-8", errors="replace")
        try:
            tree = ast.parse(src, filename=str(path))
        except SyntaxError as e:
            skipped.append(
                Skipped(
                    location=Location(rel_path, int(getattr(e, "lineno", 1) or 1)),
                    reason="python-syntax-error-while-parsing-reference",
                    snippet=str(e),
                )
            )
            continue

        # 2) Semantics tests extracted from `unittest.TestCase` methods, with a
        #    simple "preamble" context.
        for node in tree.body:
            if not isinstance(node, ast.ClassDef):
                continue
            # Rough check for TestCase subclasses.
            if not any(
                isinstance(base, ast.Attribute) and base.attr == "TestCase"
                or isinstance(base, ast.Name) and base.id == "TestCase"
                for base in node.bases
            ):
                continue

            for item in node.body:
                if not isinstance(item, ast.FunctionDef):
                    continue
                if not item.name.startswith("test"):
                    continue

                preamble: list[str] = []
                preamble_src = ""
                preamble_enabled = True

                for stmt in item.body:
                    if (
                        isinstance(stmt, ast.Expr)
                        and isinstance(stmt.value, ast.Call)
                        and (
                            is_self_assert_call(stmt.value, "assertEqual")
                            or is_self_assert_call(stmt.value, "assertTrue")
                            or is_self_assert_call(stmt.value, "assertFalse")
                            or is_self_assert_call(stmt.value, "assertRaises")
                        )
                    ):
                        call = stmt.value
                        loc = Location(rel_path, getattr(call, "lineno", 1))

                        if is_self_assert_call(call, "assertEqual") and len(call.args) == 2:
                            lhs, rhs = call.args
                            if not is_context_free_expr(lhs) or not is_context_free_expr(rhs):
                                skipped.append(
                                    Skipped(
                                        location=loc,
                                        reason="assertEqual-expr-not-context-free",
                                        snippet=ast_unparse(call),
                                    )
                                )
                                continue

                            lhs_expr = source_text(src, lhs)
                            rhs_expr = source_text(src, rhs)

                            ok_lhs, lhs_repr, lhs_err = safe_exec_eval(preamble_src, lhs_expr)
                            ok_rhs, rhs_repr, rhs_err = safe_exec_eval(preamble_src, rhs_expr)
                            if not ok_lhs or not ok_rhs:
                                skipped.append(
                                    Skipped(
                                        location=loc,
                                        reason="assertEqual-safe-exec-eval-failed",
                                        snippet=f"{lhs_expr}=>{lhs_err}; {rhs_expr}=>{rhs_err}",
                                    )
                                )
                                continue

                            # Confirm equality in the same restricted environment.
                            try:
                                globals_ = {"__builtins__": SAFE_EVAL_BUILTINS}
                                locals_: dict[str, Any] = {}
                                if preamble_src.strip():
                                    exec(preamble_src, globals_, locals_)
                                if eval(lhs_expr, globals_, locals_) != eval(rhs_expr, globals_, locals_):
                                    skipped.append(
                                        Skipped(
                                            location=loc,
                                            reason="assertEqual-safe-exec-eval-not-equal",
                                            snippet=f"{lhs_expr} ({lhs_repr}) != {rhs_expr} ({rhs_repr})",
                                        )
                                    )
                                    continue
                            except Exception as e:
                                skipped.append(
                                    Skipped(
                                        location=loc,
                                        reason="assertEqual-safe-exec-eval-compare-failed",
                                        snippet=f"{lhs_expr} ?= {rhs_expr} => {type(e).__name__}: {e}",
                                    )
                                )
                                continue

                            chosen_expr = lhs_expr
                            chosen_repr = lhs_repr
                            if interestingness_score(rhs_expr) > interestingness_score(lhs_expr):
                                chosen_expr = rhs_expr
                                chosen_repr = rhs_repr

                            program = (preamble_src + "\n" if preamble_src else "") + chosen_expr
                            name = test_name_for(loc, f"{node.name}.{item.name}/assertEqual")
                            key = ("assertEqual", program, chosen_repr)
                            if key in emitted_keys:
                                continue
                            emitted_keys.add(key)
                            emitted_tests.append(
                                "\n".join(
                                    [
                                        "///|",
                                        f'test "{moonbit_escape_string(name)}" {{',
                                        "  let vm = @python.Vm::new()",
                                        f'  let value = vm.exec_program("{moonbit_escape_string(program)}")',
                                        f'  assert_eq(value.repr(), "{moonbit_escape_string(chosen_repr)}")',
                                        "}",
                                    ]
                                )
                            )
                            continue

                        if (is_self_assert_call(call, "assertTrue") or is_self_assert_call(call, "assertFalse")) and len(call.args) == 1:
                            expr_node = call.args[0]
                            if not is_context_free_expr(expr_node):
                                skipped.append(
                                    Skipped(
                                        location=loc,
                                        reason="assertTrue/False-expr-not-context-free",
                                        snippet=ast_unparse(call),
                                    )
                                )
                                continue

                            expr = source_text(src, expr_node)
                            ok_eval, repr_eval, err_eval = safe_exec_eval(preamble_src, f"bool({expr})")
                            if not ok_eval:
                                skipped.append(
                                    Skipped(
                                        location=loc,
                                        reason="assertTrue/False-safe-exec-eval-failed",
                                        snippet=f"bool({expr}) => {err_eval}",
                                    )
                                )
                                continue

                            expected_bool = "True" if is_self_assert_call(call, "assertTrue") else "False"
                            program = (preamble_src + "\n" if preamble_src else "") + f"bool({expr})"
                            kind = "assertTrue" if expected_bool == "True" else "assertFalse"
                            name = test_name_for(loc, f"{node.name}.{item.name}/{kind}")
                            key = (kind, program, expected_bool)
                            if key in emitted_keys:
                                continue
                            emitted_keys.add(key)
                            emitted_tests.append(
                                "\n".join(
                                    [
                                        "///|",
                                        f'test "{moonbit_escape_string(name)}" {{',
                                        "  let vm = @python.Vm::new()",
                                        f'  let value = vm.exec_program("{moonbit_escape_string(program)}")',
                                        f'  assert_eq(value.repr(), "{expected_bool}")',
                                        "}",
                                    ]
                                )
                            )
                            continue

                        if is_self_assert_call(call, "assertRaises") and len(call.args) >= 2:
                            exc = exc_name(call.args[0])
                            pattern = build_error_pattern(exc) if exc else None
                            if pattern is None:
                                skipped.append(
                                    Skipped(
                                        location=loc,
                                        reason="assertRaises-unsupported-exception-type",
                                        snippet=ast_unparse(call),
                                    )
                                )
                                continue

                            callee_name = ast_unparse(call.args[1])

                            # assertRaises(SyntaxError, eval, "<code>")
                            if callee_name == "eval" and len(call.args) >= 3:
                                code = extract_literal(call.args[2])
                                if not isinstance(code, str):
                                    skipped.append(
                                        Skipped(
                                            location=loc,
                                            reason="assertRaises-eval-non-string-arg",
                                            snippet=ast_unparse(call),
                                        )
                                    )
                                    continue
                                name = test_name_for(loc, f"{node.name}.{item.name}/assertRaises/{exc}/eval")
                                key = (f"assertRaises/{exc}/eval", code, "")
                                if key in emitted_keys:
                                    continue
                                emitted_keys.add(key)
                                emitted_tests.append(
                                    "\n".join(
                                        [
                                            "///|",
                                            f'test "{moonbit_escape_string(name)}" {{',
                                            f'  guard (try? @python.eval_expr("{moonbit_escape_string(code)}")) is Err({pattern})',
                                            "}",
                                        ]
                                    )
                                )
                                continue

                            # assertRaises(SyntaxError, compile, "<code>", "<file>", "exec"|"eval")
                            if callee_name == "compile" and len(call.args) >= 5:
                                code = extract_literal(call.args[2])
                                mode = extract_literal(call.args[4])
                                if not isinstance(code, str) or mode not in ("eval", "exec"):
                                    skipped.append(
                                        Skipped(
                                            location=loc,
                                            reason="assertRaises-compile-unsupported-args",
                                            snippet=ast_unparse(call),
                                        )
                                    )
                                    continue
                                name = test_name_for(loc, f"{node.name}.{item.name}/assertRaises/{exc}/compile/{mode}")
                                key = (f"assertRaises/{exc}/compile/{mode}", code, "")
                                if key in emitted_keys:
                                    continue
                                emitted_keys.add(key)
                                if mode == "eval":
                                    emitted_tests.append(
                                        "\n".join(
                                            [
                                                "///|",
                                                f'test "{moonbit_escape_string(name)}" {{',
                                                f'  guard (try? @python.eval_expr("{moonbit_escape_string(code)}")) is Err({pattern})',
                                                "}",
                                            ]
                                        )
                                    )
                                else:
                                    emitted_tests.append(
                                        "\n".join(
                                            [
                                                "///|",
                                                f'test "{moonbit_escape_string(name)}" {{',
                                                "  let vm = @python.Vm::new()",
                                                f'  guard (try? vm.exec("{moonbit_escape_string(code)}")) is Err({pattern})',
                                                "}",
                                            ]
                                        )
                                    )
                                continue

                            # assertRaises(ValueError, int, ...)
                            if callee_name == "int" and len(call.args) >= 3:
                                if not all(is_context_free_expr(a) for a in call.args[2:]):
                                    skipped.append(
                                        Skipped(
                                            location=loc,
                                            reason="assertRaises-int-args-not-context-free",
                                            snippet=ast_unparse(call),
                                        )
                                    )
                                    continue
                                args = [source_text(src, a) for a in call.args[2:]]
                                expr = "int(" + ", ".join(args) + ")"
                                name = test_name_for(loc, f"{node.name}.{item.name}/assertRaises/{exc}/int")
                                key = (f"assertRaises/{exc}/int", expr, "")
                                if key in emitted_keys:
                                    continue
                                emitted_keys.add(key)
                                emitted_tests.append(
                                    "\n".join(
                                        [
                                            "///|",
                                            f'test "{moonbit_escape_string(name)}" {{',
                                            f'  guard (try? @python.eval_expr("{moonbit_escape_string(expr)}")) is Err({pattern})',
                                            "}",
                                        ]
                                    )
                                )
                                continue

                            skipped.append(
                                Skipped(
                                    location=loc,
                                    reason="assertRaises-unsupported-callee-shape",
                                    snippet=ast_unparse(call),
                                )
                            )
                        continue

                    # Track a "safe prelude" prefix only until we hit an unsupported stmt.
                    if preamble_enabled and is_context_free_stmt(stmt):
                        segment = ast.get_source_segment(src, stmt)
                        if segment is None:
                            segment = ast_unparse(stmt)
                        preamble.append(segment)
                        preamble_src = "\n".join(preamble)
                    else:
                        preamble_enabled = False

    header = "\n".join(
        [
            "///|",
            "// GENERATED FILE; DO NOT EDIT BY HAND.",
            "//",
            "// Generated from CPython-style unittest sources under `reference_pub_test/`",
            "// by `scripts/generate_tests_from_reference.py`.",
            "//",
            "// Contents:",
            "// - `check_syntax_file(...)` tests for every `test_*.py` module",
            "// - Extracted assertions from `unittest.TestCase` methods, using",
            "//   `Vm::exec_program(...)` with a conservative statement prelude when possible.",
            "//",
            "// This is intentionally only a subset of CPython assertions: anything that",
            "// depends on imports/stdlib/IO/framework internals is recorded in the report.",
            "// See `python/generated_test.report.json` for everything we could not yet convert.",
            "",
        ]
    )

    OUT_MBT.write_text(header + "\n\n".join(emitted_tests) + "\n", encoding="utf-8")

    OUT_REPORT.write_text(
        json.dumps(
            {
                "reference_dir": str(REFERENCE_DIR),
                "test_files": [str(p.relative_to(REFERENCE_DIR)) for p in test_files],
                "generated_test_file": str(OUT_MBT),
                "counts": {
                    "generated_tests": len(emitted_tests),
                    "skipped_assertions": len(skipped),
                },
                "skipped": [
                    {
                        "path": s.location.path,
                        "line": s.location.line,
                        "reason": s.reason,
                        "snippet": s.snippet,
                    }
                    for s in skipped
                ],
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> None:
    if not REFERENCE_DIR.exists():
        raise SystemExit(f"reference dir not found: {REFERENCE_DIR}")
    generate()
    print(f"Wrote: {OUT_MBT}")
    print(f"Wrote: {OUT_REPORT}")


if __name__ == "__main__":
    main()
