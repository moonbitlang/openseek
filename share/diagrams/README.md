# Inline diagrams in SeekMoon

Write a complete fenced `diago` block in your Markdown response to show a diagram
directly to the user. `d2` is an alias for the same renderer. No installation,
image file, or rendering command is needed. During streaming, the source remains
visible until the closing fence arrives; invalid diagrams remain code blocks.

Use diagrams when connections or grouping explain something more clearly than
prose: workflows, architecture, dependencies, and ownership. Keep small diagrams
focused, and explain their meaning in the surrounding text. Use tables or an
appropriate plotting tool for quantitative charts.

## Basic syntax

Diago uses D2-style syntax. The examples below are verified against the
SeekMoon renderer's current dependency, `moonbit-community/diago@0.4.0`.
Use these forms as a starting point rather than assuming all D2 features are
available. Mermaid syntax belongs in a separate `mermaid` fence.

- `id: Label` defines a node; use short stable IDs and readable labels.
- `a -> b: Label` draws a directed connection. `a -- b` is undirected.
- `direction: right` lays out left to right; `down` lays out top to bottom.
- Braces group node attributes or contain child nodes. Refer to a child as
  `group.child` when connecting across groups.
- `shape: diamond` marks a decision; `shape: cylinder` represents a data store.
- Let the renderer place nodes and choose default styling. Start with a small
  set of nodes and add detail only when it helps the explanation.

## Workflow with a decision

Label branches so the reader can follow each outcome.

```diago
direction: down
request: Download file
cached: Complete cached bytes? {
  shape: diamond
}
validate: Check file version
fetch: Fetch original bytes
save: Save to Downloads
request -> cached
cached -> validate: Yes
cached -> fetch: No
validate -> save: Unchanged
validate -> fetch: Changed
fetch -> save
```

## System architecture

Label connections with the operation or data they carry.

```diago
direction: right
client: Desktop app
api: Cloud API
sessions: Session store {
  shape: cylinder
}
files: File store {
  shape: cylinder
}
client -> api: HTTPS
api -> sessions: Conversation history
api -> files: Original file bytes
```

## Module dependencies

State what an arrow means; here, the source imports the destination.

```diago
direction: down
app: App
editor: Editor
search: Search
model: Shared model
app -> editor
app -> search
editor -> model
search -> model
```

## Groups and relationships

Use containers to distinguish boundaries and dotted IDs for cross-group links.

```diago
direction: right
desktop: Desktop {
  panel: File panel
  cache: Preview cache
  panel -> cache: Read original bytes
}
cloud: Cloud {
  api: Cloud API
  storage: File store {
    shape: cylinder
  }
  api -> storage: Read
}
desktop.panel -> cloud.api: Download
desktop.cache -- cloud.storage: Same file version
```
