# Bundled workflows

These OpenSeek scripts ship in the toolchain payload's `share/workflow/`,
alongside the official documentation in `share/doc/moonbit/`.
`OPENSEEK_REFERENCES` points to `share/`.

The scripts are packaged for future integration. The agent does not yet
advertise or automatically select them, and no filename tool API is added here.

- `check.mbtx` runs `moon check`.
- `test.mbtx` runs `moon test` without updating snapshots.
- `check-test.mbtx` runs check then test, stopping on the first failure.
- `info-fmt.mbtx` runs info then fmt, modifying generated interfaces and formatting.
- `check-json.mbtx` relays `moon check --output-json` diagnostics without filtering.

The commands use project/toolchain target defaults, stream
output, and fail when the underlying command fails. Follow repository-specific
validation commands when they differ from these defaults.

The bundled copies are read-only installation resources.
