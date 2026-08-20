///|
/// DOM span/character coordinate for a rendered line.
pub(all) struct DomPosition {
  part_index : Int
  char_index : Int
} derive(Eq, Debug)

///|
/// Mapping entry from one line column to rendered DOM coordinates and visible
/// monospace column.
pub struct CharacterMappingEntry {
  part_index : Int
  char_index : Int
  visible_column : Int
} derive(Eq, Debug)

///|
/// Column-to-DOM mapping produced while rendering a line.
pub struct CharacterMapping {
  length : Int
  entries : Array[CharacterMappingEntry]
} derive(Eq, Debug)

///|
/// Creates a mapping with `length` column slots.
pub fn CharacterMapping::CharacterMapping(length : Int) -> CharacterMapping {
  let entries : Array[CharacterMappingEntry] = []
  for _ in 0..<length {
    entries.push({ part_index: 0, char_index: 0, visible_column: 0 })
  }
  { length, entries }
}

///|
/// Stores DOM and visible-column info for a one-based line column.
pub fn CharacterMapping::set_column_info(
  self : CharacterMapping,
  column : Int,
  part_index : Int,
  char_index : Int,
  visible_column : Int,
) -> Unit {
  let index = column - 1
  if index >= 0 && index < self.entries.length() {
    self.entries[index] = { part_index, char_index, visible_column }
  }
}

///|
/// Returns the DOM position nearest a one-based line column.
pub fn CharacterMapping::get_dom_position(
  self : CharacterMapping,
  column : Int,
) -> DomPosition {
  if self.length == 0 {
    return { part_index: 0, char_index: 0 }
  }
  let index = (column - 1).clamp(min=0, max=self.length - 1)
  let entry = self.entries[index]
  { part_index: entry.part_index, char_index: entry.char_index }
}

///|
/// Returns the one-based line column nearest a DOM position, transcribing
/// Monaco's `CharacterMapping.getColumn`/`partDataToCharOffset`. The mapping
/// entries are laid out left-to-right, so their `(part_index, char_index)`
/// ranks increase monotonically; a binary search brackets the DOM position
/// between two columns and returns the nearer one. `part_length` bounds the
/// "sitting between parts" case, where the upper column starts a new part.
pub fn CharacterMapping::get_column(
  self : CharacterMapping,
  dom_position : DomPosition,
  part_length : Int,
) -> Int {
  self.part_data_to_char_offset(
    dom_position.part_index,
    part_length,
    dom_position.char_index,
  ) +
  1
}

///|
fn CharacterMapping::part_data_to_char_offset(
  self : CharacterMapping,
  part_index : Int,
  part_length : Int,
  char_index : Int,
) -> Int {
  if self.length == 0 {
    return 0
  }
  let search = mapping_rank(part_index, char_index)
  let (min, max) = for min = 0, max = self.length - 1; min + 1 < max; {
    let mid = (min + max) / 2
    let mid_entry = mapping_rank_entry(self.entries[mid])
    if mid_entry == search {
      break (mid, mid)
    } else if mid_entry > search {
      continue min, mid
    } else {
      continue mid, max
    }
  } nobreak {
    (min, max)
  }
  if min == max {
    return min
  }
  let min_entry = self.entries[min]
  let max_entry = self.entries[max]
  if mapping_rank_entry(min_entry) == search {
    return min
  }
  if mapping_rank_entry(max_entry) == search {
    return max
  }
  let min_char_index = min_entry.char_index
  let max_char_index = if min_entry.part_index != max_entry.part_index {
    // Sitting between parts: the upper bracket starts a new part, so its
    // distance is measured against the hit part's length.
    part_length
  } else {
    max_entry.char_index
  }
  let min_entry_distance = char_index - min_char_index
  let max_entry_distance = max_char_index - char_index
  if min_entry_distance <= max_entry_distance {
    min
  } else {
    max
  }
}

///|
/// Visible monospace column for a one-based line column.
pub fn CharacterMapping::get_horizontal_offset(
  self : CharacterMapping,
  column : Int,
) -> Int {
  if self.length == 0 {
    return 0
  }
  let index = (column - 1).clamp(min=0, max=self.length - 1)
  self.entries[index].visible_column
}

///|
/// Horizontal CSS-pixel offset for a one-based line column.
pub fn CharacterMapping::column_horizontal_offset(
  self : CharacterMapping,
  column : Int,
  space_width~ : Double,
) -> Double {
  self.get_horizontal_offset(column).to_double() * space_width
}

///|
/// Copies the raw mapping entries for diagnostics and tests.
pub fn CharacterMapping::inflate(
  self : CharacterMapping,
) -> Array[CharacterMappingEntry] {
  self.entries.copy()
}

///|
fn mapping_rank(part_index : Int, char_index : Int) -> Int {
  part_index * 65536 + char_index
}

///|
fn mapping_rank_entry(entry : CharacterMappingEntry) -> Int {
  mapping_rank(entry.part_index, entry.char_index)
}

///|
/// Render output when the caller owns the output builder.
pub struct RenderLineOutput {
  character_mapping : CharacterMapping
  contains_foreign_elements : ForeignElementType
} derive(Eq, Debug)

///|
/// Render output including generated HTML.
pub struct RenderLineOutput2 {
  html : String
  character_mapping : CharacterMapping
  contains_foreign_elements : ForeignElementType
} derive(Eq, Debug)

///|
#deprecated
pub extend CharacterMapping with Debug::{to_repr}

///|
pub extend CharacterMapping with Eq::{equal, not_equal}

///|
#deprecated
pub extend CharacterMappingEntry with Debug::{to_repr}

///|
pub extend CharacterMappingEntry with Eq::{equal, not_equal}

///|
#deprecated
pub extend DomPosition with Debug::{to_repr}

///|
pub extend DomPosition with Eq::{equal, not_equal}

///|
#deprecated
pub extend RenderLineOutput with Debug::{to_repr}

///|
pub extend RenderLineOutput with Eq::{equal, not_equal}

///|
#deprecated
pub extend RenderLineOutput2 with Debug::{to_repr}

///|
pub extend RenderLineOutput2 with Eq::{equal, not_equal}
