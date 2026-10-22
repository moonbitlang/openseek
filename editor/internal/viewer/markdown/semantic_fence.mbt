///|
/// The outer resource kind is deliberately explicit: a matching fence in an
/// ordinary Markdown resource is static code, not a MoonBit provider surface.
pub(all) enum MarkdownResourceKind {
  OrdinaryMarkdown
  MoonBitMarkdown
} derive(Eq, Debug)

///|
/// Whether this block uses the MoonBit compiler's Markdown-test prefix grammar:
/// exact lowercase `mbt check` or `moonbit check`, split only on ASCII space,
/// with repeated spaces ignored and trailing tokens allowed.
pub fn MarkdownCodeBlock::is_moonbit_check_fence(
  self : MarkdownCodeBlock,
  resource_kind : MarkdownResourceKind,
) -> Bool {
  guard resource_kind is MoonBitMarkdown &&
    self.full_info_string is Some(info_string) else {
    return false
  }
  markdown_info_string_is_moonbit_check(info_string)
}

///|
fn markdown_info_string_is_moonbit_check(info_string : String) -> Bool {
  let tokens : Array[String] = [
    for token in info_string.split(" ") if !token.is_empty() => token.to_owned()
  ]
  guard tokens is [first, second, ..] else { return false }
  (first == "mbt" || first == "moonbit") && second == "check"
}

///|
pub extend MarkdownResourceKind with Debug::{to_repr}

///|
pub extend MarkdownResourceKind with Eq::{equal, not_equal}
