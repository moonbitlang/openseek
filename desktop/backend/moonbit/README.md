# Working-host resources and MoonBit selection

An embedding host passes `HostResources` to `ApiState`. The API gives its
`moonbit` selection to both the engine actor and host operations. Language
commands, IDE requests, terminals, semantic search, pattern repair, and
scheduled engine runs therefore use the working host's selection.

Desktop starts with `desktop_resources(resources)`. This preserves discovery
of the seed next to the packaged engine, bundled search tools, and visualizer
assets. Missing visualizer files fail at export time, without preventing the
rest of the host from starting. `None` for a search tool means unavailable;
operations do not reinterpret it as a request to search PATH.

Other embedders can start with `HostResources::from_path()` and override the
fields they own. This explicitly selects external tools and has no visualizer
assets. `moonbit` has three policies:

- `DesktopBundle`: discover the desktop seed relative to the engine; search
  external installations only when no seed was found.
- `External`: search absolute PATH entries, then `~/.moon/bin`.
- `Bundled`: prepare an explicitly selected seed. Use `bundled_source` to
  validate its absolute directory, version marker, and platform against the
  working host before constructing the API. Handle `None` as an absent or empty
  marker; invalid selections and filesystem errors still propagate as errors. Explicit seeds support
  `linux-x64`, `linux-arm64`, and `macos-arm64`; desktop discovery retains its
  existing Windows support.

A selected seed requires a writable runtime directory. Its prepared payload
lives at `runtime/toolchains/moonbit/<platform>`, regardless of the seed
directory's basename. Preparation keeps the existing in-process semaphore and
cross-process file lock. A matching version stamp reuses the payload; a seed
version change rebuilds it. Embedders must assign different version markers to
different seed contents, and use separate runtime directories for independently
versioned hosts.

Failure to prepare an explicit or discovered seed fails the operation; it does
not silently choose another installation. The selected `bin` directory is
prepended to child PATH. `MOON_HOME` remains untouched because it owns registry
credentials and caches, not compiler selection.

Semantic search uses the selected toolchain's `moonx` when configured with a
`moonx` command, and keeps the pinned moongrep package arguments. SDK payloads
without the installer's alias gain a `moonx` copy beside `moon`, under the same
payload locks. A standalone moongrep executable is used directly.

This API is independent of transport. SSH launch flags, remote installation,
daemon lifetime, and service/window separation are separate changes.
