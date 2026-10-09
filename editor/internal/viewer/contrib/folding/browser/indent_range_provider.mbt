// Port of `vscode/src/vs/editor/contrib/folding/browser/indentRangeProvider.ts`
// (checked-in vscode submodule): the
// indentation-based folding-range computation — `IndentRangeProvider`,
// `RangesCollector`, `computeRanges`.
//
// Deviations, following the `GuidesTextModelPart` precedent: `tab_size` is a
// parameter defaulting to 4 rather than `model.getOptions().tabSize` (the
// viewer's `TextModel` carries no editor options), and the provider takes
// a `LanguageHandle` in place of `ILanguageConfigurationService`.

///|
/// `MAX_FOLDING_REGIONS_FOR_INDENT_DEFAULT` (`indentRangeProvider.ts:14`).
const MAX_FOLDING_REGIONS_FOR_INDENT_DEFAULT : Int = 5000

///|
/// The indentation range provider — Monaco's `IndentRangeProvider`
/// (`indentRangeProvider.ts:18`).
struct IndentRangeProvider {
  editor_model : @model.TextModel
  language_configuration_service : @languages.LanguageHandle
  folding_ranges_limit : FoldingLimitReporter
  tab_size : Int
}

///|
pub fn IndentRangeProvider::IndentRangeProvider(
  editor_model : @model.TextModel,
  language_configuration_service : @languages.LanguageHandle,
  folding_ranges_limit : FoldingLimitReporter,
  tab_size? : Int = 4,
) -> IndentRangeProvider {
  {
    editor_model,
    language_configuration_service,
    folding_ranges_limit,
    tab_size,
  }
}

///|
fn IndentRangeProvider::dispose(self : IndentRangeProvider) -> Unit {
  ignore(self)
}

///|
/// `compute` (`indentRangeProvider.ts:29`): resolves the language's folding
/// rules and runs `computeRanges`.
pub fn IndentRangeProvider::compute(
  self : IndentRangeProvider,
) -> FoldingRegions {
  let folding_rules = self.language_configuration_service.get_language_configuration(
      self.editor_model.language_id,
    ).folding_rules
  let off_side = folding_rules is Some(rules) && rules.off_side
  let markers = match folding_rules {
    Some(rules) => rules.markers
    None => None
  }
  compute_ranges(
    self.editor_model,
    off_side,
    markers?,
    folding_ranges_limit=self.folding_ranges_limit,
    tab_size=self.tab_size,
  )
}

///|
/// Collects candidate ranges bottom-up and enforces the region limit by
/// dropping the deepest indents first — Monaco's `RangesCollector`
/// (`indentRangeProvider.ts:38`). White-box tests exercise it without adding
/// it to the package API.
priv struct RangesCollector {
  start_indexes : Array[Int]
  end_indexes : Array[Int]
  indent_occurrences : Array[Int]
  mut length : Int
  folding_ranges_limit : FoldingLimitReporter
}

///|
fn RangesCollector::RangesCollector(
  folding_ranges_limit : FoldingLimitReporter,
) -> RangesCollector {
  {
    start_indexes: [],
    end_indexes: [],
    indent_occurrences: [],
    length: 0,
    folding_ranges_limit,
  }
}

///|
/// `insertFirst` (`indentRangeProvider.ts:53`). Ranges arrive innermost/last
/// first; `toIndentRanges` reverses them into document order.
fn RangesCollector::insert_first(
  self : RangesCollector,
  start_line_number : Int,
  end_line_number : Int,
  indent : Int,
) -> Unit {
  if start_line_number > MAX_LINE_NUMBER || end_line_number > MAX_LINE_NUMBER {
    return
  }
  self.start_indexes.push(start_line_number)
  self.end_indexes.push(end_line_number)
  self.length += 1
  if indent < 1000 {
    // The source's sparse-array bump `_indentOccurrences[indent]++`.
    while self.indent_occurrences.length() <= indent {
      self.indent_occurrences.push(0)
    }
    self.indent_occurrences[indent] += 1
  }
}

