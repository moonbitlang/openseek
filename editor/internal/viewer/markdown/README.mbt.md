# internal/viewer/markdown

Multi-target safe Markdown-to-HTML conversion shared by browser features.

The package owns the cmark boundary. One parse with `layout=true` and
`locs=true` supplies both safe HTML and a `MarkdownDocumentProjection`, so the
rendered document and its source facts cannot describe different parses.
Callers must pass the exact LF-normalized `TextSnapshot::get_value`; this
package does not create a second coordinate space by normalizing input itself.
The current cmark inline cleaner cannot safely consume an isolated low
surrogate, so the parser boundary replaces each isolated surrogate unit with
one U+FFFD while preserving valid pairs and total UTF-16 length. Locations
still index the original snapshot exactly, and HTML/projection use that same
sanitized parse.

`MarkdownCodeBlock`, `MarkdownCodeLine`, and `MarkdownBlockAnchor` are
cmark-independent MoonBit values. Their ranges and boundary offsets are
zero-based, half-open UTF-16 coordinates over that exact input. Each code line
maps every displayed boundary back to the source. Leading spaces synthesized
by cmark for partially consumed indentation are retained for static rendering
but have `None` boundary entries. An unrepresentable displayed/source
relationship likewise remains visible with an entirely non-semantic map
instead of guessing a provider position.

Top-level blocks that the current safe renderer produces as one root HTML
element receive an explicit `rendered_element_index`. Nested anchors and
source blocks that produce comments, text, or no in-place element receive
`None`; blank lines, link definitions, and omitted raw HTML therefore never
shift a root-element ordinal. Code-block identity and per-line projection are
independent of that DOM association. For a code block, the ordinal is valid
for the default renderer and the current one-root code-override contract; the
package-owned Diago, tokenized-code, and Mermaid paths all satisfy that
contract. A caller that returns zero or multiple root elements must not use the
ordinal for DOM association.

`MarkdownResourceKind` keeps outer resource policy typed. A block opts into
MoonBit Markdown semantics only for a `MoonBitMarkdown` resource and a full
info string whose first two nonempty ASCII-space-separated tokens are exactly
`mbt check` or `moonbit check`. Repeated spaces and trailing tokens are
accepted; case changes and tabs are not.

Every conversion uses the safe HTML renderer. A conversion error falls back to
one escaped plaintext paragraph, reports no code block, and returns an empty
projection. `MarkdownRenderFact` otherwise reports whether rendering visited a
code block independently of whether a caller overrode its HTML.

Direct and linked image-only paragraphs receive
`data-markdown-image-only="true"` while their cmark inline structure is still
explicit. Adjacent prose prevents the marker. Browser layout can therefore
select figure-width paragraphs without reconstructing Markdown semantics from
rendered DOM text nodes.

## Rendering

Every conversion uses the safe HTML renderer, and one parse supplies both the
HTML and the projection, so the rendered document and its source facts cannot
describe different parses.

```mbt check
///|
test "one parse yields safe HTML and a code-block fact" {
  let prose = @markdown.render_markdown("# Title\n\nSome *prose*.\n")
  let with_code = @markdown.render_markdown(
    "Intro\n\n```mbt check\ntest { }\n```\n",
  )
  debug_inspect(
    (prose.has_code_block, prose.html, with_code.has_code_block),
    content=(
      #|(false, "<h1>Title</h1>\n<p>Some <em>prose</em>.</p>\n", true)
    ),
  )
}
```

Raw HTML in the source is not passed through — the renderer is the safe one, so
a Markdown comment cannot inject markup into the editor.

```mbt check
///|
test "raw HTML is not passed through the safe renderer" {
  let rendered = @markdown.render_markdown(
    "before\n\n<script>alert(1)</script>\n\nafter\n",
  )
  debug_inspect(
    rendered.html.contains("<script>"),
    content=(
      #|false
    ),
  )
}
```

## Code blocks and the `mbt check` fence

`MarkdownResourceKind` keeps outer resource policy typed. A block opts into
MoonBit Markdown semantics only for a `MoonBitMarkdown` resource and a full
info string whose first two nonempty ASCII-space-separated tokens are exactly
`mbt check` or `moonbit check`. Repeated spaces and trailing tokens are
accepted; case changes and tabs are not.

This is the rule that decides whether a fence in a `.mbt.md` file gets semantic
source boundaries — and therefore whether hovering inside it reaches the real
compiler.

