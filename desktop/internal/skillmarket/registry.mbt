// The mooncakes.io skill registry client: the catalog of published skills,
// and the per-skill API that locates one skill's archive (`skills.zip`) and
// the digest the download is verified against.

///|
/// The registry every fetch defaults to. Overridable per call so tests can
/// run against a local server — there is no user-facing registry setting.
const DefaultRegistry = "https://mooncakes.io"

///|
/// Keep preview parsing bounded so a malformed or unexpectedly large registry
/// document cannot stall the frontend renderer.
const MaxPreviewBytes : Int = 512 * 1024

///|
/// Bound the packaged archive download, and separately its decompressed
/// contents, so a hostile or malformed archive cannot exhaust memory.
const MaxArchiveBytes : Int = 32 * 1024 * 1024

///|
const MaxArchiveTotalBytes : Int = 64 * 1024 * 1024

///|
const MaxArchiveEntries : Int = 512

///|
/// A registry or library failure with a user-facing message; the host's op
/// boundary unwraps it into the error the webview displays.
pub(all) suberror SkillMarketError {
  SkillMarketError(String)
}

///|
/// One installable catalog entry: a published MoonBit package that shipped a
/// skill archive next to its wasm entry point.
pub struct MarketSkill {
  // Registry entry name, `module_name` plus the subpackage path when the skill
  // lives in one (e.g. "alice/alpha/cmd/run").
  name : String
  module_name : String
  // Subpackage path relative to the module root; "" for a root skill.
  package_path : String
  version : String
  description : String
  author : String
  repository : String
} derive(ToJson)

///|
/// GET `url`, returning the status code and body. Transport failures (DNS,
/// TLS, a refused connection) become a `SkillMarketError`; non-200 codes are
/// returned for the caller to judge with context of its own.
async fn fetch_response(url : String) -> (Int, &@io.Data) {
  let (response, data) = @http.get(url) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise SkillMarketError("cannot reach the skill registry: \{error}")
  }
  (response.code, data)
}

///|
/// The registry's skill catalog: every published skill at its latest module
/// version, installable entries only.
pub async fn fetch_catalog(
  registry? : String = DefaultRegistry,
) -> Array[MarketSkill] {
  let (code, data) = fetch_response("\{registry}/api/v0/skills")
  guard code == 200 else {
    raise SkillMarketError("skill catalog request returned HTTP \{code}")
  }
  let json = data.json() catch {
    _ => raise SkillMarketError("skill registry returned a malformed catalog")
  }
  decode_catalog(json)
}

///|
/// Decode the `/api/v0/skills` payload. The registry catalogs every wasm
/// entry point; only entries that publish a skill archive — non-empty
/// `archive_url` and `archive_digest` — and carry a description are kept.
/// (Install re-resolves the archive through the per-skill API rather than
/// trusting catalog data.)
fn decode_catalog(json : Json) -> Array[MarketSkill] raise SkillMarketError {
  // The plain catalog is a bare array; filtered responses (`?recent=N`)
  // arrive wrapped in an object. Accept both so a server-side default change
  // cannot break the panel.
  let items = match json {
    Array(items) => items
    { "all": Array(items), .. } => items
    _ => raise SkillMarketError("skill registry returned a malformed catalog")
  }
  let skills : Array[MarketSkill] = []
  for item in items {
    guard item
      is {
        "module": String(module_name),
        "version": String(version),
        "name": String(name),
        ..
      } else {
      continue
    }
    guard item
      is {
        "archive_url": String(archive_url),
        "archive_digest": String(archive_digest),
        ..
      } &&
      !archive_url.is_empty() &&
      !archive_digest.is_empty() else {
      continue
    }
    let description = if item
      is { "metadata": { "description": String(description), .. }, .. } &&
      !description.is_blank() {
      description
    } else if item is { "description": String(description), .. } &&
      !description.is_blank() {
      description
    } else {
      continue
    }
    let package_path = if item is { "package": String(package_path), .. } {
      package_path
    } else {
      ""
    }
    let author = if item is { "author": String(author), .. } {
      author
    } else if module_name.split_once("/") is Some((owner, _)) {
      owner.to_owned()
    } else {
      module_name
    }
    let repository = if item is { "repository": String(repository), .. } {
      repository
    } else {
      ""
    }
    skills.push({
      name,
      module_name,
      package_path,
      version,
      description,
      author,
      repository,
    })
  }
  skills
}

