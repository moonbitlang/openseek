#!/usr/bin/env python3
"""
Generate MoonBit tests from the official pugjs/pug fixtures.

Source repo: https://github.com/pugjs/pug/tree/master/packages/pug/test

This script downloads a tarball of `pugjs/pug`, extracts
`packages/pug/test/{cases,cases-es2015}`, and generates MoonBit tests that:

- Embed the `.pug` source as a MoonBit multiline string.
- Compare rendered HTML against the corresponding `.html` fixture with
  whitespace between tags collapsed (to match compact render output).
- Use `TemplateRegistry` for include/extends resolution (no filesystem IO).

Regenerate:
  python3 pug/scripts_priv_test/generate_tests_from_pugjs.py
"""

from __future__ import annotations

import argparse
import json
import os
import re
import tarfile
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple


ROOT = Path(__file__).resolve().parents[1]  # pug/
OUT_MBT = ROOT / "pugjs_generated_test.mbt"
OUT_REPORT = ROOT / "pugjs_generated_test.report.json"
CACHE_DIR = ROOT / "_build" / "pugjs_cache"


def _codeload_url(ref: str) -> str:
    if "/" not in ref:
        ref = f"refs/heads/{ref}"
    return f"https://codeload.github.com/pugjs/pug/tar.gz/{ref}"


