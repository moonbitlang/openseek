# Desktop styling

`desktop/app.css` is the development import manifest. Production packaging
concatenates the same files in the same order, so every application style must
live in one of the listed sources. Viewer styles are separate and must not be
targeted through global element selectors.

## Browser baseline

The Desktop's pinned Proton 0.3.0 runtime bundles CEF 150.0.19, based on
Chromium 150.0.7871.252. The canonical version comes from the resolved
`proton_cefsetup` package's `requirements.json`; update this section when the
Proton dependencies change. `.proton/runtime.json` describes only the locally
prepared runtime and may lag until setup runs again.

Prefer the strongest stable CSS feature available in that Chromium baseline
when it makes layout ownership clearer, removes JavaScript measurement, or
replaces a hand-built browser primitive. No fallback for older browsers is
needed. Examples include container queries for resizable panes and CSS anchor
positioning with the Popover API for floating controls.

Using a newer feature is not itself a design goal. Keep application state such
as persisted user-resized dimensions in the model, and do not add motion or
visual treatment merely because the engine supports it.

## Tokens

### Palette playground

Open [`../dev/theme-lab.html`](../dev/theme-lab.html) directly in a browser
to compare light and dark presets, edit colors, and copy a replacement
[`palette-light.css`](palette-light.css) or
[`palette-dark.css`](palette-dark.css). No build step or network is needed;
keep the HTML inside the checkout so its relative stylesheet link resolves.
Drafts are saved in the browser's local storage; copy CSS to share a palette.

The preview is an illustrative layout, not the production frontend. Its
current presets read both palette files when the page loads. Other presets
adapt their reference palettes to SeekMoon's semantic roles. Reset the current
preset to discard a saved browser draft and see the file's colors.

Copying does not modify the application. Replace the entire contents of
the matching `palette-light.css` or `palette-dark.css` with the copied CSS,
then refresh the development app or rebuild the packaged app. The copy
notification names the destination file. Light and dark drafts are independent;
the original-color comparison follows the selected mode. Verify the editor,
terminal, overlays, and interaction states.

### Shared values

`palette-light.css` owns the `--light-*` color inputs; `palette-dark.css` owns
the matching `--dark-*` inputs. `tokens.css` maps each semantic role through
`light-dark(var(--light-role), var(--dark-role))`, preserving both explicit
theme overrides and the system preference. Replacing one palette does not
change the other or force the app into a particular mode. Theme Lab copies
six-digit hex colors; preserve that format for its color controls.

Define shared semantic values in `tokens.css`: palette mappings, the small type
scale, radii, and the few values that genuinely recur across components. A
one-off measurement stays beside its component; a CSS variable is not useful
merely because a literal exists.

Component styles consume semantic names such as `--color-text-muted` and
`--color-focus-ring`. They do not introduce aliases for a single call site or
encode component names into global tokens.

### Typography and appearance settings

`Font size` sets `--font-size-base` (14px by default). Use the existing scale
for all readable app text, including Jobs, Codex conversations, and dock UI:

| Role | Token | Default |
| --- | --- | --- |
| Body text, chat prose, composer input, and task names | `--font-size-md` | 14px |
| Controls and code | `--font-size-sm` | 13px |
| Timestamps, status, and other metadata | `--font-size-xs` | 12px |
| Panel headings | `--font-size-lg` | 17px |

Do not hardcode text sizes in pixels. Markdown may size headings relative to
its surrounding text; larger page headings may derive from the base. Use
unitless line heights so text grows without clipping. Icon glyphs use the
icon scale and do not acquire text-sizing rules merely to size an SVG.

Ordinary text inherits `--font-family-sans` and `--font-weight-regular` from
the app (400), with antialiased font smoothing on macOS. Markdown emphasis
uses 600 rather than the browser's default bold weight. Chat prose and
composer input use normal letter spacing for mixed Chinese and Latin text.
Code blocks, commands, logs, and paths displayed as code use
`--font-family-mono`, the one monospace stack the CSS code surfaces, the editor,
and the terminal share. Avoid independent font stacks or misspelled fallback
tokens that bypass it. Task names may use weight 500 and headings 600 to
express hierarchy.

The code editor and terminal also need their measured options updated:
`AppFontSize::apply` writes the root type scale and both widgets' measured
sizes. Both resolve the monospace stack themselves — the editor's default is
that stack, and a new terminal reads `--font-family-mono` through CSSOM when it
mounts. New terminals read `--font-size-sm` through CSSOM too, so its
registered `<length>` type must keep resolving to pixels. The Viewer theme's
standalone defaults are overridden for every embedded app code surface in
`tokens.css`.

Verify changed typography at the minimum and maximum font settings, after
reload, and in both light and dark themes; let content wrap or reduce columns
as text grows.

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

## Button ownership

A button's geometry belongs to a recognized component base, while short intent
classes only choose that component's appearance:

- `.button` owns the padding, type size, focus ring, and responsive target size
  of ordinary labeled actions.
- Specialized controls such as `.sidebar-button`, `.icon-button`, and
  `.queued-input-action` own their own geometry.
- `primary`, `secondary`, and `danger` may be nested variants of those bases,
  but must not define dimensions on their own or through a global selector such
  as `button.danger`.

This contract makes stylesheet order irrelevant to component geometry: adding
`danger` to an icon action may change its semantic color, but cannot turn it
into a labeled action button.
