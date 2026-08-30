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
// for is what a reader is trying to see. The recorded payload stays a click
// away in the shared Original JSON tab.

///|
/// One edit's rendering: the chips that anchor it and the diff it describes.
priv struct EditDiff {
  chips : Array[String]
  diff : String
}

///|
/// How many edits of a `multi_edit` batch to render. A batch is built by a
/// script and can be long, and every edit's diff is built on every render even
/// behind a collapsed card. What is dropped is stated in the card rather than
/// silently truncated, and the Original JSON still carries the whole batch.
const MAX_RENDERED_EDITS = 50

///|
/// The card body for an `edit` call: the change it asked for as a diff, under
/// the chips that anchor it. `None` when the payload is not a readable edit —
/// it then keeps the generic JSON rendering, which clamps before parsing.
fn edit_card(arguments : String) -> @html.Html? {
  guard card_fields(arguments) is Some(fields) else { return None }
  guard decode_edit(fields, path_key="path") is Some(edit) else { return None }
  Some(
    @html.div(class="edit-args", [chip_row(edit.chips), diff_block(edit.diff)]),
  )
}

///|
/// The card body for a `multi_edit` call: one anchored diff per edit in the
/// batch, under the chips for the call's own arguments. `None` when the
/// payload carries no readable edit at all; a batch whose entries are only
/// partly readable renders the ones that are, and the rest stay in the
/// original — dropping the whole card would hide the edits that did decode.
fn multi_edit_card(arguments : String) -> @html.Html? {
  guard card_fields(arguments) is Some(fields) else { return None }
  guard fields.get("edits") is Some(Array(entries)) else { return None }
  let rendered : Array[@html.Html] = []
  let mut shown = 0
  for entry in entries {
    if shown == MAX_RENDERED_EDITS {
      break
    }
    guard entry is Object(entry_fields) &&
      decode_edit(entry_fields, path_key="file") is Some(edit) else {
      continue
    }
    shown += 1
    rendered.push(
      @html.div(class="edit-entry", [
        chip_row(edit.chips),
        diff_block(edit.diff),
      ]),
    )
  }
  if rendered.is_empty() {
    return None
  }
  let body : Array[@html.Html] = [
    chip_row(
      scalar_chips(
        fields,
        known=[
          "edits_file", "revert_when_errors_above", "revert_on_parse_errors",
        ],
        dramatized=["edits"],
      ),
    ),
    ..rendered,
  ]
  // A batch longer than the card renders says so, rather than reading as the
  // whole batch. `entries` counts what the model sent, including entries this
  // card could not read, which is what the reader is being told about.
  if entries.length() > shown {
    body.push(
      @html.div(
        class="edit-omitted",
        "⋯ \{entries.length() - shown} more edits, in the original ⋯",
      ),
    )
  }
  Some(@html.div(class="edit-args", body))
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
  let chips = scalar_chips(
    fields,
    // The order the tools' schemas list them in: what file, then where in it.
    known=[
      path_key, "start_line", "end_line", "replace_all_preview", "revert_on_parse_errors",
    ],
    dramatized=["old_string", "new_string"],
  )
  Some({ chips, diff: @edit_diff.generate(old, new), })
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
