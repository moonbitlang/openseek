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

Follow the [Rabbita UI conventions](../AGENTS.md#rabbita-ui).

TODO: Remove `frontend/select_control` and migrate its callers to `@rui.select`.

### Component and state boundary

Keep the component instance stable across unrelated parent updates. The
application owns business values and their effects; internal interaction state
stays with the component. Labels remain separate from wire values.

### Review requirements

For a new or reworked select, verify that:

- it uses the corresponding `rui` component, directly or through a wrapper
  that preserves its state ownership;
- an unrelated application update while the menu is open preserves its open
  state, active option, and focus;
- selecting an option updates the intended business value; and
- presentation changes preserve keyboard navigation, dismissal, accessibility,
  and readability in the affected themes and viewports.

Select validation using
[Desktop's change-scope guidance](AGENTS.md#validation-by-change-scope).
