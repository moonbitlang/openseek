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
/// Decompression floor and ratio for one downloaded archive. How large a
/// published archive may be is the registry's publish policy, not ours — but
/// a zip's decompressed size is not bounded by its packaged size (deflate
/// reaches ~1000:1), publishing is open to anyone, and this reader inflates
/// in memory, so a small hostile package must not expand without limit. A
/// generous multiple of the packaged bytes never brakes a legitimately large
/// skill, while the floor keeps small archives clear of the edge.
const ArchiveExpansionFloorBytes : Int = 256 * 1024 * 1024

///|
const ArchiveExpansionRatio : Int = 64

///|
const MaxArchiveEntries : Int = 65536

///|
/// Decompression ceilings for an archive of `package_bytes` packaged size.
fn archive_limits(package_bytes : Int) -> @zip.ReadLimits {
  let saturation = 0x7fff_ffff / ArchiveExpansionRatio
  let scaled = if package_bytes >= saturation {
    0x7fff_ffff
  } else if package_bytes * ArchiveExpansionRatio > ArchiveExpansionFloorBytes {
    package_bytes * ArchiveExpansionRatio
  } else {
    ArchiveExpansionFloorBytes
  }
  @zip.ReadLimits::default()
  .with_entries_limit(MaxArchiveEntries)
  .with_entry_limit(scaled)
  .with_total_limit(scaled)
}

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
/// Redirect hops one fetch will follow. The registry's download host hands
/// archives to its object store through a redirect; the cap keeps a
/// misconfigured server from looping forever.
const MaxRedirects = 5

///|
/// GET `url`, following redirects, and return the final status code and
/// body. Transport failures (DNS, TLS, a refused connection) become a
/// `SkillMarketError`; non-200 final codes are returned for the caller to
/// judge with context of its own. A hop onto plain http is accepted:
/// integrity never rests on the transport, since archives are verified
/// against the registry's declared digest after download.
async fn fetch_response(url : String) -> (Int, &@io.Data) {
  let mut current = url
  for _ in 0..<MaxRedirects {
    let (response, data) = @http.get(current) catch {
      error if @async.is_being_cancelled() => raise error
      error =>
        raise SkillMarketError("cannot reach the skill registry: \{error}")
    }
    guard response.code is (301 | 302 | 303 | 307 | 308) &&
      response.headers.get("Location") is Some(location) else {
      return (response.code, data)
    }
    current = redirect_target(current, location)
  }
  raise SkillMarketError("the skill registry redirected too many times")
}

///|
/// The absolute URL a redirect points at. `Location` may be absolute or
/// host-relative — the only forms real registries emit; anything else is
/// refused rather than guessed at.
fn redirect_target(
  current : String,
  location : String,
) -> String raise SkillMarketError {
  if location.has_prefix("http://") || location.has_prefix("https://") {
    return location
  }
  if location.has_prefix("/") && current.find("://") is Some(scheme_end) {
    let host_start = scheme_end + 3
    let origin_end = match current[host_start:].to_owned().find("/") {
      Some(offset) => host_start + offset
      None => current.length()
    }
    return "\{current[0:origin_end].to_owned()}\{location}"
  }
  raise SkillMarketError("the skill registry sent an unsupported redirect")
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
/// decompression runs under ceilings scaled to the packaged size. The
/// download itself is not size-capped here: publish limits are the
/// registry's policy, and the digest pins the content either way.
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
  guard content_digest(bytes) == source.digest else {
    raise SkillMarketError(
      "the archive for \{entry} does not match its published digest",
    )
  }
  let limits = archive_limits(bytes.length())
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
test "redirect targets resolve absolute and host-relative locations" {
  assert_eq(
    redirect_target(
      "https://download.example/skills/a.zip", "http://store.example:9002/blob/a.zip",
    ),
    "http://store.example:9002/blob/a.zip",
  )
  assert_eq(
    redirect_target("https://download.example/skills/a.zip", "/blob/a.zip"),
    "https://download.example/blob/a.zip",
  )
  assert_eq(
    redirect_target("https://download.example", "/blob/a.zip"),
    "https://download.example/blob/a.zip",
  )
  // A relative or garbage location is refused, not guessed at.
  try {
    let _ = redirect_target(
      "https://download.example/skills/a.zip", "blob/a.zip",
    )
    fail("a relative redirect must be refused")
  } catch {
    SkillMarketError(_) => ()
    error => raise error
  }
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
