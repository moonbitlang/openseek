# OpenSeek session visualizer

A browser viewer for OpenSeek's durable session logs. It renders the
`openseek_session-<id>.jsonl` file of a session (a header line plus append-only event lines) two ways, side by side behind a
toggle:

- **Raw log** — every event in file order, grouped into turns (user prompt →
  assistant messages, tool results, runtime notices, terminal).
- **Model view** — exactly what `Session::chat_messages` feeds the model:
  summaries replace the events they cover, and tool calls left dangling by a
  crashed process show the synthesized "previous agent process exited…" marker.

A standalone export opens on **Raw log** so loading an archived trace never
appears to discard history. The live viewer retains its **Model view** default;
either view remains available from the toggle.

A Light / Dark / System theme toggle sits in the sidebar (default Light;
System follows the OS via `prefers-color-scheme`).

## Who said it

Both views give a prompt a person actually typed a Codex-style treatment — a
raised card with a shadow, the prompt in bold headline type, captioned **You**
beneath it — so the human side of a long conversation is findable at a glance.
A turn header also counts the mid-turn steers it hides while collapsed
(`✋ 2 steers`).

Not every user-role message is the user's, and the viewer says so rather than
lending them the raised card:

| Message | Caption |
|---|---|
| A prompt or steer someone typed | **You** (raised card) |
| `@agent_session.GoalContinuePrompt`, which serve submits to relaunch a turn on a standing goal | **Auto-continue** |
| The opening task of a sub-run child session (`<parent>-sr-N`), written by the agent that spawned it | **Task from parent** |
| A runtime notice or compaction summary, which `chat_messages` replays as a user-role message | **Runtime notice** / **Summary**, as in the raw log |

The auto-continue text is matched against the constant the engine submits, so
rewording that prompt stops the match instead of quietly captioning engine
text as the user's.

A Codex-style prompt navigator rides the log's left gutter in both views: one
tick mark per typed prompt, in a column that stays put while the log scrolls.
Hovering a tick raises the same card the prompt wears — its text, wall-clock
stamp, a `had errors` flag when the span it started hit failed tools, and the
opening of the reply it drew — and clicking jumps to the prompt's card
(recording the position in the hash's `seq=`, like the step scrubber).

## Pieces

| Package          | Target | Role                                                                 |
|------------------|--------|---------------------------------------------------------------------|
| `viz`            | js     | Pure parse + render: session-file text → typed events → `@html.Html`. Reuses `agent_session` decoders and projection, so it stays correct as the format evolves. |
| `cmd/viz_app`    | js     | The rabbita (TEA) frontend: session browser, fetch, mode toggle.    |
| `inspect`        | native+wasm | Read-only web server (`moonbitlang/async/http`, standalone module `bobzhang/inspect`) exposing a JSON/raw-file API over discovered `openseek_session-*.jsonl` files. It never writes, so pointing it at a live session root is safe. |

The `viz` library keeps its parsing, projection, and error-count rules
headless-testable. `render_session` returns `@html.Html`, which the Rabbita
browser application mounts into the page; the repository does not serialize
that virtual tree for string-based render assertions. Run
`just viz-test-browser` from the repository root, or `just test-browser` from
`cmd/viz_app/`, for the Playwright DOM coverage of the mounted viewer.

## Server API

- `GET /` → the viewer shell (`web/index.html`)
- `GET /viz_app.js` → the compiled frontend bundle (auto-located from the moon build output)
- `GET /api/sessions` → `[{key, id, root, root_label, last_active, first_prompt}, …]`, most recent first across all roots
- `GET /api/sessions/<key>` → `{found, events, events_bytes}` envelope for the frontend (`events` is the raw session-file text; its first line is the header record)
- `GET /api/sessions/<key>/openseek_session-<id>.jsonl` → raw session file

## Drag and drop

A session file is self-contained (the header line carries the id and system
prompt), so the viewer also renders files that are not in any scanned store:
drop any session `.jsonl` anywhere in the window and it is read and
rendered entirely client-side — nothing is uploaded. Selecting a session from
the sidebar returns to the served view.

## Running it

```bash
# 1. Build the frontend bundle (JS backend)
moon build cmd/viz_app --target js

# 2. Serve sessions discovered under the current tree
moon run inspect -- --search-dir . --port 8080

# 3. Open http://127.0.0.1:8080
```

By default the server scans `.` recursively for `.openseek` directories and
also includes the compatibility `--session-root` (default `.openseek`). Session
rows are discovered from `openseek_session-*.jsonl` files under each root's
`sessions/` tree, so stray files like `.DS_Store` and husk directories are not
listed. A directory or single file of copied `openseek_session-*.jsonl` logs can
also be passed directly as `--session-root`. The scanner skips `.git`,
`node_modules`, `.mooncakes`, and `_build`. Repeat `--search-dir` to scan
several trees, and use `--session-root-name` when a different marker such as
`.openroot` should be treated as the session root.

`--search-dir`, `--session-root-name`, `--port`, `--web-dir`, and `--bundle`
have env-var fallbacks (`OPENSEEK_VIZ_SEARCH_DIR`,
`OPENSEEK_VIZ_SESSION_ROOT_NAME`, `OPENSEEK_VIZ_PORT`, …). Pass
`--session-root` explicitly when selecting a compatibility root; run with
`--help` for the full list.

## Resilient parsing

`parse_events` tolerates a half-written log: a truncated final line (a process
that exited between writing an event and its newline) is reported as a benign
truncated tail, and any single line that fails to decode becomes an inline error
card while the rest of the conversation still renders.

## Subagent transcripts

A sub-run (a review/subtask child, or a workflow scout) of a durable session persists its own
transcript as a sibling session named `<parent id>-sr-N`. The parent's tool
results carry the sub-run id in their display-only `brief`; the viewer turns
that into a `↳ subagent` chip on the result card (an in-page `#s=<child id>`
navigation) and — in the raw view, once the app has loaded the child — nests
the child's full transcript inside the card. The model view stays chip-only:
the child's turn is nothing the parent's model was fed. The sidebar lists
child sessions indented under their parent.
