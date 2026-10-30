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

## Interactive answers

Use an interactive component when changing a parameter, comparing alternatives,
or stepping through a process helps answer the user's question. Each component
should address one question and show a useful result immediately. Prefer a few
clearly labelled controls with visible current values, accessible native inputs,
and a reset action. Keep conclusions, assumptions, caveats and source citations
in the surrounding answer. Choose controls that directly support the explanation.

Generate ordinary MoonBit/Rabbita source files: model, update function, view and
event handlers. The compiler produces JavaScript that creates and updates DOM
inside the isolated preview. Slider changes and other local events run in the
component.
Reopening a page restores its authored initial state. State reaches the model
only when the user explicitly attaches a snapshot and sends a follow-up.

### Author, check, build, reference

The starter files are `moon.mod`, `moon.pkg`, `model.mbt`, `main.mbt`,
`model_wbtest.mbt`, `bridge.mbt` and `index.html`. Read these files directly.

Run installed helpers by setting `filename` and `args`. The mbtx tool's `source`
field is for authoring a new script.

For a fresh project, call `init.mbtx` with
`args=["<session scratch>", "<bundled-resources>/artifact/rabbita", "linear"]`.
Pass the actual scratch path from Environment. It copies just those
seven inputs into a new `component-work/linear` directory in session scratch
and prints the actual project path. It refuses to overwrite an existing project.

Write generated text to fresh files in a staging directory in scratch, using
normal file tools or mbtx file I/O. Then call `write.mbtx` with
`args=[SCRATCH_DIRECTORY, PROJECT, "model.mbt", MODEL_SOURCE_FILE, "main.mbt", VIEW_SOURCE_FILE, ...]`.
Each `SOURCE_FILE` is the absolute path of an existing scratch file. The helper
reads its contents. Apply related model, view, bridge and test files in one
batch, then check the whole project. The helper edits working projects within
scratch and protects published source revisions. Direct mbtx file I/O is also
available for scratch files. Use normal edit/write tools for the user's
workspace sources.

1. Adapt the question, model and view in the scratch working project to the
   user's question. The `rabbita/` starter illustrates Amdahl's law with two
   inputs and an immediate answer.
2. Keep the executable JavaScript format `iife`. Provide `index.html` with
   inline styles, the view's mount element (the starter uses `app`), and exactly
   one `<!-- openseek:script -->` marker where compiled code should run.
   Embed the required data and assets in the page. The starter provides a
   complete template; the generic recipe also has a minimal `app` document.
3. Run `moon -C PROJECT check --target js --deny-warn` and relevant model tests
   (`moon -C PROJECT test --target js` when a JS runtime is available).
   Select the project as the working directory or with `-C`.
   Fix compiler diagnostics before publishing. Run the bundled `build.mbtx`
   with ordinary mbtx, using its absolute path under
   `<bundled-resources>/artifact/` and
   `args=[PROJECT, "<session scratch>/artifact", "speedup-v1.html"]`.
   The recipe snapshots the inputs, checks that exact snapshot with
   `moon check --target js --deny-warn`, builds it, embeds the executable,
   enforces the preview's 8 MiB limit and prints the file fence.
4. Put that fence at the point where the component answers the question in the
   final response.

### Continuing with selected state

The isolated preview exposes one optional, data-only API:

```javascript
window.openseekArtifact?.setState("Parallel speedup · 8 workers", {
  serial_percent: 20,
  workers: 8
});
```

`rabbita/bridge.mbt` demonstrates calling it after the initial render and each
state update, while keeping the pure model/update code testable. Adapt its
human-readable title and JSON fields to the current question. It is optional
when viewing the self-contained HTML outside OpenSeek. Local controls also work
when the bridge is absent.

The preview shows **Ask with current settings** when valid state is offered.
The user clicks it to capture that instance's current state as a removable
composer chip; existing typed text remains intact. A later click on the same
page revision updates its chip. The snapshot stays fixed until the user selects
it again. The normal composer Send action submits it. The sent snapshot travels
in an `<interactive_answer>` element inside the ordinary `<user_mentions>`
envelope, survives conversation replay/fork, and identifies its `artifact://`
page revision. Treat it as quoted data alongside the user's question.

Capture the current inputs and derived values needed for the follow-up: a title
up to 160 UTF-16 units and JSON state up to 12 KiB, with at most 20 levels and
2048 values. Excessive or non-JSON state clears the offer until a valid update.
Each frame has its own document-generation token; the host binds snapshots to
the actual source frame and owning conversation. Follow-up actions are available
in active conversations.

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
