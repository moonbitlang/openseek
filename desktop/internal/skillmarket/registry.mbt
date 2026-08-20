// The mooncakes.io skill registry client: the catalog of published skills and
// the per-skill API that confirms one entry is a skill and locates its
// SKILL.md.

///|
/// The registry every fetch defaults to. Overridable per call so tests can
/// run against a local server — there is no user-facing registry setting.
const DefaultRegistry = "https://mooncakes.io"

///|
/// A registry or library failure with a user-facing message; the host's op
/// boundary unwraps it into the error the webview displays.
pub(all) suberror SkillMarketError {
  SkillMarketError(String)
}

///|
/// One installable catalog entry: a published MoonBit package whose doc
/// build shipped a SKILL.md next to its wasm entry point.
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
/// entry point; only entries with a description are kept — the registry's
/// doc builder extracts it from SKILL.md frontmatter, so a present
/// description marks an entry that actually ships a SKILL.md. (Install
/// confirms the SKILL.md is really there before writing anything.)
fn decode_catalog(json : Json) -> Array[MarketSkill] raise SkillMarketError {
  guard json is Array(items) else {
    raise SkillMarketError("skill registry returned a malformed catalog")
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
    guard item is { "metadata": { "description": String(description), .. }, .. } &&
      !description.is_blank() else {
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
/// Confirm `entry` (`module@version[/package]`) is a published skill via the
/// registry's per-skill API, and return where its SKILL.md lives. The skills
/// API 404s for anything that is not a registered skill; the SKILL.md itself
/// sits beside the skill's assets, so its URL is derived from the entry.
async fn skill_md_url(registry : String, entry : String) -> String {
  let (code, _data) = fetch_response("\{registry}/api/v0/skills/\{entry}")
  if code == 404 {
    raise SkillMarketError("\{entry} is not a published skill")
  }
  guard code == 200 else {
    raise SkillMarketError("skill lookup for \{entry} returned HTTP \{code}")
  }
  "\{registry}/assets/\{entry}/SKILL.md"
}

// The pure halves of the registry client and the library: wire decoding,
// digest and slug checks, frontmatter parsing.

///|
test "catalog decoding keeps only entries that ship a SKILL.md" {
  let json : Json = [
    {
      "module": "alice/alpha",
      "version": "0.2.0",
      "name": "alice/alpha/cmd/run",
      "package": "cmd/run",
      "author": "alice",
      "repository": "https://github.com/alice/alpha",
      "metadata": { "description": "Run alpha commands" },
    },
    // No description: a bare wasm entry without a SKILL.md.
    {
      "module": "bob/beta",
      "version": "0.1.0",
      "name": "bob/beta",
      "package": "",
      "author": "bob",
      "metadata": { "description": "" },
    },
    // No metadata at all.
    { "module": "carol/gamma", "version": "0.1.0", "name": "carol/gamma" },
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
      "metadata": { "description": "Root skill" },
    },
  ]
  guard decode_catalog(json) is [skill] else { fail("expected one entry") }
  assert_eq(skill.package_path, "")
  assert_eq(skill.author, "alice")
  assert_eq(skill.repository, "")
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
