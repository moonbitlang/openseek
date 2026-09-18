///|
/// Immutable comparison identity. The digest covers both complete source
/// texts; only explicitly selected lines are carried to the agent.
pub(all) struct ReviewSource {
  workspace : String
  file : String
  original_file : String?
  base : String?
  version : String
} derive(Eq, Debug)

///|
pub(all) struct ChangeLine {
  number : Int
  text : String
} derive(Eq, Debug)

///|
/// A selection made by the user, independent of subsequent display grouping.
pub(all) struct ChangeExcerpt {
  original : Array[ChangeLine]
  modified : Array[ChangeLine]
} derive(Eq, Debug)

///|
pub(all) struct ReviewChanges {
  source : ReviewSource
  excerpts : Array[ChangeExcerpt]
} derive(Eq, Debug)

///|
pub(all) enum ContextCoverage {
  NotIncluded
  PartlyIncluded
  Included
} derive(Eq, Debug)

///|
pub fn ChangeExcerpt::is_empty(self : ChangeExcerpt) -> Bool {
  self.original.is_empty() && self.modified.is_empty()
}

///|
pub fn ReviewChanges::without(
  self : ReviewChanges,
  other : ReviewChanges,
) -> ReviewChanges {
  if self.source != other.source {
    return self
  }
  let original : Array[ChangeLine] = []
  let modified : Array[ChangeLine] = []
  for excerpt in other.excerpts {
    original.append(excerpt.original)
    modified.append(excerpt.modified)
  }
  {
    ..self,
    excerpts: self.excerpts
    .map(excerpt => ChangeExcerpt::{
      original: excerpt.original.filter(line => !original.contains(line)),
      modified: excerpt.modified.filter(line => !modified.contains(line)),
    })
    .filter(excerpt => !excerpt.is_empty()),
  }
}

///|
pub fn ReviewChanges::coverage(
  self : ReviewChanges,
  selected : Array[ReviewChanges],
) -> ContextCoverage {
  let mut remaining = self
  for existing in selected {
    remaining = remaining.without(existing)
  }
  if remaining.excerpts.is_empty() {
    Included
  } else if remaining == self {
    NotIncluded
  } else {
    PartlyIncluded
  }
}

///|
pub fn review_changes(mentions : Array[MentionRef]) -> Array[ReviewChanges] {
  mentions.filter_map(mention => {
    match mention {
      ReviewChanges(changes) => Some(changes)
      _ => None
    }
  })
}

///|
/// Union/subtraction uses exact, versioned changed lines, never the visible
/// hunk index or its navigation context. Retained excerpts keep their order.
pub fn with_review_changes(
  mentions : Array[MentionRef],
  selection : ReviewChanges,
  adding~ : Bool,
) -> Array[MentionRef] {
  let result : Array[MentionRef] = []
  let mut remaining = selection
  for mention in mentions {
    match mention {
      ReviewChanges(existing) if existing.source == selection.source =>
        if adding {
          remaining = remaining.without(existing)
          result.push(mention)
        } else {
          let retained = existing.without(selection)
          if !retained.excerpts.is_empty() {
            result.push(ReviewChanges(retained))
          }
        }
      _ => result.push(mention)
    }
  }
  if adding && !remaining.excerpts.is_empty() {
    match
      result.search_by(mention => {
        match mention {
          ReviewChanges(existing) => existing.source == selection.source
          _ => false
        }
      }) {
      Some(index) =>
        if result[index] is ReviewChanges(existing) {
          result[index] = ReviewChanges({
            ..existing,
            excerpts: existing.excerpts + remaining.excerpts,
          })
        }
      None => result.push(ReviewChanges(remaining))
    }
  }
  result
}

///|
pub extend ReviewSource with Eq::{equal, not_equal}

///|
pub extend ReviewSource with Debug::{to_repr}

///|
pub extend ChangeLine with Eq::{equal, not_equal}

///|
pub extend ChangeLine with Debug::{to_repr}

///|
pub extend ChangeExcerpt with Eq::{equal, not_equal}

///|
pub extend ChangeExcerpt with Debug::{to_repr}

///|
pub extend ReviewChanges with Eq::{equal, not_equal}

///|
pub extend ReviewChanges with Debug::{to_repr}

///|
pub extend ContextCoverage with Eq::{equal, not_equal}

///|
pub extend ContextCoverage with Debug::{to_repr}
