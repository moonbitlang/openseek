// Decoding a downloaded skill archive into the files an install writes:
// the SKILL.md instructions plus any supporting files, as validated
// library-relative paths. The archive's bytes were already verified against
// the registry's digest; this half guards the extraction — per-entry CRCs,
// wrapper stripping, and path safety.

///|
/// The instruction file every skill archive must carry at its root.
const SkillFile = "SKILL.md"

///|
/// The decoded contents of one skill archive. `files` holds every entry to
/// stage — SKILL.md included — while `skill_md` gives the instructions their
/// own handle for frontmatter parsing and preview.
priv struct SkillArchive {
  skill_md : Bytes
  files : Map[String, Bytes]
}

///|
/// Decode the members of one skill archive. Publishers may zip the skill's
/// files directly or a single wrapping directory; the wrapper is stripped so
/// the SKILL.md always lands at the installed root. Every payload is checked
/// against its stored CRC-32 and every path validated as a safe relative
/// path, so a corrupt or hostile archive can neither smuggle bad data nor
/// escape the staged directory.
fn skill_files(
  archive : @zip.Archive,
  entry : String,
) -> SkillArchive raise SkillMarketError {
  let members : Array[(String, Bytes)] = []
  for item in archive.entries() {
    let name = item.name()
    if name.has_suffix("/") {
      // Directory placeholders carry no data; directories are recreated from
      // file paths at staging time.
      continue
    }
    guard @checksum.crc32(item.data()) == item.crc32() else {
      raise SkillMarketError(
        "the archive for \{entry} is corrupt: \{name} fails its checksum",
      )
    }
    members.push((name, item.data().to_owned()))
  }
  let prefix = wrapper_prefix(members, entry)
  let files : Map[String, Bytes] = Map([])
  let mut skill_md : Bytes? = None
  for item in members {
    let (name, content) = item
    guard name.strip_prefix(prefix) is Some(relative) else { continue }
    let relative = relative.to_owned()
    guard safe_archive_path(relative) else {
      raise SkillMarketError(
        "the archive for \{entry} contains an unsafe path: \{name}",
      )
    }
    if relative == SidecarFile {
      // The provenance sidecar is this library's own record; an archive can
      // never supply it.
      continue
    }
    // Duplicate names are a classic parser-differential vector; refuse them
    // rather than letting the last occurrence win silently.
    guard !files.contains(relative) else {
      raise SkillMarketError(
        "the archive for \{entry} names \{relative} more than once",
      )
    }
    if relative == SkillFile {
      skill_md = Some(content)
    }
    files[relative] = content
  }
  guard skill_md is Some(skill_md) else {
    raise SkillMarketError(
      "the archive for \{entry} does not contain a SKILL.md",
    )
  }
  { skill_md, files, }
}

///|
/// The directory prefix to strip from every archive entry: `""` when the SKILL.md
/// sits at the archive root, `"<dir>/"` when all members share one wrapping
/// directory that carries it. Anything else is not a skill archive.
fn wrapper_prefix(
  members : Array[(String, Bytes)],
  entry : String,
) -> String raise SkillMarketError {
  for item in members {
    if item.0 == SkillFile {
      return ""
    }
  }
  let mut wrapper : String? = None
  for item in members {
    guard item.0.split_once("/") is Some((top, rest)) && !rest.is_empty() else {
      wrapper = None
      break
    }
    let top = top.to_owned()
    match wrapper {
      None => wrapper = Some(top)
      Some(existing) =>
        if existing != top {
          wrapper = None
          break
        }
    }
  }
  if wrapper is Some(wrapper) {
    for item in members {
      if item.0 == "\{wrapper}/\{SkillFile}" {
        return "\{wrapper}/"
      }
    }
  }
  raise SkillMarketError("the archive for \{entry} does not contain a SKILL.md")
}

///|
/// Whether `path` can safely be written below the staged skill directory:
/// `/`-separated non-empty segments, no `.` or `..`, and none of the
/// characters that switch directories or drives on any supported platform.
fn safe_archive_path(path : String) -> Bool {
  if path.is_empty() || path.length() > 512 {
    return false
  }
  for segment in path.split("/") {
    let segment = segment.to_owned()
    if segment.is_empty() || segment == "." || segment == ".." {
      return false
    }
    for ch in segment {
      if ch is ('\\' | ':' | '\u{0}') {
        return false
      }
    }
  }
  true
}

///|
test "skill files accept a flat archive and skip a smuggled sidecar" {
  let archive = @zip.Archive::Archive()
  archive.add("SKILL.md", b"instructions")
  archive.add("reference/usage.md", b"notes")
  archive.add(".mooncakes.json", b"{\"module\":\"fake\"}")
  archive.add("reference/", b"")
  let skill = skill_files(archive, "acme/widget@1.0.0")
  assert_eq(skill.skill_md, b"instructions")
  assert_eq(skill.files.keys().collect(), ["SKILL.md", "reference/usage.md"])
}

///|
test "an archive naming one path twice is refused" {
  let archive = @zip.Archive::Archive()
  archive.add("SKILL.md", b"one")
  archive.add("SKILL.md", b"two")
  try {
    let _ = skill_files(archive, "acme/widget@1.0.0")
    fail("duplicate archive entries must be refused")
  } catch {
    SkillMarketError(message) => assert_true(message.contains("more than once"))
    error => raise error
  }
}

///|
test "skill files strip a single wrapping directory" {
  let archive = @zip.Archive::Archive()
  archive.add("widget/SKILL.md", b"instructions")
  archive.add("widget/scripts/run.sh", b"echo")
  let skill = skill_files(archive, "acme/widget@1.0.0")
  assert_eq(skill.skill_md, b"instructions")
  assert_eq(skill.files.keys().collect(), ["SKILL.md", "scripts/run.sh"])
}

///|
test "an archive without a SKILL.md is refused" {
  let archive = @zip.Archive::Archive()
  archive.add("README.md", b"no instructions")
  try {
    let _ = skill_files(archive, "acme/widget@1.0.0")
    fail("an archive without a SKILL.md must be refused")
  } catch {
    SkillMarketError(message) =>
      assert_true(message.contains("does not contain a SKILL.md"))
    error => raise error
  }
  // Two top-level directories are not a single wrapper either.
  let archive = @zip.Archive::Archive()
  archive.add("one/SKILL.md", b"a")
  archive.add("two/other.md", b"b")
  try {
    let _ = skill_files(archive, "acme/widget@1.0.0")
    fail("a multi-root archive must be refused")
  } catch {
    SkillMarketError(_) => ()
    error => raise error
  }
}

///|
test "an archive with an unsafe entry path is refused" {
  let archive = @zip.Archive::Archive()
  archive.add("SKILL.md", b"instructions")
  archive.add("../evil.md", b"escape")
  try {
    let _ = skill_files(archive, "acme/widget@1.0.0")
    fail("a path-escaping archive must be refused")
  } catch {
    SkillMarketError(message) => assert_true(message.contains("unsafe path"))
    error => raise error
  }
}

///|
test "archive path safety rejects everything that could leave the staging dir" {
  assert_true(safe_archive_path("SKILL.md"))
  assert_true(safe_archive_path("reference/usage.md"))
  assert_false(safe_archive_path(""))
  assert_false(safe_archive_path("/etc/passwd"))
  assert_false(safe_archive_path("../evil.md"))
  assert_false(safe_archive_path("a/../b.md"))
  assert_false(safe_archive_path("a/./b.md"))
  assert_false(safe_archive_path("a//b.md"))
  assert_false(safe_archive_path("a\\b.md"))
  assert_false(safe_archive_path("C:evil.md"))
}
