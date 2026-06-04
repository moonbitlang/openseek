///|
fn display_width(text : String) -> Int {
  @displaytext.DisplayText(text).width()
}

///|
fn display_prefix(text : String, units : Int) -> String {
  let line = @displaytext.DisplayText(text)
  let mut end = line.start()
  let mut remaining = units.max(0)
  while remaining > 0 {
    match line.next(end) {
      Some(next) => {
        end = next
        remaining = remaining - 1
      }
      None => remaining = 0
    }
  }
  line.view(line.start(), end).to_owned()
}

///|
test "composer surface renders viewport rows and cursor" {
  let surface = @render.composer_surface(
    @composer.Model::new(""),
    activity=None,
    queued_inputs=[],
    status=@doc.Text::plain("ready"),
    notice=None,
    cols=12,
    max_rows=24,
  )
  inspect(
    surface.height(),
    content=(
      #|5
    ),
  )
  inspect(
    surface.line_at(0).text(),
    content=(
      #|
    ),
  )
  inspect(
    surface.line_at(1).text().trim(),
    content=(
      #|────────────
    ),
  )
  inspect(display_width(surface.line_at(1).text()), content="12")
  inspect(
    surface.line_at(2).text(),
    content=(
      #|❯           
    ),
  )
  inspect(
    surface.cursor().row(),
    content=(
      #|2
    ),
  )
  inspect(surface.cursor().col(), content="2")
}

///|
test "composer surface grows with multiline input up to max rows" {
  let two_lines = @composer.Model::new("")
  two_lines.insert("a\nb")
  let two_line_surface = @render.composer_surface(
    two_lines,
    activity=None,
    queued_inputs=[],
    status=@doc.Text::plain(""),
    notice=None,
    cols=12,
    max_rows=24,
  )
  inspect(
    two_line_surface.height(),
    content=(
      #|6
    ),
  )
  inspect(
    two_line_surface.line_at(1).text().trim(),
    content=(
      #|────────────
    ),
  )
  inspect(display_width(two_line_surface.line_at(1).text()), content="12")
  inspect(
    display_prefix(two_line_surface.line_at(2).text(), 2),
    content=(
      #|❯ 
    ),
  )
  inspect(
    two_line_surface.line_at(2).text().trim(),
    content=(
      #|❯ a
    ),
  )
  inspect(display_width(two_line_surface.line_at(2).text()), content="12")
  let five_lines = @composer.Model::new("")
  five_lines.insert("a\nb\nc\nd\ne")
  let capped_surface = @render.composer_surface(
    five_lines,
    activity=None,
    queued_inputs=[],
    status=@doc.Text::plain(""),
    notice=None,
    cols=12,
    max_rows=24,
  )
  inspect(
    capped_surface.height(),
    content=(
      #|8
    ),
  )
  inspect(
    display_prefix(capped_surface.line_at(1).text(), 2),
    content=(
      #|──
    ),
  )
  inspect(
    capped_surface.line_at(1).text().trim(),
    content=(
      #|────────────
    ),
  )
  inspect(display_width(capped_surface.line_at(1).text()), content="12")
  inspect(display_prefix(capped_surface.line_at(4).text(), 2), content="  ")
  inspect(
    capped_surface.line_at(4).text().trim(),
    content=(
      #|d
    ),
  )
  inspect(display_width(capped_surface.line_at(4).text()), content="12")
}

///|
test "composer surface renders queued inputs above composer" {
  let surface = @render.composer_surface(
    @composer.Model::new(""),
    activity=None,
    queued_inputs=[Prompt("first"), Command("pwd")],
    status=@doc.Text::plain("ready"),
    notice=None,
    cols=40,
    max_rows=24,
  )
  inspect(
    surface.height(),
    content=(
      #|9
    ),
  )
  inspect(
    surface.line_at(0).text(),
    content=(
      #|
    ),
  )
  inspect(
    surface.line_at(1).text(),
    content=(
      #|  Queued follow-up inputs:
    ),
  )
  inspect(
    surface.line_at(2).text(),
    content=(
      #|  1. ❯ first
    ),
  )
  inspect(
    display_width(surface.line_at(3).text()),
    content=(
      #|10
    ),
  )
  inspect(
    surface.cursor().row(),
    content=(
      #|6
    ),
  )
  inspect(surface.cursor().col(), content="2")
}

///|
test "composer surface renders the input viewport" {
  let surface = @render.composer_surface(
    @composer.Model::new(""),
    activity=None,
    queued_inputs=[],
    status=@doc.Text::plain("ready"),
    notice=None,
    cols=40,
    max_rows=24,
  )
  inspect(
    surface.height(),
    content=(
      #|5
    ),
  )
  inspect(
    surface.line_at(0).text(),
    content=(
      #|
    ),
  )
  inspect(
    surface.line_at(1).text().trim(),
    content=(
      #|────────────────────────────────────────
    ),
  )
  inspect(display_width(surface.line_at(1).text()), content="40")
  inspect(
    surface.line_at(2).text(),
    content=(
      #|❯                                       
    ),
  )
  inspect(
    surface.cursor().row(),
    content=(
      #|2
    ),
  )
  inspect(surface.cursor().col(), content="2")
}

