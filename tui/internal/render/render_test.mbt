///|
test "composer surface renders viewport rows and cursor" {
  let surface = @render.composer_surface(
    @composer.Model::new(),
    activity=None,
    queued_inputs=[],
    status=@doc.Text::plain("ready"),
    notice=None,
    cols=12,
  )
  inspect(surface.height(), content="4")
  inspect(
    surface.line_at(0).text(),
    content="────────────",
  )
  inspect(surface.line_at(1).text().trim(), content=">")
  inspect(@text.display_width(surface.line_at(1).text()), content="12")
  inspect(
    surface.line_at(2).text(),
    content="────────────",
  )
  inspect(surface.cursor().row(), content="1")
  inspect(surface.cursor().col(), content="2")
}

///|
test "composer surface grows with multiline input up to max rows" {
  let two_lines = @composer.Model::new()
  two_lines.insert("a\nb")
  let two_line_surface = @render.composer_surface(
    two_lines,
    activity=None,
    queued_inputs=[],
    status=@doc.Text::plain(""),
    notice=None,
    cols=12,
  )
  inspect(two_line_surface.height(), content="5")
  inspect(two_line_surface.line_at(1).text().trim(), content="> a")
  inspect(@text.display_width(two_line_surface.line_at(1).text()), content="12")
  inspect(
    @text.grapheme_slice(two_line_surface.line_at(2).text(), 0, 2),
    content="  ",
  )
  inspect(two_line_surface.line_at(2).text().trim(), content="b")
  inspect(@text.display_width(two_line_surface.line_at(2).text()), content="12")
  let five_lines = @composer.Model::new()
  five_lines.insert("a\nb\nc\nd\ne")
  let capped_surface = @render.composer_surface(
    five_lines,
    activity=None,
    queued_inputs=[],
    status=@doc.Text::plain(""),
    notice=None,
    cols=12,
  )
  inspect(capped_surface.height(), content="7")
  inspect(
    @text.grapheme_slice(capped_surface.line_at(1).text(), 0, 2),
    content="  ",
  )
  inspect(capped_surface.line_at(1).text().trim(), content="b")
  inspect(@text.display_width(capped_surface.line_at(1).text()), content="12")
  inspect(
    @text.grapheme_slice(capped_surface.line_at(4).text(), 0, 2),
    content="  ",
  )
  inspect(capped_surface.line_at(4).text().trim(), content="e")
  inspect(@text.display_width(capped_surface.line_at(4).text()), content="12")
}

///|
test "composer surface renders queued inputs above composer" {
  let surface = @render.composer_surface(
    @composer.Model::new(),
    activity=None,
    queued_inputs=[Prompt("first"), Command("pwd")],
    status=@doc.Text::plain("ready"),
    notice=None,
    cols=40,
  )
  inspect(surface.height(), content="7")
  inspect(surface.line_at(0).text(), content="queued follow-up inputs:")
  inspect(surface.line_at(1).text(), content="  1. > first")
  inspect(surface.line_at(2).text(), content="  2. $ pwd")
  inspect(@text.display_width(surface.line_at(3).text()), content="40")
  inspect(surface.cursor().row(), content="4")
  inspect(surface.cursor().col(), content="2")
}

///|
test "composer surface renders the input viewport" {
  let surface = @render.composer_surface(
    @composer.Model::new(),
    activity=None,
    queued_inputs=[],
    status=@doc.Text::plain("ready"),
    notice=None,
    cols=40,
  )
  inspect(surface.height(), content="4")
  inspect(
    surface.line_at(0).text(),
    content="────────────────────────────────────────",
  )
  inspect(surface.line_at(1).text().trim(), content=">")
  inspect(@text.display_width(surface.line_at(1).text()), content="40")
  inspect(
    surface.line_at(2).text(),
    content="────────────────────────────────────────",
  )
  inspect(surface.cursor().row(), content="1")
  inspect(surface.cursor().col(), content="2")
}

///|
test "composer surface renders activity above separator" {
  let surface = @render.composer_surface(
    @composer.Model::new(),
    activity=Some(@doc.Text::plain("Working (0s • esc to interrupt)")),
    queued_inputs=[],
    status=@doc.Text::plain("gpt-5 · ~/repo · Context 100% left"),
    notice=None,
    cols=50,
  )
  inspect(surface.height(), content="7")
  inspect(surface.line_at(0).text(), content="")
  inspect(
    surface.line_at(1).text(),
    content="Working (0s • esc to interrupt)",
  )
  inspect(surface.line_at(2).text().trim(), content="")
  inspect(@text.display_width(surface.line_at(2).text()), content="0")
  inspect(
    surface.line_at(3).text(),
    content="──────────────────────────────────────────────────",
  )
}

///|
test "composer surface notice overrides persistent status" {
  let surface = @render.composer_surface(
    @composer.Model::new(),
    activity=None,
    queued_inputs=[],
    status=@doc.Text::plain("gpt-5 · ~/repo"),
    notice=Some(@doc.Text::plain("ignored key")),
    cols=40,
  )
  inspect(
    surface.line_at(2).text(),
    content="────────────────────────────────────────",
  )
}
