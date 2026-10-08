///|
/// Text inserted into a rendered line without existing in the source document.
pub struct InjectedText {
  position : @base_common.Position
  text : String
  class_name : String
  source_index : Int
} derive(Eq, Debug)

///|
/// Builds injected text at a model position.
pub fn InjectedText::InjectedText(
  position : @base_common.Position,
  text : String,
  class_name : String,
  source_index? : Int = -1,
) -> InjectedText {
  { position, text, class_name, source_index, }
}

///|
/// Segment kind inside a projected line: source text or injected text.
pub enum ProjectedLinePartKind {
  SourceSegment(model_start~ : Int, model_end~ : Int)
  InjectedSegment(
    model_column~ : Int,
    injected_text_index~ : Int,
    class_name~ : String
  )
} derive(Eq, Debug)

///|
/// Half-open projected text segment with its source/injected identity.
pub struct ProjectedLinePart {
  start : Int
  end : Int
  kind : ProjectedLinePartKind
} derive(Eq, Debug)

///|
/// One model line with sparse source/injection spans. The identity case owns
/// no per-character maps; mapping costs depend on injection count, not length.
pub struct ProjectedTextLine {
  text : String
  model_line_length : Int
  parts : Array[ProjectedLinePart]
  injections : Array[ProjectedLinePart]
} derive(Eq, Debug)

///|
/// Projection for a line with no injected text.
pub fn ProjectedTextLine::identity(line_text : String) -> ProjectedTextLine {
  ProjectedTextLine::from_injected_text(line_text, [])
}

///|
/// Builds projected text and column maps for one model line plus injected text.
pub fn ProjectedTextLine::from_injected_text(
  line_text : String,
  injected_text : Array[InjectedText],
) -> ProjectedTextLine {
  let normalized = normalize_injected_text(line_text, injected_text[:])
  if normalized.length() == 0 {
    return identity_projected_text_line(line_text)
  }
  let builder = StringBuilder()
  let parts : Array[ProjectedLinePart] = []
  let injections : Array[ProjectedLinePart] = []
  let mut source_cursor = 0
  let mut view_cursor = 0
  for item in normalized {
    let column = item.position.column
    if column > source_cursor {
      builder.write_view(line_text[source_cursor:column])
      parts.push({
        start: view_cursor,
        end: view_cursor + column - source_cursor,
        kind: SourceSegment(model_start=source_cursor, model_end=column),
      })
      view_cursor += column - source_cursor
      source_cursor = column
    }
    builder.write_string(item.text)
    let part : ProjectedLinePart = {
      start: view_cursor,
      end: view_cursor + item.text.length(),
      kind: InjectedSegment(
        model_column=column,
        injected_text_index=item.source_index,
        class_name=item.class_name,
      ),
    }
    parts.push(part)
    injections.push(part)
    view_cursor = part.end
  }
  if source_cursor < line_text.length() {
    builder.write_view(line_text[source_cursor:])
    parts.push({
      start: view_cursor,
      end: view_cursor + line_text.length() - source_cursor,
      kind: SourceSegment(
        model_start=source_cursor,
        model_end=line_text.length(),
      ),
    })
  }
  {
    text: builder.to_string(),
    model_line_length: line_text.length(),
    parts,
    injections,
  }
}

///|
/// Maps a model column to a projected display column.
///
/// The injection branch of `translateToOutputPosition`
/// (`modelLineProjectionData.ts:111-128`): only `Right` resolves a boundary
/// column to the far side of every injection anchored there; every other
/// affinity (the `None` default included) stays left of them, which is what
/// sparse offsets preserve.
pub fn ProjectedTextLine::model_column_to_projected_column(
  self : ProjectedTextLine,
  model_column : Int,
  affinity? : @model.PositionAffinity,
) -> Int {
  let column = model_column.clamp(min=0, max=self.model_line_length)
  let right = affinity is Some(Right)
  let index = for low = 0, high = self.injections.length(); low < high; {
    let mid = (low + high) / 2
    let anchor = injected_part_anchor(self.injections[mid])
    if anchor < column || (right && anchor == column) {
      continue mid + 1, high
    } else {
      continue low, mid
    }
  } nobreak {
    low
  }
  if index == 0 {
    column
  } else {
    let part = self.injections[index - 1]
    column + part.end - injected_part_anchor(part)
  }
}