///|
test "composer surface renders activity above separator" {
  let surface = @render.composer_surface(
    @composer.Model::new(""),
    activity=Some(@doc.Text::plain("Working (0s • esc to interrupt)")),
    queued_inputs=[],
    status=@doc.Text::plain("gpt-5 · ~/repo · Context 100% left"),
    notice=None,
    cols=50,
    max_rows=24,
  )
  inspect(
    surface.height(),
    content=(
      #|7
    ),
  )
  inspect(surface.line_at(0).text(), content="")
  inspect(
    surface.line_at(1).text(),
    content=(
      #|  Working (0s • esc to interrupt)
    ),
  )
  inspect(
    surface.line_at(2).text().trim(),
    content=(
      #|
    ),
  )
  inspect(
    display_width(surface.line_at(2).text()),
    content=(
      #|0
    ),
  )
  inspect(
    surface.line_at(3).text(),
    content=(
      #|──────────────────────────────────────────────────
    ),
  )
}

///|
test "composer surface puts activity above queued inputs" {
  let surface = @render.composer_surface(
    @composer.Model::new(""),
    activity=Some(@doc.Text::plain("Working (3s)")),
    queued_inputs=[Prompt("next")],
    status=@doc.Text::plain("ready"),
    notice=None,
    cols=40,
    max_rows=24,
  )
  // Spacer, the current task, a blank, then the indented queue that follows it.
  inspect(surface.line_at(0).text(), content="")
  inspect(
    surface.line_at(1).text(),
    content=(
      #|  Working (3s)
    ),
  )
  inspect(surface.line_at(2).text(), content="")
  inspect(
    surface.line_at(3).text(),
    content=(
      #|  Queued follow-up inputs:
    ),
  )
  inspect(
    surface.line_at(4).text(),
    content=(
      #|  1. ❯ next
    ),
  )
}

///|
test "composer surface shows a notice when the terminal is below the minimum" {
  let surface = @render.composer_surface(
    @composer.Model::new(""),
    activity=Some(@doc.Text::plain("Working")),
    queued_inputs=[Prompt("a")],
    status=@doc.Text::plain("ready"),
    notice=None,
    cols=60,
    max_rows=4,
  )
  inspect(surface.height(), content="1")
  inspect(
    surface.line_at(0).text(),
    content="Terminal too small — resize to at least 5 rows",
  )
}

///|
test "composer surface drops activity and queue when the terminal is too short" {
  let surface = @render.composer_surface(
    @composer.Model::new(""),
    activity=Some(@doc.Text::plain("Working (3s)")),
    queued_inputs=[Prompt("a"), Prompt("b")],
    status=@doc.Text::plain("ready"),
    notice=None,
    cols=40,
    max_rows=6,
  )
  // Only the composer + chrome remain (spacer, separators, prompt, status); the
  // activity line and queue are dropped so the prompt is never clipped.
  inspect(surface.height(), content="5")
  inspect(display_prefix(surface.line_at(2).text(), 1), content="❯")
  inspect(surface.cursor().row(), content="2")
}

///|
test "composer surface bounds queued previews so the composer stays visible" {
  let surface = @render.composer_surface(
    @composer.Model::new(""),
    activity=Some(@doc.Text::plain("Working")),
    queued_inputs=[
      Prompt("a"),
      Prompt("b"),
      Prompt("c"),
      Prompt("d"),
      Prompt("e"),
    ],
    status=@doc.Text::plain("ready"),
    notice=None,
    cols=40,
    max_rows=10,
  )
  // The live area fits the budget and the overflowing queue collapses to a
  // single summary line instead of pushing the composer off screen.
  inspect(surface.height(), content="10")
  inspect(
    surface.line_at(4).text(),
    content=(
      #|  … 5 more
    ),
  )
  // The composer prompt survives and the cursor stays on it, not on a queue row.
  inspect(display_prefix(surface.line_at(7).text(), 1), content="❯")
  inspect(surface.cursor().row(), content="7")
}

///|
test "composer surface notice overrides persistent status" {
  let surface = @render.composer_surface(
    @composer.Model::new(""),
    activity=None,
    queued_inputs=[],
    status=@doc.Text::plain("gpt-5 · ~/repo"),
    notice=Some(@doc.Text::plain("ignored key")),
    cols=40,
    max_rows=24,
  )
  inspect(
    surface.line_at(2).text(),
    content=(
      #|❯                                       
    ),
  )
}
