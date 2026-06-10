///|
/// Terminal styling applied while a span is written.
///
/// A style can set foreground color, background color, and underline. Terminal
/// styling is reset after each span is emitted.
pub struct Style {
  foreground : @tty/color.Color
  background : @tty/color.Color
  underline : Bool
} derive(Eq, Debug)

///|
/// The terminal's own colors, no underline — text with no styling applied.
pub let default : Style = Style()

///|
/// Build a style; omitted fields keep the terminal default. Pass only what
/// the span should change, e.g. `Style(foreground=Basic(Yellow))`.
pub fn Style::Style(
  foreground? : @tty/color.Color = Default,
  background? : @tty/color.Color = Default,
  underline? : Bool = false,
) -> Style {
  { foreground, background, underline }
}

///|
/// De-emphasized text (bright black): labels, separators, secondary detail.
pub let dim : Style = Style(foreground=Basic(BrightBlack))

///|
/// Success accent (green): completed statuses and confirmations.
pub let ok : Style = Style(foreground=Basic(Green))

///|
/// Failure accent (red): error items and failed statuses.
pub let error : Style = Style(foreground=Basic(Red))
