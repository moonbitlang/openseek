# agent_tool/internal/manifest_path

Four predicates that answer "is this path a MoonBit manifest?" — the shared
vocabulary behind the write tools' manifest guards. `internal/manifest_error`
uses them to reject known-bad manifest rewrites before `edit`, `multi_edit`, and
`write` touch the file; `internal/auto_check` uses them to decide which paths
deserve a follow-up `moon check`.

Every function is a pure string operation. Nothing here opens, stats, or
resolves anything on disk, so a path that does not exist classifies exactly like
one that does.

## The contract

- **Backslashes are separators.** Input is normalized `\` → `/` first, so a
  Windows path from a tool call classifies the same as its POSIX form and needs
  no pre-cleaning.
- **Matching is case-sensitive**, on every platform.
- **`.` and `..` are not interpreted.** These are name tests, not containment
  tests; normalize first if that matters.
- **Basename or full path both work.** A bare `moon.mod` classifies the same as
  `packages/demo/moon.mod`.

## The three manifest predicates

`is_moon_mod_path`, `is_moon_mod_json_path`, and `is_moon_pkg_path` are anchored
at a separator: the match is either the whole path or a complete final
component. That anchoring is the point — it is what keeps a file merely *named*
like a manifest from being treated as one.

```mbt check
///|
test "manifest predicates match a whole final component" {
  inspect(@manifest_path.is_moon_mod_path("moon.mod"), content="true")
  inspect(
    @manifest_path.is_moon_mod_path("packages/demo/moon.mod"),
    content="true",
  )
  // Windows input classifies identically.
  inspect(
    @manifest_path.is_moon_mod_path("packages\\demo\\moon.mod"),
    content="true",
  )
  // Anchored at the separator: a name that merely ends in "moon.mod" is not a
  // manifest, so `notmoon.mod` stays writable.
  inspect(@manifest_path.is_moon_mod_path("notmoon.mod"), content="false")
  // Case-sensitive.
  inspect(@manifest_path.is_moon_mod_path("MOON.MOD"), content="false")
}

///|
test "the module manifest and its legacy JSON form are separate questions" {
  inspect(
    @manifest_path.is_moon_mod_json_path("packages/demo/moon.mod.json"),
    content="true",
  )
  // `moon.mod.json` is NOT a `moon.mod`: the suffixes are distinct, so a caller
  // that wants "either module manifest" must ask both.
  inspect(@manifest_path.is_moon_mod_path("moon.mod.json"), content="false")
  inspect(@manifest_path.is_moon_mod_json_path("moon.mod"), content="false")
}

///|
test "package manifests, and the JSON form this package does not classify" {
  inspect(@manifest_path.is_moon_pkg_path("moon.pkg"), content="true")
  inspect(
    @manifest_path.is_moon_pkg_path("agent_tool/mbtx/moon.pkg"),
    content="true",
  )
  // There is deliberately no `is_moon_pkg_json_path`. Only `moon.mod.json` has
  // a predicate here, because only that legacy form is guarded on creation.
  inspect(@manifest_path.is_moon_pkg_path("moon.pkg.json"), content="false")
}
```

## The generated-interface predicate

`is_generated_mbti_path` is the odd one out: it is a **plain suffix test**, not
an anchored component test, because `*.generated.mbti` names a file by its
extension rather than by a fixed filename. Any basename may precede it.

```mbt check
///|
test "generated interfaces are matched by extension, not by filename" {
  inspect(
    @manifest_path.is_generated_mbti_path("agent_tool/mbtx/pkg.generated.mbti"),
    content="true",
  )
  // Any stem works — the extension is what is being recognized.
  inspect(
    @manifest_path.is_generated_mbti_path("anything.generated.mbti"),
    content="true",
  )
  // A hand-written interface is not a generated one.
  inspect(@manifest_path.is_generated_mbti_path("pkg.mbti"), content="false")
  // The leading dot is part of the suffix, so a bare `generated.mbti` misses.
  inspect(
    @manifest_path.is_generated_mbti_path("generated.mbti"),
    content="false",
  )
}
```

## Edges worth knowing

Trailing slashes are *not* normalized. These predicates classify files, and a
path ending in `/` names a directory, so it correctly fails every test — but the
failure is silent, and a caller that strips its own trailing slashes elsewhere
should strip them before asking here too.

```mbt check
///|
test "a trailing slash defeats every predicate" {
  inspect(@manifest_path.is_moon_mod_path("demo/moon.mod/"), content="false")
  inspect(@manifest_path.is_moon_pkg_path("demo/moon.pkg/"), content="false")
}

///|
test "`..` is not interpreted, because these are name tests" {
  // Both of these are about the final component only; neither says anything
  // about where the path actually lands.
  inspect(
    @manifest_path.is_moon_mod_path("demo/../../../etc/moon.mod"),
    content="true",
  )
  inspect(
    @manifest_path.is_moon_mod_path("demo/moon.mod/../x"),
    content="false",
  )
}
```

For "is this path inside the workspace?" — the question these predicates
deliberately do not answer — see `internal/workspace_path`, and
`agent_tool/internal/source_write_policy` for the combined protected-source
decision.