```mbt check
///|
fn fence_is_semantic(
  info : String,
  kind : @markdown.MarkdownResourceKind,
) -> Bool {
  let rendered = @markdown.render_markdown("```" + info + "\nlet x = 1\n```\n")
  match rendered.projection.code_blocks {
    [block, ..] => block.is_moonbit_check_fence(kind)
    _ => false
  }
}

///|
test "only an exact mbt check fence in a MoonBit Markdown resource is semantic" {
  debug_inspect(
    (
      fence_is_semantic("mbt check", MoonBitMarkdown),
      fence_is_semantic("moonbit check", MoonBitMarkdown),
      // repeated spaces and trailing tokens are accepted
      fence_is_semantic("mbt   check  extra", MoonBitMarkdown),
      // case changes are not
      fence_is_semantic("MBT check", MoonBitMarkdown),
      // neither is a plain fence
      fence_is_semantic("mbt", MoonBitMarkdown),
      // and the resource kind still gates it
      fence_is_semantic("mbt check", OrdinaryMarkdown),
    ),
    content=(
      #|(true, true, true, false, false, false)
    ),
  )
}
```

A code block retains its source range and per-line boundaries, which is what
lets a DOM caret inside the rendered fence map back to an offset in the original
document. The package-internal example also inspects parser-only fields that are
not exported.

```mbt nocheck
///|
test "a code block keeps its source range and per-line projection" {
  let rendered = @markdown.render_markdown(
    "intro\n\n```mbt check\nlet x = 1\n```\n",
  )
  match rendered.projection.code_blocks {
    [block, ..] =>
      debug_inspect(
        (
          block.language_id,
          block.full_info_string,
          block.code,
          block.block_source_range,
          block.code_lines.length(),
        ),
        content=(
          #|(
          #|  Some("mbt"),
          #|  Some("mbt check"),
          #|  "let x = 1\n",
          #|  { start: 7, end_exclusive: 33 },
          #|  1,
          #|)
        ),
      )
    _ => fail("expected one code block")
  }
}
```

Failure is contained: a conversion error falls back to one escaped plaintext
paragraph, reports no code block, and returns an empty projection.


The exact lowercase `d2`/`diago` and `uml`/`plantuml` fences are built-in
synchronous aliases for the Diago and UML adapters respectively. They compile
source directly to wrapped SVG before a caller-supplied code-block renderer
runs. UML output uses host CSS variables for its foreground and neutral
surfaces, so the retained SVG follows theme changes without rerendering. Parse
or render failures fall through to that caller override, or to cmark's ordinary
`<pre><code>` output when no override exists. Unknown, differently cased,
unlabelled, and indented code blocks are never diagrams.

```d2
direction: right

fence: fenced code block
lang: supported diagram fence?
compile: Diago or UML compile
svg: wrapped inline SVG
override: caller override?
tokens: tokenized editor HTML
cmark: cmark pre code fallback

fence -> lang
lang -> compile: yes
lang -> override: no
compile -> svg: success
compile -> override: failure
override -> tokens: yes
override -> cmark: no
```

`render_tokenized_code_block` is the shared editor override: it selects a fenced
or active model language, threads tokenizer state across lines, and emits the
existing `monaco-tokenized-source`/`mtk*` classes. Hover and whole-line Markdown
comments both use that owner.

## Sections

`markdown_sections` derives the heading tree from an already-parsed projection.
A heading at level `L` owns every following anchor until the next anchor at
level `L` or shallower; a deeper heading is part of that body *and* opens its
own nested section. Sections are emitted in document order, outermost first.

The heading level is retained during the same parse that produced the HTML and
the source projection (`MarkdownBlockAnchor::heading_level`), so section
structure can never describe a different parse than the document.

```mbt nocheck
///|
test "a deeper heading nests, a same-level heading ends the section" {
  let projection = @markdown.render_markdown(
      (
        #|# Outer
        #|
        #|outer body
        #|
        #|## Inner
        #|
        #|inner body
        #|
        #|# Next
        #|
      ),
    ).projection
  debug_inspect(
    @markdown.markdown_sections(projection).map(section => {
      (
        section.level,
        section.body_anchor_indexes.length(),
        section.is_foldable(projection),
      )
    }),
    content=(
      #|[(1, 3, true), (2, 1, true), (1, 0, false)]
    ),
  )
}
```

A heading with no body carries no fold control, mirroring how separator-only or
one-line API blocks stay expanded without a toggle.

```mbt check
///|
test "an empty section is not foldable" {
  let projection = @markdown.render_markdown(
      (
        #|# Empty
        #|# Has a body
        #|
        #|text
        #|
      ),
    ).projection
  debug_inspect(
    @markdown.markdown_sections(projection).map(section => {
      section.is_foldable(projection)
    }),
    content=(
      #|[false, true]
    ),
  )
}
```

