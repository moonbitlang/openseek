///|
/// One-based line decoration range plus CSS class.
pub struct LineDecoration {
  start_column : Int
  end_column : Int
  class_name : String
  decoration_type : InlineDecorationType
} derive(Eq, Debug)

///|
/// Builds a line decoration.
pub fn LineDecoration::LineDecoration(
  start_column : Int,
  end_column : Int,
  class_name : String,
  decoration_type? : InlineDecorationType = Regular,
) -> LineDecoration {
  { start_column, end_column, class_name, decoration_type, }
}

///|
/// Sort order used before decoration normalization.
pub fn LineDecoration::compare(
  left : LineDecoration,
  right : LineDecoration,
) -> Int {
  if left.start_column != right.start_column {
    left.start_column - right.start_column
  } else if left.end_column != right.end_column {
    left.end_column - right.end_column
  } else {
    let type_cmp = inline_decoration_type_order(left.decoration_type) -
      inline_decoration_type_order(right.decoration_type)
    if type_cmp != 0 {
      type_cmp
    } else {
      // Monaco compares class names with JS string `<`, i.e. lexicographic by
      // UTF-16 code unit. MoonBit's `String::compare` is length-first, so this
      // must go through `@base_common.compare`.
      @base_common.compare(left.class_name, right.class_name)
    }
  }
}

///|
fn inline_decoration_type_order(decoration_type : InlineDecorationType) -> Int {
  match decoration_type {
    Before => 0
    After => 1
    Regular => 2
    RegularAffectingLetterSpacing => 3
  }
}

///|
/// Normalized decoration segment in zero-based offsets.
pub(all) struct DecorationSegment {
  start_offset : Int
  end_offset : Int
  class_name : String
  metadata : Int
} derive(Eq, Debug)

///|
/// Normalizes overlapping line decorations into contiguous CSS segments.
#warnings("-struct_never_constructed")
pub struct LineDecorationsNormalizer {}

///|
/// Converts sorted line decorations into renderer segments, preserving
/// surrogate-pair boundaries.
pub fn LineDecorationsNormalizer::normalize(
  line_content : String,
  line_decorations : Array[LineDecoration],
) -> Array[DecorationSegment] {
  if line_decorations.length() == 0 {
    return []
  }
  let result : Array[DecorationSegment] = []
  let stack = DecorationSegmentStack::DecorationSegmentStack()
  let line_length = line_content.length()
  let mut next_start_offset = 0
  for decoration in line_decorations {
    let mut start_column = decoration.start_column
    let mut end_column = decoration.end_column
    if start_column > 1 &&
      start_column - 2 < line_length &&
      @base_common.is_high_surrogate(line_content[start_column - 2].to_int()) {
      start_column -= 1
    }
    if end_column > 1 &&
      end_column - 2 < line_length &&
      @base_common.is_high_surrogate(line_content[end_column - 2].to_int()) {
      end_column -= 1
    }
    let start_offset = (start_column - 1).clamp(min=0, max=line_length)
    let end_offset_high = if line_length == 0 {
      start_offset - 1
    } else {
      (line_length - 1).max(start_offset - 1)
    }
    let end_offset = (end_column - 2).clamp(
      min=start_offset - 1,
      max=end_offset_high,
    )
    next_start_offset = stack.consume_lower_than(
      start_offset, next_start_offset, result,
    )
    if stack.count == 0 {
      next_start_offset = start_offset
    }
    stack.insert(
      end_offset,
      decoration.class_name,
      line_decoration_metadata(decoration.decoration_type),
    )
  }
  stack.consume_lower_than(2147483647, next_start_offset, result) |> ignore
  result
}

///|
priv struct DecorationSegmentStack {
  stop_offsets : Array[Int]
  class_names : Array[String]
  metadata : Array[Int]
  mut count : Int
}

///|
fn DecorationSegmentStack::DecorationSegmentStack() -> DecorationSegmentStack {
  { stop_offsets: [], class_names: [], metadata: [], count: 0, }
}

///|
fn DecorationSegmentStack::consume_lower_than(
  self : DecorationSegmentStack,
  max_stop_offset : Int,
  next_start_offset : Int,
  result : Array[DecorationSegment],
) -> Int {
  let mut offset = next_start_offset
  while self.count > 0 && self.stop_offsets[0] < max_stop_offset {
    let mut stop_index = 0
    while stop_index + 1 < self.count &&
          self.stop_offsets[stop_index] == self.stop_offsets[stop_index + 1] {
      stop_index += 1
    }
    result.push({
      start_offset: offset,
      end_offset: self.stop_offsets[stop_index],
      class_name: self.class_names.join(" "),
      metadata: decoration_stack_metadata(self.metadata),
    })
    offset = self.stop_offsets[stop_index] + 1
    for _ in 0..<=stop_index {
      self.stop_offsets.remove(0) |> ignore
      self.class_names.remove(0) |> ignore
      self.metadata.remove(0) |> ignore
    }
    self.count = self.count - stop_index - 1
  }
  if self.count > 0 && offset < max_stop_offset {
    result.push({
      start_offset: offset,
      end_offset: max_stop_offset - 1,
      class_name: self.class_names.join(" "),
      metadata: decoration_stack_metadata(self.metadata),
    })
    offset = max_stop_offset
  }
  offset
}

///|
fn DecorationSegmentStack::insert(
  self : DecorationSegmentStack,
  stop_offset : Int,
  class_name : String,
  metadata : Int,
) -> Unit {
  if self.count == 0 || self.stop_offsets[self.count - 1] <= stop_offset {
    self.stop_offsets.push(stop_offset)
    self.class_names.push(class_name)
    self.metadata.push(metadata)
  } else {
    let mut inserted = false
    let mut index = 0
    while index < self.count && !inserted {
      if self.stop_offsets[index] >= stop_offset {
        self.stop_offsets.insert(index, stop_offset)
        self.class_names.insert(index, class_name)
        self.metadata.insert(index, metadata)
        inserted = true
      }
      index += 1
    }
  }
  self.count += 1
}

///|
fn decoration_stack_metadata(metadata : Array[Int]) -> Int {
  metadata.fold(init=0, (bits, item) => bits | item)
}

///|
fn line_decoration_metadata(decoration_type : InlineDecorationType) -> Int {
  match decoration_type {
    Regular => 0
    Before => line_part_metadata_pseudo_before
    After => line_part_metadata_pseudo_after
    RegularAffectingLetterSpacing => 0
  }
}

///|
pub extend DecorationSegment with Debug::{to_repr}

///|
pub extend DecorationSegment with Eq::{equal, not_equal}

///|
pub extend LineDecoration with Debug::{to_repr}

///|
pub extend LineDecoration with Eq::{equal, not_equal}