///|
/// The registry path naming one skill: `module@version`, plus the
/// subpackage path when the skill lives in one.
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
/// Where one published skill's archive lives and the digest it must hash to.
priv struct ArchiveSource {
  url : String
  digest : String
}

///|
/// Confirm `entry` (`module@version[/package]`) is a published skill via the
/// registry's per-skill API, and return where its archive lives. The skills
/// API 404s for anything that is not a registered skill; a registered skill
/// without archive coordinates has nothing this client can install.
async fn fetch_archive_source(
  registry : String,
  entry : String,
) -> ArchiveSource {
  let (code, data) = fetch_response("\{registry}/api/v0/skills/\{entry}")
  if code == 404 {
    raise SkillMarketError("\{entry} is not a published skill")
  }
  guard code == 200 else {
    raise SkillMarketError("skill lookup for \{entry} returned HTTP \{code}")
  }
  let json = data.json() catch {
    _ =>
      raise SkillMarketError("skill registry returned a malformed skill entry")
  }
  guard json
    is { "archive_url": String(url), "archive_digest": String(digest), .. } &&
    !url.is_empty() &&
    !digest.is_empty() else {
    raise SkillMarketError("\{entry} does not publish a skill archive")
  }
  { url, digest: digest.trim().to_owned().to_lower(), }
}

///|
/// Download the archive behind `source` and decode it. Every byte is checked
/// against the digest the registry declared before any entry is trusted, and
/// decompression runs under explicit size and entry-count ceilings.
async fn fetch_archive(entry : String, source : ArchiveSource) -> @zip.Archive {
  let (code, data) = fetch_response(source.url)
  if code == 404 {
    raise SkillMarketError(
      "the archive for \{entry} is missing from the registry",
    )
  }
  guard code == 200 else {
    raise SkillMarketError("skill archive download returned HTTP \{code}")
  }
  let bytes = data.binary()
  guard bytes.length() <= MaxArchiveBytes else {
    raise SkillMarketError("the archive for \{entry} is too large to install")
  }
  guard content_digest(bytes) == source.digest else {
    raise SkillMarketError(
      "the archive for \{entry} does not match its published digest",
    )
  }
  let limits = @zip.ReadLimits::default()
    .with_package_limit(MaxArchiveBytes)
    .with_entries_limit(MaxArchiveEntries)
    .with_entry_limit(MaxArchiveTotalBytes)
    .with_total_limit(MaxArchiveTotalBytes)
  @zip.read(bytes, limits~, cancelled=@async.is_being_cancelled) catch {
    error if @async.is_being_cancelled() => raise error
    ZipError(_, message) =>
      raise SkillMarketError(
        "the archive for \{entry} cannot be unpacked: \{message}",
      )
  }
}

///|
/// Fetch the published instructions without changing the local library.
pub async fn fetch_skill_content(
  module_name~ : String,
  version~ : String,
  package_path~ : String,
  registry? : String = DefaultRegistry,
) -> String {
  let entry = entry_path(module_name, version, package_path)
  let source = fetch_archive_source(registry, entry)
  let skill = skill_files(fetch_archive(entry, source), entry)
  guard skill.skill_md.length() <= MaxPreviewBytes else {
    raise SkillMarketError("SKILL.md is too large to preview")
  }
  @utf8.decode(skill.skill_md) catch {
    _ =>
      raise SkillMarketError(
        "the archive for \{entry} holds an unreadable SKILL.md",
      )
  }
}

