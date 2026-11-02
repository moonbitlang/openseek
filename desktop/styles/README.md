# Desktop styling

`desktop/app.css` is the development import manifest. Production packaging
concatenates the same files in the same order, so every application style must
live in one of the listed sources. Viewer styles are separate and must not be
targeted through global element selectors.

## Browser baseline

The Desktop's pinned Proton 0.5.1 runtime bundles CEF 150.0.19, based on
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

#### Type roles

`Font size` sets `--font-size-base` on `html` (14px by default, range 12–18px).
Use the proportional type roles for readable application text:

| Role | Token | Default |
| --- | --- | --- |
| Body text, chat prose, composer input, and task names | `--font-size-md` | 14px |
| Controls and code | `--font-size-sm` | 13px |
| Timestamps, status, and other metadata | `--font-size-xs` | 12px |
| Panel headings | `--font-size-lg` | 17px |
| Small badges and compact metadata | `--font-size-micro`, `--font-size-caption` | 10px, 11px |
| Emphasized labels and dialog titles | `--font-size-emphasis` | 16px |
| Section and page titles | `--font-size-title`, `--font-size-page-title` | 20px, 26px |

Ordinary text inherits `--font-family-sans` and `--font-weight-regular` (400),
with antialiased font smoothing on macOS. Task names may use weight 500 and
headings 600; Markdown emphasis uses 600. Chat prose and composer input use
normal letter spacing for mixed Chinese and Latin text. Code surfaces,
including the editor and terminal, share `--font-family-mono`.

#### Dimensions and ownership

- Use `--space-1` through `--space-7` for shared padding, margins and gaps;
  keep one-off dimensions local as simple `rem` values, not pixel-conversion
  fractions. Exact ratios belong in shared scales or coupled geometry.
- Use `em` for text-control geometry and unitless text line heights.
  Markdown headings may size relative to their surrounding text.
- Use `--icon-xs/sm/md/lg` for control glyphs, not text-size overrides.
  Component classes own button geometry: scale text, hit areas and whitespace
  together, including titlebar controls.
- Use `%`, `fr` and viewport/container units for available space. Prefer
  minimum heights and content-driven sizing so text can wrap without clipping.

#### Exceptions

Thin borders, deliberate fixed icon grids, resize handles and native window
geometry may remain in pixels. Native window-control insets set a lower bound
on header geometry. Document-authored Office typography, zoom and measured
document coordinates are separate from application UI.

Retain the question input's 16px mobile focus floor and the narrow Composer's
existing 16px override until their mobile-focus policy is reviewed.

The editor and terminal require numerical font sizes for measured layout.
Resolve those from CSSOM's computed `--font-size-sm`, keeping its registered
`<length>` type; do not duplicate the CSS ratio in application code.

#### Verification

Verify changed typography at 12px, 14px and 18px, after reload, in existing
and new editors/terminals, and in both light and dark themes. Include narrow
panes, control whitespace, clipping, wrapping/scrolling and graph alignment;
computed font-size assertions alone do not establish layout correctness.

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
  of ordinary labeled actions. Its `compact` variant supplies the smaller
  padding and minimum height used above the composer; contextual appearance
  is expressed through the existing `--button-*` properties.
- Specialized controls such as `.sidebar-button`, `.icon-button`, and
  `.queued-input-action` own their own geometry.
- `primary`, `secondary`, and `danger` may be nested variants of those bases,
  but must not define dimensions on their own or through a global selector such
  as `button.danger`.

This contract makes stylesheet order irrelevant to component geometry: adding
`danger` to an icon action may change its semantic color, but cannot turn it
into a labeled action button.
