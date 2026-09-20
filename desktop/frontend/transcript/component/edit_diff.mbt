// The `edit` and `multi_edit` tools' arguments, read back out of the
// transcript as the change they describe.
//
// Their payload states a replacement as two separate fields — `old_string` and
// `new_string` — and the generic rendering prints both, JSON-escaped, one
// after the other. What the model actually did is the difference between them,
// and reading it out of two escaped blobs is work a reader should not be
// doing. The card below synthesizes the diff, the way `viz` does for the same
// two tools. Detailed mode keeps argument chips; minimal mode uses a file
// titlebar and the shared editor diff preview with source-line gutters.
//
// The diff is *derived*, not recorded: it is these two strings compared, not
// what the tool wrote to the file. Whether the edit applied at all is the
// paired result — a rejected call still renders, because the change it asked
// for is what a reader is trying to see. Only the file and line anchors
// accompany the diff; every other argument stays in the recorded payload,
// which detailed mode keeps a click away in its Original JSON tab.

///|
/// One recorded edit with structured coordinates and a bounded numbered
/// preview. Detailed mode retains its argument chips; copying uses the full diff.
priv struct EditDiff {
  anchors : Array[String]
  diff : String
  path : String?
  start_line : Int?
  lines : Array[EditDiffLine]
} derive(Eq)

///|
/// How many edits of a `multi_edit` batch to render. A batch is built by a
/// script and can be long, and every edit's diff is built on every render even
/// behind a collapsed card. What is dropped is stated in the card rather than
/// silently truncated, and the Original JSON still carries the whole batch.
const MAX_RENDERED_EDITS = 50

///|
/// The decoded change an `edit` or `multi_edit` call asked for, shared by both
/// transcript modes: one anchored diff per readable entry, and how many
/// entries are not shown. `None` for any other tool and for a payload with no
/// readable edit — a batch whose entries are only partly readable renders the
/// ones that are, since dropping the whole card would hide the edits that did
/// decode. Holding derived text rather than raw arguments keeps the minimal
/// projection structurally comparable.
priv struct EditChanges {
  edits : Array[EditDiff]
  omitted : Int
} derive(Eq)

///|
fn EditChanges::from_arguments(
  name : String,
  arguments : String,
) -> EditChanges? {
  guard name == "edit" || name == "multi_edit" else { return None }
  guard card_fields(arguments) is Some(fields) else { return None }
  if name == "edit" {
    if EditDiff::from_fields(fields, path_key="path") is Some(edit) {
      return Some({ edits: [edit], omitted: 0, })
    }
    // Codex supplies recorded unified patches rather than old/new snippets.
    // Reuse those patches verbatim; do not reconstruct full file contents or
    // interpret headers as proof that a failed request applied successfully.
    guard fields.get("changes") is Some(Array(entries)) else { return None }
    let edits : Array[EditDiff] = []
    for entry in entries {
      if edits.length() == MAX_RENDERED_EDITS {
        break
      }
      if entry is Object(change) &&
        change.get("diff") is Some(String(diff)) &&
        !diff.is_blank() {
        let anchors : Array[String] = []
        if change.get("path") is Some(path) &&
          chip_text("path", path) is Some(anchor) {
          anchors.push(anchor)
        }
        let path = if change.get("path") is Some(String(path)) &&
          !path.is_blank() {
          Some(path)
        } else {
          None
        }
        edits.push(EditDiff::new(anchors, path, None, diff, unified=true))
      }
    }
    guard !edits.is_empty() else { return None }
    return Some({ edits, omitted: entries.length() - edits.length(), })
  }
  guard fields.get("edits") is Some(Array(entries)) else { return None }
  let edits : Array[EditDiff] = []
  for entry in entries {
    if edits.length() == MAX_RENDERED_EDITS {
      break
    }
    if entry is Object(entry_fields) &&
      EditDiff::from_fields(entry_fields, path_key="file") is Some(edit) {
      edits.push(edit)
    }
  }
  guard !edits.is_empty() else { return None }
  // `entries` counts what the model sent, including entries this card could
  // not read, which is what the reader is being told about.
  Some({ edits, omitted: entries.length() - edits.length(), })
}

///|
/// A batch longer than the card renders says so, rather than reading as the
/// whole batch. The wording names only what is missing: minimal mode has no
/// Original JSON tab to point at.
fn EditChanges::render(self : EditChanges) -> @html.Html {
  let body : Array[@html.Html] = []
  for edit in self.edits {
    body.push(
      @html.div(class="edit-entry", [
        chip_row(edit.anchors),
        diff_block(edit.diff),
      ]),
    )
  }
  if self.omitted > 0 {
    body.push(
      @html.div(
        class="edit-omitted",
        "⋯ \{self.omitted} more edits not shown ⋯",
      ),
    )
  }
  @html.div(class="edit-args", body)
}

