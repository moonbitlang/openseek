///|
/// Renders the tag's variant name for protocol/debug presentation.
pub impl Show for HighlightTag with fn output(self, logger) {
  logger.write_string(
    match self {
      Keyword => "Keyword"
      Identifier => "Identifier"
      String => "String"
      Number => "Number"
      Comment => "Comment"
      Punctuation => "Punctuation"
      Plain => "Plain"
      Operator => "Operator"
      Delimiter => "Delimiter"
      Type => "Type"
      Function => "Function"
      Variable => "Variable"
      Constant => "Constant"
      StringEscape => "StringEscape"
      CommentDoc => "CommentDoc"
      Regexp => "Regexp"
      Tag => "Tag"
      Attribute => "Attribute"
      Invalid => "Invalid"
    },
  )
}

///|
/// Creates an isolated registry for hosts which do not use the process-wide
/// singleton.
pub fn TokenizationRegistry::TokenizationRegistry() -> TokenizationRegistry {
  TokenizationRegistry::new_impl()
}

///|
pub fn TokenizationRegistry::handle_change(
  self : TokenizationRegistry,
  language_ids : Array[String],
) -> Unit {
  self.handle_change_impl(language_ids)
}

///|
pub fn TokenizationRegistry::is_resolved(
  self : TokenizationRegistry,
  language_id : String,
) -> Bool {
  self.is_resolved_impl(language_id)
}

///|
pub fn TokenizationRegistry::set_color_map(
  self : TokenizationRegistry,
  color_map : Array[String],
) -> Unit {
  self.set_color_map_impl(color_map)
}

///|
pub fn TokenizationRegistry::get_color_map(
  self : TokenizationRegistry,
) -> Array[String]? {
  self.get_color_map_impl()
}

///|
pub fn TokenizationRegistry::get_default_background(
  self : TokenizationRegistry,
) -> String? {
  self.get_default_background_impl()
}

///|
pub extend HighlightTag with Show::{output, to_string}
