///|
pub(all) enum SemanticReviewStatus {
  Identical
  Changed
  Reordered
  NoStructuralChanges
  IgnoredOnly
} derive(Eq, Debug)

///|
/// One physical source range owned by a semantic section. Line numbers are
/// one-based for display; section DiffEditors use local model coordinates.
pub(all) struct SemanticReviewSourceRange {
  start_line_number : Int
  line_count : Int
} derive(Eq, Debug)

///|
pub(all) enum SemanticReviewSectionKind {
  Whole
  Matched
  Deleted
  Inserted
} derive(Eq, Debug)

///|
/// The provider used inside one section DiffEditor. Inserted and deleted
/// declarations use Line because one model is intentionally empty; matched
/// and whole fragments retain MoonDiff's local intraline result.
pub(all) enum SemanticReviewDiff {
  Line
  Fragment(@diff.DocumentDiff)
} derive(Eq, Debug)

///|
/// One independently rendered semantic section. It carries source slices and
/// a fragment-local diff only; no global two-sided line order is synthesized.
pub(all) struct SemanticReviewSection {
  key : String
  identity : Int?
  kind : SemanticReviewSectionKind
  old_range : SemanticReviewSourceRange?
  new_range : SemanticReviewSourceRange?
  old_context : String?
  new_context : String?
  fallbacks : Array[String]
  original_source : String
  modified_source : String
  diff : SemanticReviewDiff
} derive(Eq, Debug)

///|
/// Main sections follow MoonDiff's new-side order. Deleted sections remain a
/// separate old-side ordered group, so reordered identities never cross in a
/// single DiffEditor mapping.
pub(all) struct SectionedSemanticReviewPlan {
  requested : MoonDiffMode
  status : SemanticReviewStatus
  reordered : Bool
  main_sections : Array[SemanticReviewSection]
  deleted_sections : Array[SemanticReviewSection]
} derive(Eq, Debug)

///|
fn semantic_status(status : @mbtdiff.DiffStatus) -> SemanticReviewStatus {
  match status {
    Identical => Identical
    Changed => Changed
    Reordered => Reordered
    NoStructuralChanges => NoStructuralChanges
    IgnoredOnly => IgnoredOnly
  }
}

///|
fn fallback_stage_text(stage : @mbtdiff.ComputationStage) -> String {
  match stage {
    TopLevelAlignment => "top-level alignment"
    SyntaxMatching => "syntax matching"
    IntralineMatching => "intraline matching"
  }
}

///|
fn fallback_sides_text(sides : ArrayView[@mbtdiff.DiffSide]) -> String {
  let names = sides.map(side => {
    match side {
      Old => "old"
      New => "new"
    }
  })
  match names {
    [] => ""
    [side] => "the \{side} side"
    _ => "the \{names.join(" and ")} sides"
  }
}

///|
fn fallback_reason_text(reason : @mbtdiff.FallbackReason) -> String {
  match reason {
    ParseError(detail~, ..) => detail
    SyntaxPositionsOutOfBounds(sides~) => {
      let sides = fallback_sides_text(sides)
      if sides.is_empty() {
        "syntax positions out of bounds"
      } else {
        "syntax positions out of bounds on \{sides}"
      }
    }
    GraphLimitExceeded(limit~) => "graph limit exceeded (\{limit})"
    ComputationLimitExceeded(stage~, limit~) =>
      "computation limit exceeded (\{limit}) during \{fallback_stage_text(stage)}"
  }
}

///|
fn fallback_texts(
  fallbacks : ArrayView[@mbtdiff.FallbackReason],
) -> Array[String] {
  fallbacks.map(fallback_reason_text)
}

///|
/// Normalize LF, CRLF, and CR to local LF-separated model text while keeping
/// a terminating newline as a final empty line.
fn normalized_source_lines(source : String) -> Array[String] {
  let chars = source.to_array()
  let lines : Array[String] = []
  let mut line_start = 0
  let mut index = 0
  while index < chars.length() {
    match chars[index] {
      '\r' => {
        lines.push(String::from_array(chars[line_start:index]))
        index += 1
        if index < chars.length() && chars[index] == '\n' {
          index += 1
        }
        line_start = index
      }
      '\n' => {
        lines.push(String::from_array(chars[line_start:index]))
        index += 1
        line_start = index
      }
      _ => index += 1
    }
  }
  lines.push(String::from_array(chars[line_start:chars.length()]))
  lines
}

