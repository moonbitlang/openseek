# Desktop design conventions

This document records visual and shared-component constraints that should
remain true as the Desktop UI grows. A new feature should follow these
constraints instead of creating a second implementation with similar behavior.

For product-level interaction principles, see
[`UX_GUIDELINES.md`](UX_GUIDELINES.md). For concrete feedback, motion, timing,
recovery, and accessibility defaults, see
[`UX_GUARDRAILS.md`](UX_GUARDRAILS.md).

## Visual direction

SeekMoon uses a quiet, low-chrome interface. "Low chrome" means that borders,
dividers, and decorative frames recede behind the content. A surface should
usually be recognized from a small tonal difference and, when necessary, a
soft ambient shadow rather than from a visible outline.

This is not neumorphism. Components should remain flat and should not use
gradients, inset highlights, or paired light and dark shadows to simulate
physical thickness.

### Surface hierarchy

Use the smallest visual distinction that still makes the structure clear:

1. The canvas uses `--color-bg-canvas`.
2. A card above the canvas uses `--color-bg-surface` and, when it needs a
   persistent boundary, `--shadow-surface`.
3. A compact control inside a card uses `--color-control-surface`. It normally
   needs neither a visible border nor its own shadow.
4. A temporary overlay uses `--color-bg-surface` and `--shadow-overlay` because
   it must remain distinct while crossing other surfaces.

Semantic surfaces follow the same hierarchy. When a status needs a surface,
mix a semantic soft color with the appropriate neutral surface. A status that
already has clear placement and spacing may remain unboxed instead.

### Boundaries

- Prefer flat tonal separation before adding a border.
- Keep a one-pixel transparent border where focus or another state will later
  recolor that edge. This reserves the geometry and prevents layout movement.
- Use `--shadow-surface` for a persistent card and `--shadow-overlay` for a
  temporary surface. Do not invent a new component-specific shadow when one of
  these roles fits.
- Use a visible border only when the boundary itself carries information or
  when adjacent surfaces cannot otherwise remain distinguishable.
- Keep structural separators quiet. They organize regions but should not make
  every region look like a boxed panel.

Avoid using gradients, inset highlights, or hard drop shadows merely to make a
surface look more "finished." Those effects imply physical thickness and do
not belong to this design language.

### Controls and focus

The idle state should feel calm. Focus is the moment when a field boundary is
allowed to become explicit.

- An idle field wrapper uses a transparent border. The input composer is the
  exception described under its reference surface.
- The element marked with `data-focus-owner` owns the one visible focus edge.
- A nested `data-focus-target` does not draw another outline.
- Hover may strengthen the control fill and text, but should not introduce a
  second border or shadow.
- Keyboard focus must remain unmistakable even though idle boundaries are
  quiet.

The detailed ownership contract lives in `styles/README.md` and the shared
focus rule lives in `styles/base.css`.

### Semantic status

Error, warning, and success states should identify themselves without filling
every surrounding surface with status color.

- Use a compact semantic icon as the strongest color signal where possible.
- A terse, unboxed status may use semantic text color. Longer explanatory prose
  normally stays on a text role such as `--color-text-secondary`; exact
  diagnostics may remain semantic when the whole row represents failure.
- Prefer an unboxed status row when placement, spacing, and semantic color
  already make its role clear.
- When a status needs stronger grouping, use its semantic soft color as a
  restrained surface tint.
- Preserve exact diagnostics and inline code; visual quietness must not reduce
  technical precision.
- A durable transcript status stays in transcript order. Presentation must not
  change whether the status is persisted.

### Reference surfaces

Use these existing components as the visual reference before creating a new
surface treatment.

#### Idle input composer

`.composer-inner` is the reference persistent card:

- `border: 1px solid var(--color-border)`
- `background: var(--color-bg-surface)`
- `box-shadow: var(--shadow-surface)`
- `border-radius: var(--radius-lg)`

The composer is the page's standing input target, so its edge stays visible
while idle; the shared focus-owner rule recolors it on focus. The card holds a
single row: the attachment button, the draft, and the send or stop actions,
which stay on the draft's last line as it grows. The controls that shape the
next turn sit below the card as quiet text in `.composer-toolbar`: approval,
worktree, and git state lead; the model and reasoning trail.

#### Transcript error

`.transcript-error-row` is an unboxed durable status inside transcript order:

- no background, border, or shadow
- danger color on the status icon and exact diagnostic text
- tighter row spacing than surfaced cards and prose blocks
- wrapping preserved for long diagnostics and inline code

It should read as transcript status, not as a separate alert system.

### Visual review requirements

Before accepting a new or changed surface, check all of the following:

- Is the visible border necessary, or can tone and an existing shadow define
  the boundary?
- Does the component stay flat without gradients or inset highlights?
- Is its shadow using the correct shared elevation role?
- Does semantic color identify the state without overwhelming the content?
- Does keyboard focus remain clear and have exactly one owner?
- Does the result remain readable in light and dark themes?
- Do long labels, diagnostics, and URLs wrap without horizontal overflow at a
  390px viewport?

## Select controls

Every user-visible single-choice select menu in the Desktop must use
`openseek_desktop/frontend/select_control`. Call
`@select_control.Control::render` directly, or use a package wrapper that
delegates to that method, such as the composer model and reasoning selectors.

Do not add an `@html.select`, a handwritten `<select>`, or a feature-local
button/listbox implementation. Native selects vary across webviews and cannot
share the Desktop's popup styling and interaction behavior. A second custom
implementation would let keyboard, focus, accessibility, and visual behavior
drift between screens.

If a new select needs behavior or a visual form that `Control` cannot express,
extend `select_control` first. Add the required input or `Presentation` variant,
shared styles, interaction behavior, and tests there, then use it from the
feature. Do not bypass the shared control to meet a local deadline.

### Component and state boundary

`Control` is a shared view component. Its public rendering boundary is:

```moonbit
pub fn Control::render(Self) -> @html.Html
```

It deliberately does not return `@rabbita.Val[@html.Html]`. A Rabbita component
with that return type owns or derives an independently updating subtree. A
select's selected value and open state are application state, so they belong to
the caller's model: either the root model or a containing stateful component.
The caller's `Val` causes its view to run again, and that view renders the
shared `Control` with the new values.

The caller owns:

- the options and stable wire values;
- the selected value, disabled state, and whether this menu is open;
- a stable, unique DOM `id`;
- update messages for toggle, dismiss, and value changes; and
- closing or replacing the open menu during application-level transitions.

`select_control` owns:

- the trigger, popup, groups, option rows, and selected indicator;
- the `listbox`/`option` roles and related ARIA attributes;
- label presentation separately from wire values;
- Arrow, Home, End, Escape, and focus behavior, including dismissal when focus
  leaves the control; and
- the shared `Composer` and `Setting` presentations and their styling.

Document-level click-away handling may dispatch the caller's dismiss message,
but it must not duplicate the control's DOM or keyboard behavior.

### Review requirements

A change that introduces or modifies a select must demonstrate that:

- rendered application markup contains no native `<select>` for that control;
- the feature renders `@select_control.Control` directly or through a documented
  wrapper;
- selection and open-menu transitions are tested in the caller that owns the
  state; and
- shared keyboard, focus, accessibility, or presentation changes are tested in
  `frontend/select_control` rather than copied into feature packages.
