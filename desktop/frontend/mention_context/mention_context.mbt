// The `<user_mentions>` envelope: the text protocol that carries the
// composer's mention chips inside the outgoing prompt as a durable user
// message. `encode` builds the envelope the engine stores; `parse` recovers
// the chips when the transcript renders a user message (live echo and
// reloaded session alike). The two are a matched pair, so the format lives in
// one place and neither end can drift from the other. Rendering (chip glyphs,
// jump wiring) stays with the caller — this package only owns the wire form.
//
// The pattern mirrors the TUI's `<user_shell_command>` envelope
// (cmd/tui/internal/command_context): the payloads are interpolated raw, NOT
// escaped, because the envelope is read by the *model* as natural tagged
// context — readability of the inner text is the priority. The typed task
// comes first (the engine titles a session by its first prompt's first
// line), then the tagged mention block:
//
//   look at this
//
//   <user_mentions>
//   <skill name="review-pr"/>
//   <symbol name="parse_hover" file="a.mbt" line="5"/>
//   <annotation file="a.mbt" lines="12-20">
//   <quote>
//   ...the selected source, verbatim...
//   </quote>
//   <user_comment>
//   ...what the user said about it...
//   </user_comment>
//   </annotation>
//   </user_mentions>
//
// Tags sit alone on their own lines, flush left, and element bodies are
// verbatim lines between them — quoted code must survive the round trip, so
// nothing is indented or escaped. `parse` also accepts a `<symbol ...>` with
// a body (truncated source ahead of `</symbol>`), so the encoder can start
// embedding symbol content later without breaking older messages. We accept
// that a task whose own tail happens to spell a well-formed envelope would be
// misread on re-render; the blast radius is a cosmetic chip row on one
// message, not corruption — the engine stores the text verbatim and never
// parses it.

///|
/// One mention chip in envelope form. `Symbol`'s `file` is `""` (and `line`
/// 0) when the language server could not place it; `Annotation` is an editor
/// comment — the selected source and what the user said about it.
pub(all) enum MentionRef {
  Skill(name~ : String)
  Symbol(name~ : String, file~ : String, line~ : Int)
  Annotation(
    file~ : String,
    start_line~ : Int,
    end_line~ : Int,
    quote~ : String,
    comment~ : String
  )
} derive(Eq, Debug)

///|
/// A `<user_mentions>` envelope parsed back into its parts: the chips and the
/// typed task text (possibly empty — a draft of chips alone still sends).
pub(all) struct MentionMessage {
  mentions : Array[MentionRef]
  task : String
} derive(Debug)

///|
/// Encode the composer draft into the outgoing prompt: the typed task first,
/// then one element per chip inside the `<user_mentions>` block. A draft with
/// no chips is passed through untouched, so ordinary prompts stay ordinary.
pub fn encode(mentions : Array[MentionRef], task : String) -> String {
  let task = task.trim().to_owned()
  if mentions.is_empty() {
    return task
  }
  let parts = StringBuilder()
  if !task.is_empty() {
    parts <+ "\{task}\n\n"
  }
  parts <+ "<user_mentions>\n"
  for mention in mentions {
    write_mention(parts, mention)
  }
  parts <+ "</user_mentions>"
  parts.to_string()
}

///|
fn write_mention(parts : StringBuilder, mention : MentionRef) -> Unit {
  match mention {
    Skill(name~) => parts <+ "<skill name=\"\{name}\"/>\n"
    Symbol(name~, file~, line~) =>
      if file.is_empty() {
        parts <+ "<symbol name=\"\{name}\"/>\n"
      } else {
        parts <+
          "<symbol name=\"\{name}\" file=\"\{file}\" line=\"\{line}\"/>\n"
      }
    Annotation(file~, start_line~, end_line~, quote~, comment~) => {
      parts <+
        "<annotation file=\"\{file}\" lines=\"\{start_line}-\{end_line}\">\n"
      parts <+ "<quote>\n"
      write_body(parts, quote)
      parts <+ "</quote>\n"
      parts <+ "<user_comment>\n"
      write_body(parts, comment)
      parts <+ "</user_comment>\n"
      parts <+ "</annotation>\n"
    }
  }
}

///|
/// An element body, verbatim, ending in exactly one newline; an empty body
/// contributes no lines (its tags close ranks).
fn write_body(parts : StringBuilder, body : String) -> Unit {
  let body = body.trim_end(chars="\n").to_owned()
  if !body.is_empty() {
    parts <+ "\{body}\n"
  }
}

