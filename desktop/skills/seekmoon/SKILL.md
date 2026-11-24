---
name: seekmoon
description: Use the SeekMoon desktop app for browser-use tasks in tabs the user can watch beside the conversation. Read and message the user's other chats, ask the user questions, show workspace files to the user, and attach this session's pull requests and branches.
---
The SeekMoon desktop app offers tools through its MCP server
`seekmoon`, in groups named by the tools' prefix:

- `browser_*`: open and navigate tabs, read pages, click, type, and take
  screenshots in the desktop app's browser, which the user can watch
  beside the conversation.
- `session_*`: list and read the user's other chats, and send one a message
  the user approves.
- `ask_user`: ask the user questions, with suggested answers.
- `preview_open`: show a workspace file (HTML, PDF, an image, an Office
  document, code) to the user.
- `artifacts_*`: list and attach this session's pull requests and branches.

From an mbtx script, find which of them this host offers, and their
arguments, with `@mcp.search(server="seekmoon")`; call one with
`@mcp.call("seekmoon", "<tool>", arguments)`. The server connects on the
first search or call.
