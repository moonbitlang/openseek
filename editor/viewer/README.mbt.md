# viewer

The js-only public façade for three readonly surfaces:

- `Viewer` is a standalone code editor;
- `MarkdownViewer` is a rich Markdown document viewer; and
- `DiffEditor` is a first-class two-model diff editor.

`pkg.generated.mbti` is the authoritative API. This page records ownership and
dependency rules that are intentionally not encoded in public signatures.

## Diagram embedding

Consumers with their own Markdown parser can use `render_diago_diagram_svg`
for D2/Diago and `render_uml_diagram_svg` for UML/PlantUML. Both return `None`
for invalid input so the consumer can retain the source as code.
`MermaidDiagram` owns a single diagram inside a caller-owned, childless DOM
container. It uses the same local Mermaid assets, strict rendering policy,
escaped source fallback, and stale-result protection as `MarkdownViewer`.
Call `set_dark_mode` when the application appearance changes, and `dispose`
before replacing its source or removing its container. Its size callback lets
the consumer refresh `DiagramViewports` and recompute surrounding layout.

Desktop transcripts use these entries for exact lowercase `mermaid`, `d2`,
`diago`, `uml`, and `plantuml` fences; ordinary prose and code remain under the
transcript's existing Markdown renderer.

## Explicit presentation selection

Presentation policy belongs to the host. `Viewer` never inspects a URI suffix
or language id and never creates a Markdown renderer.

```mbt nocheck
let code = @viewer.Viewer::create(code_host, services=services)
code.set_model(Some(code_model))

let markdown = @viewer.MarkdownViewer::create(markdown_host, services=services)
markdown.set_model(Some(@viewer.MarkdownViewerModel(
  markdown_model,
  @viewer.OrdinaryMarkdown,
)))

let moonbit_markdown = @viewer.MarkdownViewerModel(
  mbt_markdown_model,
  @viewer.MoonBitMarkdown,
)
```

Hosts normally select `MarkdownViewer` for a decoded lowercase `.md` path or
the exact `markdown` language id. `.mbt.md` uses `MoonBitMarkdown`; other
Markdown resources use `OrdinaryMarkdown`. A diff always displays source code,
including for Markdown paths.

This split is deliberately breaking. `Viewer` is code-only; rich Markdown
selection is an explicit host responsibility, with no hybrid compatibility
path inside the code editor.

## Runtime ownership

```text
public Viewer
└── internal CodeEditorWidget
    ├── EditorConfigurationState
    ├── one model slot
    │   ├── TextModel                borrowed
    │   ├── ViewModel
    │   ├── View
    │   └── MouseHandler
    └── code contributions

public MarkdownViewer
└── internal MarkdownViewerWidget
    ├── TextModel                    borrowed
    ├── MarkdownDocumentView
    └── Markdown hover/definition/folding lifetimes

public DiffEditor
└── internal DiffEditorWidget
    ├── DiffEditorViewModel          exactly one
    └── DiffEditorEditors
        ├── CodeEditorWidget         original
        └── CodeEditorWidget         modified
```

`DiffEditorWidget` does not create, contain, or call the public `Viewer`. It
depends directly on `internal/viewer/code_editor_widget` and coordinates the
two kernels with one diff generation, one layout transaction, and one feature
lifecycle. The code widget does not import the public `viewer` package,
`diff_editor`, or Markdown document packages.

The public `Viewer` is a real opaque wrapper rather than a type alias. This is
required by the internal package boundary and prevents the kernel type from
leaking into external interfaces. One wrapper owns exactly one kernel.

## Models and services

Hosts own every `TextModel`, DOM host, and explicitly supplied
`ViewerServices` value.

- `Viewer::set_model` borrows one model; replacing or clearing it never
  disposes the model.
- `MarkdownViewer::set_model` returns the fully detached previous
  `MarkdownViewerModel?`, so a host may dispose it immediately when it owns the
  model.
- `DiffEditor::set_model` installs the original/modified pair atomically and
  returns the fully detached previous pair. No observer can see a new/old pane
  mixture.
