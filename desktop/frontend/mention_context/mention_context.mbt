// The `<user_mentions>` envelope: the text protocol that carries the
// composer's mention chips inside the outgoing prompt as a durable user
// message. `encode` builds the envelope the engine stores; `parse` recovers
// the chips when the transcript renders a user message (live echo and
// reloaded session alike). The two are a matched pair, so the format lives in
// one place and neither end can drift from the other. Rendering (chip glyphs,
// jump wiring) stays with the caller — this package only owns the wire form.
//
// The pattern mirrors the TUI's `<user_shell_command>` envelope (the terminal
// UI's command_context package in moonbitlang/openseek_tui): element bodies
// remain verbatim because the envelope is read by the *model* as natural
// tagged context. Attribute
// values use the ordinary XML entities for structural characters and line
// breaks, then `parse` decodes them back into the exact chip value. The typed
// task comes first (the engine titles a session by its first prompt's first
// line), then the tagged mention block:
//
//   look at this
//
//   <user_mentions>
//   <skill name="review-pr"/>
//   <file path="src/main.mbt"/>
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
// a body (truncated source ahead of `</symbol>`), so the wire form can carry
// truncated symbol source when available. We accept
// that a task whose own tail happens to spell a well-formed envelope would be
// misread on re-render; the blast radius is a cosmetic chip row on one
// message, not corruption — the engine stores the text verbatim and never
// parses it.

///|
/// One mention chip in envelope form. `Symbol`'s `file` is `""` (and `line`
/// 0) when the language server could not place it; `Annotation` is an editor
/// comment — the selected source, its revision side, and what the user said.
pub(all) enum AnnotationSide {
  WorkingRevision
  OriginalRevision
} derive(Eq, Debug)

///|
pub(all) enum MentionRef {
  ReviewChanges(ReviewChanges)
  Skill(name~ : String)
  File(path~ : String)
  Symbol(name~ : String, file~ : String, line~ : Int)
  SemanticSearch(SemanticSearchReference)
  SemanticSearchArtifact(SemanticSearchArtifact)
  SemanticSearchPending(SemanticSearchReference)
  Annotation(
    file~ : String,
    start_line~ : Int,
    end_line~ : Int,
    quote~ : String,
    comment~ : String,
    side~ : AnnotationSide
  )
} derive(Eq, Debug)

///|
/// A snapshot of selected semantic-search results. It is one Composer mention
/// even when it contains many files and ranges; the snapshot stays independent
/// from the live Search panel so later searches cannot silently change it.
pub(all) struct SemanticSearchReference {
  id : String
  root : String
  patterns : Array[String]
  include_glob : String
  exclude_glob : String
  matches : Array[SemanticSearchReferenceMatch]
} derive(Eq, Debug)

///|
/// Small selections stay in the prompt as structured XML. Larger selections
/// are materialized only when the user sends, so the composer never creates
/// files merely because a search row was toggled.
const MaxInlineSemanticReferenceMatches : Int = 100

///|
const MaxInlineSemanticReferenceSourceUnits : Int = 24000

///|
pub fn SemanticSearchReference::is_inlineable(
  self : SemanticSearchReference,
) -> Bool {
  self.matches.length() <= MaxInlineSemanticReferenceMatches &&
  self.matches
  .map(match_ => match_.matched_source.length())
  .fold(init=0, (total, size) => total + size) <=
  MaxInlineSemanticReferenceSourceUnits
}

///|
pub(all) struct SemanticSearchReferenceMatch {
  rule_id : String?
  description : String?
  file : String
  start_line : Int
  start_column : Int
  end_line : Int
  end_column : Int
  matched_source : String
} derive(Eq, Debug)

///|
/// A generated JSONL snapshot used when a semantic selection is too large to
/// put in the prompt itself.
pub(all) struct SemanticSearchArtifact {
  path : String
  pattern_count : Int
  match_count : Int
} derive(Eq, Debug)

///|
/// A `<user_mentions>` envelope parsed back into its parts: the chips and the
/// typed task text (possibly empty — a draft of chips alone still sends).
pub struct MentionMessage {
  mentions : Array[MentionRef]
  task : String
} derive(Debug)

///|
/// One mention-tag attribute in its wire representation. Keeping encoding and
/// decoding on the same type makes the text protocol a matched pair: quotes,
/// ampersands, angle brackets, and line breaks cannot terminate or reshape a
/// tag, while ordinary paths remain readable to the model.
priv struct MentionAttribute {
  wire : String
}

