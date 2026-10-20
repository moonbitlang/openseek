# MCP tool search over programmatic tool calls

## Problem

Every request carries every MCP tool's description and schema in the `tools`
field. The cost grows with each configured server, and the provider limit of
128 function definitions forces `MaxTotalMcpTools = 100`
([tools.mbt](../../mcp/tools/tools.mbt)), which silently drops tools beyond the
budget.

## Decision

MCP tools leave the model's function list. They stay registered as program
tools, so a PTC script calls them through `@tools.call("mcp__…", arguments)`
exactly as it does today. A new direct tool, `tool_search`, tells the model
which MCP tools exist and what arguments they take.

- **The `tools` field never changes during an engine's life.** It holds the
  built-ins and `tool_search`. Loading an MCP tool changes nothing in the
  request, so the provider prefix cache survives every discovery.
- **No loaded-tool state.** `tool_search` is a pure query. Compaction, resume,
  and fork restore nothing. Codex and pi persist a loaded set because their
  models call discovered tools directly; PTC-only calls make that set
  unnecessary.
- **The system prompt does not change.** It is fixed at session creation and
  stored with the session, while the MCP tool set belongs to each engine. A
  tool list in the stored prompt would go stale on resume.
- **No provider capability is required.** DeepSeek's public Anthropic-compatible
  API documents no `defer_loading` or `tool_addition`, and `/chat/completions`
  has neither.

### Alternatives considered

| Approach | Rejected because |
|---|---|
| Append discovered tools to `tools` | Each load invalidates the cache for the whole conversation on `/chat/completions`. |
| `call_tool(name, arguments)` proxy | Equivalent to a weaker PTC, which already exists. |
| Native `defer_loading` + `tool_addition` (deepseek-harness) | Not in DeepSeek's public API. |
| Tool names listed in the prompt (Claude Code) | Grows with tool count and goes stale on resume. Server-level listing keeps the discovery cue at a fraction of the size. |

References read on 2026-10-20: codex `codex-rs/core/src/tools/handlers/tool_search.rs`,
pi `packages/durable/src/tool-search/tool-search.ts`, deepseek-harness
`.agents/notes/implemented/architecture/2026-09-20-dynamic-tool-updates.md`.

## `tool_search`

```json
{
  "query": "string, optional: keywords to rank tools by",
  "server": "string, optional: restrict results to one MCP server",
  "limit": "integer, optional, default 8",
  "offset": "integer, optional, default 0: skip this many results"
}
```

At least one of `query` and `server` is required. `server` alone lists that
server's tools in registration order. `query` ranks with BM25 (k1 = 1.2,
b = 0.75) over each tool's name, its description, and its schema's property
names and descriptions, collected recursively; both together rank within one
server. The tokenizer splits names at `_`, `-`, and camelCase boundaries, drops
stop words, and folds simple plurals. This is the corpus codex and pi use.

**Description.** The description is built once per engine from the connected
servers. It names each server with its tool count and states that MCP tools are
callable only from PTC scripts. Server descriptions come from the MCP
`initialize` result's `instructions`, truncated. This server list is the model's
only cue that a capability exists, so it is required. The listing is stable for
the engine's life, so it never invalidates the cache mid-session.

**Result.** For each match, the result gives the exact exposed name, the
description, the JSON Schema of the arguments, and the server's
`outputSchema` (MCP 2025-06-18) when declared, which describes the `data` a
script reads. The footer recalls the `@openseek_tools.call(name, arguments)`
form. Rendering the schemas as the MoonBit `Json` a script matches, with
examples, is a separate step (below).

Results are paged with `limit` and `offset`, and a page holds only the whole
entries that fit 40,000 characters, below the agent loop's per-result clamp,
so large schemas never cut through an entry; the footer names the next
`offset`. No match is an ordinary result that names the servers. An unknown
`server` and invalid arguments are error results.

`tool_search` is a direct tool and is not program-callable in v1.

## Calls to MCP names outside PTC

A direct call whose name is an MCP tool fails with an error that points to
`@openseek_tools.call` in an mbtx script, not with an unknown-tool error.

## Change notice

The `tool_search` description always reflects the current engine. History can
still mention tools from an earlier engine: a resumed session whose `mcp.json`
changed may hold calls to tools that no longer exist. When the server set
differs from the one last recorded in the session, the engine appends one notice
before the first turn it runs. The notice gives the diff at server level only,
for example: "`calendar` connected (23 tools); `foo` is gone".

This needs the last-seen server set in the durable log. `RuntimeNotice` is
plain text, so the notice requires a structured session item or field. That is
a session format change, so it ships as a separate PR. Evaluate it after the first PR lands:
the always-current description may be enough.

## Prompt

The "Host tool calls" section of
[default_prompt.mbt.md](../../prompt/default_prompt.mbt.md) changes from
"use … its advertised arguments" to "find MCP tools and their arguments with
`tool_search`, then call them from a script". If evaluation shows the model
avoids or misuses the flow, fix the prompt rather than restoring direct calls.
The section also says that an MCP call which changes something acts on real
systems: make each change once, never send a probe call, and verify by
reading. Scripts made the model more willing to "try" a write, which a direct
call did not show.

## Out of scope

- MCP approval. Neither direct nor PTC MCP calls request approval today, and
  this change keeps that.
- Making `tool_search` program-callable.
- A per-server option to keep tools direct. Add it only if a real server needs
  single direct calls.

## Delivery

Stacked PRs, each leaving `main` working:

1. **Structured MCP results for scripts.** Scripts already call MCP tools
   through PTC, so this stands alone.
   - A result's `structuredContent` reaches scripts as `data`, whole and only
     when it fits beside the text (which a direct call's model reads and which
     renders it too), and a declared `outputSchema` rides on the tool
     definition as `output_schema`.
   - MCP results are capped by their JSON-encoded length rather than their
     character count, so an accepted result always fits the PTC reply limit
     (64K characters serialized) instead of turning into an error after the
     call already ran.
2. **The search packages** (this plan): `internal/bm25` with the ranking and
   `agent_tool/tool_search` with the description, ranking, paging, and size
   caps, showing schemas as JSON Schema text. Nothing uses them yet.
3. **MoonBit-shaped schemas.** Show a schema as the `Json` a script builds and
   matches (`{ "repo": String, "done"?: True | False }`), with a compilable
   example on the best matches, for a whitelist of schema forms; anything
   else stays JSON Schema text. Benchmarks put it at a modest gain (fewer
   `Json` misuse errors in scripts), so it stands apart from the search.
4. **The switch.**
   - A `program_only` flag on `AgentToolDefinition`, beside `program_callable`
     and `control`: `function_tools` leaves such tools out, a direct call gets
     the redirecting error, and `program_tools` offers them as ordinary
     entries. The MCP bridge sets it, so the registry wiring is unchanged.
   - `tool_search` is wired in `build_extra_tools`, with each server's
     `initialize` instructions; the prompt and docs send the model through it.
   - Delete `MaxTotalMcpTools` and the server/tool skipping it drives. Its
     only reason was the 128-function request limit, which program-only tools
     no longer count against. The `McpToolsCapped` and
     `McpServerSkippedOverCap` events and the `skipped` server state lose
     their producer but stay in the published `openseek_protocol` for now:
     `openseek_tui` matches on them, so removing them is a protocol release
     coordinated with the TUI.

Follow-up PR, **change notice** (optional, see above): add a structured
last-seen server set to the session and append the diff notice at engine start.
