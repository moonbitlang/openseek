///|
/// A SKILL.md split into its YAML frontmatter and Markdown body.
priv struct SkillDocument {
  metadata : Array[(String, String)]
  body : String
}

///|
/// Split the common, top-level frontmatter form used by SKILL.md files. This is
/// deliberately not a YAML evaluator: unknown values remain display strings,
/// and an unterminated header is kept as ordinary Markdown instead of being
/// silently removed.
fn parse_skill_document(source : String) -> SkillDocument {
  let lines = source.split("\n").map(line => line.to_owned()).collect()
  guard lines is [first, .. rest] else {
    return { metadata: [], body: source, }
  }
  let first = first.trim()
  let first = if first.has_prefix("\u{feff}") {
    first[3:].trim()
  } else {
    first
  }
  let rest_array : Array[String] = []
  for line in rest {
    rest_array.push(line)
  }
  let rest = rest_array
  guard first == "---" else { return { metadata: [], body: source, } }
  let closing = find_frontmatter_close(rest)
  guard closing is Some(index) else { return { metadata: [], body: source, } }
  let metadata : Array[(String, String)] = []
  for line in rest[0:index] {
    let line = line.trim()
    guard !line.is_empty() && !line.has_prefix("#") else { continue }
    guard line.find(":") is Some(colon) else { continue }
    let key = line[0:colon].trim().to_owned()
    guard !key.is_empty() else { continue }
    metadata.push((key, line[colon + 1:].trim().to_owned()))
  }
  let body_lines : Array[String] = []
  for body_line in rest[index + 1:] {
    body_lines.push(body_line)
  }
  { metadata, body: lines_to_string(body_lines), }
}

///|
fn find_frontmatter_close(lines : Array[String]) -> Int? {
  for index, line in lines {
    let marker = line.trim()
    if marker == "---" || marker == "..." {
      return Some(index)
    }
  }
  None
}

///|
fn lines_to_string(lines : Array[String]) -> String {
  let out = StringBuilder()
  for index, line in lines {
    if index > 0 {
      out.write_char('\n')
    }
    out.write_string(line)
  }
  out.to_string()
}

///|
test "skill documents separate closed frontmatter" {
  let document = parse_skill_document(
    "\u{feff}---\r\nname: widget\r\ndescription: Build widgets\r\nlicense: MIT\r\n---\r\n\r\n# Instructions\r\nUse it.",
  )
  assert_eq(document.metadata, [
    ("name", "widget"),
    ("description", "Build widgets"),
    ("license", "MIT"),
  ])
  assert_eq(document.body, "\r\n# Instructions\r\nUse it.")
}

///|
test "skill documents keep ordinary markdown and unterminated headers" {
  let plain = parse_skill_document("# Title\nbody")
  assert_eq(plain.metadata.length(), 0)
  assert_eq(plain.body, "# Title\nbody")
  let open = parse_skill_document("---\nname: widget\n# missing close\n# body")
  assert_eq(open.metadata.length(), 0)
  assert_eq(open.body, "---\nname: widget\n# missing close\n# body")
}
