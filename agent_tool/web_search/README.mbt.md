# Web Search Tool

`web_search` searches the web for current information and returns a bounded,
citeable source list. The model passes one `query` string; the result is a
markdown list of sources (`- [title](url) — snippet (published)`), a
refine-the-query note when the result cap dropped sources, and a standing
instruction to cite the relevant URLs as markdown links.

## Design Rationale

The backend is **DeepSeek's own native search**, not a third-party search API:
one Messages call against DeepSeek's Anthropic-compatible endpoint
(`https://api.deepseek.com/anthropic/v1/messages`) carrying the
`web_search_20250305` server tool. Each search costs an auxiliary model turn,
but returns structured `web_search_tool_result` blocks — and absence of those
blocks is reported as an error rather than falling back to scraping the
model's prose. The design (and the block-walking, citation-joining, URL-dedup
mapping) is a port of the DeepSeek provider in the dsh harness's web
capability seam.

Only the **API key** is shared with the agent's own chat client. The endpoint
base is deliberately separate from `--api-url`: that flag names a
chat-completions-compatible proxy, which need not expose the Anthropic-format
`/messages` route this tool requires.

The searched sources arrive in two pieces that the tool joins by URL: the
citeable items (`url`, `title`, `page_age`) live in `web_search_tool_result`
blocks, while the snippet for a URL is the `cited_text` of a `text` block's
citation entry. Sources are deduped by URL (a `max_uses > 1` request can
surface the same URL across searches) and cut to a consumer-owned result cap
(default 8) — the model just asks a question; the product controls how much
context comes back.

Failure is graceful by contract: provider errors, timeouts, and malformed
arguments come back as `is_error` tool results the model can react to — a
failed search never breaks the turn.

## Registration

The tool needs a DeepSeek API key, so it is registered through the
`extra_tools` seam in `internal/openseek` rather than the standard registry: a
DeepSeek-model run reuses the turn's own key, any other provider needs the
dedicated `--deepseek-api-key`/`$DEEPSEEK` credential, and a run with neither
simply does not expose the tool.
