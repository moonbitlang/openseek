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

- **Discovery is a library call, not a tool, and it runs in the script.**
  `@mcp.search` downloads the catalog from the host once per script, ranks it
  in the SDK, and returns both a rendered page for the model to read and
  typed records for the script to compute with. Nothing about MCP appears in
  the function list, and the engine's MCP host only lists the catalog and
  forwards calls.
- **MCP has its own host beside PTC.** Scripts reach MCP servers through a
  loopback service of its own (`mcp/host`, handed over as `OPENSEEK_MCP`), so
  PTC stays the host's tool protocol and knows nothing of MCP.
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
| Search in the host, `@mcp.search` sending the query | A page then crosses the transport, so the catalog has to fit text and records together into one 64K reply, which ties ranking and rendering to a transport limit; and every improvement to ranking or rendering needs a host release. |
| MCP requests as new shapes of the PTC protocol | PTC has to learn MCP's calls, its catalog, and the 0.2.0 names, and every MCP change touches the host's tool protocol. A host of its own keeps the two apart; what it gives up is the program trace (below). |
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

The host hands scripts the catalog as a flat list of items, each server
followed by its tools, in configuration order:

- a server: `{"server", "instructions"?, "error"?}`, with `error` when it is
  unavailable (it failed to connect, or its connection was lost);
- a tool: `{"server", "tool": {"name", "description", "input_schema",
  "output_schema"?}}`.

Server-supplied parts are capped where the items are built, so any one item
fits a reply: a description at 1,024 characters (cut and marked), an
arguments schema that is not an object or is over 16,384 characters becomes
the open object schema, an oversized result schema is dropped, and
instructions and errors are cut at 4,000 characters.

## The MCP host

`mcp/host` is a loopback HTTP service the engine starts once per session,
beside PTC, over the servers it connected from the `--mcp-config` files. It
lives as long as the session's connections do: across turns, not across a
resume, which connects again. A session with no configured server starts no
host.

- **Handoff.** `OPENSEEK_MCP` = `{"version": 1, "url", "token"}`, passed to
  every script mbtx runs, as `OPENSEEK_PTC` is. One bearer token per
  session: the host does not know which script is calling. A run without
  an MCP host gets `{"version": 1, "available": false}` in its place, as
  for PTC, so an engine started under a hosted snippet never hands its
  scripts the parent session's servers.
- **Framing.** The same bounded single-request HTTP reader as PTC (`POST
  /call`, headers within 8 KiB, a body within 64 KiB, no `Origin`), shared
  through `internal/loopback_http`.
- **Requests.** `{"version": 1, "list": {"cursor"?}}` and
  `{"version": 1, "call": {"server", "tool", "arguments"}}`, answered with
  PTC's envelope `{"version": 1, "content", "is_error", "data"?}`.
- **Listing.** The host owns its reply limit (64K characters): it packs whole
  catalog items into each `list` reply and returns `next_cursor` for the
  rest.
- **Calls** go to the named server with the bridge's behavior (timeout,
  output cap, `data`). They request no approval and take no lock: like a
  child process a script spawns, an MCP call runs beside the agent's file
  tools rather than inside the file gate.
- **Stopping.** A connection carries one request, so a script that closes
  its connection before the reply has been stopped (a cancelled turn, a
  stopped job). The host then cancels the call, and the MCP client tells
  the server, as stopping a script cancels its PTC calls.
- **Images.** A reply is JSON for the script, so the host cannot hand an
  image to the model. It writes each image in a result to the session's
  scratch directory (`mcp-images/`, readable only by the user), puts each
  path in the text where the image was, and lists them in the reply's
  `images`. A script shows one to the model with the `read_image` host tool,
  as pi's codemode shows one with `image()`. Without a scratch directory the
  text says the image was dropped.
- **No trace.** PTC's program trace records host tool calls; MCP calls and
  listings appear in no trace, only in what the script prints.

## Search

