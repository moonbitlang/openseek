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
fn optional_review_string(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> String? raise @json.JsonDecodeError {
  match fields.get(key) {
    None | Some(Null) => None
    Some(value) => Some(@json.from_json(value, path=path.add_key(key)))
  }
}

///|
// Required fields reject missing/null/malformed values. Optional metadata
// accepts missing/null; unknown fields are intentionally ignored.
pub impl @json.FromJson for ReviewSource with fn from_json(json, path) {
  guard json is Object(fields) &&
    json is { "workspace": workspace, "file": file, "version": version, .. } else {
    raise @json.JsonDecodeError((path, "expected a review source"))
  }
  {
    workspace: @json.from_json(workspace, path=path.add_key("workspace")),
    file: @json.from_json(file, path=path.add_key("file")),
    version: @json.from_json(version, path=path.add_key("version")),
    original_file: optional_review_string(fields, "original_file", path),
    base: optional_review_string(fields, "base", path),
  }
}

///|
pub impl ToJson for ReviewSource with fn to_json(self) {
  let fields : Map[String, Json] = {
    "workspace": self.workspace.to_json(),
    "file": self.file.to_json(),
    "version": self.version.to_json(),
  }
  if self.original_file is Some(file) {
    fields["original_file"] = file.to_json()
  }
  if self.base is Some(base) {
    fields["base"] = base.to_json()
  }
  fields.to_json()
}

///|
pub impl @json.FromJson for ChangeLine with fn from_json(json, path) {
  guard json is { "line": number, "text": text, .. } else {
    raise @json.JsonDecodeError((path, "expected a selected line"))
  }
  let number : Int = @json.from_json(number, path=path.add_key("line"))
  guard number > 0 else {
    raise @json.JsonDecodeError((path, "line must be positive"))
  }
  { number, text: @json.from_json(text, path=path.add_key("text")), }
}

///|
pub impl ToJson for ChangeLine with fn to_json(self) {
  { "line": self.number, "text": self.text }
}

///|
pub impl @json.FromJson for ChangeExcerpt with fn from_json(json, path) {
  guard json is { "original": original, "modified": modified, .. } else {
    raise @json.JsonDecodeError((path, "expected both change sides"))
  }
  let excerpt : ChangeExcerpt = {
    original: @json.from_json(original, path=path.add_key("original")),
    modified: @json.from_json(modified, path=path.add_key("modified")),
  }
  guard !excerpt.is_empty() else {
    raise @json.JsonDecodeError((path, "empty change"))
  }
  excerpt
}

///|
pub impl ToJson for ChangeExcerpt with fn to_json(self) {
  { "original": self.original, "modified": self.modified }
}

///|
pub impl @json.FromJson for ReviewChanges with fn from_json(json, path) {
  guard json is { "source": source, "excerpts": excerpts, .. } else {
    raise @json.JsonDecodeError((path, "expected selected review changes"))
  }
  let changes : ReviewChanges = {
    source: @json.from_json(source, path=path.add_key("source")),
    excerpts: @json.from_json(excerpts, path=path.add_key("excerpts")),
  }
  guard !changes.excerpts.is_empty() else {
    raise @json.JsonDecodeError((path, "empty review selection"))
  }
  changes
}

///|
pub impl ToJson for ReviewChanges with fn to_json(self) {
  { "source": self.source, "excerpts": self.excerpts }
}

///|
pub extend ReviewSource with Eq::{equal, not_equal}

///|
pub extend ReviewSource with Debug::{to_repr}

///|
pub extend ReviewSource with ToJson::{to_json}

///|
pub extend ReviewSource with @json.FromJson::{from_json}

///|
pub extend ChangeLine with Eq::{equal, not_equal}

///|
pub extend ChangeLine with Debug::{to_repr}

///|
pub extend ChangeLine with ToJson::{to_json}

///|
pub extend ChangeLine with @json.FromJson::{from_json}

///|
pub extend ChangeExcerpt with Eq::{equal, not_equal}

///|
pub extend ChangeExcerpt with Debug::{to_repr}

///|
pub extend ChangeExcerpt with ToJson::{to_json}

///|
pub extend ChangeExcerpt with @json.FromJson::{from_json}

///|
pub extend ReviewChanges with Eq::{equal, not_equal}

///|
pub extend ReviewChanges with Debug::{to_repr}

///|
pub extend ReviewChanges with ToJson::{to_json}

///|
pub extend ReviewChanges with @json.FromJson::{from_json}

///|
pub extend ContextCoverage with Eq::{equal, not_equal}

///|
pub extend ContextCoverage with Debug::{to_repr}
