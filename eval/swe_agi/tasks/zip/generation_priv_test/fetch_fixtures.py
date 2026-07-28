#!/usr/bin/env python3
"""Build the maintainer-only ZIP corpus used to generate benchmark tests."""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
# Corpus construction stays under the excluded generation directory. This keeps
# source selection and hidden fixture provenance out of the agent workspace.
FIXTURES_DIR = ROOT / "generation_priv_test" / "fixtures"
SOURCES_DIR = FIXTURES_DIR / "sources"
MANIFEST_PATH = FIXTURES_DIR / "manifest.json"

TARGET_COUNT = 1000
MAX_MAVEN_JAR_BYTES = 5_000_000
MAX_ARTIFACTS_PER_GROUP = 80
MAX_VERSIONS_PER_ARTIFACT = 20
MAVEN_CLASSIFIERS = ["", "-sources", "-javadoc"]

GIT_SOURCES = [
  {
    "name": "cpython",
    "url": "https://github.com/python/cpython",
    "subdirs": ["Lib/test/ziptestdata"],
  },
  {
    "name": "golang",
    "url": "https://github.com/golang/go",
    "subdirs": ["src/archive/zip/testdata"],
  },
  {
    "name": "libzip",
    "url": "https://github.com/nih-at/libzip",
    "subdirs": ["regress", "tests", "src"],
  },
  {
    "name": "libarchive",
    "url": "https://github.com/libarchive/libarchive",
    "subdirs": ["libarchive/test"],
  },
  {
    "name": "zip-rs",
    "url": "https://github.com/zip-rs/zip",
    "subdirs": ["tests", "testdata"],
  },
]

MAVEN_GROUPS = [
  "org/apache/commons",
  "org/apache/httpcomponents",
  "org/apache/logging/log4j",
  "org/apache/lucene",
  "org/apache/ant",
]

MAVEN_BASE = "https://repo1.maven.org/maven2"

ZIP_EXTS = {".zip", ".jar", ".ZIP", ".JAR"}
NONZIP_DIR = SOURCES_DIR / "manual" / "nonzip"
SOURCE_URLS = {repo["name"]: repo["url"] for repo in GIT_SOURCES}


def run(cmd: list[str]) -> None:
  subprocess.run(cmd, check=True)


