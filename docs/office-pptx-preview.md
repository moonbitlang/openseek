# PowerPoint preview

Desktop opens `.pptx` files in the shared read-only Office surface. Each slide
retains selectable SVG text and embedded fonts. Search, zoom, slide thumbnails
and visual region annotations use the existing Office controls. Region context
includes the original file identity, slide number and normalized geometry.
PowerPoint comments and logical Word/Excel selectors are unavailable.

The static drawing support and explicit unsupported-feature errors come from
`office.mbt`'s `pagelayout/pptx` renderer. Font replacement warnings remain visible.
The renderer's MPL-2.0 MTX decoder license and source notice are staged alongside
the viewer's runtime assets in both browser and packaged Desktop builds.

## Published dependencies

Desktop uses `Lampese/office-viewer@0.2.6`, built from the merged
[office-viewer#12](https://github.com/moonbit-community/office-viewer/pull/12),
and the published `moonbitlang/pagelayout@0.8.1` PPTX renderer from
[office.mbt#654](https://github.com/moonbitlang/office.mbt/pull/654).
Compilation, fonts, thumbnails, PDF runtime and license assets all come from
that pinned Viewer package. No local workspace member or asset-source override
is required for browser or packaged Desktop builds.

The public two-slide fixture in `desktop/e2e/fixtures/office` is independently
generated; its generator and provenance are included. The private reference deck
and its embedded fonts are never committed.
