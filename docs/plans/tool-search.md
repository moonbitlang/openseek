# MCP tools as a script-side catalog

## Problem

Every request carries every MCP tool's description and schema in the `tools`
field. The cost grows with each configured server, and the provider limit of
128 function definitions forces `MaxTotalMcpTools = 100`
([tools.mbt](../../mcp/tools/tools.mbt)), which silently drops tools beyond the
budget.

## Decision

MCP tools stop being agent tools. They leave the model's function list and
the `AgentToolDefinition` registry, and become a catalog that mbtx scripts
search and call through the tools SDK's `mcp` package:

```mbtx
import {
  "moonbitlang/openseek_tools@0.3.0/mcp" @mcp,
  "moonbitlang/async",
}

async fn main {
  let page = @mcp.search(query="list issues")
  println(page.text)
  let result = @mcp.call("tracker", "list_issues", { "repo": "alpha" })
  println(result.content)
}
```

- **Discovery is a library call, not a tool.** `@mcp.search` ranks
  the catalog and returns both a rendered page for the model to read and
  typed records for the script to compute with. Nothing about MCP appears in
  the function list.
- **Two kinds of tools, two entry points.** `@openseek_tools.call(name,
  arguments)` stays the entry point for the host's own tools (`edit`, `write`,
  `web_search`, …), which are also direct tools. `@mcp.call(server, tool,
  arguments)`, in the SDK's `mcp` package, is the entry point for MCP tools,
  which are never direct.
  Each keeps what only it needs: MCP tools carry an output schema and
  untrusted server metadata; host tools carry approval, concurrency, and
  control flags. `AgentToolDefinition` loses `output_schema` and never gains
  `program_only`.
- **Scripts use the server's own tool names.** The `mcp__<server>__<tool>`
  form, its sanitizing, and collision handling exist only to satisfy the
  provider's function-name rules. A script addresses a tool by its server and
  its original name.
- **The request does not depend on MCP.** The `tools` field and the stored
  system prompt are the same whatever is configured, so the provider prefix
  cache survives every discovery and every configuration change.
- **No loaded-tool state.** Searching is a pure query. Compaction, resume,
  and fork restore nothing. Codex and pi persist a loaded set because their
  models call discovered tools directly; script-only calls make that set
  unnecessary.
- **No server list yet.** Where a list of servers belongs (the system
  prompt, a tool description, or a notice that survives compaction) is
  deferred; see "Server list".
- **No provider capability is required.** DeepSeek's public Anthropic-compatible
  API documents no `defer_loading` or `tool_addition`, and `/chat/completions`
  has neither.

### How others do it

Read on 2026-10-21 (origin heads of each repository):

| | Direct entry | Discovery inside scripts |
|---|---|---|
| Claude Code | `ToolSearch` loads deferred tools, which then become directly callable. | None. |
| codex | `tool_search` (Responses-native) loads deferred namespaces for direct calls. | `ALL_TOOLS` global (`{name, description}`); behind `code_mode_tool_search` (under development, off by default) the same tool is callable as `tools.tool_search({query, limit})` returning `{tools: [{name, description}]}`. |
| pi | Optional `tool_search` extension activates matches for direct calls. | Runtime globals `ALL_TOOLS`, `searchTools()`, `describeTool()`, `describeNamespace()`; MCP tools default to `codemode` exposure (internally `deferred`), callable only from scripts and listed in no description. Servers are listed in an `mcp_servers` system prompt section (4,096 characters, one line per server); when it changes, pi records a system message holding the new section, sent mid-conversation where the model accepts that and folded into the leading prompt (losing the cache) elsewhere. Compaction snapshots the replayed prompt into the compaction entry. |
| deepseek-harness | No search; `tool_addition` / `tool_removal` blocks change direct tools. | None. |

pi's default is the closest: script-only MCP tools, discovery as runtime
functions rather than tools. This plan differs in returning typed records
with raw schemas beside the rendered text, so scripts can select tools by
schema.

### Alternatives considered

