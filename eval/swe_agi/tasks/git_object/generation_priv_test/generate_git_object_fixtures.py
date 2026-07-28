#!/usr/bin/env python3
import argparse
import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zlib
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
OBJECTS_DIR = ROOT / "fixtures" / "objects"
EXPECTED_DIR = ROOT / "fixtures" / "expected"
INVALID_DIR = ROOT / "fixtures" / "invalid"
INDEX_PATH = ROOT / "fixtures" / "index.json"

DEFAULT_REPO = Path.home() / "Workspace" / "git"
TOTAL_TESTS = 1000
SHA1_MISMATCH = 20
MAX_SIZE = 65536
QUOTAS = {
    "blob": 450,
    "tree": 300,
    "commit": 200,
    "tag": 50,
}


def run_git(
    repo: Path,
    args: List[str],
    input_bytes: Optional[bytes] = None,
    env_overrides: Optional[Dict[str, str]] = None,
) -> bytes:
    env = os.environ.copy()
    env["GIT_OPTIONAL_LOCKS"] = "0"
    if env_overrides:
        env.update(env_overrides)
    proc = subprocess.run(
        ["git", "-C", str(repo), *args],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr.decode("utf-8", errors="replace"))
        raise RuntimeError(f"git {' '.join(args)} failed with {proc.returncode}")
    return proc.stdout


def list_objects(repo: Path, max_size: int) -> List[Tuple[str, str, int]]:
    out = run_git(
        repo,
        [
            "cat-file",
            "--batch-all-objects",
            "--batch-check=%(objectname) %(objecttype) %(objectsize)",
        ],
    )
    entries: List[Tuple[str, str, int]] = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) != 3:
            continue
        oid = parts[0].decode("ascii")
        kind = parts[1].decode("ascii")
        size = int(parts[2])
        if kind not in QUOTAS:
            continue
        if size > max_size:
            continue
        entries.append((oid, kind, size))
    return entries


def select_objects(entries: List[Tuple[str, str, int]], total: int) -> List[Tuple[str, str, int]]:
    by_type: Dict[str, List[Tuple[str, str, int]]] = {k: [] for k in QUOTAS}
    for entry in entries:
        by_type[entry[1]].append(entry)
    for kind in by_type:
        by_type[kind].sort(key=lambda item: item[0])

    selected: List[Tuple[str, str, int]] = []
    for kind, quota in QUOTAS.items():
        selected.extend(by_type[kind][:quota])

    if len(selected) > total:
        selected = selected[:total]
        return selected

    selected_oids = {entry[0] for entry in selected}
    pool: List[Tuple[str, str, int]] = []
    for kind in by_type:
        pool.extend([entry for entry in by_type[kind] if entry[0] not in selected_oids])
    pool.sort(key=lambda item: item[0])
    remaining = total - len(selected)
    if remaining > 0:
        selected.extend(pool[:remaining])

    if len(selected) < total:
        raise RuntimeError("Not enough objects to satisfy test count")
    return selected


def parse_batch(output: bytes) -> Dict[str, Tuple[str, int, bytes]]:
    result: Dict[str, Tuple[str, int, bytes]] = {}
    i = 0
    length = len(output)
    while i < length:
        line_end = output.find(b"\n", i)
        if line_end == -1:
            break
        header = output[i:line_end]
        i = line_end + 1
        if not header:
            continue
        parts = header.split()
        if len(parts) < 3:
            raise RuntimeError(f"Unexpected batch header: {header!r}")
        oid = parts[0].decode("ascii")
        kind = parts[1].decode("ascii")
        size = int(parts[2])
        content = output[i : i + size]
        i += size
        if i < length and output[i : i + 1] == b"\n":
            i += 1
        result[oid] = (kind, size, content)
    return result


def mutate_oid(oid: str) -> str:
    if oid[-1] != "0":
        return oid[:-1] + "0"
    return oid[:-1] + "1"


def loose_object_path(oid: str) -> Path:
    return OBJECTS_DIR / oid[:2] / oid[2:]


