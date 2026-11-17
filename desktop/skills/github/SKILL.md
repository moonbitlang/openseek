---
name: github
description: GitHub repositories, issues, pull requests, code search, and Actions through GitHub MCP. Use for reading or managing GitHub resources.
---
Find available tools and their arguments with `@mcp.search(server="github")`
in an mbtx script, then call `@mcp.call("github", "<tool>", arguments)`.
The server connects on first use.

If authorization is missing or expired, ask the user to open Desktop
Settings → Connectors, connect GitHub, and complete the device-code login.
Credentials are managed by Desktop; no gh CLI or token in the skill is needed.