| Approach | Not chosen because |
|---|---|
| Append discovered tools to `tools` | Each load invalidates the cache for the whole conversation on `/chat/completions`. |
| MCP tools as `program_only` agent tools behind `@openseek_tools.call` | Puts MCP-only fields on every tool definition and keeps the `mcp__` naming scheme for calls no provider ever sees. |
| `tool_search` as a program-only tool called through `@openseek_tools.call` | Searching becomes a tool call returning text; scripts get no typed catalog. |
| A direct `tool_search` beside `@mcp.search` (variant A) | Kept as the benchmark's comparison: it lets the model look without writing a script and is a visible cue that MCP exists, at the cost of one MCP-specific entry in the function list. |
| Native `defer_loading` + `tool_addition` (deepseek-harness) | Not in DeepSeek's public API. |
| Tool names listed in the prompt (Claude Code) | Grows with tool count and goes stale on resume. |

## The MCP catalog

`mcp/tools` produces a catalog instead of `AgentToolDefinition`s: for each
configured server, its name, whether it connected (and the error when it did
not), its instructions (from `initialize` or `server/discover`), and its tools
as `{name, description, input_schema, output_schema?}` with the server's own
names. It also answers a call by server and tool name, with the behavior the
bridge has today: the 120-second timeout, the JSON-encoded output cap, text
plus `data` (the whole `structuredContent`, only when it fits beside the
text), and images.

Two consumers read it:

- `internal/tool_catalog`, which ranks and renders the catalog. It depends on
  neutral records it owns (`Source`, `Tool`), not on `mcp`, and it is not an
  agent tool, so it does not live under `agent_tool`.
- `agent_tool/ptc`, which routes MCP requests to it. The PTC service takes an
  optional MCP endpoint, a ptc-owned record of functions (call, search, and
  the SDK 0.2.0 name lookup) over typed arguments, so `ptc` does not depend
  on `mcp` either.

MCP calls are not serialized with file edits and request no approval, as
today.

## Search

`@mcp.search(query?, server?, limit?, offset?)`:

- `server` alone lists that server's tools in registration order; neither
  lists every tool. `query` ranks with BM25 (k1 = 1.2, b = 0.75) over each
  tool's name, its description, and its schemas' property names and
  descriptions, collected recursively; both together rank within one server.
  The tokenizer splits names at `_`, `-`, and camelCase boundaries, drops stop
  words, and folds simple plurals. This is the corpus codex and pi use.
- Results are paged by `limit` (default 8) and `offset`.
- No match is an ordinary page with no tools. An unknown `server`, a `limit`
  below 1, and a negative or past-the-end `offset` raise `SearchError`.
- `Catalog::search` takes these as typed, labelled arguments. Decoding the
  wire object is PTC's job: a field of the wrong type makes the request
  malformed, refused before any search, like any other malformed request.

**The page** carries the same tools twice, for two readers:

- `text`, for the model once a script prints it: a heading, each tool with
  its server, name, description, arguments, and result, the paging line, and
  a closing note on the `@mcp.call` form and how shapes read as patterns.
- `tools`, for the script: typed records with the raw JSON Schemas, so it can
  select tools by name or by what they accept, for example every server's
  `health` tool, or every tool whose `input_schema` takes a `query`.

**Rendering.** Both schemas are rendered as the `Json` a script builds and
matches: `{ "repo": String, "page"?: Number, "done"?: True | False }` names
the constructors a pattern uses (`String(s)`, `Number(n, ..)`, `True`), `?`
marks optional fields, and validation keywords follow their type in
parentheses. The rendering covers a whitelist of forms: types,
`properties`/`required`, single-schema `items`, `enum`/`const` (beside a
`type` only), `anyOf`, `oneOf` over disjoint plain types, local `$ref`s
standing alone, and `additionalProperties` that only allows or forbids extra
fields. Anything else, a schema over 400 nodes once references expand, or a
sketch over 2,000 characters is shown as JSON Schema text. The two best
matches carry a compilable example: `@mcp.call(server, tool, …)`
with a value of an allowed type for every required argument (nested objects
included) and a `guard` binding the required result fields as `<field>_`. A
result's shape describes the `data` a script reads when the result carries
it; a result too large to carry `data` beside its text omits it.

**Server instructions.** A search that names a `server` opens with that
server's instructions, whole up to 4,000 characters and marked when cut,
before its tools: that is when the model is about to use the server, which is
what instructions are for. Only the first page (`offset` 0) carries them. A
configured server that failed to connect has no tools; a search that names it
is an ordinary page saying it is unavailable, with the connection error. A
listing of every tool (no arguments, first page) ends with the servers that
did not connect, one line each, so a missing service is not taken as absent.

**Size.** A page holds only the whole tools whose `text` fits 40,000
characters and whose text and records together, JSON-encoded, fit the 64K
characters a PTC reply carries, so a large schema never cuts through an entry
and a reply is never refused. `next_offset` continues the listing.

