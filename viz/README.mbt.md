# OpenSeek session visualizer

A browser viewer for OpenSeek's durable session logs. It renders the
`openseek_session-<id>.jsonl` file of a session (a header line plus append-only event lines) two ways, side by side behind a
toggle:

- **Raw log** — every event in file order, grouped into turns (user prompt →
  assistant messages, tool results, runtime notices, terminal).
- **Model view** — exactly what `Session::chat_messages` feeds the model:
  summaries replace the events they cover, and tool calls left dangling by a
  crashed process show the synthesized "previous agent process exited…" marker.

A Light / Dark / System theme toggle sits in the sidebar (default Light;
System follows the OS via `prefers-color-scheme`).

## Pieces

| Package          | Target | Role                                                                 |
|------------------|--------|---------------------------------------------------------------------|
| `viz`            | js     | Pure parse + render: session-file text → typed events → `@html.Html`. Reuses `agent_session` decoders and projection, so it stays correct as the format evolves. |
| `cmd/viz_app`    | js     | The rabbita (TEA) frontend: session browser, fetch, mode toggle.    |
| `cmd/viz_server` | native | Read-only web server (`moonbitlang/async/http`) exposing a JSON/raw-file API over a `SessionStore`. It never writes, so pointing it at a live session root is safe. |

The `viz` library is headless-testable: `render_session` returns `@html.Html`,
which `@rabbita.render_to_string` turns into a string for snapshot assertions —
no browser needed in CI.

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
moon run cmd/viz_server --target native -- --search-dir . --port 8080

# 3. Open http://127.0.0.1:8080
```

By default the server scans `.` recursively for `.openseek` directories and
also includes the compatibility `--session-root` (default `.openseek`). The
scanner skips `.git`, `node_modules`, `.mooncakes`, and `_build`. Repeat
`--search-dir` to scan several trees, and use `--session-root-name` when a
different marker such as `.openroot` should be treated as the session root.

`--session-root`, `--search-dir`, `--session-root-name`, `--port`,
`--web-dir`, and `--bundle` all have env-var fallbacks
(`OPENSEEK_SESSION_ROOT`, `OPENSEEK_VIZ_SEARCH_DIR`,
`OPENSEEK_VIZ_SESSION_ROOT_NAME`, `OPENSEEK_VIZ_PORT`, …); run with `--help`
for the full list.

## Resilient parsing

`parse_events` tolerates a half-written log: a truncated final line (a process
that exited between writing an event and its newline) is reported as a benign
truncated tail, and any single line that fails to decode becomes an inline error
card while the rest of the conversation still renders.
