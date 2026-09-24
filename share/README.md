# Bundled resources

This directory is checked in and installed as `share/` beside OpenSeek's `bin/`.
OpenSeek resolves it from its current executable (or loaded Wasm module), without
an environment override or a working-directory fallback. The prompt's
`Bundled resources` field gives the resolved absolute path.

- `doc/moonbit/`: official MoonBit documentation from the upstream markdown build.
- `doc/moonbit.commit`: the exact upstream build commit used for the snapshot.
- `desktop-proton/`: OpenSeek-maintained reference for the Proton CLI workflow,
  moved out of the system prompt and read on demand.
- `examples/`: verified `.mbtx` examples inlined into the system prompt by
  `md_to_mbt_string`; CI type-checks and runs them.
- `frontend-rabbita/`: OpenSeek-maintained reference for MoonBit browser UIs
  and full-stack web applications with Rabbita, read on demand.
- `moongrep/`: OpenSeek-maintained reference for the structural search and
  lint tool, moved out of the system prompt and read on demand.
- `workflow/`: OpenSeek-maintained scripts, packaged for future agent integration.

The documentation comes from https://github.com/moonbitlang/moonbit-docs.
Its original README records the source commit that produced the markdown build.
Keep edits upstream; refresh this snapshot periodically or when updating the
bundled toolchain:

```sh
just update-docs
# Or select a specific upstream markdown-build commit:
just update-docs <40-character-commit>
```

The default resolves the latest `markdown-build` branch to a full commit SHA
before downloading; `doc/moonbit.commit` always records the exact snapshot.
Run from the repository root with `git`, `curl`, and `tar` installed. The command downloads
and validates the new snapshot before replacing `doc/moonbit/`. It preserves the
upstream files except browser presentation assets and upstream ignore rules.
The updater also regenerates the static system prompt's directory layout.
Review and commit the documentation diff, `doc/moonbit.commit`, and generated prompt.
After manually changing resource directories, run `just prompt`.
Packaging copies this checked-in tree directly into the application, independently
of the MoonBit toolchain cache. It does not download documentation.

A raw `moon build` output has no bundled resources unless `../share` exists
relative to its executable directory. It can still run, but bundled documentation
and `@builtin/` workflows are unavailable.
