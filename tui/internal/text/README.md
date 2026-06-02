# bobzhang/openseek/tui/internal/text

This is the **terminal-aware string toolbox** the rest of the TUI shares. A
terminal measures text in display cells, not code points — a CJK character is
two cells wide, an emoji is one grapheme made of several code points — and
getting layout right means measuring and slicing the way the terminal sees it.
These are the small pure functions that do that, with no state and no IO.

## Usage

```mbt
@text.display_width("日本語")          // 6 — East-Asian wide chars count as 2
@text.truncate_line("hello world", 8)  // "hello w…" — fits to 8 cells, adds ellipsis
@text.grapheme_count("a👨‍👩‍👧b")          // 3 — counts clusters, not code points
@text.grapheme_slice("héllo", 1, 4)    // "éll" — [start, end) by grapheme, clamped

let lines = @text.split_lines("a\nb\nc") // ["a", "b", "c"], always non-empty
@text.line_at(lines, 9)                // "" — out-of-range is empty, never aborts
```

Bounds are clamped rather than aborting, so callers can pass loose indices.
Internal to `tui/` — only importable within the module.