///|
/// Decode one edit-shaped object — `edit`'s own arguments, or one entry of a
/// `multi_edit` batch — into the chips that anchor it and the diff between its
/// two strings. `None` when it is not an edit this card can show: no string
/// pair, or a pair with no difference (which the tools reject anyway, and
/// which would render as an empty change).
fn EditDiff::from_fields(
  fields : Map[String, Json],
  path_key~ : String,
) -> EditDiff? {
  guard fields.get("old_string") is Some(String(old)) &&
    fields.get("new_string") is Some(String(new)) &&
    old != new else {
    return None
  }
  // The order the tools' schemas list them in: what file, then where in it.
  let anchors : Array[String] = []
  for key in [path_key, "start_line", "end_line"] {
    if fields.get(key) is Some(value) && chip_text(key, value) is Some(text) {
      anchors.push(text)
    }
  }
  let path = if fields.get(path_key) is Some(String(path)) && !path.is_blank() {
    Some(path)
  } else {
    None
  }
  let start_line : Int? = fields
    .get("start_line")
    .bind(value => {
      let line : Int = @json.from_json(value) catch { _ => return None }
      if value is Number(number, ..) && line > 0 && number == line.to_double() {
        Some(line)
      } else {
        None
      }
    })
  Some(EditDiff::new(anchors, path, start_line, @edit_diff.generate(old, new)))
}

///|
/// Synthesized snippets and recorded unified patches share colored lines:
/// `+` added, `-` removed; file headers and other lines are context, including
/// the skip marker `truncate_output` leaves in a long change.
fn diff_block(text : String) -> @html.Html {
  let mut in_hunk = false
  let lines : Array[@html.Html] = [
    for raw in truncate_output(text, line_prefix_width=2).split("\n") => {
      let line = raw.to_owned()
      if line.has_prefix("@@ ") {
        in_hunk = true
      }
      // File headers precede hunks. Inside a hunk even "+++" can be added
      // source text, so it must retain the addition color.
      let header = !in_hunk &&
        (line.has_prefix("+++ ") || line.has_prefix("--- "))
      let cls = if !header && line.has_prefix("+") {
        "diff-add"
      } else if !header && line.has_prefix("-") {
        "diff-del"
      } else {
        "diff-ctx"
      }
      @html.div(class=cls, line)
    }
  ]
  @html.div(class="tool-diff", lines)
}

///|
/// Numbers are computed before display truncation. Omitted rows must still
/// advance each side, and a unified hunk resets both absolute positions.
priv struct EditDiffLine {
  text : String
  old_line : Int?
  new_line : Int?
  class_name : String
  source_offset : Int?
  truncated : Bool
} derive(Eq)

///|
fn EditDiff::new(
  anchors : Array[String],
  path : String?,
  start_line : Int?,
  diff : String,
  unified? : Bool = false,
) -> EditDiff {
  let mut old_line = start_line
  let mut new_line = start_line
  let mut first_line = start_line
  let mut in_hunk = !unified
  let rows : Array[EditDiffLine] = []
  for raw in diff.split("\n") {
    let text = raw.to_owned()
    if unified && text.has_prefix("@@ ") {
      // Parse only the coordinates; section names after @@ are source text.
      let fields = [..text.split(" ")]
      old_line = None
      new_line = None
      in_hunk = false
      if fields.length() >= 4 &&
        fields[3] == "@@" &&
        fields[1].has_prefix("-") &&
        fields[2].has_prefix("+") {
        let old_start = fields[1][1:].split(",").next()
        let new_start = fields[2][1:].split(",").next()
        old_line = old_start.bind(value => {
          try {
            let n = @string.parse_int(value)
            if n >= 0 {
              Some(n)
            } else {
              None
            }
          } catch {
            _ => None
          }
        })
        new_line = new_start.bind(value => {
          try {
            let n = @string.parse_int(value)
            if n >= 0 {
              Some(n)
            } else {
              None
            }
          } catch {
            _ => None
          }
        })
        in_hunk = old_line is Some(_) && new_line is Some(_)
        if first_line is None && in_hunk {
          first_line = new_line.map(line => line.max(1))
        }
      }
      rows.push({
        text,
        old_line: None,
        new_line: None,
        class_name: "diff-ctx",
        source_offset: None,
        truncated: false,
      })
      continue
    }
    let added = in_hunk && text.has_prefix("+")
    let removed = in_hunk && text.has_prefix("-")
    let context = in_hunk && text.has_prefix(" ")
    let source_offset = if added || removed || context {
      Some(if unified { 1 } else { 2 })
    } else {
      None
    }
    rows.push({
      source_offset,
      truncated: false,
      text,
      old_line: if removed || context {
        old_line
      } else {
        None
      },
      new_line: if added || context {
        new_line
      } else {
        None
      },
      class_name: if added {
        "diff-add"
      } else if removed {
        "diff-del"
      } else {
        "diff-ctx"
      },
    })
    if removed || context {
      old_line = old_line.bind(line => {
        if line < 2147483647 {
          Some(line + 1)
        } else {
          None
        }
      })
    }
    if added || context {
      new_line = new_line.bind(line => {
        if line < 2147483647 {
          Some(line + 1)
        } else {
          None
        }
      })
    }
  }
  // Keep the same head/tail proportions as the transcript's text previews.
  // Bound characters as well as rows, but retain each surviving row's number.
  let visible : Array[EditDiffLine] = []
  let mut head_chars = 0
  let mut head_end = 0
  while head_end < rows.length() && head_end < 60 && head_chars < 12000 {
    let row = rows[head_end]
    let text = if row.text.length() > 12000 - head_chars {
      row.text[:12000 - head_chars].to_owned() + "…"
    } else {
      row.text
    }
    visible.push({ ..row, text, truncated: text != row.text, })
    head_chars += row.text.length()
    head_end += 1
  }
  let mut tail_start = rows.length()
  let mut tail_chars = 0
  let tail : Array[EditDiffLine] = []
  while tail_start > head_end &&
        rows.length() - tail_start < 40 &&
        tail_chars < 8000 {
    tail_start -= 1
    let row = rows[tail_start]
    let text = if row.text.length() > 8000 - tail_chars {
      row.text[:8000 - tail_chars].to_owned() + "…"
    } else {
      row.text
    }
    tail.push({ ..row, text, truncated: text != row.text, })
    tail_chars += row.text.length()
  }
  if tail_start > head_end {
    visible.push({
      source_offset: None,
      truncated: false,
      text: "⋯ \{tail_start - head_end} lines skipped ⋯",
      old_line: None,
      new_line: None,
      class_name: "diff-ctx",
    })
  }
  for row in tail.rev_iter() {
    visible.push(row)
  }
  { anchors, path, start_line: first_line, diff, lines: visible, }
}

