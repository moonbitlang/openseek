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
// for is what a reader is trying to see. Detailed mode keeps the recorded
// payload in its Original JSON tab. Minimal mode shares this diff but shows
// only file/line anchors, with no raw payload.

///|
/// One edit's rendering: the chips that anchor it and the diff it describes.
priv struct EditDiff {
  chips : Array[String]
  diff : String
} derive(Eq)

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
  EditChanges::from_arguments("edit", arguments).map(changes => {
    changes.render(original_available=true)
  })
}

///|
fn multi_edit_card(arguments : String) -> @html.Html? {
  EditChanges::from_arguments("multi_edit", arguments).map(changes => {
    changes.render(original_available=true)
  })
}

///|
/// Both transcript modes share bounded decoding and the same single-column
/// diff. Keep derived data, not raw arguments or editor instances, in the
/// minimal projection so structural equality still skips unchanged views.
priv struct EditChanges {
  chips : Array[String]
  edits : Array[EditDiff]
  omitted : Int
} derive(Eq)

///|
fn EditChanges::from_arguments(
  name : String,
  arguments : String,
  minimal? : Bool = false,
) -> EditChanges? {
  guard name == "edit" || name == "multi_edit" else { return None }
  guard card_fields(arguments) is Some(fields) else { return None }
  if name == "edit" {
    guard EditDiff::from_fields(fields, path_key="path", minimal~) is Some(edit) else {
      return None
    }
    return Some({ chips: [], edits: [edit], omitted: 0, })
  }
  guard fields.get("edits") is Some(Array(entries)) else { return None }
  let edits : Array[EditDiff] = []
  for entry in entries {
    if edits.length() == MAX_RENDERED_EDITS {
      break
    }
    if entry is Object(entry_fields) &&
      EditDiff::from_fields(entry_fields, path_key="file", minimal~)
      is Some(edit) {
      edits.push(edit)
    }
  }
  guard !edits.is_empty() else { return None }
  Some({
    chips: if minimal {
      []
    } else {
      scalar_chips(
        fields,
        known=[
          "edits_file", "revert_when_errors_above", "revert_on_parse_errors",
        ],
        dramatized=["edits"],
      )
    },
    edits,
    omitted: entries.length() - edits.length(),
  })
}

///|
fn EditChanges::render(
  self : EditChanges,
  original_available~ : Bool,
) -> @html.Html {
  let body : Array[@html.Html] = [chip_row(self.chips)]
  for edit in self.edits {
    body.push(
      @html.div(class="edit-entry", [
        chip_row(edit.chips),
        diff_block(edit.diff),
      ]),
    )
  }
  // Invalid entries and entries beyond the display cap are both accounted for.
  // Minimal mode has no Original JSON tab to send the reader to.
  if self.omitted > 0 {
    body.push(
      @html.div(
        class="edit-omitted",
        if original_available {
          "⋯ \{self.omitted} more edits, in the original ⋯"
        } else {
          "⋯ \{self.omitted} edits not shown · enable transcript details to inspect the original ⋯"
        },
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
  minimal? : Bool = false,
) -> EditDiff? {
  guard fields.get("old_string") is Some(String(old)) &&
    fields.get("new_string") is Some(String(new)) &&
    old != new else {
    return None
  }
  let chips = if minimal {
    // Only anchors accompany the diff; other scalar arguments remain exclusive
    // to detailed mode. Never disclose a whole payload through metadata chips.
    let anchors : Array[String] = []
    for key in [path_key, "start_line", "end_line"] {
      if fields.get(key) is Some(value) && chip_text(key, value) is Some(text) {
        anchors.push(text)
      }
    }
    anchors
  } else {
    scalar_chips(
      fields,
      // The order the tools' schemas list them in: what file, then where in it.
      known=[
        path_key, "start_line", "end_line", "replace_all_preview", "revert_on_parse_errors",
      ],
      dramatized=["old_string", "new_string"],
    )
  }
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
