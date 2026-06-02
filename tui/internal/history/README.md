# bobzhang/openseek/tui/internal/history

This is the **shell-style command history** behind the input box: press Up to
walk back through what you've submitted, Down to come forward, and your
in-progress draft is preserved at the boundary so you don't lose it. Same
behavior you get in bash or a REPL.

The central type, `History`, stores submitted entry *values* — the text plus the
[`composer`](../composer/) `Mode` it was entered in — and a navigation cursor.
It does not touch the composer or read keys; the caller drives navigation and
loads recalled values back into the editor. The cursor ranges over
`[0, entries.length()]`, where the past-the-end position means "editing the fresh
draft".

## Usage

Push on submit, then walk back and forth, feeding the current draft in so it can
be saved and restored at the boundary:

```mbt
let history = @history.History::new()

// On submit: record it (empty text and adjacent duplicates are skipped).
history.push(@history.Entry::new(model.text(), model.mode()))

// Up / Ctrl-P: recall the previous entry, saving the live draft on the way back.
match history.previous(@history.Entry::new(model.text(), model.mode())) {
  Some(entry) => model.replace(entry.text(), mode=entry.mode())
  None => () // nothing older
}

// Down / Ctrl-N: move forward; past the last entry it returns the saved draft.
match history.next() {
  Some(entry) => model.replace(entry.text(), mode=entry.mode())
  None => () // already on the fresh draft
}
```

On any edit, submit, or cancel, call `reset_navigation()` to return the cursor
to the fresh draft.
