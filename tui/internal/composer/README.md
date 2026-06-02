# bobzhang/openseek/tui/internal/composer

This is the **text editor** behind the input box — the readline-like editing
core that turns keystrokes into the text the user submits. If you've wired up
emacs-style editing before, the model is familiar: it owns the buffer and a
cursor, soft-wraps each logical line to the current width, and exposes editing
and motion operations (insert, kill-line, word motion, vertical movement across
wrapped rows).

The central type, `Model`, deliberately knows nothing about colors, surfaces, or
the terminal. It only produces plain text plus a cursor offset; the
[`render`](../render/) layer turns that into a styled surface and
[`viewport`](../viewport/) draws it. That split is what keeps editing logic
testable without a terminal in the loop.

## Usage

```mbt
let model = @composer.Model::new(max_text_rows=4)
model.resize(cols=80)         // relay out for the terminal width

model.insert_user_text("!ls") // leading '!' on empty input → Shell mode ("! ")
model.insert(" -la")
model.move_word_left()        // emacs-style motion
model.delete_before()         // backspace

let text = model.text()                // "ls -l"
let is_shell = model.mode().is_shell() // true
```

Reading it back for the renderer:

```mbt
for row in 0..<model.visible_text_rows() {
  let prefix = model.input_prefix(row)   // "> ", "! ", or continuation padding
  let line = model.visible_line(row)     // wrapped row text
}
model.cursor_row()    // cursor's visible row
model.cursor_offset() // cursor's display-cell column
```

## History handoff

`move_vertical(delta)` moves between *wrapped* rows. When the cursor is already
at the top/bottom edge, `cursor_at_first_visual_row()` /
`cursor_at_last_visual_row()` tell the caller to recall from
[`history`](../history/) instead. Load a recalled entry with
`replace(text, mode~)`; clear with `reset()`.