///|
/// Parse a user message back into its chips and task, or `None` when
/// `content` does not end in a well-formed envelope (an ordinary user
/// message). The structure is validated strictly — the closing tag must be
/// the last line (one trailing blank tolerated), an opener must precede it,
/// and everything between must parse as mention elements — so a prompt that
/// merely mentions the tags is not misread as chips.
pub fn parse(content : String) -> MentionMessage? {
  let lines = [
    for raw in content.split("\n") => raw.trim_end(chars="\r").to_owned()
  ]
  let lines = if lines is [.. head, ""] { head } else { lines[:] }
  guard lines is [.. head, "</user_mentions>"] else { return None }
  // The task text is arbitrary, so the envelope's opener is the last one —
  // matched from the end inward, as the closing tag was.
  let mut open_index = None
  for index, line in head {
    if line == "<user_mentions>" {
      open_index = Some(index)
    }
  }
  guard open_index is Some(open) else { return None }
  guard parse_mention_block(head[open + 1:]) is Some(mentions) else {
    return None
  }
  Some({ mentions, task: head[:open].join("\n").trim().to_owned() })
}

///|
/// `<skill name="..."/>`, alone on its line.
let skill_pattern : Regex = re"^<skill name=\"(?<name>[^\"]+)\"/>$"

///|
/// `<symbol name="..."/>` with an optional resolved location, self-closing or
/// opening a body of truncated source (`tail` is `/>` or `>`).
let symbol_pattern : Regex = re"^<symbol name=\"(?<name>[^\"]+)\"( file=\"(?<file>[^\"]+)\" line=\"(?<line>[0-9]+)\")?(?<tail>/>|>)$"

///|
/// `<annotation file="..." lines="start-end">`, opening the quote/comment body.
let annotation_pattern : Regex = re"^<annotation file=\"(?<file>[^\"]+)\" lines=\"(?<start>[0-9]+)-(?<end>[0-9]+)\">$"

///|
/// The lines between `<user_mentions>` and `</user_mentions>` as chips, or
/// `None` when anything in the block is not a well-formed mention element.
/// An empty block is malformed — `encode` never writes one.
fn parse_mention_block(lines : ArrayView[String]) -> Array[MentionRef]? {
  guard !lines.is_empty() else { return None }
  let mentions : Array[MentionRef] = []
  let mut index = 0
  while index < lines.length() {
    let line = lines[index]
    if skill_pattern.execute(line) is Some(matched) {
      guard matched.named_group("name") is Some(name) else { return None }
      mentions.push(Skill(name=name.to_owned()))
      index += 1
      continue
    }
    if symbol_pattern.execute(line) is Some(matched) {
      guard matched.named_group("name") is Some(name) else { return None }
      let (file, line_number) = if matched.named_group("file") is Some(file) &&
        matched.named_group("line") is Some(line_text) {
        let line_number = @string.parse_int(line_text) catch {
          _ => return None
        }
        (file.to_owned(), line_number)
      } else {
        ("", 0)
      }
      mentions.push(Symbol(name=name.to_owned(), file~, line=line_number))
      if matched.named_group("tail") is Some(">") {
        // A body of truncated source: skipped — a chip renders from the
        // attributes alone; the content was for the model.
        guard lines[index + 1:].search("</symbol>") is Some(end) else {
          return None
        }
        index += end + 2
      } else {
        index += 1
      }
      continue
    }
    if annotation_pattern.execute(line) is Some(matched) {
      guard matched.named_group("file") is Some(file) &&
        matched.named_group("start") is Some(start_text) &&
        matched.named_group("end") is Some(end_text) else {
        return None
      }
      let start_line = @string.parse_int(start_text) catch { _ => return None }
      let end_line = @string.parse_int(end_text) catch { _ => return None }
      guard lines[index + 1:].search("</annotation>") is Some(length) else {
        return None
      }
      let body = lines[index + 1:index + 1 + length]
      guard parse_annotation_body(body) is Some((quote, comment)) else {
        return None
      }
      mentions.push(
        Annotation(
          file=file.to_owned(),
          start_line~,
          end_line~,
          quote~,
          comment~,
        ),
      )
      index += length + 2
      continue
    }
    return None
  }
  if mentions.is_empty() {
    None
  } else {
    Some(mentions)
  }
}

///|
/// An annotation's body: exactly a `<quote>` block then a `<user_comment>`
/// block, their contents verbatim.
fn parse_annotation_body(lines : ArrayView[String]) -> (String, String)? {
  guard lines is ["<quote>", .. rest] else { return None }
  guard rest.search("</quote>") is Some(quote_end) else { return None }
  guard rest[quote_end + 1:] is ["<user_comment>", .. comment] else {
    return None
  }
  guard comment is [.. comment_body, "</user_comment>"] else { return None }
  Some((rest[:quote_end].join("\n"), comment_body.join("\n")))
}
