// The `edit` and `multi_edit` tools' arguments, read back out of the
// transcript as the change they describe.
//
// Their payload states a replacement as two separate fields — `old_string` and
// `new_string` — and the generic rendering prints both, JSON-escaped, one
// after the other. What the model actually did is the difference between them,
// and reading it out of two escaped blobs is work a reader should not be
// doing. The card below synthesizes the diff, the way `viz` does for the same
// two tools, and states the anchors (`path`/`file`, `start_line`) as chips.
//
// The diff is *derived*, not recorded: it is these two strings compared, not
// what the tool wrote to the file. Whether the edit applied at all is the
// paired result — a rejected call still renders, because the change it asked
// for is what a reader is trying to see. Only the file and line anchors
// accompany the diff; every other argument stays in the recorded payload,
// which detailed mode keeps a click away in its Original JSON tab.

///|
/// One decoded edit: the file and line chips that place it, and the diff it
/// describes.
priv struct EditDiff {
  anchors : Array[String]
  diff : String
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
    guard decode_edit(fields, path_key="path") is Some(edit) else {
      return None
    }
    return Some({ edits: [edit], omitted: 0, })
  }
  guard fields.get("edits") is Some(Array(entries)) else { return None }
  let edits : Array[EditDiff] = []
  for entry in entries {
    if edits.length() == MAX_RENDERED_EDITS {
      break
    }
    if entry is Object(entry_fields) &&
      decode_edit(entry_fields, path_key="file") is Some(edit) {
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
fn decode_edit(fields : Map[String, Json], path_key~ : String) -> EditDiff? {
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
  Some({ anchors, diff: @edit_diff.generate(old, new), })
}

///|
/// A synthesized diff as colored lines: `+ ` added, `- ` removed, anything
/// else context — including the skip marker `truncate_output` leaves behind in
/// a long change, which is context about the diff itself.
fn diff_block(text : String) -> @html.Html {
  let lines : Array[@html.Html] = [
    for raw in truncate_output(text, line_prefix_width=2).split("\n") => {
      let line = raw.to_owned()
      let cls = if line.has_prefix("+ ") {
        "diff-add"
      } else if line.has_prefix("- ") {
        "diff-del"
      } else {
        "diff-ctx"
      }
      @html.div(class=cls, line)
    }
  ]
  @html.div(class="tool-diff", lines)
}