def _download(url: str, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as resp:
        data = resp.read()
    dst.write_bytes(data)


def _extract_test_dir(tarball: Path, tmp: Path) -> Path:
    tmp.mkdir(parents=True, exist_ok=True)
    with tarfile.open(tarball, "r:gz") as tf:
        members = tf.getmembers()
        root_prefix = None
        for m in members:
            if m.isdir():
                root_prefix = m.name.split("/")[0]
                break
        if not root_prefix:
            raise RuntimeError("unexpected tarball layout (no root dir)")
        test_prefix = f"{root_prefix}/packages/pug/test/"

        selected = [m for m in members if m.name.startswith(test_prefix)]

        def is_within_directory(directory: str, target: str) -> bool:
            abs_directory = os.path.abspath(directory)
            abs_target = os.path.abspath(target)
            return os.path.commonpath([abs_directory]) == os.path.commonpath(
                [abs_directory, abs_target]
            )

        for m in selected:
            target = os.path.join(tmp, m.name)
            if not is_within_directory(str(tmp), target):
                raise RuntimeError(f"unsafe path in tarball: {m.name}")

        tf.extractall(tmp, members=selected)

    test_dir = tmp / root_prefix / "packages" / "pug" / "test"
    if not test_dir.is_dir():
        raise RuntimeError("failed to extract `packages/pug/test`")
    return test_dir


def _moon_string_expr_lines(s: str, base_indent: str) -> List[str]:
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    lines = s.split("\n")
    out: List[str] = []
    out.append(base_indent + "(")
    for line in lines:
        out.append(base_indent + "  " + "#|" + line)
    out.append(base_indent + ")")
    return out


def _moon_multiline_let_string_lines(s: str, base_indent: str) -> List[str]:
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    lines = s.split("\n")
    return [base_indent + "#|" + line for line in lines]


def _moon_hashpipe_lines(s: str, base_indent: str) -> List[str]:
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    return [base_indent + "#|" + line for line in s.split("\n")]


def _normalize_expected_html(html: str) -> str:
    html = html.replace("\r", "").strip()
    # Collapse whitespace that is purely between tags. This keeps whitespace in
    # text nodes intact (e.g. inside <pre>).
    html = re.sub(r">\s+<", "><", html)
    return html


_RE_FILTER = re.compile(r"(?m)^\s*:(?P<name>[\w-]+)\b")
_RE_INCLUDE_EXTENDS = re.compile(r"(?m)^\s*(?P<kw>include|extends)\s+(?P<rest>.+?)\s*$")
_RE_INCLUDE_FILTER = re.compile(r"(?m)^\s*include:[^\s]+\s+")


def _has_unsupported_filter(src: str) -> Optional[str]:
    if _RE_INCLUDE_FILTER.search(src):
        return "include-filter (include:<filter>)"
    for m in _RE_FILTER.finditer(src):
        name = m.group("name")
        if name != "plain":
            return f"filter `:{name}`"
    return None


def _tokenize_path(rest: str) -> Optional[str]:
    # `include foo.pug` / `extends layout` / `include ./x.pug`
    token = rest.strip().split()[0]
    if not token:
        return None
    if token[0] in "\"'`":
        return None
    if "#" in token or "{" in token or "}" in token:
        return None
    return token


def _resolve_dep_file(
    *,
    suite_dir: Path,
    from_file: Path,
    token: str,
) -> Optional[Path]:
    def try_candidates(base: Path, t: str) -> Optional[Path]:
        candidates = [base / t]
        if not t.endswith(".pug"):
            candidates.append(base / (t + ".pug"))
        for p in candidates:
            if p.is_file():
                return p
        return None

    if token.startswith("/"):
        p = try_candidates(suite_dir, token.lstrip("/"))
        if p:
            return p
    p = try_candidates(from_file.parent, token)
    if p:
        return p
    p = try_candidates(suite_dir, token)
    return p


def _key_variants(token: str) -> List[str]:
    keys = {token}
    if token.startswith("./"):
        keys.add(token[2:])
    if token.startswith("/"):
        keys.add(token[1:])
    if token.endswith(".pug"):
        keys.add(token[:-4])
    else:
        keys.add(token + ".pug")
    return sorted(keys)


@dataclass(frozen=True)
class Case:
    suite: str
    name: str
    pug_src: str
    expected_html: str
    deps: List[Tuple[str, str]]  # (registry_key, template_src)


def _collect_deps(
    *,
    suite_dir: Path,
    entry_file: Path,
    entry_src: str,
) -> Tuple[List[Tuple[str, str]], Optional[str]]:
    # Returns (registrations, skip_reason). Registrations include transitive deps.
    # We register multiple keys per include token to tolerate implementation-side
    # normalization.
    registrations: Dict[str, str] = {}
    visited_files: Set[Path] = set()

    def visit_file(file_path: Path, src: str) -> Optional[str]:
        visited_files.add(file_path.resolve())
        for m in _RE_INCLUDE_EXTENDS.finditer(src):
            token = _tokenize_path(m.group("rest"))
            if token is None:
                return "dynamic include/extends path"
            dep_file = _resolve_dep_file(
                suite_dir=suite_dir,
                from_file=file_path,
                token=token,
            )
            if dep_file is None:
                return f"missing dependency `{token}`"
            dep_src = dep_file.read_text(encoding="utf-8")
            for key in _key_variants(token):
                # Only keep the first registration for a key to be deterministic.
                registrations.setdefault(key, dep_src)
            rp = dep_file.resolve()
            if rp not in visited_files:
                reason = visit_file(dep_file, dep_src)
                if reason:
                    return reason
        return None

    reason = visit_file(entry_file, entry_src)
    if reason:
        return ([], reason)
    items = sorted(registrations.items(), key=lambda kv: kv[0])
    return (items, None)


def _load_cases(test_dir: Path) -> Tuple[List[Case], Dict[str, List[str]]]:
    cases: List[Case] = []
    report: Dict[str, List[str]] = {"generated": [], "skipped": []}

    for suite in ["cases", "cases-es2015"]:
        suite_dir = test_dir / suite
        if not suite_dir.is_dir():
            report["skipped"].append(f"{suite}: missing directory")
            continue

        for entry_file in sorted(suite_dir.glob("*.pug")):
            name = entry_file.stem
            key = f"{suite}/{name}"
            html_file = suite_dir / f"{name}.html"
            if not html_file.is_file():
                report["skipped"].append(f"{key}: missing .html fixture")
                continue

            pug_src = entry_file.read_text(encoding="utf-8")

            filter_reason = _has_unsupported_filter(pug_src)
            if filter_reason:
                report["skipped"].append(f"{key}: unsupported {filter_reason}")
                continue

            expected = _normalize_expected_html(html_file.read_text(encoding="utf-8"))

            deps, dep_reason = _collect_deps(
                suite_dir=suite_dir,
                entry_file=entry_file,
                entry_src=pug_src,
            )
            if dep_reason:
                report["skipped"].append(f"{key}: {dep_reason}")
                continue

            cases.append(
                Case(
                    suite=suite,
                    name=name,
                    pug_src=pug_src,
                    expected_html=expected,
                    deps=deps,
                )
            )
            report["generated"].append(key)

    return cases, report


def _emit_mbt(cases: List[Case], ref: str) -> str:
    header = "\n".join(
        [
            "// ============================================================================ ",
            "// AUTO-GENERATED FILE - DO NOT MODIFY MANUALLY",
            "// Generated by: pug/scripts_priv_test/generate_tests_from_pugjs.py",
            "// Source: https://github.com/pugjs/pug/tree/master/packages/pug/test",
            f"// Ref: {ref}",
            "// ============================================================================ ",
            "",
            "///|",
            "fn pugjs_default_locals() -> Locals {",
            '  let locals = Locals::new()',
            '  locals.set(\"title\", \"Pug\")',
            "  locals",
            "}",
            "",
        ]
    )

    blocks: List[str] = [header]
    for c in cases:
        test_name = f"pug/pugjs/{c.suite}/{c.name}"
        lines = ["///|", f'test "{test_name}" {{']
        lines.append("  let locals = pugjs_default_locals()")
        lines.append("  let registry = TemplateRegistry::new()")
        for key, dep_src in c.deps:
            lines.append("  registry.register(")
            lines.append(f'    "{key}",')
            lines.extend(_moon_string_expr_lines(dep_src, base_indent="    "))
            lines.append("  )")
        lines.append("  let pug =")
        lines.extend(_moon_multiline_let_string_lines(c.pug_src, base_indent="    "))
        lines.append("  inspect(")
        lines.append("    render_with_registry(pug, locals, registry).trim(),")
        lines.append("    content=(")
        lines.extend(_moon_hashpipe_lines(c.expected_html, base_indent="      "))
        lines.append("    ),")
        lines.append("  )")
        lines.append("}")
        blocks.append("\n".join(lines))
    return "\n\n".join(blocks) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="master", help="GitHub ref (default: master).")
    ap.add_argument("--out", type=Path, default=OUT_MBT)
    ap.add_argument("--report", type=Path, default=OUT_REPORT)
    args = ap.parse_args()

    url = _codeload_url(args.ref)
    tarball = CACHE_DIR / f"pugjs-pug-{args.ref.replace('/', '_')}.tar.gz"
    if not tarball.exists():
        _download(url, tarball)

    with tempfile.TemporaryDirectory(prefix="pugjs-pug-") as tmp:
        test_dir = _extract_test_dir(tarball, Path(tmp))
        cases, report = _load_cases(test_dir)

    args.out.write_text(_emit_mbt(cases, args.ref), encoding="utf-8")
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
