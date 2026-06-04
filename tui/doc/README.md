# bobzhang/openseek/tui/doc

This is the **styled-text vocabulary** of the TUI — the layer where you describe
what content should look like before anything is drawn. If you've used a rich
console library, the shape is familiar: a `Span` is a run of text with a style, a
`Text` is one logical line of spans, and a `Doc` is a block of lines. The one
thing they all know how to do is **lay themselves out to a width**, producing the
[`surface`](../internal/surface/) `Line`s the renderer consumes.

It also owns the `ToDoc` trait — the single seam through which a semantic value
(an `@core.Input`, a tool call) turns into a renderable `Doc`. So `doc` answers
"how does this look", while [`core`](../core/) supplies "what does this mean".

## Usage

Build a styled block and lay it out:

```mbt
let doc = Doc::Doc([
  Text::Text([
    Span(@displaytext.DisplayText("error: "), style=Style::error()),
    Span::plain("oops"),
  ]),
  Text::plain("see the log for details"),
])
let lines = doc.layout(width=40) // wraps and tab-expands to 40 cols
```

Shortcuts for the common cases:

```mbt
Doc::Doc([Text::plain("a\nb")]) // a Doc of one block, wrapped on '\n' at layout
Text::plain("one line")         // single Text
dim_text("muted")               // a dim single-line Text
Style::dim() / Style::prompt() / Style::error() / Style::default()
```

`Doc::layout(width~)` lays a whole block out into rows; `Text::first_line(width~)`
gives just the first wrapped row; `Text::split_lines()` splits on hard newlines;
`Text::prepend_span` glues a prefix (e.g. a prompt marker) onto a line.

## Making your own types renderable

Implement `ToDoc` in the type's home package so the UI can render it:

```mbt
pub impl @doc.ToDoc for MyEvent with to_doc(self) {
  @doc.Doc::Doc([@doc.Text::plain(self.message)])
}
```

Cross-package callers invoke it as `@doc.ToDoc::to_doc(value)` — the dot-call
`value.to_doc()` only resolves inside the implementing package. See
[`core`](../core/) for the `Input` / `TranscriptItem` impls.
