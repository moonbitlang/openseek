# bobzhang/openseek/tui/internal/geometry

This is the **pure arithmetic half of [`viewport`](../viewport/)** — all the
"where does the live area go and which rows does a redraw touch" math, with no
terminal and no IO. `viewport` does the actual drawing; it delegates every
placement decision here, so that logic can be unit-tested without a tty.

The central type, `Geometry`, is just a block of terminal rows: a 1-based `top`,
a `height`, and a derived `bottom`. Coordinates are 1-based to match ANSI cursor
addressing. Every function here is total and returns a result already clamped to
the screen, so callers never have to re-validate.

## Usage

```mbt
let area = @geometry.Geometry::new(top=20, height=4)
area.bottom() // 23  (== top + height - 1)
```

Placing an area for a desired height against a terminal size:

```mbt
let height = @geometry.clamp_height(size, height=4)          // into 1 ..= rows
let max_top = @geometry.calculate_max_top(size, height)      // lowest fully-on-screen start
let top = @geometry.clamp_top(size, height~, top=cursor_row) // into 1 ..= max_top
```

Internal to `tui/` — only importable within the module.
