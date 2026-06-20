///|
fn strip(markdown : String) -> String {
  @markdown_comments.without_comments(markdown)
}

///|
fn visible_cr(markdown : String) -> String {
  markdown.split("\r").collect().join("|")
}

///|
test "without comments keeps ordinary markdown unchanged" {
  inspect(
    strip("# Title\n\nBody with <span>html</span>.\n"),
    content="# Title\n\nBody with <span>html</span>.\n",
  )
}

///|
test "top-level block comments are removed" {
  inspect(
    strip(
      (
        #|# Title
        #|
        #|<!-- hidden block
        #|still hidden -->
        #|
        #|Visible.
        #|
      ),
    ),
    content=(
      #|# Title
      #|
      #|
      #|
      #|Visible.
      #|
    ),
  )
}

///|
test "single-line block comments can share a line with visible text" {
  inspect(
    strip("<!-- hidden --> Visible after block comment.\n"),
    content=" Visible after block comment.\n",
  )
}

///|
test "adjacent comment ranges are all removed" {
  inspect(
    strip("<!-- first --> Visible <!-- second --> after.\n"),
    content=" Visible  after.\n",
  )
}

///|
test "inline comments are removed from paragraphs" {
  inspect(
    strip("Visible <!-- hidden inline --> text.\n"),
    content="Visible  text.\n",
  )
}

///|
test "multiline inline comments are removed from paragraphs" {
  inspect(strip("foo <!-- hidden\ncomment --> bar\n"), content="foo  bar\n")
}

///|
test "comments in headings and emphasis are removed" {
  inspect(
    strip("# Title <!-- hidden --> now\n\nA **bold <!-- hidden --> word**.\n"),
    content="# Title  now\n\nA **bold  word**.\n",
  )
}

///|
test "comments in blockquotes and lists are removed" {
  inspect(
    strip(
      (
        #|> Quoted <!-- hidden --> text.
        #|
        #|- First <!-- hidden --> item
        #|- <!-- hidden --> second
        #|
      ),
    ),
    content=(
      #|> Quoted  text.
      #|
      #|- First  item
      #|-  second
      #|
    ),
  )
}

///|
test "comments in table cells are removed" {
  inspect(
    strip(
      (
        #|| Left | Right |
        #|| --- | --- |
        #|| a <!-- hidden --> cell | <!-- hidden --> b |
        #|
      ),
    ),
    content=(
      #|| Left | Right |
      #|| --- | --- |
      #|| a  cell |  b |
      #|
    ),
  )
}

///|
test "fenced and indented code keep comment text" {
  inspect(
    strip(
      (
        #|```markdown
        #|<!-- kept in fenced code -->
        #|```
        #|
        #|    <!-- kept in indented code -->
        #|
      ),
    ),
    content=(
      #|```markdown
      #|<!-- kept in fenced code -->
      #|```
      #|
      #|    <!-- kept in indented code -->
      #|
    ),
  )
}

///|
test "plain html blocks are preserved" {
  inspect(strip("<div>kept html</div>\n"), content="<div>kept html</div>\n")
}

///|
test "comments inside multiline html blocks are removed" {
  inspect(
    strip(
      (
        #|<div>
        #|<!-- hidden inside html block -->
        #|kept html block
        #|</div>
        #|
      ),
    ),
    content=(
      #|<div>
      #|
      #|kept html block
      #|</div>
      #|
    ),
  )
}

///|
test "same-line html block comments are removed" {
  inspect(
    strip("<div><!-- hidden same-line html block -->kept html inline</div>\n"),
    content="<div>kept html inline</div>\n",
  )
}

///|
test "multiple html block comments are removed independently" {
  inspect(
    strip("<section><!-- one -->kept<!-- two --></section>\n"),
    content="<section>kept</section>\n",
  )
}

///|
test "unicode before comments keeps byte ranges aligned" {
  inspect(
    strip("Hello 月 <!-- hidden --> world\n"),
    content="Hello 月  world\n",
  )
}

///|
test "cr-only line endings preserve preceding text" {
  inspect(
    visible_cr(
      strip("Before\r<!-- hidden --> Visible <!-- second --> after\rAfter\r"),
    ),
    content="Before| Visible  after|After|",
  )
}

///|
test "crlf line endings preserve visible text" {
  inspect(
    visible_cr(strip("Before\r\n<!-- hidden --> Visible\r\nAfter\r\n")),
    content="Before|\n Visible|\nAfter|\n",
  )
}

///|
test "incomplete comments are preserved" {
  inspect(
    strip("Before <!-- hidden\nAfter\n"),
    content="Before <!-- hidden\nAfter\n",
  )
}
