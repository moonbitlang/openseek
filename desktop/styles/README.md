# Desktop styling

`desktop/app.css` is the development import manifest. Production packaging
concatenates the same files in the same order, so every application style must
live in one of the listed sources. Viewer styles are separate and must not be
targeted through global element selectors.

## Tokens

Define shared semantic values in `tokens.css`: palette roles, the small type
scale, radii, and the few values that genuinely recur across components. A
one-off measurement stays beside its component; a CSS variable is not useful
merely because a literal exists.

Component styles consume semantic names such as `--color-text-muted` and
`--color-focus-ring`. They do not introduce aliases for a single call site or
encode component names into global tokens.

## Form-field focus ownership

Every form field has exactly one element that draws its focus border:

- A plain `input`, `textarea`, or `select` carries `data-focus-owner`. The
  shared rule recolors its existing border when it has one and always removes
  the browser's native outline.
- A composite field puts `data-focus-owner` on its bordered wrapper and
  `data-focus-target` on the nested text control. The nested control has no
  visible border of its own.
- The shared rules in `base.css` change the owner's existing one-pixel border
  to `--color-focus-ring` and suppress the target's browser outline.
- Component styles define geometry, normal border, background, and content.
  They must not add form-field `:focus`, `:focus-within`, or focus outlines.

A structural separator is not a focus border. For example, Quick Open keeps
its full-width bottom separator neutral and puts `data-focus-owner` on the
borderless input itself; focusing the input must not recolor the dialog divider.

These attributes are intentionally opt-in. The embedded Viewer shares the
document and application stylesheet, but its controls do not carry the
attributes, so Desktop focus rules cannot restyle them.

Buttons, links, and other discrete actions are not form fields. They may use a
component-appropriate `:focus-visible` indicator because they often have no
persistent border to recolor.
