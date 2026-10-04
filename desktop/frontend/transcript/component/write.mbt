// The `write` tool's arguments, read back out of the transcript.
//
// A write carries a whole file body in one JSON string. The generic arguments
// view already lifts it out of its quotes, but leaves it as uncolored text;
// the card below shows it as numbered source, highlighted by the same
// extension policy `edit` diffs use, under a chip row for the path and any
// other scalar arguments. The recorded payload stays in the neighboring
// Original JSON tab.

///|
/// The Content view for a `write` call, or `None` when the payload is not a
/// call this card can show, which keeps the generic rendering.
///
/// Like the `mbtx` source, the body skips `truncate_output` so diagnostics
/// that cite `line:column` positions still match the numbers: `card_fields`
/// refuses payloads past the shared ceiling, and the numbered renderer clamps
/// a degenerate line count itself.
fn write_card(
  locale? : @i18n.Locale = English,
  arguments : String,
) -> (String, @html.Html)? {
  guard card_fields(arguments) is Some(fields) &&
    fields.get("content") is Some(String(content)) else {
    return None
  }
  let path = match fields.get("path") {
    Some(String(path)) => Some(path)
    _ => None
  }
  let chips = scalar_chips(fields, known=["path", "revert_on_parse_errors"], dramatized=[
    "content",
  ])
  Some(
    (
      ui(locale, ContentLabel),
      @html.div(class="write-args", [
        chip_row(chips),
        @html.pre(class="moonbit-source", [
          @syntax_html.numbered_source(content, tokenizer?=path_tokenizer(path)),
        ]),
      ]),
    ),
  )
}
