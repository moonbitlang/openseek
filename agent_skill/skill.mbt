///|
/// One workspace skill: a markdown playbook the model can pull into context
/// when its task matches. Skills are advertised to the model as a name, a
/// one-line description, and the file path to read — the body itself stays
/// out of the prompt until the model decides it is relevant, so a large
/// skill library costs a few listing lines, not its full text.
#derive(Debug)
struct Skill {
  name : String
  description : String
  path : String
  /// The `mcp.json` beside a `<name>/SKILL.md`, naming the MCP servers the
  /// skill brings; `None` when it brings none.
  mcp_config : String?
}

///|
/// Read `name` and `description` from a markdown frontmatter block: the YAML
/// between a leading `---` line and the next `---` line, the block the skill
/// registry validates when a skill is published. A missing, unclosed or
/// malformed block, or a value that is not a string, falls back to
/// `fallback_name` / empty: a broken header demotes the skill's listing
/// quality, it never hides the skill. The description is the listing's
/// one-line summary, so a block scalar's line breaks become spaces.
pub fn parse_frontmatter(
  text : String,
  fallback_name : String,
) -> (String, String) {
  let fallback = (fallback_name, "")
  let lines = [..text.split("\n")]
  guard lines is [first, .. rest] && first.trim() == "---" else {
    return fallback
  }
  let header : Array[String] = []
  let mut closed = false
  for line in rest {
    if line.trim() == "---" {
      closed = true
      break
    }
    header.push("\{line}")
  }
  guard closed else { return fallback }
  let documents = @yaml.Yaml::load_from_string(header.join("\n")) catch {
    _ => return fallback
  }
  guard documents is [Map(fields)] else { return fallback }
  let name = match fields.get("name") {
    Some(String(name)) if !name.trim().is_empty() => name
    _ => fallback_name
  }
  let description = match fields.get("description") {
    Some(String(description)) =>
      description
      .split("\n")
      .map(line => line.trim())
      .filter(line => !line.is_empty())
      .map(line => "\{line}")
      .collect()
      .join(" ")
    _ => ""
  }
  (name, description)
}

///|
/// The markdown file's stem (`foo` for `dir/foo.md`), used as the fallback
/// skill name.
fn file_stem(path : String) -> String {
  let base = match path.rev_split_once("/") {
    Some((_, base)) => base
    None => path
  }
  match base.rev_split_once(".") {
    Some((stem, _)) => "\{stem}"
    None => "\{base}"
  }
}

///|
/// Discover the skills under `dir`: every `<dir>/<name>.md`, plus every
/// `<dir>/<name>/SKILL.md` for skills that ship companion files. A missing
/// or unreadable directory is an empty library, never an error — most
/// workspaces define no skills. Results are sorted by name (MoonBit's
/// String order: length first, then code units) so the prompt listing is
/// deterministic — and therefore prefix-cache stable — across runs.
pub async fn discover_skills(dir : String) -> Array[Skill] {
  let skills : Array[Skill] = []
  let entries = @fs.readdir(dir) catch { _ => return skills }
  for entry in entries {
    let entry_path = "\{dir}/\{entry}"
    if entry.has_suffix(".md") {
      add_skill_file(skills, entry_path)
    } else {
      let nested = "\{entry_path}/SKILL.md"
      // exists() raises ENOTDIR when entry_path is a plain file; either way
      // there is no nested skill here.
      let has_nested = @fs.exists(nested) catch { _ => false }
      if has_nested {
        let config = "\{entry_path}/mcp.json"
        let has_config = @fs.exists(config) catch { _ => false }
        let mcp_config = if has_config { Some(config) } else { None }
        add_skill_file(skills, nested, mcp_config?)
      }
    }
  }
  skills.sort_by((a, b) => a.name.compare(b.name))
  skills
}

///|
async fn add_skill_file(
  skills : Array[Skill],
  path : String,
  mcp_config? : String,
) -> Unit {
  let text = @fs.read_text(path) catch { _ => return }
  let fallback = match file_stem(path) {
    "SKILL" => {
      // For <name>/SKILL.md layouts the directory carries the name — its
      // full basename, dots included ("node.js" stays "node.js").
      let parent = match path.rev_split_once("/") {
        Some((parent, _)) => parent
        None => path
      }
      match parent.rev_split_once("/") {
        Some((_, name)) => "\{name}"
        None => "\{parent}"
      }
    }
    stem => stem
  }
  let (name, description) = parse_frontmatter(text, fallback)
  skills.push({ name, description, path, mcp_config, })
}

///|
/// Combine a base skill library with an overriding one: an override skill
/// shadows a same-named base skill, so a workspace can specialize a
/// user-level (global) playbook without renaming it. The result is
/// re-sorted by name, keeping the prompt listing deterministic regardless
/// of which library each skill came from.
pub fn merge_skills(
  base : ArrayView[Skill],
  overrides~ : ArrayView[Skill],
) -> Array[Skill] {
  let taken : Set[String] = Set([ for skill in overrides => skill.name ])
  let merged = [
    ..overrides,
    ..[
      for skill in base if !taken.contains(skill.name) => skill
    ],
  ]
  merged.sort_by((a, b) => a.name.compare(b.name))
  merged
}

///|
/// The prompt block advertising `skills`, or `None` for an empty library so
/// callers can skip the section entirely. Tells the model exactly how to
/// use a skill: read the listed file first, then follow it.
pub fn skills_prompt_section(skills : Array[Skill]) -> String? {
  guard skills.length() > 0 else { return None }
  // Entries are joined with newlines; the `$|` block below supplies the one
  // before the first entry.
  let listing = [
    for skill in skills => {
      let description = if skill.description() == "" {
        "(no description)"
      } else {
        skill.description()
      }
      "- \{skill.name()} — \{description} (file: \{skill.path()})"
    }
  ].join("\n")
  let section =
    $|## Skills
    $|
    $|Reusable skills are available. When a task matches one, read its file through mbtx (filename="@builtin/read.mbtx", args=[the file path]) BEFORE doing the work, then follow it. Listed skill files are pre-approved reads even when they sit outside the working directory.
    $|\{listing}
  Some(section)
}

///|
#doc(hidden)
#deprecated
pub extend Skill with Debug::{to_repr}
