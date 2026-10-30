# Session file artifacts

Write a completed file with ordinary code, then reference it in the final answer.

## Storage and references

Write completed files under `<session scratch>/artifact/`, using the actual
scratch path shown in Environment and its existing write permissions. Pass
paths explicitly to scripts and create the directory when needed.
User-requested project files still belong at the requested workspace paths.

Use a new descriptive filename for every revision. Insert the finished file
where it belongs in the answer:

````markdown
```openseek-file
artifact://answer-v1.html
```
````

The URI contains a relative file path within the owning session's artifact
directory. HTML and SVG render in an isolated iframe after the final answer is
confirmed. Other types use ordinary file cards.

The artifact subtree is retained across calls, saved-session restarts and
archive/restore. A fork copies it into its own scratch directory; working
projects outside that subtree stay with the original session. Permanent session
deletion removes its retained files.

## Self-contained HTML

Embed the scripts, styles, data, images and fonts needed to reopen the file.
External requests and relative asset loads are unavailable in the isolated
preview. The iframe has an opaque origin, scripts enabled and a restrictive
content security policy. The inline preview limit is 8 MiB.

The optional `build.mbtx` recipe packages an ordinary MoonBit JS application:

```text
args=[PROJECT_DIRECTORY, "<session scratch>/artifact", "answer-v1.html"]
```

Run the installed script by its absolute `filename` with `args`, omitting mbtx's
`source` field. The recipe creates the output directory if needed and refuses a
symlink there. Keep working projects and build caches outside `scratch/artifact/`.

Use IIFE executable output. An optional `index.html` contains inline styles,
the application's mount element and exactly one `<!-- openseek:script -->`
marker. The recipe replaces that marker with the compiled executable.
The default template supplies a minimal document with an `app` mount.

The recipe snapshots regular source files, checks that exact snapshot with
`moon check --target js --deny-warn`, builds it, escapes embedded script text,
and enforces the size limit. A failed check/build publishes no page or source
revision. Read diagnostics, repair the source and retry.

Every successful build publishes two sibling outputs:

```text
answer-v1.html
answer-v1.html.source/
```

The retained source excludes dependency/build caches and rejects links or special
files. Copy that source into a fresh working directory before editing a revision,
then publish a new filename. Both outputs follow the existing session lifecycle.
Run the application's relevant tests before publishing.

Every mbtx script compiles to Wasm before its entry point runs. The HTML
application compiles separately for JavaScript and runs inside the preview.

## Interactive charts

Charts use the `Lampese/mathplotlib` and Rabbita APIs to produce interactive HTML.

Copy all four inputs from `example/`: `moon.mod`, `moon.pkg`, `main.mbt` and
`index.html`. The example's own HTML template supplies the `chart` mount and
inline chart styles. Edit the MoonBit application for the actual data, check it
with `moon -C PROJECT check --target js --deny-warn`, run relevant tests, and use
the generic `build.mbtx` recipe described above.

The example includes hover values, click selection and legend toggles. Keep
these interactions in local Rabbita state. Cite data sources in the surrounding
answer.

Previously saved structured chart artifacts remain supported by the Desktop
chart renderer. New file artifacts use the ordinary `openseek-file` reference.
