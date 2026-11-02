# Editor Context Menu Browser Shell

This JS-only package owns the Monaco-shaped HTML shell for one editor context
menu. Root `viewer` passes an already-filtered immutable entry tree and retains
all command, model, selection, presentation, and definition policy.

`ContextMenuWidget` owns its detached body-level DOM, temporary item/document/
window listeners, focus-return element, submenu timers, and exactly-once
disposal. A new show replaces the old menu. Action activation hides and
restores focus before invoking the opaque command-id callback. Escape, Tab,
outside primary mousedown, focus leaving the menu, and window blur cancel it.
An unhandled `contextmenu` outside the shell also retires the stale custom menu
before the browser-native surface opens.

The root menu and an optional selected submenu are fixed-position overlays.
They prefer right/down placement, flip at visual-viewport edges, and clamp when
the menu is larger than the viewport. The current definition menu uses only
top-level actions; if another caller supplies a submenu, deeper menu data is
intentionally not rendered as another flyout.

The detached menu copies `--ui-font-family` and `--ui-font-size` together
with its host's palette. Text, action-row height and internal spacing follow
that UI size (13px standalone default); menu placement uses the resulting
measured bounds.

Rows expose `menu`/`menuitem`, `aria-haspopup`, and `aria-expanded` semantics.
Up/Down/Home/End/PageUp/PageDown move among non-separator rows, Enter/Space
activate, Right opens a submenu, and Left returns to its parent. Pointer hover
uses Monaco's 250 ms submenu-open and 750 ms submenu-close delays.

The emitted stylesheet lives at
`viewer/contrib/contextmenu/browser/contextmenu.css`. Exact callable types are
in `pkg.generated.mbti`. Run focused tests with:

```sh
moon test internal/viewer/contrib/contextmenu/browser --target js
```
