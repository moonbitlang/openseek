# MoonBit Toolchain Seed Executable Bits

## Goal

Fix macOS package builds that bundle the MoonBit toolchain seed when the
downloaded MoonBit archive contains `bin/*` files without executable bits.

## Accepted Design

- After extracting a staged MoonBit toolchain seed, mark non-directory files in
  the staged `bin` directory as executable before validating the compiler
  version.
- Keep the chmod step inside `desktop/package/internal/moonbit` so every
  platform that uses the shared seed staging helper benefits from the same
  normalization.
- Keep the helper private and small; it is package-time implementation detail,
  not a new public API.
- For macOS distribution signing, recursively scan the staged MoonBit seed and
  sign every Mach-O file before signing the app bundle, so nested tools such as
  `bin/internal/tcc` and dylibs such as `lib/libbinaryen.dylib` satisfy
  notarization.

## Target Files And Surfaces

- `desktop/package/internal/moonbit/toolchain.mbt`
- `desktop/package/macos/main.mbt`

## API And Interface Diff

- No public MoonBit package API should change.
- `desktop/package/internal/moonbit/pkg.generated.mbti` should remain
  unchanged after `moon info`.
- `desktop/package/macos/pkg.generated.mbti` should remain unchanged after
  `moon info`.

## Open Questions

- None. The current archive permissions are not reliable enough to trust during
  packaging, so the package script should normalize them explicitly. The current
  seed also contains nested Mach-O files outside `bin`'s top level, so macOS
  signing should not assume a flat executable directory.

## Next Implementation Step

Add a private seed `bin` executable-bit normalization helper and call it before
`compiler_version(...)` in `stage_moonbit_toolchain_seed`, then make the macOS
seed signing helper recursively sign all staged Mach-O files.

## Validation Plan

- Run `moon -C desktop check package/internal/moonbit --target native`.
- Run `moon -C desktop check package/macos --target native`.
- Run `moon -C desktop info && moon -C desktop fmt`.
- Run the macOS package command with `--sign` and `--notarize` to verify the
  staged `moonc` can execute and signing can continue.