///|
fn normalized_source(source : String) -> String {
  normalized_source_lines(source).join("\n")
}

///|
fn source_range(range : @mbtdiff.LineRange) -> SemanticReviewSourceRange {
  { start_line_number: range.start + 1, line_count: range.len, }
}

///|
fn source_slice(lines : Array[String], range : @mbtdiff.LineRange) -> String? {
  if range.start < 0 ||
    range.len < 0 ||
    range.start > lines.length() ||
    range.len > lines.length() - range.start {
    return None
  }
  Some(lines[range.start:range.start + range.len].join("\n"))
}

///|
fn fragment_has_output(fragment : @mbtdiff.DiffFragment) -> Bool {
  !fragment.document.hunks.is_empty() || !fragment.fallbacks.is_empty()
}

///|
fn section_diff(
  fragment : @mbtdiff.DiffFragment,
  original_source : String,
  modified_source : String,
  one_sided : Bool,
) -> SemanticReviewDiff? {
  if one_sided {
    return Some(Line)
  }
  fragment_document_diff(fragment.document, original_source, modified_source).map(diff => {
      Fragment(diff)
    },
  )
}

///|
fn whole_section(
  fragment : @mbtdiff.DiffFragment,
  old_source : String,
  new_source : String,
) -> SemanticReviewSection? {
  let original_source = normalized_source(old_source)
  let modified_source = normalized_source(new_source)
  guard section_diff(
      fragment,
      original_source,
      modified_source,
      old_source.is_empty() || new_source.is_empty(),
    )
    is Some(diff) else {
    return None
  }
  Some({
    key: "whole",
    identity: None,
    kind: Whole,
    old_range: None,
    new_range: None,
    old_context: None,
    new_context: None,
    fallbacks: fallback_texts(fragment.fallbacks),
    original_source,
    modified_source,
    diff,
  })
}

///|
fn top_level_section(
  identity : Int,
  section : @mbtdiff.DiffSection,
  old_lines : Array[String],
  new_lines : Array[String],
) -> SemanticReviewSection? {
  let (kind, old_range, new_range, old_context, new_context, fragment) = match
    section {
    Matched(old~, new~, old_context~, new_context~, diff~) =>
      (
        SemanticReviewSectionKind::Matched,
        Some(old),
        Some(new),
        old_context,
        new_context,
        diff,
      )
    Deleted(old~, old_context~, diff~) =>
      (Deleted, Some(old), None, old_context, None, diff)
    Inserted(new~, new_context~, diff~) =>
      (Inserted, None, Some(new), None, new_context, diff)
  }
  let original_source = match old_range {
    Some(range) => {
      guard source_slice(old_lines, range) is Some(source) else { return None }
      source
    }
    None => ""
  }
  let modified_source = match new_range {
    Some(range) => {
      guard source_slice(new_lines, range) is Some(source) else { return None }
      source
    }
    None => ""
  }
  guard section_diff(
      fragment,
      original_source,
      modified_source,
      old_range is None || new_range is None,
    )
    is Some(diff) else {
    return None
  }
  Some({
    key: "section-\{identity}",
    identity: Some(identity),
    kind,
    old_range: old_range.map(source_range),
    new_range: new_range.map(source_range),
    old_context,
    new_context,
    fallbacks: fallback_texts(fragment.fallbacks),
    original_source,
    modified_source,
    diff,
  })
}

///|
fn valid_top_level_orders(top : @mbtdiff.TopLevelDiff) -> Bool {
  let old_seen = Array::make(top.sections.length(), false)
  let new_seen = Array::make(top.sections.length(), false)
  let mut old_end = 0
  let mut new_end = 0
  for identity in top.old_order {
    if identity < 0 || identity >= top.sections.length() || old_seen[identity] {
      return false
    }
    let range = match top.sections[identity] {
      Matched(old~, ..) | Deleted(old~, ..) => old
      Inserted(..) => return false
    }
    if range.start < old_end || range.len < 0 {
      return false
    }
    old_seen[identity] = true
    old_end = range.start + range.len
  }
  for identity in top.new_order {
    if identity < 0 || identity >= top.sections.length() || new_seen[identity] {
      return false
    }
    let range = match top.sections[identity] {
      Matched(new~, ..) | Inserted(new~, ..) => new
      Deleted(..) => return false
    }
    if range.start < new_end || range.len < 0 {
      return false
    }
    new_seen[identity] = true
    new_end = range.start + range.len
  }
  for identity, section in top.sections {
    match section {
      Matched(..) =>
        if !old_seen[identity] || !new_seen[identity] {
          return false
        }
      Deleted(..) =>
        if !old_seen[identity] || new_seen[identity] {
          return false
        }
      Inserted(..) =>
        if old_seen[identity] || !new_seen[identity] {
          return false
        }
    }
  }
  true
}

