#!/usr/bin/env python3
"""Convert captured zipinfo output into structural JSON oracles."""

import json
import re
import struct
import zlib
from typing import Optional, Tuple, List
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES_DIR = ROOT / "generation_priv_test" / "fixtures"
RAW_DIR = FIXTURES_DIR / "zipinfo_raw"
INDEX_PATH = RAW_DIR / "index.json"
EXPECTED_DIR = FIXTURES_DIR / "expected"
EXPECTED_INDEX = EXPECTED_DIR / "index.json"

LISTING_RE = re.compile(
  r"^(\S+)\s+(\d+\.\d+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.+)$"
)
HEADER_RE = re.compile(r"^Zip file size: (\d+) bytes, number of entries: (\d+)")
SUMMARY_RE = re.compile(
  r"^(\d+) file(?:s)?, (\d+) bytes uncompressed, (\d+) bytes compressed: *([0-9.]+%)"
)
EOCD_SIG = b"PK\x05\x06"
ZIP64_LOCATOR_SIG = b"PK\x06\x07"
ZIP64_EOCD_SIG = b"PK\x06\x06"


def find_eocd(data: bytes) -> int:
  start = max(0, len(data) - (22 + 0xFFFF))
  index = data.rfind(EOCD_SIG, start)
  if index == -1:
    raise ValueError("EOCD not found")
  return index


def parse_zip64_eocd(data: bytes, eocd_offset: int) -> Optional[Tuple[int, int, int]]:
  locator_offset = eocd_offset - 20
  if locator_offset < 0:
    return None
  locator = data[locator_offset:locator_offset + 20]
  if len(locator) != 20 or locator[:4] != ZIP64_LOCATOR_SIG:
    return None
  _, _, zip64_eocd_offset, _ = struct.unpack("<4sIQI", locator)
  if zip64_eocd_offset < 0 or zip64_eocd_offset + 56 > len(data):
    return None
  record = data[zip64_eocd_offset:zip64_eocd_offset + 56]
  if record[:4] != ZIP64_EOCD_SIG:
    return None
  unpacked = struct.unpack("<4sQHHIIQQQQ", record)
  _, _, _, _, _, _, _, total_entries, cd_size, cd_offset = unpacked
  return int(cd_offset), int(total_entries), int(cd_size)


def iter_central_directory(data: bytes) -> List[Tuple[int, bytes, bytes]]:
  eocd_offset = find_eocd(data)
  eocd = data[eocd_offset:eocd_offset + 22]
  if len(eocd) < 22:
    raise ValueError("EOCD too short")
  _, _, _, _, total_entries, cd_size, cd_offset, _ = struct.unpack("<4sHHHHIIH", eocd)
  if total_entries == 0xFFFF or cd_size == 0xFFFFFFFF or cd_offset == 0xFFFFFFFF:
    zip64 = parse_zip64_eocd(data, eocd_offset)
    if zip64 is not None:
      cd_offset, total_entries, cd_size = zip64
  entries: list[tuple[int, bytes, bytes]] = []
  offset = cd_offset
  end = cd_offset + cd_size
  while offset < end:
    if data[offset:offset + 4] != b"PK\x01\x02":
      raise ValueError("central directory signature mismatch")
    header = data[offset:offset + 46]
    if len(header) < 46:
      raise ValueError("central directory header truncated")
    unpacked = struct.unpack("<4sHHHHHHIIIHHHHHII", header)
    _, _, _, flags, _, _, _, _, _, _, name_len, extra_len, comment_len, _, _, _, _ = unpacked
    name_start = offset + 46
    name_end = name_start + name_len
    extra_start = name_end
    extra_end = extra_start + extra_len
    comment_end = extra_end + comment_len
    if comment_end > len(data):
      raise ValueError("central directory entry exceeds file size")
    name_bytes = data[name_start:name_end]
    extra = data[extra_start:extra_end]
    entries.append((flags, name_bytes, extra))
    offset = comment_end
  if total_entries not in (0xFFFF, len(entries)) and len(entries) != total_entries:
    raise ValueError("central directory entry count mismatch")
  return entries


def unicode_path_from_extra(extra: bytes, name_bytes: bytes) -> Optional[str]:
  i = 0
  while i + 4 <= len(extra):
    header_id, size = struct.unpack("<HH", extra[i:i + 4])
    i += 4
    data = extra[i:i + size]
    i += size
    if header_id != 0x7075 or len(data) < 5:
      continue
    expected_crc = struct.unpack("<I", data[1:5])[0]
    if zlib.crc32(name_bytes) & 0xFFFFFFFF != expected_crc:
      continue
    try:
      return data[5:].decode("utf-8")
    except UnicodeDecodeError:
      return None
  return None


