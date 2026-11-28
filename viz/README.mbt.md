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
| `trajectory`     | native+js+wasm | Pure fold of one run's session files into a timeline: sessions, turns, model calls, tool steps, `.mbtx` scripts and their PTC calls, background jobs, waits and milestones, each with a start, an end and a status, plus the axis they are drawn on. A PTC call is a real interval when the trace timed it and a zero-width marker when it predates that. |
| `cmd/viz_app`    | js     | The rabbita (TEA) frontend: session browser, fetch, mode toggle, run waterfall. |
| `inspect`        | native+wasm | Read-only web server (`moonbitlang/async/http`, standalone module `moonbitlang/inspect`) exposing a JSON/raw-file API over discovered `openseek_session-*.jsonl` files. It never writes, so pointing it at a live session root is safe. |

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
- `GET /api/trajectory/<root id>` → `{root_session_id, t0_ms, t_end_ms, live, sessions, spans, stats}`, one run folded into a single timeline (see the Trajectory section of `inspect/README.md`)
- `GET /api/sessions/<key>/jobs/<job>` → `{found, job, output}`, one background job's record plus a page of the text it wrote (`?start=<ms>` picks the generation, `?cursor=<byte>` continues from a page already sent)

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

## Run waterfall

`Trajectory` in a session header opens `#t=<session id>`: every session the run
spawned, every turn, every step, on one axis, indented by nesting and coloured by
kind. A child normally mounts on the exact step that spawned it — the
`subagent` tool's own result names the child session — and only a child the log
never named falls back to time (the parent's tool call open when the child's
first event landed).

Bars keep true durations. The header cards give the run's duration against its
start and end clock, its shape, and where the time went (model, tools, waiting,
tokens, failures with a jump to the first one). Below them an activity strip
draws one column per slice of the same axis — model calls, tool calls and a red
mark over any slice holding a failure — so a spike sits directly above the steps
that made it. The ruler draws one block per stretch of work and one narrow
hatched slot per folded idle stretch, labelled with how long that stretch really
was, so a gap cannot be mistaken for a pause of the same size. A row with
children draws them inside its own bar as kind-coloured ticks, which is what
makes a folded turn readable without expanding a thousand steps; hovering a row
opens a card with the step's kind, outcome, duration, `brief` and prompt, and the
`↗` beside its duration opens that session's log at the event the step was read
from.

A dated scale above the rows names the clock — `Nov 1` at a day boundary,
`02:00` otherwise, with the seconds when the run is only seconds long — and
casts that grid down the rows, so a bar can be read against the time of day
without leaving its line. Each lane's first row carries its role: the run's own
session, or an agent the run spawned.

A row that names a background job carries a `.out` button beside its label:
opening it reads that job's own file and draws it in place, under the row. The
text never comes from the transcript — a job can print megabytes the log never
carries — so it is fetched as a tail of up to 64 KiB, with one line saying when
earlier output was left out. A job that is still running is followed from where
the last page ended, and a record that cannot be read shows as an error block,
not as an empty log. An `--export` archive bakes session logs and waterflows but
not job outputs, so its job rows offer no `.out` button rather than one that
would fail on click.

`Idle folded` collapses the idle stretches between work, because a run saved
across a night is otherwise almost entirely blank; `Idle at scale` shows the true
gaps. A step with children folds with its chevron, and a folded row keeps its
place so the tree stays aligned. `Failures only` — the button carries the count —
narrows the rows to the failed steps plus the ancestors that place them, and a
run with none reads `Failures · none` instead of drawing an empty axis.

## Subagent transcripts

A sub-run (a review child, or a workflow scout) of a durable session persists its own
transcript as a sibling session named `<parent id>-sr-N`. The parent's tool
results carry the sub-run id in their display-only `brief`; the viewer turns
that into a `↳ subagent` chip on the result card (an in-page `#s=<child id>`
navigation) and — in the raw view, once the app has loaded the child — nests
the child's full transcript inside the card. The model view stays chip-only:
the child's turn is nothing the parent's model was fed. The sidebar lists
child sessions indented under their parent.