// The pure halves of the registry client and the library: wire decoding,
// digest and slug checks, frontmatter parsing.

///|
test "catalog decoding keeps only entries that publish a skill archive" {
  let json : Json = [
    {
      "module": "alice/alpha",
      "version": "0.2.0",
      "name": "alice/alpha/cmd/run",
      "package": "cmd/run",
      "author": "alice",
      "repository": "https://github.com/alice/alpha",
      "metadata": { "description": "Run alpha commands" },
      "archive_url": "https://download.example/skills/alice/alpha@0.2.0/cmd/run/skills.zip",
      "archive_digest": "sha256:abc",
    },
    // No archive: a bare wasm entry without a published skill archive.
    {
      "module": "bob/beta",
      "version": "0.1.0",
      "name": "bob/beta",
      "package": "",
      "author": "bob",
      "metadata": { "description": "Not installable" },
    },
    // An archive whose description never made it into the registry metadata.
    {
      "module": "carol/gamma",
      "version": "0.1.0",
      "name": "carol/gamma",
      "archive_url": "https://download.example/skills/carol/gamma@0.1.0/skills.zip",
      "archive_digest": "sha256:def",
      "metadata": { "description": "" },
    },
    // Malformed entry: skipped, not fatal.
    "nonsense",
  ]
  let skills = decode_catalog(json)
  guard skills is [skill] else { fail("expected exactly one catalog entry") }
  assert_eq(skill.name, "alice/alpha/cmd/run")
  assert_eq(skill.module_name, "alice/alpha")
  assert_eq(skill.package_path, "cmd/run")
  assert_eq(skill.version, "0.2.0")
  assert_eq(skill.description, "Run alpha commands")
  assert_eq(skill.author, "alice")
  assert_eq(skill.repository, "https://github.com/alice/alpha")
}

///|
test "catalog decoding fills optional fields from the module name" {
  let json : Json = [
    {
      "module": "alice/alpha",
      "version": "0.2.0",
      "name": "alice/alpha",
      "archive_url": "https://download.example/skills/alice/alpha@0.2.0/skills.zip",
      "archive_digest": "sha256:abc",
      "description": "Root skill",
    },
  ]
  guard decode_catalog(json) is [skill] else { fail("expected one entry") }
  assert_eq(skill.package_path, "")
  assert_eq(skill.author, "alice")
  assert_eq(skill.repository, "")
  assert_eq(skill.description, "Root skill")
}

///|
test "a wrapped catalog response decodes like a bare one" {
  let entry : Json = {
    "module": "alice/alpha",
    "version": "0.2.0",
    "name": "alice/alpha",
    "archive_url": "https://download.example/skills/alice/alpha@0.2.0/skills.zip",
    "archive_digest": "sha256:abc",
    "metadata": { "description": "Root skill" },
  }
  guard decode_catalog({ "all": [entry] }) is [skill] else {
    fail("expected one entry from the wrapped catalog")
  }
  assert_eq(skill.name, "alice/alpha")
}

///|
test "a non-array catalog is an error" {
  try {
    let _ = decode_catalog({ "detail": "Skill not found" })
    fail("a non-array catalog must be an error")
  } catch {
    SkillMarketError(_) => ()
    error => raise error
  }
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
test "content_digest hashes the exact bytes" {
  // sha256 of the empty input — the classic known vector.
  assert_eq(
    content_digest(b""),
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
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
    ),
    "alice/alpha@0.2.0/cmd/run",
  )
  assert_eq(
    decode_sidecar("{\"module\":\"alice/alpha\",\"version\":\"0.2.0\"}"),
    "alice/alpha@0.2.0",
  )
  assert_eq(decode_sidecar("not json"), "")
  assert_eq(decode_sidecar("{\"version\":\"0.2.0\"}"), "")
}

///|
pub extend MarketSkill with ToJson::{to_json}
