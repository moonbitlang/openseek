# Presentation Design Guidelines

**General principle**: Skip any step below if the model does not support it. Any specification from the user—template, brand guidelines, color scheme, fonts, reference styles, attachments, and so on—takes precedence over this guide and any design system document.

## 1. Understanding the Requirements

- **Clarify the requirements**: Determine the purpose, audience, page count, and style direction, as well as the input type (topic only / full document / page-by-page outline and script).
- **Determine the page count**: Follow the user's specification first; otherwise align with the page-by-page outline or script; if neither exists, infer it from the topic and the amount of content, and explain your reasoning.
- **Do not interrupt by default**: When requirements are unclear, proceed with reasonable defaults; ask questions only for hard blockers such as an attachment that cannot be opened or contradictory intent.

## 2. Design System and Color Scheme

- **Choose a scenario**: Select the primary scenario based on the audience and the reader's task: analytical decision-making / business proposal / management report / academic research / education and training / technical engineering / brand creativity. Add a secondary scenario when necessary; if nothing matches, use a general-purpose approach rather than forcing a fit. For tasks that reproduce an image/PDF in Typst, analyze the original document directly without choosing a scenario.
- **Unified design system**: Use a single set of color, font, whitespace, and layout rules throughout the presentation; do not introduce conflicting constraints midway.
- **Color scheme priority**: User specification > the organization's primary color > the design system's recommendation. When the user states their organization, search for its logo first and extract the primary color.
- **Color constraints**: Avoid stacking red, purple, yellow, and green at the same time; unless specified by the user or a skill, use no more than three colors throughout. Text and background must have clear contrast.

## 3. Fonts and Symbols

- **Language and punctuation**: Default to Simplified Chinese unless the user requests Traditional; use full-width punctuation for Chinese, and half-width for English words, numbers, code, URLs, paths, technical identifiers, and mathematical content.
- **Font choice**: Choose fonts by language and tone. Use sans-serif for general reports; serif for academic, cultural, and formal presentations; rounded fonts for children's and educational scenarios; and monospaced fonts for code, number alignment, and metrics.
- **Font hierarchy**: Clearly define the division of labor between display and body fonts, unify the size baselines for headings, body text, captions, and sources, and establish hierarchy through size and weight rather than color.

## 4. Content Organization and Page Layout

- **Page task and title**: Before designing, clarify what each page should make the reader understand, believe, decide, or do; make titles state a judgment and avoid empty labels such as "Work Report", "Overview", or "Background".
- **Pacing**: Decide based on the content whether to include a table of contents page and section pages, balancing quick scanning with close reading of key points.
- **Table of contents layout**: Avoid stacking small text or leaving large blank areas; spread section blocks evenly across the page; if a single column does not fit, switch to two columns, arranging numbers and names separately.
- **Layout and alignment**: Choose the layout based on the content; do not default to thirds, quarters, or a 2×2 matrix. When using a horizontally parallel layout at the same level, default to equal widths with uniform alignment; use different widths only when you need to express a primary/secondary relationship.
- **Expressing hierarchy**: Unless the user requests otherwise, do not use rectangles or rounded cards to build hierarchy or achieve alignment; use line segments, whitespace, and contrast in font size and weight instead.

## 5. Data, Charts, and Sources

- **Do not fabricate**: Do not fabricate data, citations, customer cases, experimental results, or sources; mark missing materials as placeholders, assumptions, or to be supplemented.
- **Source attribution**: Pages involving external facts and data must state the source, date or time range, and methodology.
- **Structured presentation**: Use native tables or chart components for data comparisons, metric lists, parameter descriptions, and dimension breakdowns; do not use Markdown tables.
- **Legend legibility**: The colors of each legend in pie and donut charts must be easy to distinguish; you may use the primary color or a gradient of opacity.
- **Chart styling**: Check whether the default style is clear and consistent with the design system; adjust inappropriate axes, grid lines, legend boxes, and borders, and remove rainbow color schemes, 3D, gradients, and shadow effects that interfere with reading.

## 6. Images and Assets

- **Image usage**: Place images as the content requires and avoid overuse; cover images must be high quality. Do not use abstract shapes as decoration on the cover, closing, or section pages; when visual assets are needed, prefer high-quality images.
- **Attached images**: Keep them as-is and do not crop them; let the layout adapt to the image.