`body_rendered_element_indexes` is the run of root-element ordinals a collapse
would hide. It excludes the heading's own element — the heading stays visible as
the affordance — and skips anchors that produced no in-place root element, so
hiding the run never shifts an unrelated element's ordinal.

```mbt check
///|
test "the hidden run is the body's ordinals, never the heading's" {
  let projection = @markdown.render_markdown(
      (
        #|# Title
        #|
        #|first
        #|
        #|second
        #|
      ),
    ).projection
  guard @markdown.markdown_sections(projection) is [section, ..] else {
    fail("expected one section")
  }
  debug_inspect(
    (
      projection.block_anchors[section.heading_anchor_index].rendered_element_index,
      section.body_rendered_element_indexes(projection),
    ),
    content=(
      #|(Some(0), [1, 2])
    ),
  )
}
```

### Reconciliation keys

A source or theme replacement rebuilds the article wholesale, so element
identity cannot carry fold state across it, and anchor indexes shift whenever
anything earlier in the document is edited. `markdown_section_keys` derives a
key per section from the heading's level, its normalized text, and its ordinal
among identical headings.

```mbt check
///|
test "repeated headings differ only by occurrence" {
  let source =
    #|## Example
    #|
    #|first
    #|
    #|## Example
    #|
    #|second
    #|
  let projection = @markdown.render_markdown(source).projection
  debug_inspect(
    @markdown.markdown_section_keys(
      @markdown.markdown_sections(projection),
      projection,
      source,
    ).map(key => key.replace_all(old="\u{1f}", new="|")),
    content=(
      #|["2|Example|0", "2|Example|1"]
    ),
  )
}
```

The normalization is what makes a key survive an edit: ATX markers and a
closing `##` sequence are stripped, interior whitespace collapses, and a setext
heading keys identically to its ATX equivalent — so re-spelling a heading's
markup does not silently drop its fold state.

### Table of contents

`markdown_table_of_contents` derives an outline from the same section tree, so a
TOC row and a fold control can never disagree about what a section is.

`depth` is *structural* nesting, normalized so the first heading is depth 1 and a
deeper heading sits exactly one level below its parent. A document whose top
heading is `###`, or which jumps `#` straight to `###`, therefore indents
sensibly instead of leaving a gap.

```mbt nocheck
///|
test "the outline indents by structural depth, not literal level" {
  let projection = @markdown.render_markdown(
      (
        #|# Top
        #|
        #|body
        #|
        #|### Jumped straight to three
        #|
        #|body
        #|
        #|## Back to two
        #|
        #|body
        #|
      ),
    ).projection
  debug_inspect(
    @markdown.markdown_table_of_contents(projection).map(entry => {
      (entry.depth, entry.level, entry.text)
    }),
    content=(
      #|[
      #|  (1, 1, "Top"),
      #|  (2, 3, "Jumped straight to three"),
      #|  (2, 2, "Back to two"),
      #|]
    ),
  )
}
```

Each row publicly exposes `source_offset` — the heading's start, which is what
`MarkdownDocumentView::reveal_source_offset` takes. Internally it also retains
`section_index` into `markdown_sections` and the same `is_foldable` answer the
fold control uses. Headings inside a blockquote or list item are content, not
outline structure, so they do not appear.

```mbt nocheck
///|
test "outline rows are revealable and exclude container headings" {
  let projection = @markdown.render_markdown(
      (
        #|# A `code` and *emphasis* heading
        #|
        #|> # quoted, not outline structure
        #|> text
        #|
      ),
    ).projection
  debug_inspect(
    @markdown.markdown_table_of_contents(projection).map(entry => {
      (entry.text, entry.source_offset, entry.is_foldable)
    }),
    content=(
      #|[("A code and emphasis heading", 0, true)]
    ),
  )
}
```

Consumers must collapse by hiding those retained elements with `display:none`.
Re-rendering, or hiding with `visibility:hidden` or a zero height, would break
the `.mbt.md` semantic-fence contract: the hover bridge resolves a caret through
retained per-line boundary maps and a DOM descendant check, so hidden-but-
hit-testable content would produce hovers on text the reader cannot see. The
browser ownership and accessibility contract lives in
`internal/viewer/browser/markdown_document/README.mbt.md`; root state and
reconciliation are exercised through the real-browser Markdown-folding
component contract, while section discovery and auto-fold policy remain in
this package's headless tests.

Browser DOM policy, URI rewriting, listeners, target reuse, and disposal live
in `internal/viewer/browser/markdown`.

Run the focused suite on both supported targets:

```sh
moon test --target js internal/viewer/markdown
moon test --target native internal/viewer/markdown
```