///|
/// `toIndentRanges` (`indentRangeProvider.ts:66`): under the limit, reverse
/// into a `FoldingRegions`; over it, find the deepest indent level that
/// still fits and keep only shallower regions.
fn RangesCollector::to_indent_ranges(
  self : RangesCollector,
  model : @model.TextModel,
  tab_size? : Int = 4,
) -> FoldingRegions {
  let limit = (self.folding_ranges_limit.limit)()
  if self.length <= limit {
    (self.folding_ranges_limit.update)(self.length, None)
    // reverse and create arrays of the exact length
    let start_indexes = FixedArray::make(self.length, 0U)
    let end_indexes = FixedArray::make(self.length, 0U)
    for i in self.length>..0; k = 0 {
      start_indexes[k] = self.start_indexes[i].reinterpret_as_uint()
      end_indexes[k] = self.end_indexes[i].reinterpret_as_uint()
      continue k + 1
    }
    FoldingRegions(start_indexes, end_indexes)
  } else {
    (self.folding_ranges_limit.update)(self.length, Some(limit))
    let (entries, max_indent) = for i, n in self.indent_occurrences; entries = 0 {
      if n > 0 {
        if n + entries > limit {
          break (entries, i)
        }
        continue entries + n
      }
    } nobreak {
      (entries, self.indent_occurrences.length())
    }
    // reverse and create arrays of the exact length
    let start_indexes = FixedArray::make(limit, 0U)
    let end_indexes = FixedArray::make(limit, 0U)
    for i in self.length>..0; k = 0, entries = entries {
      let start_index = self.start_indexes[i]
      let line_content = model.snapshot.line_text(start_index - 1)
      let indent = @model.compute_indent_level(line_content, tab_size)
      // `indent < maxIndent || (indent === maxIndent && entries++ < limit)`
      let (take, next_entries) = if indent == max_indent {
        (entries < limit, entries + 1)
      } else {
        (indent < max_indent, entries)
      }
      if take {
        start_indexes[k] = start_index.reinterpret_as_uint()
        end_indexes[k] = self.end_indexes[i].reinterpret_as_uint()
        continue k + 1, next_entries
      }
      continue k, next_entries
    }
    FoldingRegions(start_indexes, end_indexes)
  }
}

///|
/// A block on the pending-region stack — Monaco's `PreviousRegion`
/// (`indentRangeProvider.ts:115`): `indent` is the block indent (`-1` for
/// the sentinel, `-2` for an end-marker region), `end_above` the end line
/// for the region above, `line` the start line (only used for marker
/// regions).
priv struct PreviousRegion {
  mut indent : Int
  mut end_above : Int
  mut line : Int
}

///|
/// `foldingRangesLimitDefault` (`indentRangeProvider.ts:121`).
let folding_ranges_limit_default : FoldingLimitReporter = {
  limit: () => MAX_FOLDING_REGIONS_FOR_INDENT_DEFAULT,
  update: (_computed, _limited) => (),
}

///|
/// Computes indentation-based folding regions bottom-up — Monaco's
/// `computeRanges` (`indentRangeProvider.ts:126`). A block folds from its
/// header line to the last more-indented line below it; `off_side`
/// languages attach trailing empty lines to the block above; `markers`
/// contribute `#region`/`#endregion`-style ranges. Monaco's combined
/// single-regex fast path collapses into the separate start/end probe order
/// (start wins), which is its own fallback branch.
pub fn compute_ranges(
  model : @model.TextModel,
  off_side : Bool,
  markers? : @languages.FoldingMarkers,
  folding_ranges_limit? : FoldingLimitReporter = folding_ranges_limit_default,
  tab_size? : Int = 4,
) -> FoldingRegions {
  let result = RangesCollector(folding_ranges_limit)
  let previous_regions : Array[PreviousRegion] = []
  let line_count = model.snapshot.line_count()
  // sentinel, to make sure there's at least one entry
  previous_regions.push({
    indent: -1,
    end_above: line_count + 1,
    line: line_count + 1,
  })
  for line in line_count>=..1 {
    let line_content = model.snapshot.line_text(line - 1)
    let indent = @model.compute_indent_level(line_content, tab_size)
    let mut previous = previous_regions[previous_regions.length() - 1]
    if indent == -1 {
      if off_side {
        // for offSide languages, empty lines are associated to the previous
        // block; note: the next block is already written to the results, so
        // this only impacts the end position of the block before
        previous.end_above = line
      }
      continue // only whitespace
    }
    let mut is_start_match = false
    let mut is_end_match = false
    match markers {
      Some(markers) => {
        is_start_match = (markers.start)(line_content)
        if !is_start_match {
          is_end_match = (markers.end)(line_content)
        }
      }
      None => ()
    }
    if is_start_match || is_end_match {
      // folding pattern match
      if is_start_match {
        // start pattern match: discard all regions until the folding pattern
        let mut i = previous_regions.length() - 1
        while i > 0 && previous_regions[i].indent != -2 {
          i -= 1
        }
        if i > 0 {
          while previous_regions.length() > i + 1 {
            previous_regions.pop() |> ignore
          }
          previous = previous_regions[i]
          // new folding range from pattern, includes the end line
          result.insert_first(line, previous.line, indent)
          previous.line = line
          previous.indent = indent
          previous.end_above = line
          continue
        }
        // else: no end marker found, treat line as a regular line
      } else {
        // end pattern match
        previous_regions.push({ indent: -2, end_above: line, line, })
        continue
      }
    }
    if previous.indent > indent {
      // discard all regions with larger indent
      for ;; {
        previous_regions.pop() |> ignore
        previous = previous_regions[previous_regions.length() - 1]
        if previous.indent <= indent {
          break
        }
      }
      // new folding range
      let end_line_number = previous.end_above - 1
      if end_line_number - line >= 1 {
        // needs at least size 1
        result.insert_first(line, end_line_number, indent)
      }
    }
    if previous.indent == indent {
      previous.end_above = line
    } else {
      // previous.indent < indent: new region with a bigger indent
      previous_regions.push({ indent, end_above: line, line, })
    }
  }
  result.to_indent_ranges(model, tab_size~)
}
