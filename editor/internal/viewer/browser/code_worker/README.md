# Derived editor work

This browser client runs one closed `CodeWorkerRequest` in a dedicated Worker
compiled from `internal/workers/code`. Completion, cancellation and the deadline
all terminate the thread. The main-thread deadline therefore preempts a running
synchronous algorithm. Each task owns its own worker and timer; no arbitrary
provider/tokenizer/folding-marker closure is serialized.

Publish `editor-code-worker.js` beside the host HTML entry, resolved against its
base URI. `scripts/build-web.mbtx` and the desktop browser/packaging pipeline stage
this artifact, and the shell host serves it as JavaScript. Nonbrowser/no-Worker
environments return None so their callers retain the synchronous compatibility
path. Script errors, invalid protocol data, computation failure and timeout are
explicit Result errors once a Worker was started.

The closed protocol still uses ordinary JSON, but browser/native worker code
uses native parsing/stringification and visits the resulting value tree rather
than scanning large replies character by character on the UI thread. Folding
replies omit a second copy when outline structure is identical to provider
ranges (`None` names that case); each view still constructs its own collapse
state. A native-wire unit case covers UTF16 text, Int coordinates, null/missing
fields and invalid JSON, alongside the real Worker scenarios.

The protocol preserves complete UTF16 diff coordinates and fold structure.
Callers additionally fence results by model identity/content version and their
own request generation, and validate before applying. Worker support is an
explicit opt in on the otherwise open DocumentDiffProvider contract.
