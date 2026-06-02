# bobzhang/openseek/tui/internal/render

This is where the core layout logic of the input area resides — the view layer
that decides what the bottom of an Agent TUI (Codex / Claude Code style) looks
like on any given frame. It takes the live editing state and the surrounding
context (status line, activity, queued inputs) and stacks them into a single
[`surface`](../surface/) `Surface`: the finished picture that
[`viewport`](../viewport/) then draws to the terminal.

It's one pure function, `composer_surface`. No terminal IO, no input handling —
given the same state and width it always produces the same surface, which makes
the whole input area trivial to test and reason about.

## Usage

Hand it the composer model plus the surrounding state and a column width; get
back a ready-to-draw surface with the cursor already placed on the active input
row.

```mbt
let surface = @render.composer_surface(
  model,                                   // @composer.Model being edited
  activity=Some(@doc.Text::plain("…")),    // transient busy line, or None
  queued_inputs=[@core.Input::Prompt("next")],
  status=@doc.Text::plain("ready"),        // persistent status line
  notice=None,                             // transient notice, overrides status
  cols=80,
)
```

The surface stacks, top to bottom: the queued-input preview, the optional
activity block, the bordered composer body, and the status line (`notice` wins
over `status` when present). The only state it touches is resizing the model to
`cols` for the draw.

Internal to `tui/` — only importable within the module.
