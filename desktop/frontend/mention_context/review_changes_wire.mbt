///|
fn write_review_header(
  parts : StringBuilder,
  workspace : String,
  base : String?,
) -> Unit {
  parts <+
    "<review_changes workspace=\"\{MentionAttribute::encode(workspace).wire}\""
  if base is Some(base) {
    parts <+ " base=\"\{MentionAttribute::encode(base).wire}\""
  }
  parts <+ ">\n"
}

///|
fn write_review_file(parts : StringBuilder, changes : ReviewChanges) -> Unit {
  let source = changes.source
  parts <+
    "<file path=\"\{MentionAttribute::encode(source.file).wire}\" version=\"\{MentionAttribute::encode(source.version).wire}\""
  if source.original_file is Some(path) {
    parts <+ " original_path=\"\{MentionAttribute::encode(path).wire}\""
  }
  parts <+ ">\n"
  for excerpt in changes.excerpts {
    parts <+ "<hunk>\n"
    write_review_side(parts, "original", excerpt.original)
    write_review_side(parts, "modified", excerpt.modified)
    parts <+ "</hunk>\n"
  }
  parts <+ "</file>\n"
}

///|
/// Each contiguous run gets its own range, so partial selections never
/// imply that omitted lines were included. Empty sides are self-closing.
fn write_review_side(
  parts : StringBuilder,
  side : String,
  lines : Array[ChangeLine],
) -> Unit {
  if lines.is_empty() {
    parts <+ "<\{side}/>\n"
    return
  }
  let mut index = 0
  while index < lines.length() {
    let start = index
    index += 1
    while index < lines.length() &&
          lines[index].number == lines[index - 1].number + 1 {
      index += 1
    }
    let first = lines[start].number
    let last = lines[index - 1].number
    let range = if first == last { "\{first}" } else { "\{first}-\{last}" }
    parts <+ "<\{side} lines=\"\{range}\">\n"
    for line in lines[start:index] {
      parts <+ "\{line.text}\n"
    }
    parts <+ "</\{side}>\n"
  }
}

///|
let review_changes_pattern : Regex = re"^<review_changes workspace=\"(?<workspace>[^\"]+)\"( base=\"(?<base>[^\"]+)\")?>$"

///|
let review_file_pattern : Regex = re"^<file path=\"(?<path>[^\"]+)\" version=\"(?<version>[^\"]+)\"( original_path=\"(?<original_path>[^\"]+)\")?>$"

///|
let review_side_pattern : Regex = re"^<(?<side>original|modified) lines=\"(?<start>[0-9]+)(-(?<end>[0-9]+))?\">$"

///|
fn parse_review_changes(
  lines : ArrayView[String],
) -> (Array[ReviewChanges], Int)? {
  guard lines.get(0) is Some(header) &&
    review_changes_pattern.execute(header) is Some(matched) &&
    matched.named_group("workspace") is Some(workspace) else {
    return None
  }
  let workspace = MentionAttribute::decode(workspace.to_owned())
  let base = matched
    .named_group("base")
    .map(value => MentionAttribute::decode(value.to_owned()))
  let changes : Array[ReviewChanges] = []
  let mut index = 1
  while index < lines.length() {
    if lines[index].is_empty() {
      index += 1
      continue
    }
    if lines[index] == "</review_changes>" {
      return if changes.is_empty() { None } else { Some((changes, index + 1)) }
    }
    guard review_file_pattern.execute(lines[index]) is Some(file) &&
      file.named_group("path") is Some(path) &&
      file.named_group("version") is Some(version) else {
      return None
    }
    let source : ReviewSource = {
      workspace,
      base,
      file: MentionAttribute::decode(path.to_owned()),
      version: MentionAttribute::decode(version.to_owned()),
      original_file: file
      .named_group("original_path")
      .map(value => MentionAttribute::decode(value.to_owned())),
    }
    let excerpts : Array[ChangeExcerpt] = []
    index += 1
    while lines.get(index) == Some("<hunk>") {
      guard parse_review_side(lines, index + 1, "original")
        is Some((original, next)) &&
        parse_review_side(lines, next, "modified") is Some((modified, next)) &&
        lines.get(next) == Some("</hunk>") else {
        return None
      }
      let excerpt : ChangeExcerpt = { original, modified, }
      guard !excerpt.is_empty() else { return None }
      excerpts.push(excerpt)
      index = next + 1
    }
    guard !excerpts.is_empty() && lines.get(index) == Some("</file>") else {
      return None
    }
    changes.push({ source, excerpts, })
    index += 1
  }
  None
}

///|
/// Consume exactly the declared number of source lines before checking the
/// closer. Literal XML tags and blank lines in source remain ordinary code.
fn parse_review_side(
  lines : ArrayView[String],
  start : Int,
  side : String,
) -> (Array[ChangeLine], Int)? {
  if lines.get(start) == Some("<\{side}/>") {
    return Some(([], start + 1))
  }
  let selected : Array[ChangeLine] = []
  let mut index = start
  while index < lines.length() {
    guard review_side_pattern.execute(lines[index]) is Some(matched) &&
      matched.named_group("side") == Some(side[:]) else {
      break
    }
    guard matched.named_group("start") is Some(first) else { return None }
    let first = @string.parse_int(first) catch { _ => return None }
    let last = match matched.named_group("end") {
      Some(last) => @string.parse_int(last) catch { _ => return None }
      None => first
    }
    guard first > 0 &&
      last >= first &&
      last - first < lines.length() - index - 2 else {
      return None
    }
    let count = last - first + 1
    guard lines.get(index + count + 1) == Some("</\{side}>") else {
      return None
    }
    for offset = 0; offset < count; offset = offset + 1 {
      selected.push({ number: first + offset, text: lines[index + 1 + offset], })
    }
    index += count + 2
  }
  if selected.is_empty() {
    None
  } else {
    Some((selected, index))
  }
}
