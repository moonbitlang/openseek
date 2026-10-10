///|
/// A skill shipped in this installation. Only the host reads the manifest;
/// tool callers select an id and never supply an executable path.
pub struct BuiltinSkill {
  id : String
  name : String
  description : String
  version : String
  root : String
  instructions : String
  wasm : String
}

///|
/// Qualified name used in model-facing skill listings and mentions.
pub fn BuiltinSkill::prompt_name(self : BuiltinSkill) -> String {
  "builtin:\{self.id}"
}

///|
priv struct BuiltinEntry {
  id : String
  version : String
  entry : String
} derive(FromJson)

///|
/// Read the catalog shipped with this installation's resources.
pub async fn builtin_skills(resources_dir? : String) -> Array[BuiltinSkill] {
  let resources_dir = match resources_dir {
    Some(dir) => Some(dir)
    None => @resources.directory()
  }
  guard resources_dir is Some(resources_dir) else { return [] }
  let directory = "\{resources_dir}/skills"
  let entries : Array[BuiltinEntry] = @json.from_json(
    @json.parse(@fs.read_file("\{directory}/manifest.json").text()),
  )
  let skills : Array[BuiltinSkill] = []
  for { id, version, entry, } in entries {
    let root = @fs.realpath("\{directory}/\{id}")
    let instructions = "\{root}/SKILL.md"
    let (name, description) = parse_frontmatter(
      @fs.read_file(instructions).text(),
      id,
    )
    let wasm = "\{root}/\{entry}"
    skills.push({ id, name, description, version, root, instructions, wasm, })
  }
  skills.sort_by((a, b) => a.id.compare(b.id))
  skills
}

///|
/// Builtins have qualified identities, so a user skill with the same display
/// name neither replaces nor hides them. Bodies remain ordinary SKILL.md files.
pub fn builtin_skills_prompt_section(skills : Array[BuiltinSkill]) -> String? {
  guard !skills.is_empty() else { return None }
  let listing = skills
    .map(skill => {
      "- \{skill.prompt_name()} (\{skill.name}) — \{skill.description} (file: \{skill.instructions}; runner id: \{skill.id})"
    })
    .join("\n")
  Some(
    "## Builtin skills\n\nRead the listed SKILL.md before using a skill. Execute its bundled Wasm with run_builtin_skill, passing the runner id and the arguments described in the skill. OPENSEEK_SKILL_DIR contains its supporting files; cwd remains the task working directory.\n\n\{listing}",
  )
}
