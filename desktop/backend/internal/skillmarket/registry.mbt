// Adapt moonbit-community/skills to the Desktop catalog and transactional
// local library. The client owns registry JSON, HTTP and download validation.

///|
/// Overridable per call for local registry tests.
const DefaultRegistry = "https://mooncakes.io"

///|
/// Keep documents passed to the frontend renderer bounded.
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
/// A registry or library failure with a user-facing message; the host's op
/// boundary unwraps it into the error the webview displays.
pub(all) suberror SkillMarketError {
  SkillMarketError(String)
}

///|
/// One standalone skill from the registry, projected into the host protocol.
pub struct MarketSkill {
  // The standalone skill name, matching SKILL.md frontmatter.
  name : String
  // The host protocol retains this field for the owner/name skill identity.
  module_name : String
  // Standalone skills have no subpackage; always empty for new catalog rows.
  package_path : String
  version : String
  description : String
  author : String
  repository : String
}

///|
impl ToJson for MarketSkill with fn to_json(self) {
  {
    "name": self.name,
    "module_name": self.module_name,
    "package_path": self.package_path,
    "version": self.version,
    "description": self.description,
    "author": self.author,
    "repository": self.repository,
  }
}

///|
/// List independently published skills. Keep the existing host payload shape:
/// module_name carries owner/name, and package_path is empty.
pub async fn fetch_catalog(
  registry~ : String = DefaultRegistry,
) -> Array[MarketSkill] {
  let skills = @skills.Client(registry~).list() catch {
    error => raise SkillMarketError("skill catalog from \{registry}: \{error}")
  }
  skills.map(skill => {
    name: skill.name,
    module_name: "\{skill.owner}/\{skill.name}",
    package_path: "",
    version: skill.version,
    description: skill.description,
    author: skill.owner,
    // The standalone API does not expose a source repository.
    repository: "",
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
) -> String raise SkillMarketError {
  guard package_path.is_empty() else {
    raise SkillMarketError("standalone skills do not have a package path")
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
    defer @fs.rmdir(temporary, recursive=true)
    let download = @skills.Client(registry~).download(
      entry,
      output="\{temporary}/skill.zip",
    )
    let bytes = @fs.read_file(download.path).binary()
    let archive = @zip.read(
      bytes,
      limits=archive_limits(bytes.length()),
      cancelled=@async.is_being_cancelled,
    )
    (archive, "sha256:\{download.skill.archive_sha256}")
  } catch {
    error => raise SkillMarketError("skill download for \{entry}: \{error}")
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
  let detail = @skills.Client(registry~).get(entry) catch {
    error => raise SkillMarketError("skill preview for \{entry}: \{error}")
  }
  guard @utf8.encode(detail.readme).length() <= MaxPreviewBytes else {
    raise SkillMarketError("SKILL.md is too large to preview")
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
test "slugify turns an owner/name identity into a safe single segment" {
  assert_eq(slugify("Yoorkin/cowsay"), "yoorkin-cowsay")
  assert_eq(slugify("acme/widget"), "acme-widget")
  assert_eq(slugify("moonbit-community/moongrep"), "moonbit-community-moongrep")
  assert_eq(slugify("alice/alpha/cmd/run"), "alice-alpha-cmd-run")
  // Leading/trailing and repeated separators collapse; no stray dashes.
  assert_eq(slugify("/A..B/"), "a-b")
  // Every slugify output passes the path-safety guard.
  assert_true(valid_slug(slugify("Yoorkin/cowsay")))
}

///|
test "entry paths join module, version and subpackage" {
  assert_eq(entry_path("alice/alpha", "0.2.0", ""), "alice/alpha@0.2.0")
  assert_eq(
    entry_path("alice/alpha", "0.2.0", "cmd/run"),
    "alice/alpha@0.2.0/cmd/run",
  )
}

///|
test "slug validation rejects anything that could escape the library" {
  assert_true(valid_slug("alice-alpha"))
  assert_true(valid_slug("a"))
  assert_false(valid_slug(""))
  assert_false(valid_slug(".."))
  assert_false(valid_slug("a/b"))
  assert_false(valid_slug("a\\b"))
  assert_false(valid_slug("Alice"))
  assert_false(valid_slug("a b"))
  let mut long = ""
  for _ in 0..<65 {
    long = "\{long}a"
  }
  assert_false(valid_slug(long))
}

///|
test "frontmatter parsing mirrors the engine's rules" {
  let (name, description) = parse_frontmatter(
    (
      $|---
      $|name: meta-skill
      $|description: Create MoonBit WASM skills.
      $|---
      $|
      $|# body
    ),
    "fallback",
  )
  assert_eq(name, "meta-skill")
  assert_eq(description, "Create MoonBit WASM skills.")
  let (name, description) = parse_frontmatter("# no frontmatter", "fallback")
  assert_eq(name, "fallback")
  assert_eq(description, "")
  // A blank name keeps the fallback; unknown keys are ignored.
  let (name, _) = parse_frontmatter(
    (
      $|---
      $|name:
      $|license: MIT
      $|---
    ),
    "fallback",
  )
  assert_eq(name, "fallback")
}

///|
test "sidecar decoding renders the install source" {
  assert_eq(
    decode_sidecar(
      "{\"module\":\"alice/alpha\",\"version\":\"0.2.0\",\"package\":\"cmd/run\",\"digest\":\"sha256:abc\"}",
    ).map_or("", source => source.label),
    "alice/alpha@0.2.0/cmd/run",
  )
  assert_eq(
    decode_sidecar("{\"module\":\"alice/alpha\",\"version\":\"0.2.0\"}").map_or(
      "",
      source => source.label,
    ),
    "alice/alpha@0.2.0",
  )
  assert_true(decode_sidecar("not json") is None)
  assert_true(decode_sidecar("{\"version\":\"0.2.0\"}") is None)
}

///|
pub extend MarketSkill with ToJson::{to_json}
