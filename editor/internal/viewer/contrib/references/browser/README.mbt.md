# References Browser Contribution

This JS-only package owns the detached Peek Definition/References shell and its
feature-local accessible result tree. The root Viewer owns presentation mounts,
model-resolution leases, nested preview Viewers, decorations, opening policy,
request generations, and stale-result checks. This package never resolves a
model, retains a `TextModelReference`, or imports the root Viewer.

`ReferencesPeekWidget` consumes the immutable normalized values from the
DOM-free sibling package. Its typed callbacks carry `ReferenceItem` and
`ReferenceGroup` identities; callers never recover model identity from DOM
attributes. The root captures the owning session generation around every
callback before allowing it to mutate controller state.

One-resource models render reference rows directly. Multi-resource models
render file rows and level-two reference rows, initially expanding the selected
resource. Expansion requests each group at most once so the root can lazily
resolve source snippets. `set_group_previews` replaces only that group's
reference DOM while preserving expansion, selection, and the current focus
domain.

Rows start with the stable location fallback. Successful root-supplied
`ReferenceRowPreview` values replace one group's rows with before/match/after
spans; resolution failure never makes a row unselectable. The widget's preview
host is intentionally empty: the root mounts and disposes the nested readonly
Viewer there.

The result surface is a native ARIA tree with one roving `tabindex="0"` among
visible rows. Arrow, Home, End, Left, and Right keys move or expand the tree;
Enter confirms the current reference and Ctrl+Enter or Meta+Enter requests a
side open. Escape and F4/Shift+F4 remain available from both the tree and a
nested preview, while Enter inside the preview keeps its native editor meaning.
The tree is the native content of the shared Viewer `ScrollableElementDom`, so
Definition and References modes use the same overlay rails, thumb/track input,
visibility lifecycle, and resize synchronization as other Viewer surfaces;
the ARIA tree remains the focus and keyboard owner.

The mode changes only labels and accessible messages: `Peek Definition` /
`Definitions` or `Peek References` / `References`. Empty References results use
the retained `No references found` status. The shell requests 18 lines and
retains the existing root cap of 18, 80%-of-viewport reduction, and 12-line
floor with a fixed preview-left/results-right split. Sash resizing, persisted
split ratios, virtualization, filtering, multi-selection, drag-and-drop, and a
general-purpose Tree/List abstraction are excluded.

The package uses direct Rabbita DOM primitives and imports neither the shell nor
Rabbita's TEA framework. Product behavior is a focused port of the pinned VS
Code References Peek tree/controller clusters recorded durably in
`docs/references/monaco.md`.

Exact callable types are in `pkg.generated.mbti`. Focused coverage is:

```sh
moon test internal/viewer/contrib/references/browser --target js
```

Hosts may supply `ViewerServices(resource_path_label=...)` to display a
workspace-relative resource path in Peek file rows, tooltips, and accessible
summaries. Returning `None` preserves the default label for resources outside
the workspace. Both Code and Markdown Peek use this callback; resource URIs,
group identity, resolution, and opening requests retain their original values.
