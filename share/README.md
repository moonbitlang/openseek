# Bundled resources

Packaging copies this checked-in tree to `share/` beside the application's `bin/`;
it does not download resources.

The official MoonBit documentation is a snapshot of
[moonbitlang/moonbit-docs](https://github.com/moonbitlang/moonbit-docs).
Make documentation changes upstream, then refresh from the repository root
with `git`, `curl`, and `tar` installed:

```bash
just update-docs
```

To select a specific upstream `markdown-build` commit:

```bash
just update-docs <40-character-commit>
```

The default uses the latest `markdown-build` commit; `doc/moonbit.commit` records
the exact snapshot. Review and commit the documentation changes, that commit
record, and any generated prompt changes produced by the updater.
