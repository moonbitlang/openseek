///|
/// Monaco-shaped language selector filter.
struct LanguageFilter {
  language : String?
  scheme : String?
  pattern : String?
} derive(Debug)

///|
/// Monaco-shaped language selector used during provider dispatch.
pub(all) enum LanguageSelector {
  LanguageId(String)
  LanguageFilter(LanguageFilter)
  LanguageSelectorList(Array[LanguageSelector])
} derive(Debug)

///|
/// Builds a selector filter with optional fields.
fn LanguageFilter::new_impl(
  language? : String,
  scheme? : String,
  pattern? : String,
) -> LanguageFilter {
  { language, scheme, pattern, }
}

///|
/// Builds a selector filter with optional language, scheme, and path pattern.
pub fn LanguageFilter::LanguageFilter(
  language? : String,
  scheme? : String,
  pattern? : String,
) -> LanguageFilter {
  LanguageFilter::new_impl(language?, scheme?, pattern?)
}

///|
/// Whether this selector accepts a text model.
fn LanguageSelector::matches_impl(
  self : LanguageSelector,
  model : @model.TextModel,
) -> Bool {
  self.score(model) > 0
}

///|
/// Monaco-compatible priority for the selector surface represented locally.
/// Exact language/scheme/pattern matches score 10, wildcard language/scheme
/// matches score 5, selector lists take their highest member, and a filter
/// without any constraining field does not select a model.
pub fn LanguageSelector::score(
  self : LanguageSelector,
  model : @model.TextModel,
) -> Int {
  match self {
    LanguageId("*") => 5
    LanguageId(language_id) =>
      if model.language_id == language_id {
        10
      } else {
        0
      }
    LanguageFilter(filter) => filter.score(model)
    LanguageSelectorList(selectors) =>
      for selector in selectors; result = 0 {
        let score = selector.score(model)
        if score == 10 {
          break 10
        }
        if score > result {
          continue score
        }
      } nobreak {
        result
      }
  }
}

///|
/// Whether this filter accepts a text model.
fn LanguageFilter::matches_impl(
  self : LanguageFilter,
  model : @model.TextModel,
) -> Bool {
  self.score(model) > 0
}

///|
/// Scores the language, scheme, and path-pattern subset of Monaco's
/// `LanguageFilter`.
fn LanguageFilter::score_impl(
  self : LanguageFilter,
  model : @model.TextModel,
) -> Int {
  let mut result = 0
  if self.language is Some(language) {
    if language == model.language_id {
      result = 10
    } else if language == "*" {
      result = 5
    } else {
      return 0
    }
  }
  if self.scheme is Some(scheme) {
    if scheme == model.uri.scheme {
      result = 10
    } else if scheme == "*" {
      if result < 5 {
        result = 5
      }
    } else {
      return 0
    }
  }
  // Monaco's `score()` matches globs against `uri.path` (leading slash
  // included); `path_pattern_matches` strips that slash so the relative
  // patterns hosts register keep matching.
  if self.pattern is Some(pattern) {
    if path_pattern_matches(pattern, model.uri.path) {
      result = 10
    } else {
      return 0
    }
  }
  result
}

///|
fn path_pattern_matches(pattern : String, path : String) -> Bool {
  if pattern == "" {
    return false
  }
  if pattern == "*" {
    return true
  }
  let path = if path.has_prefix("/") { path[1:].to_owned() } else { path }
  match pattern.split_once("*") {
    Some((prefix, suffix)) => path.has_prefix(prefix) && path.has_suffix(suffix)
    None => path == pattern
  }
}

///|
pub extend LanguageFilter with Debug::{to_repr}

///|
pub extend LanguageSelector with Debug::{to_repr}
