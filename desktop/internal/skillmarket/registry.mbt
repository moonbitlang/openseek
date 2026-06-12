// The mooncakes.io skill registry client: the catalog of published skills
// and the per-module Agent Skills discovery index that locates a skill's
// SKILL.md and pins its digest.

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
/// double-checks against the discovery index, which is authoritative.)
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
      !description.trim().is_empty() else {
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
/// One entry of a module's Agent Skills discovery index: the slug the
/// registry assigned, where its SKILL.md lives, and the digest the download
/// must match.
priv struct DiscoveryEntry {
  name : String
  url : String
  digest : String
}

///|
fn decode_discovery_index(json : Json) -> Array[DiscoveryEntry] {
  guard json is { "skills": Array(items), .. } else { return [] }
  let entries : Array[DiscoveryEntry] = []
  for item in items {
    guard item
      is {
        "name": String(name),
        "url": String(url),
        "digest": String(digest),
        ..
      } else {
      continue
    }
    entries.push({ name, url, digest })
  }
  entries
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
/// Fetch the discovery-index entry for one skill. The index endpoint wants
/// an explicit version and 404s when the module publishes no SKILL.md; a
/// root-skill lookup returns every skill of the module, so the entry is
/// selected by its SKILL.md path (a subpackage's URL has extra path
/// segments, so a suffix match cannot confuse the two).
async fn fetch_discovery_entry(
  registry : String,
  entry : String,
) -> DiscoveryEntry {
  let (code, data) = fetch_response(
    "\{registry}/api/v0/skill-sources/\{entry}/.well-known/agent-skills/index.json",
  )
  if code == 404 {
    raise SkillMarketError("\{entry} does not publish a SKILL.md")
  }
  guard code == 200 else {
    raise SkillMarketError("skill lookup for \{entry} returned HTTP \{code}")
  }
  let json = data.json() catch {
    _ =>
      raise SkillMarketError(
        "skill registry returned a malformed discovery index",
      )
  }
  for candidate in decode_discovery_index(json) {
    if candidate.url.has_suffix("/\{entry}/SKILL.md") {
      return candidate
    }
  }
  raise SkillMarketError("\{entry} does not publish a SKILL.md")
}
