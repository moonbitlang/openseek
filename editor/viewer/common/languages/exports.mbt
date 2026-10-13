// Deliberate host-registration contracts documented by this package but not
// yet consumed by non-test dependent packages in this repository.

///|
/// Constructs normalized line-comment configuration.
pub fn LineCommentRule::LineCommentRule(
  comment : String,
  no_indent~ : Bool = false,
) -> LineCommentRule {
  new_line_comment_rule(comment, no_indent~)
}

///|
/// Registers or replaces one language's comment and folding configuration.
pub fn Languages::set_language_configuration(
  self : Languages,
  language_id : String,
  configuration : LanguageConfiguration,
) -> Unit {
  self.set_language_configuration_impl(language_id, configuration)
}