///|
fn MentionAttribute::encode(text : String) -> MentionAttribute {
  {
    wire: text
    .replace_all(old="&", new="&amp;")
    .replace_all(old="\"", new="&quot;")
    .replace_all(old="<", new="&lt;")
    .replace_all(old=">", new="&gt;")
    .replace_all(old="\r", new="&#13;")
    .replace_all(old="\n", new="&#10;"),
  }
}

///|
fn MentionAttribute::decode(wire : String) -> String {
  wire
  .replace_all(old="&quot;", new="\"")
  .replace_all(old="&lt;", new="<")
  .replace_all(old="&gt;", new=">")
  .replace_all(old="&#13;", new="\r")
  .replace_all(old="&#10;", new="\n")
  // `&amp;` is decoded last so an original literal such as `&quot;` remains
  // literal after its leading ampersand was encoded as `&amp;quot;`.
  .replace_all(old="&amp;", new="&")
}

///|
/// The compact text shared by transcript previews and sidebar labels. It
/// preserves the typed task while replacing the wire envelope with the same
/// glyph and label shown by each mention chip.
pub fn MentionMessage::display_text(self : MentionMessage) -> String {
  let parts : Array[String] = []
  if !self.task.is_empty() {
    parts.push(self.task)
  }
  for mention in self.mentions {
    parts.push(glyph(mention) + label(mention))
  }
  parts.join(" ")
}

///|
/// The editor location represented by a mention chip. Skills and unresolved
/// symbols have no target; comments on the original revision deliberately do
/// not point into the working file.
pub struct Target {
  file : String
  range : @common.Range?
  annotation : String?
} derive(Eq, Debug)

///|
/// The short marker displayed before a mention's label.
pub fn glyph(mention : MentionRef) -> String {
  match mention {
    ReviewChanges(_) => "⑂"
    Skill(_) => "$"
    File(_) => "@"
    Symbol(_) => "#"
    SemanticSearch(_) => "⌕"
    SemanticSearchArtifact(_) => "⌕"
    SemanticSearchPending(_) => "⌕"
    Annotation(_) => "✎"
  }
}

///|
/// Human-readable text for one mention chip.
pub fn label(mention : MentionRef) -> String {
  match mention {
    ReviewChanges(changes) => "Changes · \{changes.source.file}"
    Skill(name~) => name
    File(path~) => path
    Symbol(name~, ..) => name
    SemanticSearch(reference) => {
      let pattern_count = reference.patterns.length()
      let match_count = reference.matches.length()
      "Semantic search · \{pattern_count} patterns · \{match_count} matches"
    }
    SemanticSearchArtifact(artifact) =>
      "Semantic search · \{artifact.pattern_count} patterns · \{artifact.match_count} matches (file)"
    SemanticSearchPending(reference) =>
      "Semantic search · \{reference.patterns.length()} patterns · \{reference.matches.length()} matches (preparing file…)"
    Annotation(file~, start_line~, end_line~, side~, ..) => {
      let suffix = if side is OriginalRevision { " (original)" } else { "" }
      "\{file}:\{start_line}-\{end_line}\{suffix}"
    }
  }
}

///|
/// Resolve a mention into the working-file location its chip may open.
pub fn target(mention : MentionRef) -> Target? {
  match mention {
    ReviewChanges(_) | Skill(_) => None
    File(path~) => Some({ file: path, range: None, annotation: None, })
    Symbol(file~, line~, ..) =>
      if file.is_empty() {
        None
      } else {
        Some({
          file,
          range: if line >= 1 {
            Some(@common.Range(line, 1, line, 1))
          } else {
            None
          },
          annotation: None,
        })
      }
    SemanticSearch(_)
    | SemanticSearchArtifact(_)
    | SemanticSearchPending(_)
    | Annotation(side=OriginalRevision, ..) => None
    Annotation(
      file~,
      start_line~,
      end_line~,
      comment~,
      side=WorkingRevision,
      ..
    ) =>
      Some({
        file,
        range: Some(
          @common.Range(
            start_line,
            1,
            if end_line >= start_line {
              end_line
            } else {
              start_line
            },
            1,
          ),
        ),
        annotation: Some(comment),
      })
  }
}

///|
/// Encode the composer draft into the outgoing prompt: the typed task first,
/// then the chips inside the `<user_mentions>` block. Adjacent review files
/// share their workspace/base envelope. A draft with no chips is passed
/// through untouched, so ordinary prompts stay ordinary.
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
  let mut review_group : (String, String?)? = None
  for mention in mentions {
    let group = match mention {
      ReviewChanges(changes) =>
        Some((changes.source.workspace, changes.source.base))
      _ => None
    }
    if group != review_group {
      if review_group is Some(_) {
        parts <+ "</review_changes>\n"
      }
      if group is Some((workspace, base)) {
        write_review_header(parts, workspace, base)
      }
      review_group = group
    } else if group is Some(_) {
      parts <+ "\n"
    }
    write_mention(parts, mention)
  }
  if review_group is Some(_) {
    parts <+ "</review_changes>\n"
  }
  parts <+ "</user_mentions>"
  parts.to_string()
}

