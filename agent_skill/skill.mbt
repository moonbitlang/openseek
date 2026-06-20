///|
/// One workspace skill: a markdown playbook the model can pull into context
/// when its task matches. Skills are advertised to the model as a name, a
/// one-line description, and the file path to `read` — the body itself stays
/// out of the prompt until the model decides it is relevant, so a large
/// skill library costs a few listing lines, not its full text.
pub struct Skill {
  priv name : String
  priv description : String
  priv path : String
} derive(Debug)

///|
fn Skill::Skill(name~ : String, description~ : String, path~ : String) -> Skill {
  { name, description, path }
}

///|
/// The skill's short identifier, from frontmatter `name:` or the file stem.
pub fn Skill::name(self : Skill) -> String {
  self.name
}

///|
/// One-line summary the model uses to decide relevance, from frontmatter
/// `description:` (empty when the file declares none).
pub fn Skill::description(self : Skill) -> String {
  self.description
}

///|
/// Path of the markdown file holding the full skill body.
pub fn Skill::path(self : Skill) -> String {
  self.path
}

///|
/// Parse `name:` and `description:` from a markdown frontmatter block — the
/// lines between a leading `---` and the next `---`. Anything missing falls
/// back to `fallback_name` / empty: a malformed header demotes the skill's
/// listing quality, it never hides the skill.
fn parse_frontmatter(text : String, fallback_name : String) -> (String, String) {
  let mut name = fallback_name
  let mut description = ""
  let lines = text.split("\n").map(line => line.to_owned()).collect()
  guard lines is [first, .. rest] && first.trim() == "---" else {
    return (name, description)
  }
  for line in rest {
    if line.trim() == "---" {
      break
    }
    match line.split_once(":") {
      Some((key, value)) => {
        let key = key.trim()
        let value = value.trim()
        match key {
          "name" => if value != "" { name = "\{value}" }
          "description" => description = "\{value}"
          _ => ()
        }
      }
      None => ()
    }
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
        add_skill_file(skills, nested)
      }
    }
  }
  skills.sort_by((a, b) => a.name.compare(b.name))
  skills
}

///|
async fn add_skill_file(skills : Array[Skill], path : String) -> Unit {
  let text = @fs.read_file(path).text() catch { _ => return }
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
  skills.push(Skill(name~, description~, path~))
}

///|
/// Combine a base skill library with an overriding one: an override skill
/// shadows a same-named base skill, so a workspace can specialize a
/// user-level (global) playbook without renaming it. The result is
/// re-sorted by name, keeping the prompt listing deterministic regardless
/// of which library each skill came from.
pub fn merge_skills(
  base : Array[Skill],
  overrides~ : Array[Skill],
) -> Array[Skill] {
  let merged : Array[Skill] = []
  let taken : Set[String] = Set([])
  for skill in overrides {
    taken.add(skill.name)
    merged.push(skill)
  }
  for skill in base {
    if !taken.contains(skill.name) {
      merged.push(skill)
    }
  }
  merged.sort_by((a, b) => a.name.compare(b.name))
  merged
}

///|
/// The prompt block advertising `skills`, or `None` for an empty library so
/// callers can skip the section entirely. Tells the model exactly how to
/// use a skill: read the listed file first, then follow it.
pub fn skills_prompt_section(skills : Array[Skill]) -> String? {
  guard skills.length() > 0 else { return None }
  let lines : Array[String] = []
  lines.push("## Skills")
  lines.push("")
  lines.push(
    "Reusable skills are available. When a task matches one, read its file with the read tool BEFORE doing the work, then follow it. Listed skill files are pre-approved reads even when they sit outside the working directory.",
  )
  for skill in skills {
    let description = if skill.description() == "" {
      "(no description)"
    } else {
      skill.description()
    }
    lines.push("- \{skill.name()} — \{description} (file: \{skill.path()})")
  }
  Some(lines.join("\n"))
}
