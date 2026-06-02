# bobzhang/openseek/tui

This is the terminal controller for an Agent TUI — the top-level package you
reach for to build something like the Codex or Claude Code interface: a
scrolling transcript with a live input box pinned to the bottom.

The central type, `Ui`, is best understood as the **controller** between the
terminal and your agent loop. It owns the terminal session and does all the
drawing; your job is the reverse of an event loop — you `read_event()` to get
what the user did, and call `set_*` / `append_*` to push new output back onto
the screen. Everything below this package (rendering, editing, scrollback) is an
implementation detail `Ui` drives for you.

## Usage

`with_ui` opens the terminal, draws the first frame, and hands you a live `Ui`
for the duration of your loop — restoring the terminal afterwards on both the
success and error paths.

```mbt
@tui.with_ui(ui => {
  for ;; {
    match ui.read_event() {
      @tui.Steer(input) => {
        // The user submitted — echo it into the permanent transcript, then
        // pretend to do some work.
        ui.append_item(Input(input))
        ui.set_activity(Some(@doc.Text::plain("thinking…")))
        ui.append_item(Response("you said: " + input.text()))
        ui.set_activity(None)
      }
      @tui.Queue(input) =>
        // Tab queues a follow-up instead of submitting now.
        ui.set_queued_inputs([input])
      @tui.Interrupt => ui.set_status(@doc.Text::plain("interrupted"))
      @tui.Quit => break
    }
  }
})
```

`Input` is `Prompt(text)` or `Command(text)` (shell mode, entered with a leading
`!`). `input.text()` is the body; `input.prefix()` is `""` or `! `.

What you can push onto the screen:

- `ui.append_item(TranscriptItem)` — add a permanent line to the scrollback
  transcript above the live area.
- `ui.set_activity(@doc.Text?)` — a transient busy line above the composer
  (`None` clears it); never enters the transcript.
- `ui.set_queued_inputs(Array[Input])` — render the pending input queue.
- `ui.set_status(@doc.Text)` — the persistent status line below the composer.

Tune the session with `with_ui(config=Config::new(esc_timeout_ms=…,
composer_max_rows=…), …)`.

## Key bindings

- `Enter` submits as `Steer`; `Tab` submits as `Queue`.
- A leading `!` on an empty line switches to shell mode (`Command`); the marker
  stays out of the editable text.
- `Shift-Enter` / `Ctrl-J` insert a hard newline; the composer grows up to
  `composer_max_rows` (default `4`).
- `Up`/`Down` (or `Ctrl-P`/`Ctrl-N`) move within multiline input, then recall
  history at the top/bottom edge.
- Emacs editing: `Ctrl-A`/`Ctrl-E`, `Ctrl-B`/`Ctrl-F`, `Alt-B`/`Alt-F`,
  `Ctrl-H`, `Ctrl-U`/`Ctrl-K`. `Ctrl-D` deletes forward, or quits when empty.
- `Ctrl-C` / `Esc` return `Interrupt`.

## How it fits together

`Ui` is a thin façade; the work is spread across the packages it drives:
[`core`](core/) is the semantic model it produces and re-exports (`Input`,
`Event`, `TranscriptItem`); [`doc`](doc/) is the styled-text vocabulary;
[`render`](internal/render/) lays the input area out into a surface;
[`internal/viewport`](internal/viewport/) draws that surface to the real
terminal and manages scrollback; [`internal/composer`](internal/composer/) and
[`internal/history`](internal/history/) are the editing core.
