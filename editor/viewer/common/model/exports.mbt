// Explicit exported contracts. Staged APIs without non-test consumers live
// here so `moon ide analyze` records the exception; the abstract
// `InjectedTextOptions` representation gateway lives here as well.

///|
/// Constructs the read-only injected-text payload consumed by the production
/// view-model projection.
pub fn InjectedTextOptions::InjectedTextOptions(
  content : String,
  inline_class_name? : String,
  attached_index? : Int = -1,
) -> InjectedTextOptions {
  { content, inline_class_name, attached_index }
}

///|
/// Returns the text inserted into the rendered line.
pub fn InjectedTextOptions::content(self : InjectedTextOptions) -> String {
  self.content
}

///|
/// Returns the optional inline CSS class for the inserted text.
pub fn InjectedTextOptions::inline_class_name(
  self : InjectedTextOptions,
) -> String? {
  self.inline_class_name
}

///|
/// Returns the producer-defined attachment index used by hit testing.
pub fn InjectedTextOptions::attached_index(self : InjectedTextOptions) -> Int {
  self.attached_index
}

///|
/// `IModelContentChange` (`model/mirrorTextModel.ts`): one change entry of
/// the public content-changed payload.
pub(all) struct ModelContentChange {
  /// The range that got replaced.
  range : @base_common.Range
  /// The offset of the range that got replaced.
  range_offset : Int
  /// The length of the range that got replaced.
  range_length : Int
  /// The new text for the range.
  text : String
} derive(Debug)

///|
pub extend ModelContentChange with Debug::{to_repr}
