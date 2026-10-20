///|
test "MoonBit Markdown comments prefix a core-shaped block with its item boundary" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      (
        #|///|
        #|/// # Sample API
        #|///
        #|/// Uses **shell rendering**.
        #|pub fn sample() -> Unit {}
      ),
    ),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(1, 5),
      markdown: (
        #|---
        #|
        #|# Sample API
        #|
        #|Uses **shell rendering**.
      ),
    },
  ])
}

///|
test "MoonBit Markdown comments render separators and ignore detached groups" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      (
        #|///|
        #|let first = 1
        #|/// detached
        #|///| shadow
        #|///|
        #|
        #|/// separated
        #|///|
        #|/// Valid docs
        #|pub fn valid() -> Unit {}
        #|///|
        #|/// Second docs
        #|pub fn second() -> Unit {}
      ),
    ),
  )
  assert_eq(blocks, [
    { line_range: LineRange(1, 2), markdown: "---", },
    {
      line_range: LineRange(4, 5),
      markdown: (
        #|---
        #|
        #|shadow
      ),
    },
    { line_range: LineRange(5, 6), markdown: "---", },
    {
      line_range: LineRange(8, 10),
      markdown: (
        #|---
        #|
        #|Valid docs
      ),
    },
    {
      line_range: LineRange(11, 13),
      markdown: (
        #|---
        #|
        #|Second docs
      ),
    },
  ])
}

///|
test "MoonBit Markdown comments anchor a file header with marker-line text" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      (
        #|///| Port of `uri.ts`: the `URI` class.
        #|///
        #|/// Reviewed deviations:
        #|/// - D3: hand-rolled scanners.
        #|
        #|///|
        #|/// Item docs
        #|pub fn item() -> Unit {}
      ),
    ),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(1, 5),
      markdown: (
        #|---
        #|
        #|Port of `uri.ts`: the `URI` class.
        #|
        #|Reviewed deviations:
        #|- D3: hand-rolled scanners.
      ),
    },
    {
      line_range: LineRange(5, 8),
      markdown: (
        #|---
        #|
        #|Item docs
      ),
    },
  ])
}

///|
test "MoonBit Markdown comments render consecutive undocumented item separators" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      (
        #|///|
        #|fn first {}
        #|///|
        #|fn second {}
      ),
    ),
  )
  assert_eq(blocks, [
    { line_range: LineRange(1, 2), markdown: "---", },
    { line_range: LineRange(3, 4), markdown: "---", },
  ])
}

///|
test "MoonBit Markdown comments preserve body whitespace Unicode and fences" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "///|\n///\n/// \n///  indented\n/// | literal pipe\n///\tTabbed\n/// Unicode 中\n/// ```mbt\n/// let value = 1\n/// ```\npub fn documented() -> Unit {}",
    ),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(1, 11),
      markdown: "---\n\n\n\n indented\n| literal pipe\n\tTabbed\nUnicode 中\n```mbt\nlet value = 1\n```",
    },
  ])
}

///|
test "MoonBit Markdown comments keep an EOF half-open range after CRLF normalization" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot("let before = 1\r\n///|\r\n/// EOF docs"),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(2, 4),
      markdown: (
        #|---
        #|
        #|EOF docs
      ),
    },
  ])
}

///|
test "workbench installs the provider only for MoonBit models" {
  let languages = @languages.Languages()
  install_moonbit_markdown_comment_provider(languages)
  let log_service = @log.LogService()
  let handle = languages.language_handle(log_service.log_handle())
  let moonbit = @model.TextModel(
    try! @base_common.Uri::parse("inmemory://workbench/provider.mbt"),
    "provider.mbt",
    "moonbit",
    1,
    "moonbit-revision",
    (
      #|///|
      #|/// Registered docs
      #|pub fn registered() -> Unit {}
    ),
  )
  let plaintext = @model.TextModel(
    try! @base_common.Uri::parse("inmemory://workbench/provider.txt"),
    "provider.txt",
    "plaintext",
    1,
    "plaintext-revision",
    "///|\n/// Not selected",
  )
  defer {
    moonbit.dispose()
    plaintext.dispose()
  }
  guard handle.markdown_comment_provider_render_result(moonbit) is Some(result) else {
    fail("expected the workbench MoonBit provider")
  }
  assert_true(result.foldable)
  assert_eq(result.blocks.length(), 1)
  let block = result.blocks[0]
  assert_eq(block.line_range.start_line_number, 1)
  assert_eq(block.line_range.end_line_number_exclusive, 3)
  assert_eq(
    block.markdown,
    (
      #|---
      #|
      #|Registered docs
    ),
  )
  assert_true(handle.markdown_comment_provider_render_result(plaintext) is None)
}

///|
test "MoonBit Markdown comments cover the blank lines above their marker" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "// header\n\n///|\n/// Doc.\nfn first {}\n\n///|\n\n///|\nfn second {}",
    ),
  )
  assert_eq(blocks, [
    { line_range: LineRange(2, 5), markdown: "---\n\nDoc.", },
    { line_range: LineRange(6, 8), markdown: "---", },
    { line_range: LineRange(8, 10), markdown: "---", },
  ])
}