## Server list

Deferred. The first version shows no list of servers anywhere. The model's
cue is the static prompt: MCP servers may connect external services (chat,
issue trackers, calendars, …); when a task may involve one, or before saying
it cannot do something, run `@mcp.search` from a script, which
without arguments lists every tool and with a `server` shows that server's
instructions or why it is unavailable.

Options for later, each with a cost found so far:

- **System prompt.** Built when the session is created, before the engine
  connects, so it would have to read the configuration on its own or the
  engine would connect before creating the session. Goes stale on resume
  after a configuration change.
- **A tool description** (the `mbtx` tool's, or a direct `tool_search`'s),
  rendered from the engine's MCP registry. Always current; a configuration
  change invalidates the cached prefix once.
- **A notice**, appended when the list differs and restated after
  compaction. Keeps the cache across changes, but depends on how compaction
  carries prompt state ([compaction-state.md](compaction-state.md)).

The benchmark's `announce` (the user names a channel, not a service) and
`negative` (no server can do it) tasks show whether the missing list costs
anything.

## SDK: `moonbitlang/openseek_tools@0.3.0`

The SDK lives in [tools_sdk](../../tools_sdk) but scripts import the published
package, so the new entry points reach scripts only after a release (bump
`tools_sdk/moon.mod`, then dispatch `publish-openseek-tools.yml`). The release
ships before the host switch, which then moves the prompt's imports to 0.3.0.

The module gains a package per kind of tool:

- `moonbitlang/openseek_tools`: the host's tools, unchanged. `call`,
  `CallResult`, `TransportError`.
- `moonbitlang/openseek_tools/mcp`: MCP servers' tools. A script imports it
  as `"moonbitlang/openseek_tools@0.3.0/mcp" @mcp`.
- `moonbitlang/openseek_tools/internal/transport`: the handoff decoding and
  the bounded, never-retried request both packages send. Private to the
  module.

```moonbit
// moonbitlang/openseek_tools/mcp
pub async fn call(
  server : String,
  tool : String,
  arguments : Json,
) -> @openseek_tools.CallResult

pub async fn search(
  query? : String,
  server? : String,
  limit? : Int,
  offset? : Int,
) -> SearchPage raise SearchError

pub struct SearchPage {
  text : String           // the page rendered for the model
  instructions : String?  // the named server's, on a first page
  tools : Array[Tool]
  total : Int
  next_offset : Int?
}

pub struct Tool {
  server : String
  name : String
  description : String
  input_schema : Json
  output_schema : Json?
}
```

- `call` returns the root package's `CallResult`: a tool failure is a value,
  a transport failure raises `TransportError`. The root package owns both
  types; `mcp` depends on it, never the reverse. MCP calls never wait for
  approval.