- Omitting services creates a surface-owned default bundle. Passing services
  borrows the caller's bundle, allowing code, Markdown, and diff surfaces to
  share languages, diagnostics, navigation, feedback, and quick-diff state.
- `dispose` is idempotent and removes only surface-owned listeners, scheduled
  work, observers, feature state, and DOM. It never removes the caller's host
  or disposes caller-owned models or services.

## Diff editor contract

`DiffEditor` accepts a synchronous `DocumentDiffProvider`. The default line-diff
provider lives in `viewer/common/diff`. A diff result has
two distinct inputs:

- `changes` drive decorations, overview markers, and change navigation; and
- `additional_alignments` affect geometry only.

The shared `DiffEditorViewModel` publishes `NoModel`, `Pending`, `Ready`, or
`Failed`. Model, provider, and option changes rotate a generation. Computation
reads immutable snapshots and commits only when model identity, version,
provider/options generation, and disposal state still match. A raised provider
or invalid mapping clears stale artifacts and enters `Failed`.

Before rendering, the ViewModel applies VS Code's inner-range normalization and
constructs the same `DiffState`/`DiffMapping` boundary used by VS Code. Each
feature reads those mappings directly:

```text
DocumentDiff
  -> normalizeDocumentDiff
  -> DiffState / DiffMapping
       -> Decorations
       -> alignment / Inline ViewZones
       -> original + modified Overview rulers
       -> navigation
```

`additional_alignments` is the only renderer-state extension. It is injected
only into alignment computation and cannot create decorations, overview
markers, Inline deleted blocks, or navigation targets.

The kernel exposes stable geometry, managed-zone, viewport-state, render, and
scroll adapters for this work. Diff features do not access raw `View`,
`MouseHandler`, mutable configuration, or the kernel's private model slot.

The public terminology is `SideBySide` and `Inline`. The implementation keeps
no legacy single-column renderer, tail-height compensation, diff-owned
correction scheduler, or compatibility alias.

## Public surfaces

`Viewer` retains the readonly code API: model/options lifecycle, cursor and
selection queries, scrolling and reveal operations, geometry, model
decorations, managed ViewZones and overlay widgets, Definition/References,
folding, and model/cursor/scroll/mouse/disposal events. Markdown section APIs
are not present on `Viewer`.

`MarkdownViewer` owns Markdown-specific model/options/view-state, section
folding, source reveal, content-size/scroll/model events, and rich document
features. Its `MarkdownResourceKind` is explicit and is never inferred inside
the widget.

`DiffEditor` owns the model pair, provider/options, layout, focus, current diff
state, update event, paired content-height event, and next/previous change
navigation. The height event is published only after both panes' alignment
zones commit, so a stacked host never consumes a one-pane intermediate height.
It is readonly; moves, hide-unchanged, revert, editing, and the full accessible
diff viewer are outside the current scope.

## Package and architecture boundaries

Dependencies point downward:

```text
viewer/common/diff
        ↑
internal/code_editor_widget <- internal/diff_editor
        ↑                           ↑
public viewer façade ---------------┘
```

These boundaries remain visible in `moon.pkg`, generated interfaces, and code
review:

- `diff_editor` depends on `code_editor_widget` and never on public `Viewer`;
- `code_editor_widget` never depends on public `viewer` or `diff_editor`;
- the code kernel contains no hybrid Markdown presentation policy;
- the code kernel does not export raw configuration, `ViewModel`, `View`, or
  `MouseHandler` accessors;
- diff code contains no raw editor internals, `MutationObserver`, tail balance,
  or correction scheduler; and
- the public `Viewer` is an opaque one-kernel façade.

Fast validation for this boundary:

```sh
moon -C editor check viewer internal/viewer/code_editor_widget --target js --deny-warn
moon -C editor test internal/viewer/code_editor_widget --target js --deny-warn
```

Run `just check` from the repository root for the integration gate.

Browser behavior is covered by `just editor-test-browser`; the real downstream
acceptance target remains packaged SeekMoon through its Proton/CEF CDP path.