///|
/// Minimal mode keeps source coordinates in the gutter. Its title opens the
/// current review at the recorded location even if later edits changed it.
fn EditChanges::render_minimal(
  locale? : @i18n.Locale = English,
  self : EditChanges,
  actions : Actions,
) -> @html.Html {
  let entries : Array[@html.Html] = []
  for index, edit in self.edits {
    let name = match edit.path {
      Some(path) => path
      None => ui(locale, RequestedChanges)
    }
    let coordinate = match edit.start_line {
      Some(line) => " L\{line}"
      None => ""
    }
    let label = "\{name}\{coordinate} · \{index + 1}"
    let preview = @syntax_html.diff_preview(
      edit.preview_lines(),
      label~,
      tokenizer?=edit_tokenizer(edit.path),
    )
    entries.push(
      @html.div(class="edit-entry minimal-edit-block", [
        @html.div(class="edit-titlebar", [
          if edit.path is Some(path) {
            @html.button(
              class="edit-path",
              type_="button",
              title=ui(locale, OpenDiffReview) + ": " + path,
              on_click=(actions.review)((path, edit.start_line)),
              path,
            )
          } else {
            @html.span(class="edit-path-label", ui(locale, ChangeLabel))
          },
          @markdown.copy_button(
            edit.diff,
            class="icon-button edit-copy",
            title=ui(locale, CopyDiff),
            label=ui(locale, CopyDiff),
          ),
        ]),
        @html.div(class="minimal-diff-preview moonbit-source", preview),
      ]),
    )
  }
  if self.omitted > 0 {
    entries.push(
      @html.div(
        class="edit-omitted",
        "⋯ \{self.omitted} more edits not shown ⋯",
      ),
    )
  }
  @html.div(class="edit-args", entries)
}

///|
/// File headers stay in the copied patch and detailed view. Minimal previews
/// show source rows; hunk boundaries and omitted rows reset lexical context.
fn EditDiff::preview_lines(self : EditDiff) -> Array[@syntax_html.DiffLine] {
  let rows : Array[@syntax_html.DiffLine] = []
  let mut gap = false
  for line in self.lines {
    if line.source_offset is Some(offset) && offset <= line.text.length() {
      if gap && !rows.is_empty() {
        rows.push(Gap)
      }
      gap = false
      let source = line.text[offset:].to_owned()
      rows.push(
        match line.class_name {
          "diff-add" => Added(source, line=line.new_line)
          "diff-del" => Removed(source, line=line.old_line)
          _ => Context(source, old_line=line.old_line, new_line=line.new_line)
        },
      )
      gap = line.truncated
    } else {
      gap = true
    }
  }
  // Preserve unfamiliar or malformed recorded patches as escaped text.
  if rows.is_empty() {
    for line in self.lines {
      rows.push(Context(line.text, old_line=None, new_line=None))
    }
  }
  rows
}
