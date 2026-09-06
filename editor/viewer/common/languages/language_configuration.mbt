// The comment and folding-rules slices of Monaco's language configuration
// (`vs/editor/common/languages/languageConfiguration.ts` +
// `languageConfigurationRegistry.ts`, checked-in vscode submodule): `FoldingMarkers`,
// `FoldingRules`, and a per-language registration on `Languages` standing in
// for `ILanguageConfigurationService.getLanguageConfiguration(languageId)`.
// Brackets, auto-closing pairs, indentation rules, and the rest of
// `LanguageConfiguration` remain outside the readonly viewer's surface.

///|
/// Normalized line-comment configuration. `no_indent` corresponds to Monaco's
/// optional `LineCommentConfig.noIndent` and defaults to false.
pub struct LineCommentRule {
  comment : String
  priv no_indent : Bool
} derive(Eq, Debug)

///|
/// Convenience construction corresponding to Monaco's string line-comment
/// form, with the object form's `noIndent` flag available when needed.
fn new_line_comment_rule(
  comment : String,
  no_indent? : Bool = false,
) -> LineCommentRule {
  { comment, no_indent, }
}

///|
/// Opening and closing delimiters for one block-comment form.
pub(all) struct CharacterPair {
  open : String
  close : String
} derive(Eq, Debug)

///|
/// Normalized comment rules for one language.
pub(all) struct CommentRule {
  line_comment : LineCommentRule?
  block_comment : CharacterPair?
} derive(Eq, Debug)

///|
/// Describes start/end markers of language-specific folding regions (e.g.
/// `#region` / `#endregion`) — Monaco's `FoldingMarkers`
/// (`languageConfiguration.ts`). Monaco's fields are `RegExp`s; MoonBit has
/// no regex in scope, so a marker is a whole-line predicate.
pub(all) struct FoldingMarkers {
  start : (String) -> Bool
  end : (String) -> Bool
}

///|
/// Describes language-specific folding rules — Monaco's `FoldingRules`
/// (`languageConfiguration.ts`): `off_side` marks off-side-rule languages
/// (Python-like; empty lines belong to the previous block), `markers` the
/// optional region markers.
pub(all) struct FoldingRules {
  off_side : Bool
  markers : FoldingMarkers?
}

///|
/// The comments and folding-rules subset of Monaco's `LanguageConfiguration`.
pub(all) struct LanguageConfiguration {
  comments : CommentRule?
  folding_rules : FoldingRules?
}

///|
/// Registers or replaces `language_id`'s configuration — Monaco's
/// `languages.setLanguageConfiguration` reduced to comment and folding rules.
fn Languages::set_language_configuration_impl(
  self : Languages,
  language_id : String,
  configuration : LanguageConfiguration,
) -> Unit {
  if configuration.comments is Some(comments) {
    if comments.line_comment is Some(rule) && rule.comment == "" {
      abort("line comment delimiter must not be empty")
    }
    if comments.block_comment is Some(pair) {
      if pair.open == "" {
        abort("block comment opening delimiter must not be empty")
      }
      if pair.close == "" {
        abort("block comment closing delimiter must not be empty")
      }
    }
  }
  self.language_configurations[language_id] = configuration
}

///|
/// The configuration registered for `language_id` — Monaco's
/// `ILanguageConfigurationService.getLanguageConfiguration(languageId)`,
/// with an empty configuration for unregistered languages.
fn Languages::get_language_configuration(
  self : Languages,
  language_id : String,
) -> LanguageConfiguration {
  self.language_configurations
  .get(language_id)
  .unwrap_or({ comments: None, folding_rules: None, })
}

///|
pub extend CharacterPair with Debug::{to_repr}

///|
pub extend CharacterPair with Eq::{equal, not_equal}

///|
pub extend CommentRule with Debug::{to_repr}

///|
pub extend CommentRule with Eq::{equal, not_equal}

///|
pub extend LineCommentRule with Debug::{to_repr}

///|
pub extend LineCommentRule with Eq::{equal, not_equal}