///|
fn write_mention(parts : StringBuilder, mention : MentionRef) -> Unit {
  match mention {
    ReviewChanges(changes) => write_review_file(parts, changes)
    Skill(name~) => {
      let name = MentionAttribute::encode(name).wire
      parts <+ "<skill name=\"\{name}\"/>\n"
    }
    File(path~) => {
      let path = MentionAttribute::encode(path).wire
      parts <+ "<file path=\"\{path}\"/>\n"
    }
    Symbol(name~, file~, line~) => {
      let name = MentionAttribute::encode(name).wire
      if file.is_empty() {
        parts <+ "<symbol name=\"\{name}\"/>\n"
      } else {
        let file = MentionAttribute::encode(file).wire
        parts <+
          "<symbol name=\"\{name}\" file=\"\{file}\" line=\"\{line}\"/>\n"
      }
    }
    SemanticSearch(reference) => write_semantic_search(parts, reference)
    SemanticSearchArtifact(artifact) => {
      let path = MentionAttribute::encode(artifact.path).wire
      parts <+
        "<semantic_search_file path=\"\{path}\" patterns=\"\{artifact.pattern_count}\" matches=\"\{artifact.match_count}\">\n"
      parts <+
        "This file is an immutable JSONL semantic-search selection snapshot. Inspect it selectively before reading broad source ranges.\n"
      parts <+ "</semantic_search_file>\n"
    }
    SemanticSearchPending(reference) => {
      let id = MentionAttribute::encode(reference.id).wire
      parts <+ "<semantic_search_pending id=\"\{id}\"/>\n"
    }
    Annotation(file~, start_line~, end_line~, quote~, comment~, side~) => {
      let file = MentionAttribute::encode(file).wire
      let side_attribute = match side {
        WorkingRevision => ""
        OriginalRevision => " side=\"original\""
      }
      parts <+
        "<annotation file=\"\{file}\" lines=\"\{start_line}-\{end_line}\"\{side_attribute}>\n"
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
fn write_semantic_search(
  parts : StringBuilder,
  reference : SemanticSearchReference,
) -> Unit {
  let id = MentionAttribute::encode(reference.id).wire
  let root = MentionAttribute::encode(reference.root).wire
  let include_value = MentionAttribute::encode(reference.include_glob).wire
  let exclude = MentionAttribute::encode(reference.exclude_glob).wire
  parts <+
    "<semantic_search id=\"\{id}\" root=\"\{root}\" include=\"\{include_value}\" exclude=\"\{exclude}\">\n"
  for pattern in reference.patterns {
    parts <+ "<pattern>\n"
    write_body(parts, pattern)
    parts <+ "</pattern>\n"
  }
  for hit in reference.matches {
    let file = MentionAttribute::encode(hit.file).wire
    let rule = hit.rule_id
      .map(id => " rule=\"\{MentionAttribute::encode(id).wire}\"")
      .unwrap_or("")
    let description = hit.description
      .map(text => " description=\"\{MentionAttribute::encode(text).wire}\"")
      .unwrap_or("")
    parts <+
      "<match file=\"\{file}\" lines=\"\{hit.start_line}-\{hit.end_line}\" columns=\"\{hit.start_column}-\{hit.end_column}\"\{rule}\{description}>\n"
    write_body(parts, hit.matched_source)
    parts <+ "</match>\n"
  }
  parts <+ "</semantic_search>\n"
}

///|
/// An element body, verbatim, ending in exactly one newline; an empty body
/// contributes no lines (its tags close ranks).
fn write_body(parts : StringBuilder, body : String) -> Unit {
  let body = body.trim_end(chars="\n")
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
/// merely mentions the tags is not misread as chips. Tagged attributes use
/// `MentionAttribute` encoding.
pub fn parse(content : String) -> MentionMessage? {
  let lines = content.split("\n").map(line => line.to_owned()).collect()
  let lines = if lines is [.. head, ""] { head } else { lines[:] }
  // Only normalize CRLF framing when the envelope itself uses it. A source
  // line's trailing CR inside our LF envelope belongs to the saved snapshot.
  let lines = if content
    .trim_end(chars="\r\n")
    .has_suffix("\r\n</user_mentions>") {
    lines.map(line => line.strip_suffix("\r").unwrap_or(line[:]).to_owned())
  } else {
    lines.to_owned()
  }
  guard lines is [.. head, "</user_mentions>"] else { return None }
  // Source bodies may themselves contain an opener. Try candidates from
  // the end until the whole envelope parses, keeping such source verbatim.
  for open = head.length() - 1; open >= 0; open = open - 1 {
    if head[open] == "<user_mentions>" &&
      parse_mention_block(head[open + 1:]) is Some(mentions) {
      return Some({ mentions, task: head[:open].join("\n").trim().to_owned(), })
    }
  }
  None
}

///|
/// `<skill name="..."/>`, alone on its line.
let skill_pattern : Regex = re"^<skill name=\"(?<name>[^\"]+)\"/>$"

///|
/// `<file path="..."/>`, alone on its line.
let file_pattern : Regex = re"^<file path=\"(?<path>[^\"]+)\"/>$"

///|
/// `<symbol name="..."/>` with an optional resolved location, self-closing or
/// opening a body of truncated source (`tail` is `/>` or `>`).
let symbol_pattern : Regex = re"^<symbol name=\"(?<name>[^\"]+)\"( file=\"(?<file>[^\"]+)\" line=\"(?<line>[0-9]+)\")?(?<tail>/>|>)$"

///|
/// `<annotation file="..." lines="start-end">`, optionally marked as an
/// original-revision line, opening the quote/comment body. An omitted side
/// denotes the working revision written by `encode`.
let annotation_pattern : Regex = re"^<annotation file=\"(?<file>[^\"]+)\" lines=\"(?<start>[0-9]+)-(?<end>[0-9]+)\"( side=\"(?<side>original)\")?>$"

///|
let semantic_search_pattern : Regex = re"^<semantic_search id=\"(?<id>[^\"]*)\" root=\"(?<root>[^\"]*)\" include=\"(?<include>[^\"]*)\" exclude=\"(?<exclude>[^\"]*)\">$"

///|
let semantic_search_file_pattern : Regex = re"^<semantic_search_file path=\"(?<path>[^\"]+)\" patterns=\"(?<patterns>[0-9]+)\" matches=\"(?<matches>[0-9]+)\">$"

///|
let semantic_match_pattern : Regex = re"^<match file=\"(?<file>[^\"]+)\" lines=\"(?<start>[0-9]+)-(?<end>[0-9]+)\" columns=\"(?<start_column>[0-9]+)-(?<end_column>[0-9]+)\"( rule=\"(?<rule>[^\"]*)\")?( description=\"(?<description>[^\"]*)\")?>$"

///|
/// The pre-review form is still accepted so saved transcripts can render
/// their semantic-search mention chips after the wire format changes.
let legacy_semantic_match_pattern : Regex = re"^<match pattern=\"[^\"]+\" file=\"(?<file>[^\"]+)\" lines=\"(?<start>[0-9]+)-(?<end>[0-9]+)\" columns=\"(?<start_column>[0-9]+)-(?<end_column>[0-9]+)\">$"

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
    if review_changes_pattern.execute(line) is Some(_) {
      guard parse_review_changes(lines[index:]) is Some((changes, consumed)) else {
        return None
      }
      mentions.append(changes.map(changes => ReviewChanges(changes)))
      index += consumed
      continue
    }
    if skill_pattern.execute(line) is Some(matched) {
      guard matched.named_group("name") is Some(name) else { return None }
      mentions.push(Skill(name=MentionAttribute::decode(name.to_owned())))
      index += 1
      continue
    }
    if file_pattern.execute(line) is Some(matched) {
      guard matched.named_group("path") is Some(path) else { return None }
      mentions.push(File(path=MentionAttribute::decode(path.to_owned())))
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
      mentions.push(
        Symbol(
          name=MentionAttribute::decode(name.to_owned()),
          file=MentionAttribute::decode(file),
          line=line_number,
        ),
      )
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
      let side = if matched.named_group("side") is Some(_) {
        OriginalRevision
      } else {
        WorkingRevision
      }
      guard lines[index + 1:].search("</annotation>") is Some(length) else {
        return None
      }
      let body = lines[index + 1:index + 1 + length]
      guard parse_annotation_body(body) is Some((quote, comment)) else {
        return None
      }
      mentions.push(
        Annotation(
          file=MentionAttribute::decode(file.to_owned()),
          start_line~,
          end_line~,
          quote~,
          comment~,
          side~,
        ),
      )
      index += length + 2
      continue
    }
    if semantic_search_file_pattern.execute(line) is Some(matched) {
      guard matched.named_group("path") is Some(path) &&
        matched.named_group("patterns") is Some(patterns) &&
        matched.named_group("matches") is Some(matches) else {
        return None
      }
      let body = lines[index + 1:]
      guard body.search("</semantic_search_file>") is Some(end) else {
        return None
      }
      mentions.push(
        SemanticSearchArtifact({
          path: MentionAttribute::decode(path.to_owned()),
          pattern_count: @string.parse_int(patterns) catch {
            _ => return None
          },
          match_count: @string.parse_int(matches) catch {
            _ => return None
          },
        }),
      )
      index += end + 3
      continue
    }
    if semantic_search_pattern.execute(line) is Some(matched) {
      guard matched.named_group("id") is Some(id) &&
        matched.named_group("root") is Some(root) &&
        matched.named_group("include") is Some(include_value) &&
        matched.named_group("exclude") is Some(exclude) else {
        return None
      }
      let patterns : Array[String] = []
      let matches : Array[SemanticSearchReferenceMatch] = []
      let mut cursor = index + 1
      while cursor < lines.length() && lines[cursor] != "</semantic_search>" {
        let pattern_line = lines[cursor]
        guard pattern_line == "<pattern>" else {
          let match_header = match
            semantic_match_pattern.execute(pattern_line) {
            Some(matched) => Some(matched)
            None => legacy_semantic_match_pattern.execute(pattern_line)
          }
          if match_header is Some(match_header) {
            guard match_header.named_group("file") is Some(file) &&
              match_header.named_group("start") is Some(start) &&
              match_header.named_group("end") is Some(end) &&
              match_header.named_group("start_column") is Some(start_column) &&
              match_header.named_group("end_column") is Some(end_column) else {
              return None
            }
            let match_body = lines[cursor + 1:]
            let (source, consumed) = if match_body
              is ["<matched_source>", .. source_lines] {
              guard source_lines.search("</matched_source>") is Some(source_end) else {
                return None
              }
              guard source_lines[source_end + 1:] is ["</match>", ..] else {
                return None
              }
              (source_lines[:source_end].join("\n"), source_end + 4)
            } else {
              guard match_body.search("</match>") is Some(match_end) else {
                return None
              }
              (match_body[:match_end].join("\n"), match_end + 2)
            }
            matches.push({
              rule_id: match_header
              .named_group("rule")
              .map(rule => MentionAttribute::decode(rule.to_owned())),
              description: match_header
              .named_group("description")
              .map(text => MentionAttribute::decode(text.to_owned())),
              file: MentionAttribute::decode(file.to_owned()),
              start_line: @string.parse_int(start) catch {
                _ => return None
              },
              start_column: @string.parse_int(start_column) catch {
                _ => return None
              },
              end_line: @string.parse_int(end) catch {
                _ => return None
              },
              end_column: @string.parse_int(end_column) catch {
                _ => return None
              },
              matched_source: source,
            })
            cursor += consumed
            continue
          }
          return None
        }
        let pattern_lines = lines[cursor + 1:]
        guard pattern_lines.search("</pattern>") is Some(pattern_end) else {
          return None
        }
        patterns.push(pattern_lines[:pattern_end].join("\n"))
        cursor += pattern_end + 2
      }
      guard cursor < lines.length() && lines[cursor] == "</semantic_search>" else {
        return None
      }
      mentions.push(
        SemanticSearch({
          id: MentionAttribute::decode(id.to_owned()),
          root: MentionAttribute::decode(root.to_owned()),
          patterns,
          include_glob: MentionAttribute::decode(include_value.to_owned()),
          exclude_glob: MentionAttribute::decode(exclude.to_owned()),
          matches,
        }),
      )
      index = cursor + 1
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

///|
pub extend AnnotationSide with Debug::{to_repr}

///|
pub extend AnnotationSide with Eq::{equal, not_equal}

///|
pub extend SemanticSearchReference with Eq::{equal, not_equal}

///|
pub extend SemanticSearchReference with Debug::{to_repr}

///|
pub extend SemanticSearchReferenceMatch with Eq::{equal, not_equal}

///|
pub extend SemanticSearchReferenceMatch with Debug::{to_repr}

///|
pub extend SemanticSearchArtifact with Eq::{equal, not_equal}

///|
pub extend SemanticSearchArtifact with Debug::{to_repr}

///|
pub extend MentionMessage with Debug::{to_repr}

///|
pub extend MentionRef with Debug::{to_repr}

///|
pub extend MentionRef with Eq::{equal, not_equal}

///|
pub extend Target with Debug::{to_repr}

///|
pub extend Target with Eq::{equal, not_equal}
