Discovering and using external services through MCP.

# MCP services

MCP servers can connect external services: chat, issue trackers, calendars, documents, and more. Their tools are not in your function list, and `@openseek_tools.call` does not reach them; a script uses the SDK's `mcp` package. When a task may involve such a service, or before concluding that something cannot be done, search the catalog and print the page:

```mbtx
---
import {
  "moonbitlang/openseek_tools@0.4.2/mcp" @mcp,
}
---

fn main {
  // No arguments list every tool; `query` ranks by keywords; `server` lists
  // one server's tools after its instructions, or says why it is unavailable.
  let page = @mcp.search(query="list open issues")
  println(page.text)
}
```

After the search script returns, read the tool descriptions and schemas, select a tool for the task, and construct its arguments in the next script. Call it with `@mcp.call(server, tool, arguments)`. Check `is_error` first, then match `data : Json?` against the discovered output schema and print only the fields or summary needed. For example, if discovery showed a `tracker` server with `list_issues`, a `repo` argument, and an `issues` result array:

```mbtx
---
import {
  "moonbitlang/openseek_tools@0.4.2/mcp" @mcp,
}
---

fn main {
  let result = @mcp.call("tracker", "list_issues", { "repo": "alpha" })
  if result.is_error { fail(result.content) }
  guard result.data is Some({ "issues": Array(issues), .. }) else {
    fail("Expected structured issues. Tool text: \{result.content}")
  }
  println("Issues on this page: \{issues.length()}")
}
```

`data` comes from the server's `structuredContent`; `content` renders its content blocks as text. A tool can return either or both. `data` is absent when the server supplies no structured result or it exceeds the reply budget. Use `content` for text results. For a read that needs structured data, narrow an oversized query or reduce its page size. Images are saved as files listed in `images`; pass a path to `@openseek_tools.call("image", { "path": path })` to view one. To apply a known operation across catalog entries, such as the same check on every server, iterate over `page.tools` in one script. Each record has `server`, `name`, `description`, `input_schema`, and `output_schema`. A page holds a limited number of tools; its `next_offset` continues the listing.

An MCP call that changes something (posts, creates, updates, deletes) acts on real systems: make each intended change once and treat its successful result as the outcome. Never send a test or probe call to learn how a tool behaves, and do not repeat a change to verify it; read state with a reading tool when you need to check it.
