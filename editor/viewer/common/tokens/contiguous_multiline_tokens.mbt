///| A source-shaped in-process port of Monaco's `ContiguousMultilineTokens`.
///
/// Source: `vscode/src/vs/editor/common/tokens/contiguousMultilineTokens.ts`
/// at checked-in oracle, consumed
/// closure lines 17 and 35-80. Serialization and incremental editing are not
/// part of the readonly Viewer boundary.

///|
/// Encoded tokens for one contiguous inclusive interval of one-based lines.
/// Each inner array contains `[endOffset, metadata]` pairs for one line.
/// Source: `contiguousMultilineTokens.ts:17,35-46`.
struct ContiguousMultilineTokens {
  start_line_number_ : Int32
  tokens : Array[Array[UInt32]]
}

///|
/// Retains the caller's line order and encoded token arrays.
/// Source: `contiguousMultilineTokens.ts:62-65`.
fn ContiguousMultilineTokens::ContiguousMultilineTokens(
  start_line_number : Int32,
  tokens : Array[Array[UInt32]],
) -> ContiguousMultilineTokens {
  { start_line_number_: start_line_number, tokens, }
}

///|
/// Inclusive first line of this batch.
/// Source: `contiguousMultilineTokens.ts:51-53`.
fn ContiguousMultilineTokens::start_line_number(
  self : ContiguousMultilineTokens,
) -> Int32 {
  self.start_line_number_
}

///|
/// Inclusive final line of this batch.
/// Source: `contiguousMultilineTokens.ts:58-60`.
fn ContiguousMultilineTokens::end_line_number(
  self : ContiguousMultilineTokens,
) -> Int32 {
  self.start_line_number_ + self.tokens.length() - 1
}

///|
/// Half-open line range covered by this batch.
/// Source: `contiguousMultilineTokens.ts:67-69`.
#warnings("-unused_value")
fn ContiguousMultilineTokens::get_line_range(
  self : ContiguousMultilineTokens,
) -> @base_common.LineRange {
  let range : @base_common.LineRange = {
    start_line_number: self.start_line_number_,
    end_line_number_exclusive: self.start_line_number_ + self.tokens.length(),
  }
  range
}

///|
/// Returns the encoded words for an included one-based line.
/// Source: `contiguousMultilineTokens.ts:74-76`.
fn ContiguousMultilineTokens::get_line_tokens(
  self : ContiguousMultilineTokens,
  line_number : Int32,
) -> Array[UInt32] {
  self.tokens[line_number - self.start_line_number_]
}

///|
/// Extends the batch by exactly one final line.
/// Source: `contiguousMultilineTokens.ts:78-80`.
fn ContiguousMultilineTokens::append_line_tokens(
  self : ContiguousMultilineTokens,
  line_tokens : Array[UInt32],
) -> Unit {
  self.tokens.push(line_tokens)
}
