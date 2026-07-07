///|
/// Largest code-unit offset `<= max_units` that is a valid UTF-16 character
/// boundary. A surrogate pair spans two code units; if `max_units` lands on a
/// trailing surrogate, step back one so a cut there never splits the pair.
/// `max_units <= 0` is returned unchanged. Callers pass `max_units <
/// content.length()` so the index access stays in bounds.
///
/// Shared by every tool that caps output to a UTF-16 code-unit budget (for
/// example `read`, which renders numbered lines) so the surrogate-safety rule
/// lives in exactly one place.
pub fn char_boundary_at_or_below(content : StringView, max_units : Int) -> Int {
  if max_units > 0 && content[max_units].is_trailing_surrogate() {
    max_units - 1
  } else {
    max_units
  }
}

///|
/// Keep at most `max_units` leading UTF-16 code units of `content` without
/// ever splitting a surrogate pair. This is a soft cap for rendered output, so
/// it returns the full string when already within budget.
pub fn code_unit_prefix(content : StringView, max_units : Int) -> StringView {
  if max_units <= 0 {
    ""
  } else if content.length() <= max_units {
    content
  } else {
    // The slice is already a StringView, so return it directly rather than
    // round-tripping through interpolation (which would allocate a String).
    content[:char_boundary_at_or_below(content, max_units)]
  }
}
