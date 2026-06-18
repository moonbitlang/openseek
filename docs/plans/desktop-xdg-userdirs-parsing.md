# Desktop XDG User Dirs Parsing

## Goal

Fix parsing of `XDG_DOCUMENTS_DIR` in
`${XDG_CONFIG_HOME:-~/.config}/user-dirs.dirs` so malformed values do not become
agent workspace paths and `$HOME` expansion matches `xdg-user-dirs-update`
output.

## Accepted Design

- Keep the existing Windows/non-Windows split from the `@path.Path` refactor.
- Add package-private parsing helpers in `desktop/internal/userdirs`.
- Parse one `XDG_DOCUMENTS_DIR=` assignment at a time:
  - allow an optional matched pair of outer double quotes;
  - reject unmatched or embedded quote characters instead of using
    `trim(chars="\"")`;
  - accept `$HOME` for `xdg-user-dirs-update` compatibility, plus `$HOME/...`
    and absolute paths;
  - reject `$HOMEfoo`, relative paths, and malformed values.
- Keep `documents_dir()` as the only public userdirs API.

## Target Files And Surfaces

- `desktop/internal/userdirs/documents.mbt`
- `desktop/internal/userdirs/documents_wbtest.mbt`
- `desktop/internal/userdirs/userdirs_native.c` comment cleanup if needed
- generated interface only if `moon info` changes it

## API And Interface Diff

- No intended public API change: `documents_dir() -> String?` remains the only
  exported userdirs value.

## Open Questions

- None. This does not address unrelated host cwd cleanup or bundled MoonBit
  work.

## Next Implementation Step

Replace the ad hoc quote trimming / `$HOME` prefix check with parser helpers and
add parser-focused white-box tests.

## Validation Plan

- `moon -C desktop fmt internal/userdirs/documents.mbt internal/userdirs/documents_wbtest.mbt`
- `moon -C desktop test internal/userdirs --target native`
- `moon -C desktop check --target native`
- `moon -C desktop info`