- Wire: the PTC protocol stays version 1 and the request line stays
  `POST /call`. The body gains two shapes beside the existing
  `{"version": 1, "name", "arguments"}`:
  `{"version": 1, "mcp": {"server", "tool"}, "arguments"}` and
  `{"version": 1, "search": {"query"?, "server"?, "limit"?, "offset"?}}`.
  Both are answered with the existing result envelope
  `{"version": 1, "content", "is_error", "data"?}`. For `mcp`, it is the
  tool's result, as for `name`. For `search`, `content` is the page `text`
  and `data` is `{"tools": [{"server", "name", "description",
  "input_schema", "output_schema"?}], "total", "next_offset"?,
  "instructions"?}`; a refused search (unknown server, an out-of-range
  `limit` or `offset`, a field of the wrong type) is `is_error` with the
  reason in `content` and no `data`.
  An older host answers either with its ordinary error result ("PTC requires
  version=1, name, and arguments") and executes nothing: `@mcp.call` returns
  it as a `CallResult` with `is_error`, and `@mcp.search`, which cannot
  decode a page from it, raises `SearchError` with its text.
- `search` raises `SearchError` for every failure, transport included: a
  search changes nothing, so a script needs no "outcome unknown" distinction
  and may simply run it again.

## Prompt

The "Host tool calls" section of
[default_prompt.mbt.md](../../prompt/default_prompt.mbt.md) imports
`openseek_tools@0.3.0` and its `mcp` package and says:

- MCP servers may connect external services. When a task may involve one, or
  before saying something cannot be done, search the catalog from a script
  with `@mcp.search` and print its `text`.
- Call a tool with `@mcp.call(server, tool, arguments)`. When which
  tools to call depends on the catalog itself (the same check on every
  server, one query to every search tool), work through the page's `tools` in
  the same script.
- The write rule stays: an MCP call that changes something acts on real
  systems, so make each change once, never send a probe call, and verify by
  reading.

If evaluation shows the model avoids or misuses the flow, fix the prompt
rather than restoring direct calls.

A direct call to an `mcp__…` name, as a model may still emit from habit or
from older history, fails as an unknown tool whose message points to
`@mcp.search` and `@mcp.call`.

## Open questions

1. **`@openseek_tools.call("mcp__…")` from SDK 0.2.0 scripts.** On `main`,
   scripts reach MCP tools by their `mcp__` names through `call`. Keeping that
   working needs the exposed-name map the bridge builds today, for one more
   release; dropping it makes such scripts fail with "PTC tool unavailable".
   Proposed: keep the alias, undocumented, and remove it with the next SDK
   release.
2. **Names in `mcp_status`.** The `mcp_status` event (desktop Settings) lists
   tools by their `mcp__` names. Proposed: report the server's own names,
   since nothing calls the `mcp__` form any more.

## Out of scope

- MCP approval. Neither direct nor PTC MCP calls request approval today, and
  this change keeps that.
- A per-server option to keep tools direct. Add it only if a real server needs
  single direct calls.
- A user-written `description` per server in `mcp.json`, shown in a server
  list (pi has one). Add it with the server list, if a server's name does not
  say what it is for.

## Later: scripts reaching servers directly

Worth designing after this lands. A script could talk to an MCP server itself
instead of through the PTC proxy, which removes the proxy's caps and lets a
script use the whole protocol. What has to be solved first:

- **Credentials.** A server's token (a GitHub PAT, an OAuth token) would be
  handed to model-written code, where today it stays in the host.
- **stdio servers.** The host's process is not reachable from a script, and
  starting another copy needs a spawn the mbtx sandbox does not allow, plus a
  cold start per script. Only HTTP servers are candidates.
- **Network policy.** The sandbox would have to allow the server's origin.
- **What the host loses.** The program trace, the nested call cards, and the
  per-run budgets cover only what passes through the proxy.

## Delivery

`#2145` (structured MCP results) is merged and put `output_schema` on
`AgentToolDefinition` ahead of any reader; the restacked series removes it.
Each step leaves `main` working, and each field arrives with its first reader.

0. **SDK 0.3.0** (`tools_sdk` only): the `mcp` package (`call`, `search`,
   `SearchPage`, `Tool`, `SearchError`), the shared `internal/transport`, the
   two request shapes, and their tests against a loopback server. Published
   before step 3 merges.
1. **The search packages**: `internal/bm25`, and `internal/tool_catalog` over
   its own neutral tool record (ranking, paging, size caps, the page text with
   schemas as JSON Schema text, and the records). Removes
   `AgentToolDefinition.output_schema` from `main`; `McpTool.output_schema` in
   `mcp` stays. Nothing uses the packages yet.
2. **MoonBit-shaped schemas**: the `Json`-shaped rendering and the compilable
   examples, in the `@mcp.call` form. Benchmarks put it at a modest
   gain (fewer `Json` misuse errors in scripts), so it stands apart.
3. **The switch.**
   - `mcp/tools` builds the catalog instead of agent tools; the agent's
     registry no longer holds MCP tools.
   - `agent_tool/ptc` routes the `mcp` and `search` request shapes to the
     catalog, records them in the program trace with their server, and keeps
     the 0.2.0 `mcp__` alias (open question 1).
   - The prompt and docs move to 0.3.0 and the two entry points.
   - Delete `MaxTotalMcpTools` and the server/tool skipping it drives. Its
     only reason was the 128-function request limit, which MCP tools no
     longer count against. The `McpToolsCapped` and
     `McpServerSkippedOverCap` events and the `skipped` server state lose
     their producer but stay in the published `openseek_protocol` for now:
     `openseek_tui` matches on them, so removing them is a protocol release
     coordinated with the TUI.
4. **Benchmark** before marking step 3 ready, on the 12-server stub world
   with the catalog tasks (every server's `health`; one query to every search
   tool): the switch against the current stack, and against variant A (a
   direct `tool_search` beside `@mcp.search`). `announce` and `negative` check that
   the model looks for servers with no list to prompt it.
