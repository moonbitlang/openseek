# bobzhang/openseek/tui/internal/terminal_size

This is a one-type, pure value package whose whole job is to make terminal
dimensions **safe to use without checking**. A reported terminal size can be
nonsense (0 rows, a closed pipe), and the layout math downstream divides and
clamps against those numbers. `TerminalSize` is an opaque value that normalizes
any non-positive dimension to a sane default (24×80), so every consumer can
treat `rows()` / `cols()` as always `>= 1`.

It deliberately knows nothing about terminals or IO — reading a live tty into a
`TerminalSize` is `@viewport.read_terminal_size`, which keeps this package a pure
value type with no `@tty` dependency.

## Usage

```mbt
let size = @terminal_size.TerminalSize(rows=24, cols=80)
size.rows() // >= 1
size.cols() // >= 1

@terminal_size.TerminalSize(rows=0, cols=120) // rows=0 → default → 24
@terminal_size.default                        // the 24×80 fallback
```

Internal to `tui/` — only importable within the module.
