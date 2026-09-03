// The `edit` and `multi_edit` tools' arguments, read back out of the
// transcript as the change they describe.
//
// OpenSeek tool calls state a replacement as two separate fields —
// `old_string` and `new_string` — while Codex app-server file-change items
// record a unified `diff`. The generic rendering leaves either form buried in
// JSON. The card below synthesizes the first form, reads the second verbatim,
// and states the anchors (`path`/`file`, `start_line`) as chips.
//
// For an OpenSeek tool call the diff is derived from its recorded request and
// the paired result says whether it applied. For Codex the diff itself is the
// recorded file-change payload. A rejected OpenSeek call still renders the
// change it requested, and both forms keep their exact payload a click away in
// the shared Original JSON tab.

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
/// The card body for an `edit` row: the requested or recorded change as a diff,
/// under the chips that anchor it. `None` when the payload is not readable — it
/// then keeps the generic JSON rendering, which clamps before parsing.
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
/// `multi_edit` batch — into the chips that anchor it and its diff. OpenSeek's
/// tools describe the change as `old_string` plus `new_string`; Codex app-server
/// records the applied unified `diff` directly. Both are exact recorded
/// semantics, so the shared card accepts either without attempting to derive
/// one protocol from the other.
fn decode_edit(fields : Map[String, Json], path_key~ : String) -> EditDiff? {
  let diff = match (fields.get("old_string"), fields.get("new_string")) {
    (Some(String(old)), Some(String(new))) if old != new =>
      @edit_diff.generate(old, new)
    _ =>
      match fields.get("diff") {
        Some(String(diff)) if !diff.is_blank() => diff
        _ => return None
      }
  }
  let anchor_key = if fields.get(path_key) is Some(_) {
    path_key
  } else if fields.get("path") is Some(_) {
    // Codex uses `path` for every entry, including a multi-file patch;
    // OpenSeek's `multi_edit` calls use `file`.
    "path"
  } else {
    path_key
  }
  let chips = scalar_chips(
    fields,
    // The order the tools' schemas list them in: what file, then where in it.
    known=[
      anchor_key, "start_line", "end_line", "replace_all_preview", "revert_on_parse_errors",
    ],
    dramatized=["old_string", "new_string", "diff"],
  )
  Some({ chips, diff, })
}

///|
/// A synthesized or recorded diff as colored lines. `+++` and `---` unified
/// headers remain context; other leading `+`/`-` lines are additions/removals.
/// The skip marker `truncate_output` leaves in a long change is context too.
fn diff_block(text : String) -> @html.Html {
  let lines : Array[@html.Html] = [
    for raw in truncate_output(text, line_prefix_width=2).split("\n") => {
      let line = raw.to_owned()
      let cls = if line.has_prefix("+") && !line.has_prefix("+++") {
        "diff-add"
      } else if line.has_prefix("-") && !line.has_prefix("---") {
        "diff-del"
      } else {
        "diff-ctx"
      }
      @html.div(class=cls, line)
    }
  ]
  @html.div(class="tool-diff", lines)
}
