// Adapt moonbit-community/skills to the OpenSeek skill catalog and
// transactional local library. The client owns registry JSON, HTTP, and
// download validation.

///|
/// Default standalone skills registry URL, overridable per call for tests.
const DefaultRegistry : String = "https://mooncakes.io"

///|
/// Keep documents passed to preview renderers bounded.
const MaxPreviewBytes : Int32 = 512 * 1024

///|
/// The staging decoder retains bounded, cancellation-aware extraction after
/// the client has validated the downloaded archive. Its ceilings scale with
/// packaged size; the client also applies the standalone registry's limits.
const ArchiveExpansionFloorBytes : Int32 = 256 * 1024 * 1024

///|
const ArchiveExpansionRatio : Int32 = 64

///|
const MaxArchiveEntries : Int32 = 65536

///|
/// Decompression ceilings for an archive of `package_bytes` packaged size.
fn archive_limits(package_bytes : Int32) -> @zip.ReadLimits {
  let saturation = 0x7fff_ffff / ArchiveExpansionRatio
  let scaled = if package_bytes >= saturation {
    0x7fff_ffff
  } else if package_bytes * ArchiveExpansionRatio > ArchiveExpansionFloorBytes {
    package_bytes * ArchiveExpansionRatio
  } else {
    ArchiveExpansionFloorBytes
  }
  ReadLimits(
    max_entries=MaxArchiveEntries,
    max_entry_uncompressed_bytes=scaled,
    max_total_uncompressed_bytes=scaled,
  )
}

///|
/// A registry or library failure with a user-facing message.
priv suberror SkillsError {
  SkillsError(String)
}

///|
impl Show for SkillsError with fn output(self, logger) {
  let SkillsError(message) = self
  logger.write_string(message)
}

///|
/// One standalone skill from the registry.
pub struct MarketSkill {
  /// Standalone skill name, matching SKILL.md frontmatter.
  name : String
  /// Owner/name skill identity (e.g. `moonbitlang/typst`).
  module_name : String
  /// Legacy subpackage path; always empty for standalone catalog rows.
  package_path : String
  /// Published version string.
  version : String
  /// Short one-line description from the catalog.
  description : String
  /// Registry owner/author name.
  author : String
  /// Source repository URL, if provided by the registry.
  repository : String?
}

///|
/// List independently published skills from `registry`.
pub async fn fetch_catalog(
  registry~ : String = DefaultRegistry,
) -> Array[MarketSkill] {
  let skills = @registry.Client(registry~).list() catch {
    error => raise SkillsError("skill catalog from \{registry}: \{error}")
  }
  skills.map(skill => {
    name: skill.name,
    module_name: "\{skill.owner}/\{skill.name}",
    package_path: "",
    version: skill.version,
    description: skill.description,
    author: skill.owner,
    // The standalone API does not expose a source repository.
    repository: None,
  })
}

///|
/// Source labels retain legacy subpackage paths when reading old sidecars.
fn entry_path(
  module_name : String,
  version : String,
  package_path : String,
) -> String {
  if package_path.is_empty() {
    "\{module_name}@\{version}"
  } else {
    "\{module_name}@\{version}/\{package_path}"
  }
}

///|
/// New registry references name a standalone skill, never a module subpackage.
fn skill_reference(
  module_name : String,
  version : String,
  package_path : String,
) -> String raise SkillsError {
  guard package_path.is_empty() else {
    raise SkillsError("standalone skills do not have a package path")
  }
  "\{module_name}@\{version}"
}

///|
/// The client verifies the download's SHA-256, archive layout and metadata
/// before writing a temporary ZIP. Decode it for our existing staging layer;
/// only the complete staged directory is ever made live in the local library.
async fn fetch_archive(
  registry : String,
  entry : String,
) -> (@zip.Archive, String) {
  try {
    let temporary = @fs.tmpdir(prefix="openseek-skill-download-")
    defer @fs.remove(temporary, recursive=true)
    let download = @registry.Client(registry~).download(
      entry,
      output="\{temporary}/skill.zip",
    )
    let bytes = @fs.read_binary(download.path)
    let archive = @zip.read(
      bytes,
      limits=archive_limits(bytes.length()),
      cancelled=@async.is_being_cancelled,
    )
    (archive, "sha256:\{download.skill.archive_digest}")
  } catch {
    error => raise SkillsError("skill download for \{entry}: \{error}")
  }
}

///|
/// Preview the readme from the versioned skill detail response. This does not
/// download an archive or change the local library.
pub async fn fetch_skill_content(
  module_name~ : String,
  version~ : String,
  package_path~ : String,
  registry~ : String = DefaultRegistry,
) -> String {
  let entry = skill_reference(module_name, version, package_path)
  let detail = @registry.Client(registry~).get(entry) catch {
    error => raise SkillsError("skill preview for \{entry}: \{error}")
  }
  guard @utf8.encode(detail.readme).length() <= MaxPreviewBytes else {
    raise SkillsError("SKILL.md is too large to preview")
  }
  detail.readme
}

///|
test "archive decompression ceilings scale with the packaged size" {
  // Small packages get the floor; big ones the ratio; near Int range the
  // ceiling saturates instead of overflowing.
  assert_eq(
    archive_limits(1024).max_total_uncompressed_bytes,
    ArchiveExpansionFloorBytes,
  )
  let big = 16 * 1024 * 1024
  assert_eq(
    archive_limits(big).max_total_uncompressed_bytes,
    big * ArchiveExpansionRatio,
  )
  assert_eq(
    archive_limits(0x7fff_ffff).max_total_uncompressed_bytes,
    0x7fff_ffff,
  )
  assert_eq(archive_limits(1024).max_entries, MaxArchiveEntries)
}

///|
test "entry paths join module, version and subpackage" {
  assert_eq(entry_path("alice/alpha", "0.2.0", ""), "alice/alpha@0.2.0")
  assert_eq(
    entry_path("alice/alpha", "0.2.0", "cmd/run"),
    "alice/alpha@0.2.0/cmd/run",
  )
}
