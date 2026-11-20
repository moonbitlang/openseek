# Diago / D2: architecture and dependencies

Use a `diago` or `d2` fence; both use the same bundled Diago renderer. Diago
supports a subset of D2, so start with basic nodes, edges, and containers rather
than relying on syntax from a different D2 renderer.

- `id: Label` defines a node; `a -> b: Label` is a directed connection and
  `a -- b` is undirected. For imports, state that arrows point from importer to
  dependency. For data flow, label arrows with the operation or data they carry.
- `direction: right` lays out left to right; `down` lays out top to bottom.
- Braces hold attributes or child nodes. Use containers for real boundaries,
  such as an owning service, and dotted IDs to connect across them.

## Architecture across a boundary

```diago
direction: right
desktop: Desktop {
  panel: File panel
}
cloud: Cloud {
  api: Cloud API
  storage: File store {
    shape: cylinder
  }
  api -> storage: Read original bytes
}
desktop.panel -> cloud.api: Request download
```