def sha256(path: Path) -> str:
  h = hashlib.sha256()
  with path.open("rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
      h.update(chunk)
  return h.hexdigest()


def is_zip_path(path: Path) -> bool:
  return path.suffix in ZIP_EXTS


def list_dirs(url: str) -> list[str]:
  with urllib.request.urlopen(url) as resp:
    html = resp.read().decode("utf-8", "replace")
  dirs = re.findall(r'href="([^"]+/)"', html)
  return [d for d in dirs if d not in ("../", "./")]


def fetch_url(url: str, dest: Path) -> bool:
  dest.parent.mkdir(parents=True, exist_ok=True)
  if dest.exists():
    return True
  try:
    with urllib.request.urlopen(url) as resp, dest.open("wb") as f:
      shutil.copyfileobj(resp, f)
    return True
  except Exception:
    if dest.exists():
      dest.unlink()
    return False


def iter_repo_files(repo_dir: Path, subdirs: Iterable[str]) -> list[Path]:
  files: list[Path] = []
  for subdir in subdirs:
    root = repo_dir / subdir
    if not root.exists():
      continue
    for path in root.rglob("*"):
      if path.is_file() and is_zip_path(path):
        files.append(path)
  return files


def load_existing_fixtures() -> tuple[list[dict], set[str]]:
  fixtures: list[dict] = []
  seen: set[str] = set()
  if not SOURCES_DIR.exists():
    return fixtures, seen
  for path in SOURCES_DIR.rglob("*"):
    if not path.is_file():
      continue
    rel_to_sources = path.relative_to(SOURCES_DIR)
    include_nonzip = rel_to_sources.parts[:2] == ("manual", "nonzip")
    if not (is_zip_path(path) or include_nonzip):
      continue
    rel_path = str(path.relative_to(ROOT))
    parts = path.relative_to(SOURCES_DIR).parts
    if len(parts) < 2:
      continue
    source = parts[0]
    origin = SOURCE_URLS.get(source, "")
    if source == "maven" and len(parts) >= 5:
      group = "/".join(parts[1:-3])
      artifact = parts[-3]
      version = parts[-2]
      filename = parts[-1]
      origin = f"{MAVEN_BASE}/{group}/{artifact}/{version}/{filename}"
    fixtures.append({
      "path": rel_path,
      "source": source,
      "origin": origin,
      "broken": include_nonzip,
    })
    seen.add(rel_path)
  return fixtures, seen


def copy_repo_fixtures(repo: dict, fixtures: list[dict], seen: set[str]) -> None:
  # Keep downloaded repositories in the project-local scratch directory so the
  # corpus construction is inspectable and easy to clean up.
  repo_dir = ROOT / ".tmp" / "zip-fixtures" / repo["name"]
  if not repo_dir.exists():
    repo_dir.parent.mkdir(parents=True, exist_ok=True)
    run(["git", "clone", "--depth", "1", repo["url"], str(repo_dir)])
  files = iter_repo_files(repo_dir, repo["subdirs"])
  for path in files:
    rel = path.relative_to(repo_dir)
    dest = SOURCES_DIR / repo["name"] / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
      shutil.copy2(path, dest)
    rel_path = str(dest.relative_to(ROOT))
    if rel_path in seen:
      continue
    fixtures.append({
      "path": rel_path,
      "source": repo["name"],
      "origin": repo["url"],
      "broken": False,
    })
    seen.add(rel_path)


def parse_versions(metadata_xml: bytes) -> list[str]:
  versions: list[str] = []
  root = ET.fromstring(metadata_xml)
  for version in root.findall("./versioning/versions/version"):
    if version.text:
      versions.append(version.text.strip())
  return versions


def download_maven_jars(fixtures: list[dict], seen: set[str], target_count: int) -> None:
  needed = max(target_count - len(fixtures), 0)
  if needed == 0:
    return

  candidates: list[tuple[str, Path]] = []
  for group in MAVEN_GROUPS:
    if len(candidates) >= needed:
      break
    group_url = f"{MAVEN_BASE}/{group}/"
    try:
      artifacts = sorted(list_dirs(group_url))
    except Exception:
      continue
    for artifact in artifacts[:MAX_ARTIFACTS_PER_GROUP]:
      if len(candidates) >= needed:
        break
      artifact = artifact.rstrip("/")
      metadata_url = f"{group_url}{artifact}/maven-metadata.xml"
      try:
        with urllib.request.urlopen(metadata_url) as resp:
          versions = parse_versions(resp.read())
      except Exception:
        continue
      if len(versions) > MAX_VERSIONS_PER_ARTIFACT:
        versions = versions[-MAX_VERSIONS_PER_ARTIFACT:]
      for version in versions:
        if len(candidates) >= needed:
          break
        for classifier in MAVEN_CLASSIFIERS:
          if len(candidates) >= needed:
            break
          jar_name = f"{artifact}-{version}{classifier}.jar"
          jar_url = f"{group_url}{artifact}/{version}/{jar_name}"
          dest = SOURCES_DIR / "maven" / group / artifact / version / jar_name
          rel_path = str(dest.relative_to(ROOT))
          if rel_path in seen:
            continue
          candidates.append((jar_url, dest))

  if not candidates:
    return

  with ThreadPoolExecutor(max_workers=32) as executor:
    future_map = {
      executor.submit(fetch_url, url, dest): (url, dest)
      for url, dest in candidates
    }
    for future in as_completed(future_map):
      url, dest = future_map[future]
      ok = future.result()
      if not ok:
        continue
      if dest.stat().st_size > MAX_MAVEN_JAR_BYTES:
        dest.unlink()
        continue
      rel_path = str(dest.relative_to(ROOT))
      fixtures.append({
        "path": rel_path,
        "source": "maven",
        "origin": url,
        "broken": False,
      })
      seen.add(rel_path)
      if len(fixtures) >= target_count:
        break


def add_nonzip_fixtures(fixtures: list[dict], seen: set[str]) -> None:
  NONZIP_DIR.mkdir(parents=True, exist_ok=True)
  samples = {
    "plain.txt": "This is not a zip archive.\n",
    "note.md": "# Not a zip\n\nJust a markdown file.\n",
    "data.json": "{\"not\": \"a zip\", \"ok\": true}\n",
    "config.ini": "key=value\n",
    "random.bin": bytes([0x00, 0x13, 0x37, 0x42, 0x7f, 0x80, 0xff]),
    "empty.bin": b"",
  }
  for name, content in samples.items():
    path = NONZIP_DIR / name
    if not path.exists():
      if isinstance(content, bytes):
        path.write_bytes(content)
      else:
        path.write_text(content, encoding="utf-8")
    rel_path = str(path.relative_to(ROOT))
    if rel_path in seen:
      continue
    fixtures.append({
      "path": rel_path,
      "source": "manual",
      "origin": "",
      "broken": True,
    })
    seen.add(rel_path)


def build_manifest(fixtures: list[dict]) -> None:
  entries = []
  broken_markers = ("bad", "broken", "corrupt", "invalid", "trunc", "damage")
  for item in fixtures:
    path = ROOT / item["path"]
    if not path.exists():
      continue
    name_lower = path.name.lower()
    explicit_broken = item.get("broken")
    entries.append({
      "path": item["path"],
      "source": item["source"],
      "origin": item["origin"],
      "size": path.stat().st_size,
      "sha256": sha256(path),
      "broken": explicit_broken if explicit_broken is not None else any(m in name_lower for m in broken_markers),
    })
  manifest = {
    "count": len(entries),
    "entries": entries,
  }
  MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
  with MANIFEST_PATH.open("w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)


def main() -> int:
  SOURCES_DIR.mkdir(parents=True, exist_ok=True)
  fixtures, seen = load_existing_fixtures()

  for repo in GIT_SOURCES:
    copy_repo_fixtures(repo, fixtures, seen)

  add_nonzip_fixtures(fixtures, seen)

  download_maven_jars(fixtures, seen, TARGET_COUNT)

  build_manifest(fixtures)

  print(f"Fetched {len(fixtures)} fixtures (target {TARGET_COUNT}).")
  print(f"Manifest written to {MANIFEST_PATH}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
