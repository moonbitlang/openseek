///|
/// Direction metadata for a rendered line.
pub(all) enum TextDirection {
  LTR
  RTL
} derive(Eq, Debug)

///|
/// Inline decoration placement relative to source text.
pub(all) enum InlineDecorationType {
  Regular
  Before
  After
  RegularAffectingLetterSpacing
} derive(Eq, Debug)

///|
/// Whether a rendered line contains pseudo-elements before or after text.
pub(all) enum ForeignElementType {
  None
  Before
  After
  BeforeAndAfter
} derive(Eq, Debug)

///|
/// Tokenized segment ending at `end_index` with CSS and metadata flags.
pub struct LinePart {
  end_index : Int
  class_name : String
  metadata : Int
  contains_rtl : Bool
} derive(Eq, Debug)

///|
/// Builds a line part.
pub fn LinePart::LinePart(
  end_index : Int,
  class_name : String,
  metadata? : Int = 0,
  contains_rtl? : Bool = false,
) -> LinePart {
  { end_index, class_name, metadata, contains_rtl }
}

///|
/// Whether this part represents visible whitespace.
pub fn LinePart::is_whitespace(self : LinePart) -> Bool {
  (self.metadata & line_part_metadata_is_whitespace) != 0
}

///|
/// Whether this part is a before pseudo-element.
pub fn LinePart::is_pseudo_before(self : LinePart) -> Bool {
  (self.metadata & line_part_metadata_pseudo_before) != 0
}

///|
/// Whether this part is an after pseudo-element.
pub fn LinePart::is_pseudo_after(self : LinePart) -> Bool {
  (self.metadata & line_part_metadata_pseudo_after) != 0
}

///|
let line_part_metadata_is_whitespace = 1

///|
let line_part_metadata_pseudo_before = 2

///|
let line_part_metadata_pseudo_after = 4

///|
#deprecated
pub extend ForeignElementType with Debug::{to_repr}

///|
pub extend ForeignElementType with Eq::{equal, not_equal}

///|
#deprecated
pub extend InlineDecorationType with Debug::{to_repr}

///|
pub extend InlineDecorationType with Eq::{equal, not_equal}

///|
#deprecated
pub extend LinePart with Debug::{to_repr}

///|
pub extend LinePart with Eq::{equal, not_equal}

///|
#deprecated
pub extend TextDirection with Debug::{to_repr}

///|
pub extend TextDirection with Eq::{equal, not_equal}
