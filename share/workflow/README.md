# Bundled workflows

These OpenSeek scripts ship in the toolchain payload's `share/workflow/`,
alongside the official documentation in `share/doc/moonbit/`.
`OPENSEEK_REFERENCES` points to `share/`; the engine's environment prompt gives
this resource root's absolute path.

- `check.mbtx` runs `moon check`.
- `test.mbtx` runs `moon test` without updating snapshots.
- `check-test.mbtx` runs check then test, stopping on the first failure.
- `info-fmt.mbtx` runs info then fmt, modifying generated interfaces and formatting.
- `check-json.mbtx` relays `moon check --output-json` diagnostics without filtering.

Call `mbtx(filename="@builtin/check.mbtx")` (or another bundled name) and omit `source`. No file
creation is needed. `cwd` selects the module to check or test, defaulting to
the workspace. The commands use project/toolchain target defaults, stream
output, and fail when the underlying command fails. Follow repository-specific
validation commands when they differ from these defaults.

Scripts use the ordinary mbtx sandbox and approval path. Read them with the
file tools to inspect their behavior; save a customized copy in the workspace
when needed. The bundled copies are installation resources and should not be
edited. `@builtin/` resolves under `OPENSEEK_REFERENCES/workflow/` and refuses
escaping paths. Ordinary names such as `check.mbtx` resolve from the workspace.
Missing bundled names do not fall back to workspace files. Other `@namespace/`
prefixes are reserved and currently rejected. To customize a script, save the
modified source with an ordinary workspace filename; never send source with
`@builtin/`.