def decode_name(flags: int, name_bytes: bytes, extra: bytes) -> str:
  if flags & 0x800:
    return name_bytes.decode("utf-8", errors="replace")
  unicode_path = unicode_path_from_extra(extra, name_bytes)
  if unicode_path is not None:
    return unicode_path
  return name_bytes.decode("cp437", errors="replace")


def decode_archive_names(archive: str) -> List[str]:
  archive_path = Path(archive)
  if not archive_path.is_absolute():
    archive_path = ROOT / archive_path
  data = archive_path.read_bytes()
  entries = iter_central_directory(data)
  return [decode_name(flags, name_bytes, extra) for flags, name_bytes, extra in entries]


def normalize_lines(text: str) -> list[str]:
  lines: list[str] = []
  for raw in text.splitlines():
    line = raw.rstrip()
    if not line.strip():
      continue
    if line.startswith((" ", "\t")):
      if lines:
        lines[-1] = f"{lines[-1]} {line.strip()}"
      else:
        lines.append(line.strip())
      continue
    lines.append(line)
  return lines


def parse_zipinfo(text: str, fallback_archive: str, exit_code: int) -> dict:
  archive = fallback_archive
  entries: list[dict] = []
  summary = {
    "file_size": None,
    "entries": None,
    "uncompressed_size": None,
    "compressed_size": None,
    "compression_ratio": None,
  }

  for line in normalize_lines(text):
    stripped = line.strip()
    if stripped.startswith("Archive:"):
      archive = stripped.split(":", 1)[1].strip()
      continue
    if stripped.startswith("[") and stripped.endswith("]"):
      # Redundant filename marker emitted by zipinfo on some errors.
      continue
    if stripped.lower().startswith("there is no zipfile comment"):
      continue
    header = HEADER_RE.match(stripped)
    if header:
      summary["file_size"] = int(header.group(1))
      summary["entries"] = int(header.group(2))
      continue
    listing = LISTING_RE.match(stripped)
    if listing:
      entries.append({
        "name": listing.group(10),
        "mode": listing.group(1),
        "version": listing.group(2),
        "host_os": listing.group(3),
        "uncompressed_size": int(listing.group(4)),
        "attrs": listing.group(5),
        "compressed_size": int(listing.group(6)),
        "compression_method": listing.group(7),
        "mod_date": listing.group(8),
        "mod_time": listing.group(9),
      })
      continue
    summary_match = SUMMARY_RE.match(stripped)
    if summary_match:
      summary["entries"] = int(summary_match.group(1))
      summary["uncompressed_size"] = int(summary_match.group(2))
      summary["compressed_size"] = int(summary_match.group(3))
      summary["compression_ratio"] = summary_match.group(4)
      continue
    _ = stripped

  try:
    decoded_names = decode_archive_names(archive)
  except (OSError, ValueError):
    decoded_names = None
  if decoded_names is not None and len(decoded_names) == len(entries):
    for entry, name in zip(entries, decoded_names):
      entry["name"] = name

  invalid = exit_code != 0
  return {
    "archive": archive,
    "entries": entries,
    "summary": summary,
    "invalid": invalid,
  }


def main() -> int:
  if not INDEX_PATH.exists():
    raise SystemExit("Missing zipinfo_raw/index.json; run run_zipinfo.py first.")
  data = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
  entries = []
  for item in data.get("entries", []):
    fixture = Path(item["fixture"])
    raw_path = ROOT / item["raw"]
    exit_code = item.get("exit_code", 0)
    output = raw_path.read_text(encoding="utf-8")
    parsed = parse_zipinfo(output, str(fixture), exit_code)
    expected_path = EXPECTED_DIR / fixture
    expected_path = expected_path.with_suffix(expected_path.suffix + ".json")
    expected_path.parent.mkdir(parents=True, exist_ok=True)
    expected_path.write_text(json.dumps(parsed, indent=2, sort_keys=True), encoding="utf-8")
    entries.append({
      "fixture": str(fixture),
      "expected": str(expected_path.relative_to(ROOT)),
    })

  EXPECTED_INDEX.write_text(json.dumps({"entries": entries}, indent=2), encoding="utf-8")
  print(f"Parsed zipinfo output for {len(entries)} fixtures.")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