def decode_text(data: bytes) -> Optional[str]:
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def kind_from_mode(mode: str) -> str:
    if mode == "40000":
        return "tree"
    if mode in {"100644", "100755", "120000"}:
        return "blob"
    if mode == "160000":
        return "commit"
    return "unknown"


def parse_tree_entries(data: bytes) -> List[Dict]:
    entries: List[Dict] = []
    i = 0
    while i < len(data):
        space = data.find(b" ", i)
        if space == -1:
            raise RuntimeError("Malformed tree entry: missing space")
        mode = data[i:space].decode("ascii")
        i = space + 1
        nul = data.find(b"\x00", i)
        if nul == -1:
            raise RuntimeError("Malformed tree entry: missing NUL")
        name_bytes = data[i:nul]
        name = name_bytes.decode("utf-8", errors="replace")
        i = nul + 1
        oid_bytes = data[i : i + 20]
        if len(oid_bytes) != 20:
            raise RuntimeError("Malformed tree entry: short oid")
        i += 20
        entries.append(
            {
                "mode": mode.rjust(6, "0"),
                "kind": kind_from_mode(mode),
                "oid": oid_bytes.hex(),
                "name": name,
            }
        )
    return entries


def split_headers_message(text: str) -> Tuple[List[str], str]:
    sep = "\n\n"
    if sep in text:
        headers_text, message = text.split(sep, 1)
        headers = headers_text.split("\n") if headers_text else []
        return headers, message
    headers = text.split("\n") if text else []
    return headers, ""


def init_t_repo(repo: Path) -> None:
    if repo.exists():
        shutil.rmtree(repo)
    repo.mkdir(parents=True)
    run_git(repo, ["init", "--quiet"])
    run_git(repo, ["config", "user.name", "Spec Tester"])
    run_git(repo, ["config", "user.email", "spec@example.com"])


def build_t_objects(repo: Path) -> List[Dict[str, str]]:
    init_t_repo(repo)
    hello_content = "Hello World"
    example_content = "This is an example"
    (repo / "hello").write_text(hello_content, encoding="utf-8")
    (repo / "example").write_text(example_content, encoding="utf-8")
    (repo / "path with spaces").write_text(hello_content, encoding="utf-8")
    run_git(repo, ["update-index", "--add", "hello"])
    run_git(repo, ["update-index", "--add", "example"])
    run_git(repo, ["update-index", "--add", "--chmod=+x", "path with spaces"])

    env = {
        "GIT_AUTHOR_NAME": "Spec Tester",
        "GIT_AUTHOR_EMAIL": "spec@example.com",
        "GIT_AUTHOR_DATE": "1234567890 +0000",
        "GIT_COMMITTER_NAME": "Spec Tester",
        "GIT_COMMITTER_EMAIL": "spec@example.com",
        "GIT_COMMITTER_DATE": "1234567890 +0000",
    }

    hello_oid = run_git(repo, ["hash-object", "-w", "hello"]).strip().decode("ascii")
    example_oid = run_git(repo, ["hash-object", "-w", "example"]).strip().decode("ascii")
    tree_oid = run_git(repo, ["write-tree"]).strip().decode("ascii")
    commit_message = "Initial commit"
    commit_oid = run_git(
        repo,
        ["commit-tree", tree_oid],
        input_bytes=(commit_message + "\n").encode("utf-8"),
        env_overrides=env,
    ).strip().decode("ascii")

    tag_content = (
        f"object {hello_oid}\n"
        "type blob\n"
        "tag hellotag\n"
        "tagger Spec Tester <spec@example.com> 1234567890 +0000\n"
        "\n"
        "This is a tag"
    )
    tag_oid = run_git(
        repo,
        ["hash-object", "-t", "tag", "--stdin", "-w"],
        input_bytes=tag_content.encode("utf-8"),
    ).strip().decode("ascii")

    return [
        {"oid": hello_oid, "source": "t/t1006-cat-file.sh"},
        {"oid": tree_oid, "source": "t/t1006-cat-file.sh"},
        {"oid": commit_oid, "source": "t/t1006-cat-file.sh"},
        {"oid": tag_oid, "source": "t/t1006-cat-file.sh"},
        {"oid": hello_oid, "source": "t/t1007-hash-object.sh"},
        {"oid": example_oid, "source": "t/t1007-hash-object.sh"},
    ]


