# bobzhang/openseek/tui/internal/surface

This is the **picture format** the TUI passes around — an immutable description
of one frame, with no terminal and no IO attached. A `Span` is styled text, a
`Line` is a row of spans, and a `Surface` is a full frame: its rows plus a
`Cursor`. Think of it as the handoff type between the layers that *decide* what
to draw ([`doc`](../../doc/), [`render`](../render/)) and the layer that
*draws* it ([`viewport`](../viewport/)).

Because a `Surface` is plain immutable data, the producers are pure and easy to
test, and the renderer never has to re-validate anything: `Surface::new`
normalizes the invariants up front — `width >= 1`, and the cursor clamped inside
the rows and width.

## Usage

```mbt
let line = Line::new([
  Span::new("error", style=Style::new(foreground=Red)),
  Span::new(": failed"),
])
let surface = Surface::new(
  width=80,
  rows=[line],
  cursor=Cursor::new(row=0, col=5),
)
```

Reading and shaping frames:

```mbt
surface.height()              // row count
surface.line_at(2)            // row 2, or an empty Line when out of range
surface.with_max_rows(10)     // first 10 rows as a new Surface
line.text()                   // text with styling stripped
```

Internal to `tui/` — only importable within the module.
