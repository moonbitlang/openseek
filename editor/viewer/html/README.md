# Static source and diff previews

This JS package returns escaped Rabbita HTML using the editor's production
line tokenizers and token colors. It does not mount `Viewer` or `DiffEditor`,
create text models, register providers, or own DOM lifetimes.

`moonbit_source_lines`, `moonbit_source_code`, and `moonbit_numbered_source`
render ordinary MoonBit source. `diff_preview` renders an already recorded
patch; it does not compute a diff or read current files.

## Diff preview

Call `diff_preview(lines, label=..., tokenizer=...)` when a snapshot changes;
reuse the returned `Html` during unrelated host renders. Each `DiffLine`
contains a single physical source line:

- `Context(text, old_line=..., new_line=...)` carries both coordinates.
- `Removed(text, line=...)` carries the original coordinate.
- `Added(text, line=...)` carries the modified coordinate.
- `Gap` visibly separates excerpts and resets both lexical states.

Coordinates are positive, one-based values supplied by the caller. Use `None`
when a coordinate is unknown; no replacement coordinate is fabricated.
Callers preserve row order and bound large snapshots before rendering.
Insert `Gap` where source is omitted or discontinuous. An excerpt starts with
initial lexical state because unseen context is unavailable.

The optional tokenizer accepts the editor's `syntax.LineTokenizer` contract,
including MoonBit (`.mbt`, `.mbtx`, `.mbti`), JavaScript, JSON and Moon config.
File-extension policy belongs to the caller. Without a tokenizer, source is
plain escaped text. Original and modified states advance independently;
context rows display modified-side highlighting. All text, including content
that resembles HTML, goes through Rabbita text nodes.

The required `label` is the accessible name of the focusable scroll region.
Hosts supply a localized label with file and range context to distinguish
multiple previews; the renderer has no language policy or English fallback.

## Styling and composition

Load `viewer/html/diff_preview.css`, the editor token stylesheet
`viewer/browser/view_parts/view_lines/tokens.css`, and supply editor theme
variables (the reference host uses `.editor-shell` from its theme stylesheet).
`--vscode-editor-background` must be opaque. Font family, size and line height
can be supplied through `--editor-font-family`, `--editor-font-size`, and
`--editor-line-height`.

The component owns one native horizontal scroll region. Lines never wrap;
one line-number column and change markers stay pinned together. Removed rows
show original coordinates; added rows show modified coordinates. Context uses
the modified coordinate, falling back to the original if it is unknown. Change colors
are composed over an opaque background so scrolled text cannot bleed through
the gutter. Native text selection excludes gutter text. The region can be
focused for keyboard scrolling. Hosts keep file titles, copy actions and
navigation outside this region; the component has no file-opening policy.

## Preview and validation

From the repository root:

```sh
just editor-build
just --justfile editor/justfile HOST=127.0.0.1 PORT=15188 serve
```

Open `http://127.0.0.1:15188/diff-preview.html`. The reference page includes
light/dark and wide/narrow controls, long lines, six-digit coordinates,
independent multiline syntax state, omitted excerpts, absent coordinates,
empty lines and literal HTML text. It uses in-memory snapshots and needs no
workspace requests.

`tests/browser/smoke/diff_preview.spec.js` verifies actual browser glyph
spacing, pinned gutter geometry, source scrolling, responsive layout and
escaped highlighted content.

OpenSeek's `desktop/frontend/review_changes` uses this function for composer
Changes mentions and their saved-message previews. The adapter maps recorded
original/modified lines and discontinuities to `DiffLine`, chooses the MoonBit
tokenizer for `.mbt`, `.mbti`, and `.mbtx`, and owns the surrounding file
actions. Desktop loads the shared stylesheet through its viewer CSS entrypoint
and supplies its theme and compact typography.

Minimal transcript edit cards also use this renderer. Their adapter derives
rows from edit arguments or recorded unified patches, preserves historical
coordinates through bounded head/tail excerpts, and inserts `Gap` across
omitted content. Transcript blocks retain their rendered HTML until their
projection changes. File titles, full-diff copying and file opening stay
outside the shared preview.
