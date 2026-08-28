// The pieces a custom tool card is built from.
//
// A custom card renders one tool's arguments in the shape a reader wants — an
// `edit` as a diff instead of the pretty-printed JSON the generic path shows.
// Every card needs the same two things around that shape: a row of chips for
// the arguments it did not dramatize, and the recorded payload itself, so the
// card is a reading of the call and never the only account of it.
// `mbtx` uses the same pieces for its Program view.

///|
/// The custom card for a tool whose arguments have a shape the recorded JSON
/// hides, with the section label it goes under. `None` for every other tool
/// and for a payload the card cannot read — both keep the generic rendering,
/// so a card never has to invent a reading of a call it does not understand.
fn custom_card(name : String, arguments : String) -> (String, @html.Html)? {
  match name {
    "mbtx" => mbtx_card(arguments).map(card => ("Program", card))
    "edit" => edit_card(arguments).map(card => ("Change", card))
    "multi_edit" => multi_edit_card(arguments).map(card => ("Changes", card))
    _ => None
  }
}

///|
/// A chip's value, clamped so one pathological argument cannot push the meta
/// row across the transcript. What a card dramatizes (a program, a diff) is
/// clamped separately, by the shared `truncate_output`.
const MAX_CHIP_CHARS = 120

///|
/// The scalar arguments in `fields` as `key: value` chip text: the keys in
/// `known` first, in that order, then anything else sorted, and never the keys
/// in `dramatized` — those are what the card itself is showing.
///
/// The order matters. The recorded JSON's own field order is whatever the
/// model emitted, and the parsed map does not promise to preserve it, so
/// without a fixed order the chip row could reorder itself between two
/// identical calls.
fn scalar_chips(
  fields : Map[String, Json],
  known~ : Array[String],
  dramatized~ : Array[String],
) -> Array[String] {
  let others : Array[String] = []
  for key, _ in fields {
    if !dramatized.contains(key) && !known.contains(key) {
      others.push(key)
    }
  }
  others.sort()
  let chips : Array[String] = []
  for key in [..known.filter(key => fields.get(key) is Some(_)), ..others] {
    if fields.get(key) is Some(value) && chip_text(key, value) is Some(text) {
      chips.push(text)
    }
  }
  chips
}

///|
/// One argument as chip text, or `None` for a value the chip row cannot state
/// in one line, which the Original JSON view carries instead. A JSON
/// null is a tool's own spelling of "unset", so it gets no chip either:
/// `target: null` would report a choice the model did not make.
fn chip_text(key : String, value : Json) -> String? {
  let text = match value {
    String(text) => text
    True => "true"
    False => "false"
    Number(number, repr~) =>
      match repr {
        Some(text) => text
        None => number.to_string()
      }
    Null => return None
    Object(_) | Array(_) => return None
  }
  let text = if text.length() > MAX_CHIP_CHARS {
    text.clamped_view(end=MAX_CHIP_CHARS).to_owned() + "…"
  } else {
    text
  }
  Some("\{key}: \{text}")
}

///|
/// A card's chip row, or nothing when the call set no argument worth a chip.
fn chip_row(chips : Array[String]) -> @html.Html {
  if chips.is_empty() {
    return @html.nothing
  }
  @html.div(
    class="tool-card-meta",
    chips.map(chip => @html.span(class="tool-card-chip", chip)),
  )
}

///|
/// Pretty-printed recorded arguments for a tool's Original JSON tab.
fn original_json_content(arguments : String) -> @html.Html {
  let bounded = truncate_output(arguments)
  let pretty = truncate_output(
    @json.parse(bounded).stringify(indent=2) catch {
      _ => bounded
    },
  )
  @html.pre(class="tool-card-original-json", pretty)
}

///|
/// The read tool's exact numbered protocol behind a closed disclosure. The
/// friendly view may drop protocol separators, but debugging can still inspect
/// the unmodified output and status footer.
fn original_output_view(content : String) -> @html.Html {
  @html.details(class="tool-card-original", [
    @html.summary(class="tool-card-original-summary", "Original output"),
    @html.pre(class="tool-card-original-json", content),
  ])
}

///|
/// Ceiling on a recorded payload worth decoding for a custom card, in UTF-16
/// code units.
///
/// Every render decodes, including one behind a collapsed `details` (a
/// collapsed node is still built), and the transcript records a call's
/// arguments whether or not the tool accepted them — so a degenerate payload
/// reaches these cards too. Past this bound the call keeps the generic
/// rendering, which clamps before parsing. It is a cost guard, not a second
/// copy of any tool's validation.
const MAX_CARD_PAYLOAD_CHARS = 128_000

///|
/// The parsed object of a recorded payload small enough to render as a card,
/// or `None` when it is too large, not JSON, or not an object.
fn card_fields(arguments : String) -> Map[String, Json]? {
  if arguments.length() > MAX_CARD_PAYLOAD_CHARS {
    return None
  }
  let json = @json.parse(arguments) catch { _ => return None }
  guard json is Object(fields) else { return None }
  Some(fields)
}
