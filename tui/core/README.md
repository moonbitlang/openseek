# bobzhang/openseek/tui/core

This package is the **vocabulary** of the Agent TUI — the nouns and verbs of a
conversation, with no rendering or IO attached. When the user submits something
it becomes an `Input`; when the loop needs to know what happened it reads an
`Event`; when a turn is committed to the scrolling history it becomes a
`TranscriptItem`. These are the types [`tui`](../) re-exports, so you usually
reach them as `@tui.Input`, `@tui.Event`, and so on.

Each renderable type knows how to project itself into a [`doc`](../doc/) `Doc`
(via `@doc.ToDoc`), so the UI can draw an item without `core` knowing anything
about styling or terminals — the meaning lives here, the appearance lives in
`doc`.

## Usage

What the user submits, and what the loop receives:

```mbt
// `read_event` hands you one of these:
Event::Steer(Input::Prompt("hello"))     // submit now
Event::Queue(Input::Command("ls -la"))   // queue a shell command
Event::Interrupt                         // Ctrl-C / Esc
Event::Quit                              // Ctrl-D on empty input

let input = Input::Prompt("hello")
input.text()    // "hello"
input.prefix()  // "" for Prompt, "! " for Command
```

What you append to the transcript:

```mbt
TranscriptItem::Input(Input::Prompt("hi"))
TranscriptItem::Response("the answer")
TranscriptItem::Error("chat failed")
TranscriptItem::ToolCall(
  ToolCall::ToolCall(
    @doc.Text::plain("read file"),
    status=ToolStatus::Completed,
    details=[@doc.Text::plain("config.toml")],
  ),
)
```

`Input` and `TranscriptItem` carry `@doc.ToDoc` impls, so the UI renders them
for you (`ui.append_item(...)`). To project one yourself, call
`@doc.ToDoc::to_doc(item)`. Tool styling comes from `ToolStatus` (completed,
failed).
