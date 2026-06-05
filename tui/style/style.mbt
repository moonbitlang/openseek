///|
/// Terminal styling applied while a span is written.
///
/// A style can set foreground color, background color, and underline. Terminal
/// styling is reset after each span is emitted.
pub struct Style {
  foreground : @tty/color.Color
  background : @tty/color.Color
  underline : Bool
} derive(Eq)

///|
pub let default : Style = Style()

///|
pub fn Style::Style(
  foreground? : @tty/color.Color = Default,
  background? : @tty/color.Color = Default,
  underline? : Bool = false,
) -> Style {
  Style::{ foreground, background, underline }
}

///|
pub let dim : Style = Style(foreground=Basic(BrightBlack))

///|
pub let ok : Style = Style(foreground=Basic(Green))

///|
pub let error : Style = Style(foreground=Basic(Red))
