# Sidebar WebView Menu Design

Status: confirmed implementation contract
Date: 2026-09-02
Scope: sidebar project/session action menus and session selection feedback

This document records the complete behavior contract confirmed with the user.
It contains no remaining design questions.

## Hard boundary

- Use WebView UI only.
- Do not use Desktop native menus or Proton system-menu components.
- Project and session menus share one implementation and one interaction model.
- The visual baseline is the previous WebView workspace menu, not a macOS
  system-menu imitation.

## Menu state ownership

- The shared WebView menu module owns exactly one transient menu state and
  renders exactly one overlay for the Sidebar.
- The menu state belongs to that UI module, not the Sidebar component or the
  application root `Model`.
- Project/session rows do not own menu state and do not register their own
  document-level dismissal listeners.
- A row sends an open request containing only a stable target and an anchor.
- The Sidebar supplies a target resolver and current menu definitions; it does
  not receive or forward menu state.
- The menu module resolves the target against current Sidebar input before
  rendering or executing actions. A stale or missing target is never
  actionable.
- Menu entries, labels, and enabled state are derived from the latest Sidebar
  input on every render. The open state does not retain stale command closures
  or an enabled-state snapshot.
- If an item becomes disabled while focused, focus moves to the next enabled
  item, or the previous enabled item when there is no next item.
- If no enabled items remain, the menu closes.

## Entry points and visible row controls

- Ellipsis and row context-click are two entry points into the same menu
  definition. They must expose the same items, ordering, enabled state, and
  actions.
- Menu availability is not inferred from ellipsis visibility.
- A row that has contextual actions may support a context menu without showing
  an ellipsis.
- Workspace rows keep their existing ellipsis.
- Live session/task rows keep the existing direct Archive button and do not
  gain an ellipsis.
- Archived session/task rows keep the existing direct Restore/Delete buttons
  and do not gain an ellipsis.
- Any row that already has an ellipsis must also provide an equivalent context
  menu.
- A left click on a direct Archive/Restore/Delete button executes that direct
  action.
- A right click on a direct Archive/Restore/Delete button does not execute the
  button; it opens the owning row's complete action menu.
- Subagent/sub-run rows do not provide a menu.
- Non-durable `New chat` drafts, placeholders, and empty-state rows do not
  provide a menu.
- Codex tasks follow the same menu rules as OpenSeek sessions.

## Pointer interaction

- A left click outside the menu closes it and still performs the clicked
  element's normal action. The menu must not swallow the click.
- A right click on a supported row only opens/replaces its menu; it does not
  execute that row's left-click navigation, selection, expansion, or collapse
  behavior.
- Pointer behavior follows actual DOM hit testing after the overlay appears;
  the implementation must not reinterpret every secondary click as another
  row-level open request.
- A second right click at the same screen location normally hits the menu now
  covering that location. If it hits an enabled item, it executes that item in
  exactly the same way as a left click.
- A right click at another location that actually hits a supported row replaces
  the currently open menu and uses the new pointer position. The row may be the
  previous target or another target; what matters is the element actually hit.
- A right click on an enabled menu item behaves exactly like a left click on
  that item: close the menu and execute the item.
- A left or right click on a disabled item does nothing and leaves the menu
  open.
- Executing any enabled item closes the overlay before starting the action.
  The menu does not reopen if the action later fails or opens another surface.
- If the target row disappears while its menu is open, the menu closes
  immediately.
- Clicking the currently owning ellipsis again toggles its menu closed.
- Clicking another ellipsis replaces the current menu and anchors it to the new
  button.

## Keyboard and focus interaction

- Use complete standard keyboard-menu behavior rather than the old WebView
  menu's browser-default button behavior.
- Opening focuses the menu surface without highlighting an item; the first
  arrow-key press moves focus to the first or last enabled item.
- `ArrowUp` and `ArrowDown` cycle through enabled items.
- `Home` and `End` focus the first and last enabled items.
- `Enter` and `Space` execute the focused item.
- `Tab` and `Shift+Tab` close the menu and continue normal browser focus
  traversal; focus is not trapped.
- Disabled items are neither focusable nor executable.
- `Escape` closes the menu and restores the element that had focus before the
  menu opened.
- Closing through an outside click does not restore old focus; the clicked
  element follows normal browser focus behavior.
- After executing an item, the action owns subsequent focus. For example,
  Rename focuses its input.

## Dismissal and positioning

- Window/WebView blur closes the menu. Refocusing does not restore it.
- Sidebar scrolling, window resize, or viewport/zoom changes close the menu
  rather than continuously tracking the old anchor.
