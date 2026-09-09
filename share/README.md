# Bundled resources

This directory is checked in and copied into the packaged toolchain's `share/`.
`OPENSEEK_REFERENCES` points to that installed copy.

- `doc/moonbit/`: official MoonBit documentation from the upstream markdown build.
- `doc/moonbit.commit`: the exact upstream build commit used for the snapshot.
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
Packaging reads this checked-in tree without downloading documentation; its
content hash invalidates the prepared resource cache when any file changes.