///|
fn top_level_plan(
  top : @mbtdiff.TopLevelDiff,
  old_source : String,
  new_source : String,
) -> (Array[SemanticReviewSection], Array[SemanticReviewSection])? {
  if !valid_top_level_orders(top) {
    return None
  }
  let old_lines = normalized_source_lines(old_source)
  let new_lines = normalized_source_lines(new_source)
  let main_sections : Array[SemanticReviewSection] = []
  for identity in top.new_order {
    let section = top.sections[identity]
    let fragment = match section {
      Matched(diff~, ..) | Inserted(diff~, ..) => diff
      Deleted(..) => return None
    }
    if fragment_has_output(fragment) {
      guard top_level_section(identity, section, old_lines, new_lines)
        is Some(projected) else {
        return None
      }
      main_sections.push(projected)
    }
  }
  let deleted_sections : Array[SemanticReviewSection] = []
  for identity in top.old_order {
    let section = top.sections[identity]
    if section is Deleted(diff~, ..) && fragment_has_output(diff) {
      guard top_level_section(identity, section, old_lines, new_lines)
        is Some(projected) else {
        return None
      }
      deleted_sections.push(projected)
    }
  }
  Some((main_sections, deleted_sections))
}

///|
/// Compute section ownership and fragment-local DiffEditor inputs for Token or
/// Tree mode. Line remains the ordinary full-file DiffEditor path.
pub fn compute_sectioned_semantic_review_plan(
  old_source : String,
  new_source : String,
  mode : MoonDiffMode,
  old_name? : String = "old",
  new_name? : String = "new",
  ignore_comments? : Bool = true,
  ignore_tests? : Bool = true,
) -> SectionedSemanticReviewPlan? {
  let diff_mode = match mode {
    Line => return None
    Token => @mbtdiff.DiffMode::Lexical
    Tree => Ast
  }
  let result = @mbtdiff.diff(
    old_source,
    new_source,
    old_name~,
    new_name~,
    options=DiffOptions(
      context_lines=3,
      ignore_comments~,
      ignore_tests~,
      mode=diff_mode,
    ),
  )
  let status = semantic_status(result.status())
  // These statuses formally contain no visible semantic change. Do not ask
  // an empty/ignored document to satisfy top-level projection invariants: in
  // a comment-only file MoonDiff may retain section metadata whose filtered
  // ranges intentionally no longer describe a renderable fragment.
  if status is Identical ||
    status is NoStructuralChanges ||
    status is IgnoredOnly {
    return Some({
      requested: mode,
      status,
      reordered: false,
      main_sections: [],
      deleted_sections: [],
    })
  }
  match result.document() {
    Whole(fragment) => {
      guard whole_section(fragment, old_source, new_source) is Some(section) else {
        return None
      }
      Some({
        requested: mode,
        status,
        reordered: false,
        main_sections: [section],
        deleted_sections: [],
      })
    }
    TopLevel(top) => {
      guard top_level_plan(top, old_source, new_source)
        is Some((main_sections, deleted_sections)) else {
        return None
      }
      Some({
        requested: mode,
        status,
        reordered: top.reordered,
        main_sections,
        deleted_sections,
      })
    }
  }
}

///|
pub extend SemanticReviewStatus with Eq::{equal, not_equal}

///|
pub extend SemanticReviewStatus with Debug::{to_repr}

///|
pub extend SemanticReviewSourceRange with Eq::{equal, not_equal}

///|
pub extend SemanticReviewSourceRange with Debug::{to_repr}

///|
pub extend SemanticReviewSectionKind with Eq::{equal, not_equal}

///|
pub extend SemanticReviewSectionKind with Debug::{to_repr}

///|
pub extend SemanticReviewDiff with Eq::{equal, not_equal}

///|
pub extend SemanticReviewDiff with Debug::{to_repr}

///|
pub extend SemanticReviewSection with Eq::{equal, not_equal}

///|
pub extend SemanticReviewSection with Debug::{to_repr}

///|
pub extend SectionedSemanticReviewPlan with Eq::{equal, not_equal}

///|
pub extend SectionedSemanticReviewPlan with Debug::{to_repr}