def build_invalid_cases() -> List[Dict[str, object]]:
    cases: List[Dict[str, object]] = []
    cases.append(
        {
            "name": "invalid_zlib",
            "bytes": b"not a zlib stream",
            "error": "InvalidZlib",
        }
    )
    cases.append(
        {
            "name": "invalid_header_missing_nul",
            "bytes": zlib.compress(b"blob 3abc", level=6),
            "error": "InvalidHeader",
        }
    )
    cases.append(
        {
            "name": "invalid_header_missing_space",
            "bytes": zlib.compress(b"blob3\x00abc", level=6),
            "error": "InvalidHeader",
        }
    )
    cases.append(
        {
            "name": "invalid_size_too_small",
            "bytes": zlib.compress(b"blob 2\x00abc", level=6),
            "error": "InvalidSize",
        }
    )
    cases.append(
        {
            "name": "invalid_size_too_large",
            "bytes": zlib.compress(b"blob 5\x00abc", level=6),
            "error": "InvalidSize",
        }
    )
    return cases


def build_expected(
    oid: str,
    kind: str,
    size: int,
    content: bytes,
    sha1_ok: bool,
) -> dict:
    if kind == "blob":
        text = decode_text(content)
        return {
            "oid": oid,
            "kind": kind,
            "size": size,
            "sha1_ok": sha1_ok,
            "content": {
                "type": "blob",
                "base64": base64.b64encode(content).decode("ascii"),
                "text": text,
            },
        }
    if kind == "tree":
        return {
            "oid": oid,
            "kind": kind,
            "size": size,
            "sha1_ok": sha1_ok,
            "content": {
                "type": "tree",
                "entries": parse_tree_entries(content),
            },
        }
    if kind in {"commit", "tag"}:
        text = content.decode("utf-8", errors="replace")
        headers, message = split_headers_message(text)
        return {
            "oid": oid,
            "kind": kind,
            "size": size,
            "sha1_ok": sha1_ok,
            "content": {
                "type": kind,
                "headers": headers,
                "message": message,
            },
        }
    return {
        "oid": oid,
        "kind": kind,
        "size": size,
        "sha1_ok": sha1_ok,
        "content": {
            "type": kind,
            "base64": base64.b64encode(content).decode("ascii"),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--git-repo",
        type=Path,
        default=DEFAULT_REPO,
        help="Path to the official git source repo",
    )
    parser.add_argument(
        "--total",
        type=int,
        default=TOTAL_TESTS,
        help="Total number of tests to generate",
    )
    parser.add_argument(
        "--sha1-mismatch",
        type=int,
        default=SHA1_MISMATCH,
        help="Number of tests to use mismatched expected OIDs",
    )
    parser.add_argument(
        "--max-size",
        type=int,
        default=MAX_SIZE,
        help="Maximum object size to include",
    )
    args = parser.parse_args()

    repo = args.git_repo
    t_repo = ROOT / "fixtures" / "t-repo"
    t_cases = build_t_objects(t_repo)
    t_oids = {entry["oid"] for entry in t_cases}
    invalid_cases = build_invalid_cases()

    entries = list_objects(repo, args.max_size)
    entries = [entry for entry in entries if entry[0] not in t_oids]
    base_total = args.total - len(t_cases) - len(invalid_cases)
    if base_total < 0:
        raise RuntimeError("Total test count is smaller than t/ + invalid fixture count")
    selected = select_objects(entries, base_total)

    oids = [entry[0] for entry in selected]
    batch = run_git(repo, ["cat-file", "--batch"], ("\n".join(oids) + "\n").encode("ascii"))
    raw_objects = parse_batch(batch)

    t_oids_list = [entry["oid"] for entry in t_cases]
    t_batch = run_git(
        t_repo,
        ["cat-file", "--batch"],
        ("\n".join(t_oids_list) + "\n").encode("ascii"),
    )
    t_raw_objects = parse_batch(t_batch)

    OBJECTS_DIR.mkdir(parents=True, exist_ok=True)
    EXPECTED_DIR.mkdir(parents=True, exist_ok=True)
    INVALID_DIR.mkdir(parents=True, exist_ok=True)

    mismatch_count = min(args.sha1_mismatch, len(selected))
    mismatch_set = {entry[0] for entry in selected[:mismatch_count]}

    index_entries: List[Dict] = []
    invalid_entries: List[Dict] = []
    def add_entry(
        idx: int,
        oid: str,
        kind: str,
        size: int,
        content: bytes,
        sha1_ok: bool,
        expected_oid: str,
        source: Optional[str],
    ) -> None:
        header = f"{kind} {size}\x00".encode("ascii")
        data = header + content
        computed = hashlib.sha1(data).hexdigest()
        if computed != oid:
            raise RuntimeError(f"SHA-1 mismatch for {oid}: {computed}")

        object_path = loose_object_path(oid)
        object_path.parent.mkdir(parents=True, exist_ok=True)
        object_path.write_bytes(zlib.compress(data, level=6))

        expected = build_expected(oid, kind, size, content, sha1_ok)
        expected_path = EXPECTED_DIR / f"test_{idx:04d}_{oid}.json"
        expected_path.write_text(
            json.dumps(expected, indent=2, sort_keys=True, ensure_ascii=True) + "\n",
            encoding="utf-8",
        )

        entry: Dict[str, object] = {
            "id": idx,
            "oid": oid,
            "kind": kind,
            "expected_oid": expected_oid,
            "sha1_ok": sha1_ok,
            "fixture": f"fixtures/objects/{oid[:2]}/{oid[2:]}",
            "expected": f"fixtures/expected/test_{idx:04d}_{oid}.json",
        }
        if source:
            entry["source"] = source
        index_entries.append(entry)

    idx = 0
    for case in t_cases:
        oid = case["oid"]
        raw = t_raw_objects.get(oid)
        if raw is None:
            raise RuntimeError(f"Missing t/ batch output for {oid}")
        raw_kind, raw_size, content = raw
        add_entry(
            idx=idx,
            oid=oid,
            kind=raw_kind,
            size=raw_size,
            content=content,
            sha1_ok=True,
            expected_oid=oid,
            source=case["source"],
        )
        idx += 1

    for oid, kind, size in selected:
        raw = raw_objects.get(oid)
        if raw is None:
            raise RuntimeError(f"Missing batch output for {oid}")
        raw_kind, raw_size, content = raw
        if raw_kind != kind or raw_size != size:
            raise RuntimeError(f"Metadata mismatch for {oid}")

        expected_oid = oid
        sha1_ok = True
        if oid in mismatch_set:
            expected_oid = mutate_oid(oid)
            sha1_ok = False

        add_entry(
            idx=idx,
            oid=oid,
            kind=raw_kind,
            size=raw_size,
            content=content,
            sha1_ok=sha1_ok,
            expected_oid=expected_oid,
            source=None,
        )
        idx += 1

    for inv_idx, case in enumerate(invalid_cases):
        name = case["name"]
        payload = case["bytes"]
        error_type = case["error"]
        fixture_path = INVALID_DIR / f"{name}.bin"
        fixture_path.write_bytes(payload)
        expected = {"error": {"type": error_type}}
        expected_path = EXPECTED_DIR / f"invalid_{inv_idx:04d}_{name}.json"
        expected_path.write_text(
            json.dumps(expected, indent=2, sort_keys=True, ensure_ascii=True) + "\n",
            encoding="utf-8",
        )
        invalid_entries.append(
            {
                "id": inv_idx,
                "name": name,
                "error": error_type,
                "fixture": f"fixtures/invalid/{name}.bin",
                "expected": f"fixtures/expected/invalid_{inv_idx:04d}_{name}.json",
            }
        )

    INDEX_PATH.write_text(
        json.dumps(
            {
                "git_repo": str(repo),
                "max_size": args.max_size,
                "total": len(index_entries),
                "invalid_total": len(invalid_entries),
                "sha1_mismatch": mismatch_count,
                "entries": index_entries,
                "invalid_entries": invalid_entries,
            },
            indent=2,
            sort_keys=True,
            ensure_ascii=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(index_entries)} fixtures to {OBJECTS_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
