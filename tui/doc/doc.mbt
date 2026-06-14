// Styled-text vocabulary for terminal output.
//
// `Doc`/`Text`/`Span`/`Style` describe *what* to render as logical, terminal-
// agnostic blocks of styled text. They are laid out into physical
// `@surface.Line`s (wrapping by display width, expanding tabs, dropping stray
// control characters) only when a target width is known. The `tui` package
// builds these from transcript and input state; the `render` package lays the
// composer out from them. Nothing here performs IO.

///|
/// A renderable document made of logical text blocks.
///
/// `Doc` is used for committed transcript output. Each `Text` block is wrapped
/// independently when the document is laid out for the current terminal width.
struct Doc {
  texts : Array[Text]
}

///|
/// Build a document from a sequence of text blocks.
pub fn Doc::Doc(texts : Array[Text]) -> Doc {
  { texts: texts.copy() }
}

///|
/// A logical text block made of styled spans.
///
/// Text wraps by terminal display width and treats newline characters as forced
/// row breaks.
struct Text {
  spans : Array[Span]
} derive(Debug)

///|
/// Build a text block from a sequence of styled spans.
pub fn Text::Text(spans : Array[Span]) -> Text {
  { spans: spans.copy() }
}

///|
/// Build a text block containing one unstyled span.
pub fn Text::plain(text : String) -> Text {
  Text([Span::plain(text)])
}

///|
/// A copy of this block with `span` inserted before its existing spans.
///
/// Used to attach a styled prefix (a bullet, a continuation indent) to existing
/// content without exposing the span array.
pub fn Text::prepend_span(self : Text, span : Span) -> Text {
  Text([span, ..self.spans])
}

///|
/// Split this block at line breaks into one block per source line, preserving
/// each span's style. The returned blocks contain no line-ending characters.
///
/// Every line-ending form splits a row: CRLF, CR, and LF are handled by
/// `displaytext.split_lines`, so no stray `\r` is left for `wrap` to turn into
/// an extra blank row.
pub fn Text::split_lines(self : Text) -> Array[Text] {
  let lines : Array[Text] = []
  let mut spans : Array[Span] = []
  for span in self.spans {
    let display_lines = @displaytext.split_lines(span.display.text())
    for index, display_line in display_lines {
      if display_line.start() != display_line.end() {
        spans.push(Span(display_line, style=span.style))
      }
      if index + 1 < display_lines.length() {
        lines.push(Text(spans))
        spans = []
      }
    }
  }
  lines.push(Text(spans))
  lines
}

///|
/// A string fragment with an associated terminal style.
///
/// A span normally holds a single display line. Callers split hard line breaks
/// into separate `Text` blocks with `Text::split_lines` (e.g. to prefix each
/// line with its own bullet), but a span that reaches layout with an embedded
/// newline is still handled: `Text::wrap` iterates the span's `DisplayText`
/// directly and forces a row break on CR/LF/CRLF inline, without re-segmenting
/// the string.
struct Span {
  display : @displaytext.DisplayText
  style : @style.Style
} derive(Debug)

///|
/// Build a styled span.
///
/// If `style` is omitted, the span uses `Style::default`.
pub fn Span::Span(
  text : @displaytext.DisplayText,
  style? : @style.Style = @style.default,
) -> Span {
  { display: text, style }
}

///|
/// Build an unstyled span.
pub fn Span::plain(text : String) -> Span {
  Span(DisplayText(text))
}

///|
/// Lay this block out into physical rows for `width` columns, wrapping by
/// display width, expanding tabs to the next stop, forcing a row break on every
/// hard line break (CR, LF, or CRLF), and dropping other stray controls.
fn Text::wrap(self : Text, width~ : Int) -> Array[@surface.Line] {
  let rows : Array[@surface.Line] = []
  let mut spans : Array[@surface.Span] = []
  let mut used = 0
  let width = width.max(1)
  // Accumulate consecutive units into one surface span rather than emitting one
  // span per grapheme. The renderer writes a style set + reset and an (unbuffered)
  // terminal write per span, so a per-grapheme line becomes hundreds of syscalls;
  // coalescing collapses a single-style line into one span. A span's style is
  // constant, so a run is flushed only when the input span ends or a wrap/line
  // break splits the physical row.
  let mut run = StringBuilder()
  let mut run_empty = true
  fn flush_run(style : @style.Style) -> Unit {
    if !run_empty {
      spans.push(Span(DisplayText(run.to_string()), style~))
      run = StringBuilder()
      run_empty = true
    }
  }

  for span in self.spans {
    let style = span.style
    // Iterate the span's precomputed `DisplayText` directly instead of
    // re-segmenting its string on every layout. Spans are usually newline-free
    // (callers pre-split with `Text::split_lines`), but a hard line break that
    // does reach here is honored as a row break inline (below), so layout never
    // re-runs the grapheme segmentation the `DisplayText` already paid for.
    let display_line = span.display
    let mut start = display_line.start()
    while display_line.next(start) is Some(end) {
      let unit = display_line.view(start, end)
      // Normalize control characters so the columns we count match what the
      // terminal draws. A hard line break ends the current physical row; a raw
      // `\t` jumps to the terminal's tab stop, which is not modeled by `used`,
      // so it would shove following text into the wrong column; every other
      // control is dropped.
      //
      // `Text::wrap` honors the documented contract that layout splits on hard
      // line breaks even for a span that was not pre-split with `split_lines`.
      // Grapheme segmentation already clusters CRLF into one unit, so "\r\n" is a
      // single break, matching `Text::split_lines`; a lone CR and lone LF each
      // arrive as their own unit and break once too.
      if unit == "\n" || unit == "\r" || unit == "\r\n" {
        flush_run(style)
        rows.push(@surface.Line::new(spans))
        spans = []
        used = 0
      } else if unit == "\t" {
        let spaces = @text.TabWidth - used % @text.TabWidth
        for _ in 0..<spaces {
          if used > 0 && used + 1 > width {
            flush_run(style)
            rows.push(@surface.Line::new(spans))
            spans = []
            used = 0
          }
          run <+ " "
          run_empty = false
          used += 1
        }
      } else if !@text.is_control_unit(unit) {
        let next = @text.unit_width(display_line, start~, end~)
        if used > 0 && used + next > width {
          flush_run(style)
          rows.push(@surface.Line::new(spans))
          spans = []
          used = 0
        }
        run <+ "\{unit}"
        run_empty = false
        used += next
      }
      start = end
    }
    // Flush at the input-span boundary so the next span starts its own run
    // (its style may differ).
    flush_run(style)
  }
  rows.push(@surface.Line::new(spans))
  rows
}

///|
/// The first wrapped row of this block for `width` columns, or an empty line.
pub fn Text::first_line(self : Text, width~ : Int) -> @surface.Line {
  match self.wrap(width~).get(0) {
    Some(line) => line
    None => @surface.Line::new([])
  }
}

///|
/// Lay every block out in order into physical rows for `width` columns.
pub fn Doc::layout(self : Doc, width~ : Int) -> Array[@surface.Line] {
  let rows : Array[@surface.Line] = []
  for text in self.texts {
    for row in text.wrap(width~) {
      rows.push(row)
    }
  }
  rows
}

///|
/// A one-block text in the subdued `Style::dim` style.
pub fn dim_text(text : String) -> Text {
  Text([Span(DisplayText(text), style=@style.dim)])
}
