# bobzhang/openseek/tui/internal/viewport

This is where the core layout / rendering logic of the whole Agent TUI lives —
the bottom-anchored input area with a scrolling transcript above it that you've
seen in Codex or Claude Code.

The central type, `Viewport`, is best understood as a **renderer**. You hand it
surfaces (the live input area) and scrollback rows (committed transcript lines);
it draws them to the `@tty.Tty` and keeps all the bookkeeping — where the input
composer is anchored, what's currently on screen, the terminal's size — so each
call knows what to repaint and where.

The defining choice: committed output lives in the terminal's **native
scrollback** (scroll up with the mouse, select, copy — all the usual things),
and only the small live area at the bottom is redrawn in place. That's what
makes the agent feel like a normal terminal program instead of a full-screen app
like vim.

## Usage

A `Viewport` is created already on screen: `enter` queries the cursor, anchors
the live area there, and draws the first frame. From then on you call it as
things change, and `leave` restores the terminal.

```mbt
let viewport = @viewport.Viewport::enter(
  tty,
  size=@viewport.read_terminal_size(tty),
  surface=first_frame,
  timeout_ms=100,
)

// The live area changed (a keystroke, a status update) — repaint it in place,
// keeping the same anchor:
viewport.redraw(tty, next_frame)

// Commit a transcript line: insert it above the live area, scrolling older rows
// into native scrollback.
viewport.insert_before(tty, committed_rows)

// The terminal was resized — rebuild the screen from the full transcript.
viewport.refresh_size(tty)
viewport.replay_scrollback(tty, scrollback=all_rows, surface=current_frame)

viewport.leave(tty) // restore margins/style/autowrap/cursor
```

Call `refresh_size(tty)` before a draw whenever the terminal may have resized;
`cols()` is the current width.

## How it works

`Viewport` is the IO half; the row arithmetic (where to anchor, which rows a
redraw must touch) is pure and lives next door in [`geometry`](../geometry/).

The scrollback trick is a DECSTBM scroll region set *above* the live area: with
that margin in place, a newline scrolls only the region above, pushing the
oldest live row up into native scrollback while the live area stays put. Redraws
diff against the previous frame and repaint only the rows that changed. Autowrap
is disabled while full-width rows are drawn (so they don't wrap and shove the
layout down) and restored on `leave`.

Internal to `tui/` — only importable within the module.