///|
/// Snaps a projected column that touches injected text to one of its sides,
/// `normalizeOffsetInInputWithInjectionsAroundInjections`
/// (`modelLineProjectionData.ts:204-252`). Containment mirrors
/// `getInjectedTextAtOffset` (`:255-284`): inclusive on both ends, first
/// match wins. The viewer's injected text carries no `cursorStops`, so `None`
/// behaves as Monaco's default `InjectedTextCursorStops.Both`: only
/// strictly-inside columns snap (to the injection start); boundary columns
/// already are cursor stops.
pub fn ProjectedTextLine::normalize_projected_column_around_injections(
  self : ProjectedTextLine,
  projected_column : Int,
  affinity : @model.PositionAffinity,
) -> Int {
  let parts = self.parts
  let found = for index, part in parts {
    guard part.kind is InjectedSegment(..) else { continue }
    if part.start > projected_column {
      // All later injections start even further right.
      break -1
    }
    if projected_column <= part.end {
      break index
    }
  } nobreak {
    -1
  }
  if found < 0 {
    return projected_column
  }
  let part = parts[found]
  match affinity {
    None =>
      // cursorStops = Both: the injection's end is a right cursor stop, its
      // start a left one.
      if projected_column == part.end {
        projected_column
      } else {
        part.start
      }
    Right | RightOfInjectedText => {
      // Past every injection anchored at the same model column.
      let anchor = injected_part_anchor(part)
      for index = found + 1, result = part.end; index < parts.length() &&
         parts[index].kind is InjectedSegment(model_column=next_anchor, ..) &&
         next_anchor == anchor; {
        continue index + 1, parts[index].end
      } nobreak {
        result
      }
    }
    Left | LeftOfInjectedText => {
      // Before every injection anchored at the same model column.
      let anchor = injected_part_anchor(part)
      for index = found - 1, result = part.start; index >= 0 &&
         parts[index].kind is InjectedSegment(model_column=prev_anchor, ..) &&
         prev_anchor == anchor; {
        continue index - 1, parts[index].start
      } nobreak {
        result
      }
    }
  }
}

///|
fn injected_part_anchor(part : ProjectedLinePart) -> Int {
  match part.kind {
    InjectedSegment(model_column~, ..) => model_column
    SourceSegment(..) => -1
  }
}

///|
/// Maps a projected display column back to a model column.
pub fn ProjectedTextLine::projected_column_to_model_column(
  self : ProjectedTextLine,
  projected_column : Int,
) -> Int {
  let column = projected_column.clamp(min=0, max=self.text.length())
  let index = self.injection_index_after(column, inclusive_end=true)
  if index < self.injections.length() {
    let part = self.injections[index]
    let anchor = injected_part_anchor(part)
    if column >= part.start {
      anchor
    } else {
      column - (part.start - anchor)
    }
  } else if index > 0 {
    let part = self.injections[index - 1]
    column - (part.end - injected_part_anchor(part))
  } else {
    column
  }
}

///|
/// Legacy source-index API: -1 means source text, including the end column.
pub fn ProjectedTextLine::injected_text_index_at_projected_column(
  self : ProjectedTextLine,
  projected_column : Int,
) -> Int {
  let column = projected_column.clamp(min=0, max=self.text.length())
  let index = self.injection_index_after(column, inclusive_end=false)
  if index < self.injections.length() && column >= self.injections[index].start {
    match self.injections[index].kind {
      InjectedSegment(injected_text_index~, ..) => injected_text_index
      SourceSegment(..) => -1
    }
  } else {
    -1
  }
}

///|
fn ProjectedTextLine::injection_index_after(
  self : ProjectedTextLine,
  column : Int,
  inclusive_end~ : Bool,
) -> Int {
  for low = 0, high = self.injections.length(); low < high; {
    let mid = (low + high) / 2
    let end = self.injections[mid].end
    if end < column || (!inclusive_end && end == column) {
      continue mid + 1, high
    } else {
      continue low, mid
    }
  } nobreak {
    low
  }
}

///|
fn identity_projected_text_line(line_text : String) -> ProjectedTextLine {
  let length = line_text.length()
  let parts : Array[ProjectedLinePart] = []
  if length > 0 {
    parts.push({
      start: 0,
      end: length,
      kind: SourceSegment(model_start=0, model_end=length),
    })
  }
  { text: line_text, model_line_length: length, parts, injections: [], }
}

///|
fn normalize_injected_text(
  line_text : String,
  injected_text : ArrayView[InjectedText],
) -> Array[InjectedText] {
  let normalized : Array[InjectedText] = []
  for item in injected_text {
    if item.text.length() > 0 {
      let column = item.position.column.clamp(min=0, max=line_text.length())
      normalized.push({ ..item, position: { ..item.position, column, }, })
    }
  }
  normalized.sort_by((left, right) => {
    if left.position.column != right.position.column {
      left.position.column - right.position.column
    } else {
      left.source_index - right.source_index
    }
  })
  normalized
}

///|
pub extend InjectedText with Debug::{to_repr}

///|
pub extend InjectedText with Eq::{equal, not_equal}

///|
pub extend ProjectedLinePart with Debug::{to_repr}

///|
pub extend ProjectedLinePart with Eq::{equal, not_equal}

///|
pub extend ProjectedLinePartKind with Debug::{to_repr}

///|
pub extend ProjectedLinePartKind with Eq::{equal, not_equal}

///|
pub extend ProjectedTextLine with Debug::{to_repr}

///|
pub extend ProjectedTextLine with Eq::{equal, not_equal}