- A context menu uses the pointer position as its anchor.
- An ellipsis menu uses the button's lower-right corner and aligns to its right
  edge.
- The menu opens upward when there is insufficient space below.
- Viewport overflow is corrected with the minimum necessary translation.
- The fixed overlay never participates in Sidebar layout.

## Menu contents

### Live OpenSeek session or Codex task

1. `Rename…`
2. Separator
3. `Archive`

- A running session/task can still open its menu.
- `Rename…` remains available while running.
- `Archive` is disabled while running and explains that the run must be
  stopped first.

### Archived OpenSeek session or Codex task

1. `Restore`
2. Separator
3. `Delete…`

- `Delete…` enters the existing confirmation flow; it never deletes directly
  from the menu.

### Workspace

1. `Workspace settings`
2. Separator
3. `Detach project`

- `Detach project` is not treated as destructive because files and sessions
  remain in place.

## Session selection and transcript loading

- The user's selected session and the successfully loaded active session are
  separate concepts.
- A left click immediately moves Sidebar selection/highlight to the target;
  it does not wait for transcript loading.
- `active_session` remains the successfully loaded session so stale async
  replies cannot steal the visible selection.
- A first load shows both:
  - an active highlight and a dedicated loading spinner on the selected row;
  - a dedicated `Loading conversation…` state in the Chat panel.
- The old transcript must not remain visible under a newly selected row.
- If loading ultimately fails, the failed target remains selected. The Chat
  panel shows a clear failure state and a `Retry` action. It does not silently
  jump back to the previous session.
- Rapid A → B → C selection is latest-selection-wins. Older loads may populate
  caches but cannot take back highlight, panel contents, or focus.
- Selecting a session with usable cached transcript shows the cache
  immediately. A background refresh uses only a lightweight row spinner.
- A background refresh failure retains cached content and reports a
  non-blocking warning instead of replacing the panel with a blocking error.
- Right-clicking an unselected row does not select it.
- Menu actions apply to the context target, not the selected session. Rename
  on a background row edits that row without changing the Chat panel.
- Removing a row that is not selected does not change the current selection.
- Restoring a selected archived session/task preserves selection as the row
  moves into the live section.
- Archiving or deleting the selected session/task selects the newest available
  live item in the same workspace. If none exists, the workspace enters
  `New chat`.
- Detaching the selected workspace selects the next available workspace and
  its most recent session/task; if it has none, it enters `New chat`.
- If no workspace remains, the app enters its existing no-workspace empty
  state.
- Old asynchronous replies can never restore a selection whose target has
  disappeared.

## Rename interaction

- `Rename…` closes the menu and replaces the target row label with an inline
  editor.
- The Sidebar permits only one Rename editor at a time.
- Starting Rename elsewhere, clicking another row, or opening another menu
  cancels the current unsubmitted Rename through the same blur behavior.
- The editor focuses automatically and selects the complete existing title.
- `Enter` submits and `Escape` cancels.
- Blur cancels instead of implicitly saving.
- Two small text buttons are present: `Save` and `Cancel`; they do not use
  icons.
- Blank input disables `Save`.
- During submission, `Save` reads `Saving…`; input and both buttons are
  disabled.
- Success exits editing.
- Failure retains the draft, re-enables editing and buttons, and reports the
  error.
- A right click inside the Rename input never opens the row action menu. It
  preserves the input's normal text-editing context behavior, including copy,
  paste, and select all.

## Visual baseline

- Preserve the previous WebView workspace menu's visual proportions:
  - minimum width `180px`;
  - menu padding `4px`;
  - existing border, medium radius, surface background, and overlay shadow;
  - item padding `5px 8px`;
  - small font, tight line height, and accent hover treatment.
- Workspace and session menus use the same CSS implementation.
- Add only the states required by the expanded behavior: keyboard focus,
  disabled, separator, and destructive feedback.
- Existing icons remain for Workspace settings, Detach, Archive, Restore, and
  Delete.
- Rename uses text with an empty icon-width slot so item labels remain aligned;
  no new Pencil icon is introduced.
- `Delete…` uses ordinary text/muted icon at rest and danger colors only on
  hover, keyboard focus, or pressed state.

## Repeated invocation rule

There is no special comparison of row identity or pointer coordinates. The
browser's actual hit target decides the operation:

- the same ellipsis button toggles its menu closed;
- another ellipsis opens/replaces the menu at that button;
- a secondary click hitting an existing menu item executes the item;
- a secondary click hitting a supported row opens/replaces the menu at the new
  pointer position.

This matches Codex's behavior and avoids coordinate-based special cases.