`@mcp.search(query?, server?, limit?, offset?)` runs in the SDK over the
downloaded catalog. The first search in a script downloads it (one `list`
request per reply's worth of items) and later searches reuse it: the host's
catalog changes only when a connection is lost, and a call to a lost server
says so.

- `server` alone lists that server's tools in registration order; neither
  lists every tool. `query` ranks with BM25 (k1 = 1.2, b = 0.75) over each
  tool's server, name, description, and its schemas' property names and
  descriptions, collected recursively; both together rank within one server.
  The tokenizer splits names at `_`, `-`, and camelCase boundaries, drops stop
  words, and folds simple plurals. This is the corpus codex and pi use.
- Results are paged by `limit` (default 8) and `offset`; a blank string is
  the same as leaving `query` or `server` out.
- No match is an ordinary page with no tools. An unknown `server`, a `limit`
  below 1, a negative or past-the-end `offset`, and a failure to download the
  catalog raise `SearchError`.

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
server's instructions before its tools: that is when the model is about to
use the server, which is what instructions are for. Only the first page
(`offset` 0) carries them. A configured server that is unavailable has no
tools; a search that names it is an ordinary page saying so, with the error.
A listing of every tool (no arguments, first page) ends with the servers that
are unavailable, one line each, so a missing service is not taken as absent.

**Size.** A page's `text` holds only whole tools within 40,000 characters,
what a printed page should cost the model's context; an entry too large for
what is left drops its example and notes, then its shapes, before the page
gives up on it. `next_offset` continues the listing. The page never crosses
the transport, so no transport limit applies to it.

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
  the bounded, never-retried request both packages send, each to its own
  host. Private to the module.
- `moonbitlang/openseek_tools/internal/bm25` and
  `moonbitlang/openseek_tools/internal/catalog`: the ranking, paging, and
  rendering behind `search`, over the downloaded items. Private to the
  module.

```moonbit
// moonbitlang/openseek_tools/mcp
pub async fn call(
  server : String,
  tool : String,
  arguments : Json,
) -> CallResult

pub async fn search(
  query? : String,
  server? : String,
  limit? : Int,
  offset? : Int,
) -> SearchPage raise SearchError

pub struct CallResult {
  content : String
  is_error : Bool
  data : Json?
  images : Array[String]  // files holding the result's images
}

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

- `call` returns a tool failure as a value with `is_error`; a transport
  failure raises the root package's `TransportError`. `mcp` depends on the
  root package, never the reverse. MCP calls never wait for approval.
- Wire: `@openseek_tools.call` keeps sending PTC's
  `{"version": 1, "name", "arguments"}` to `OPENSEEK_PTC`; the `mcp` package
  sends the two requests in "The MCP host" to `OPENSEEK_MCP`. For `list`,
  `content` is a one-line summary and `data` is
  `{"items": [...], "next_cursor"?}` with the items described in "The MCP
  catalog", as many whole ones as fit the reply; `next_cursor` is present
  while items remain. A cursor of the wrong type or past the end is
  `is_error`. A call's reply adds `images`, the paths of its saved images,
  when it has any. A script run with no `OPENSEEK_MCP` (an older host, or a
  session with no MCP server) gets a `TransportError` from `call` and a
  `SearchError` from `search`, saying no MCP server is configured.
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
- A result's images are files listed in `images`; show one to the model by
  calling `read_image` with its path.
- The write rule stays: an MCP call that changes something acts on real
  systems, so make each change once, never send a probe call, and verify by
  reading.

If evaluation shows the model avoids or misuses the flow, fix the prompt
rather than restoring direct calls.

A direct call to an `mcp__…` name, as a model may still emit from habit or
from older history, fails as an unknown tool whose message points to
`@mcp.search` and `@mcp.call`.

## Compatibility decisions

1. **`@openseek_tools.call("mcp__…")` from SDK 0.2.0 scripts** stops working:
   PTC has no MCP tools to map the name to, and keeping the alias would bring
   MCP back into PTC. Scripts are written per task, so the cost is a script
   saved from before the switch; it fails as an unavailable tool.
2. **Names in `mcp_status`** are the servers' own, since nothing calls the
   `mcp__` form any more; `mcp_tools_registered` lists `<server>/<tool>`.

## Out of scope

- MCP approval. Neither direct nor PTC MCP calls request approval today, and
  this change keeps that.
- Starting servers from a script (`@mcp.start`). The host would spawn a
  process outside the mbtx sandbox for the script, so it may only be offered
  to a run that already holds an approved escalation: mbtx would hand such a
  run a token that can start servers, and every other run one that can only
  list and call. A started server would live, like a configured one, until
  the session ends.
- A per-server option to keep tools direct. Add it only if a real server needs
  single direct calls.
- A user-written `description` per server in `mcp.json`, shown in a server
  list (pi has one). Add it with the server list, if a server's name does not
  say what it is for.

## Later: scripts reaching servers directly

Worth designing after this lands. A script could talk to an MCP server itself
instead of through the MCP host, which removes the proxy's caps and lets a
script use the whole protocol. What has to be solved first:

- **Credentials.** A server's token (a GitHub PAT, an OAuth token) would be
  handed to model-written code, where today it stays in the host.
- **stdio servers.** The host's process is not reachable from a script, and
  starting another copy needs a spawn the mbtx sandbox does not allow, plus a
  cold start per script. Only HTTP servers are candidates.
- **Network policy.** The sandbox would have to allow the server's origin.
- **What the host loses.** The output cap and the saved images cover only
  what passes through the host.

## Delivery

`#2145` (structured MCP results) is merged and put `output_schema` on
`AgentToolDefinition` ahead of any reader; the host switch removes it.
Each step leaves `main` working, and each field arrives with its first reader.

1. **SDK 0.3.0** (`tools_sdk` only): the `mcp` package (`call`, `search`,
   `SearchPage`, `Tool`, `SearchError`), the shared `internal/transport`,
   `internal/bm25` and `internal/catalog` (ranking, paging, the
   MoonBit-shaped rendering and examples), the `OPENSEEK_MCP` requests, and their
   tests against a loopback server. Published before step 2 merges. An older
   host hands scripts no `OPENSEEK_MCP`, so publishing first changes nothing
   for it.
2. **The host switch.**
   - `mcp/tools` builds the catalog instead of agent tools; the agent's
     registry no longer holds MCP tools, and `AgentToolDefinition` loses
     `output_schema`.
   - `mcp/host` serves the catalog and calls on a loopback port of its own;
     the engine starts it beside PTC and mbtx hands scripts its
     `OPENSEEK_MCP`. PTC's request reader moves to `internal/loopback_http`
     for both; PTC itself does not change.
   - The prompt and docs move to 0.3.0 and the two entry points.
   - Delete `MaxTotalMcpTools` and the server/tool skipping it drives. Its
     only reason was the 128-function request limit, which MCP tools no
     longer count against. The `McpToolsCapped` and
     `McpServerSkippedOverCap` events and the `skipped` server state lose
     their producer but stay in the published `openseek_protocol` for now:
     `openseek_tui` matches on them, so removing them is a protocol release
     coordinated with the TUI.
3. **Benchmark** before marking step 2 ready, on the 12-server stub world
   with the catalog tasks (every server's `health`; one query to every search
   tool): the switch against `main`, and against variant A (a direct
   `tool_search` beside `@mcp.search`). `announce` and `negative` check that
   the model looks for servers with no list to prompt it.
