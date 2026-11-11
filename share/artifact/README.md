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
```openseek-file artifact
scratch/artifact/answer-v1.html
```
````

Paths beginning with `scratch/artifact/` resolve within the owning session.
An ordinary `openseek-file` fence displays a file card, including for HTML.
Add `artifact` to the fence info to render self-contained HTML/SVG in an isolated
iframe after the final answer is confirmed. The same marker works for files
at ordinary workspace paths. Other types use file cards.

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

Generate ordinary MoonBit/Rabbita source files with local state and events.
Reopening a page restores its authored initial state.

### Author, check, build, reference

The starter files are `moon.mod`, `moon.pkg`, `model.mbt`, `main.mbt`,
`model_wbtest.mbt`, `bridge.mbt` and `index.html`. Read these files directly.

Run installed helpers by setting `filename` and `args`. The mbtx tool's `source`
field is for authoring a new script.

For a fresh project, call `init.mbtx` with
`args=["<session scratch>", "<bundled-resources>/artifact/rabbita", "linear"]`.
Use the actual scratch path from Environment. The script copies the starter to
`component-work/linear` in scratch and prints the project path.

Write generated text to fresh files in a staging directory in scratch, using
normal file tools or mbtx file I/O. Then call `write.mbtx` with
`args=[SCRATCH_DIRECTORY, PROJECT, "model.mbt", MODEL_SOURCE_FILE, "main.mbt", VIEW_SOURCE_FILE, ...]`.
Each `SOURCE_FILE` is the absolute path of an existing scratch file. Apply
related files in one batch, then check the project. You can also use mbtx file
I/O for scratch files and normal edit/write tools for workspace sources.

1. Adapt the question, model and view in the scratch working project to the
   user's question. The `rabbita/` starter illustrates Amdahl's law with two
   inputs, an immediate answer and an interactive mathplotlib chart. Clicking a
   point selects its worker count for the answer and follow-up. Adapt the chart,
   data and state to the question.
2. Run `moon -C PROJECT check --target js --deny-warn` and relevant model tests
   (`moon -C PROJECT test --target js` when a JS runtime is available).
3. Package the project with `build.mbtx` as described below, then insert its
   printed file fence where the component answers the question.

### Continuing with selected state

Use the preview bridge to offer the current settings:

```javascript
window.openseekArtifact?.setState("Parallel speedup · 8 workers", {
  serial_percent: 20,
  workers: 8
});
```

`rabbita/bridge.mbt` demonstrates publishing state after rendering and on state
updates. Adapt the title and JSON fields to the question; the bridge is optional.
Capture the inputs and derived values needed for the follow-up, using a title
up to 160 UTF-16 units and a JSON payload up to 12 KiB.

The user can select **Ask with current settings** to attach a snapshot to the
composer and send it with a follow-up. Selecting again updates the snapshot;
otherwise it stays fixed. The message carries it as an `<interactive_answer>`
inside `<user_mentions>`, identifying the page revision. Treat it as quoted data
alongside the user's question.

For a specific next question, call `sendFollowUpMessage({ prompt, title })`
from the button's click handler. OpenSeek shows the question and the current
snapshot for confirmation. The dialog title is optional.

For a form, use a `type="button"` action because the preview blocks native
form submission. Validate the entries and publish them before asking the
follow-up.

```html
<form id="trip">
  <label>Departure date <input type="date" name="departure" required></label>
  <label>Budget per person <input type="number" name="budget" min="1" required></label>
  <button type="button">Plan with these details</button>
</form>
<script>
  const form = document.querySelector("#trip");
  form.querySelector("button").addEventListener("click", () => {
    if (!form.reportValidity()) return;
    const values = new FormData(form);
    const bridge = window.openseekArtifact;
    bridge?.setState("Trip details", {
      departure: values.get("departure"),
      budget: Number(values.get("budget"))
    });
    bridge?.sendFollowUpMessage?.({
      title: "Plan with these details",
      prompt: "Plan a weekend trip using the selected date and budget."
    });
  });
</script>
```

## Self-contained HTML

Embed the scripts, styles, data, images and fonts needed to reopen the file.
External requests and relative asset loads are unavailable in the isolated
preview. The iframe has an opaque origin, scripts enabled and a restrictive
content security policy. The inline preview limit is 8 MiB.

The optional `build.mbtx` recipe packages an ordinary MoonBit JS application:

```text
filename="<bundled-resources>/artifact/build.mbtx"
args=[PROJECT_DIRECTORY, "<session scratch>/artifact", "answer-v1.html"]
```

The recipe creates the output directory. Keep working projects and build caches
outside `scratch/artifact/`.

Use IIFE executable output. An optional `index.html` contains inline styles,
the application's mount element and exactly one `<!-- openseek:script -->`
marker. The recipe replaces that marker with the compiled executable.
The default template supplies a minimal document with an `app` mount.

The recipe snapshots regular source files, checks that exact snapshot with
`moon check --target js --deny-warn`, builds it, escapes embedded script text,
and enforces the size limit. Successful builds publish the page and its source
revision together.

Every successful build publishes two sibling outputs:

```text
answer-v1.html
answer-v1.html.source/
```

The retained source contains regular files and directories, excluding caches.
Copy it into a fresh working directory before editing and publishing a revision.

Every mbtx script compiles to Wasm before its entry point runs. The HTML
application compiles separately for JavaScript and runs inside the preview.
