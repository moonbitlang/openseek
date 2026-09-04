# agent_tool/internal/source_write_policy

Workspace policy shared by the macOS sandbox profile builder and the `shell`
tool's static command preflight. This package decides which MoonBit source paths
are protected; it does not execute commands or emit SBPL.

Two callers, one answer. `agent_tool/internal/sandbox` turns these predicates
into SBPL deny rules enforced by `sandbox-exec` at runtime; `agent_tool/shell`
asks the same questions before spawning anything, so a command is refused the
same way on a platform where the sandbox is unavailable. The two must agree,
which is why the rules live here rather than in either caller — and why the
examples below are tests rather than prose: a drift in behavior fails the build
instead of quietly letting the enforcement paths diverge.

Every function is a pure string operation. Nothing here opens, stats, or
resolves symlinks.

## `is_protected_source_path` — is this a source name?

Recognizes protected source and manifest names by case-sensitive suffix. It
accepts a basename or a full path and asks nothing about location.

```mbt check
///|
test "protected names: sources, interfaces, and every manifest" {
  inspect(
    @source_write_policy.is_protected_source_path("main.mbt"),
    content="true",
  )
  // `.mbt.md` counts — a documented package's README is executable source.
  inspect(
    @source_write_policy.is_protected_source_path(
      "agent_tool/read/README.mbt.md",
    ),
    content="true",
  )
  inspect(
    @source_write_policy.is_protected_source_path("pkg.generated.mbti"),
    content="true",
  )
  // All four manifests, current and legacy, as a bare name or a full path.
  inspect(
    @source_write_policy.is_protected_source_path("moon.mod"),
    content="true",
  )
  inspect(
    @source_write_policy.is_protected_source_path("agent_tool/moon.pkg"),
    content="true",
  )
  inspect(
    @source_write_policy.is_protected_source_path("moon.work"),
    content="true",
  )
  inspect(
    @source_write_policy.is_protected_source_path("moon.pkg.json"),
    content="true",
  )
  // Everything else is writable: the policy protects source, not the tree.
  inspect(
    @source_write_policy.is_protected_source_path("notes.md"),
    content="false",
  )
  inspect(
    @source_write_policy.is_protected_source_path("target/debug/app"),
    content="false",
  )
}

///|
test "matching is case-sensitive and separator-agnostic" {
  inspect(
    @source_write_policy.is_protected_source_path("src\\main.mbt"),
    content="true",
  )
  inspect(
    @source_write_policy.is_protected_source_path("MAIN.MBT"),
    content="false",
  )
}
```

This predicate alone is **not** an authorization decision. It says nothing about
where the path is, so a source file anywhere on the machine answers `true`:

```mbt check
///|
test "a name test is not a location test" {
  inspect(
    @source_write_policy.is_protected_source_path("/etc/cron.d/payload.mbt"),
    content="true",
  )
}
```

Use `is_protected_workspace_source_path` when the answer will gate a write.

## `is_moon_managed_workspace_path` — did Moon generate this?

Recognizes `_build` and `.mooncakes` components below a workspace root. These
trees are writable because Moon generates source files in them; protecting them
would break every build.

```mbt check
///|
test "Moon's own trees are exempt, the rest of the workspace is not" {
  inspect(
    @source_write_policy.is_moon_managed_workspace_path(
      "/work", "/work/_build/native/release/gen.mbt",
    ),
    content="true",
  )
  inspect(
    @source_write_policy.is_moon_managed_workspace_path(
      "/work", "/work/.mooncakes/bobzhang/dep/lib.mbt",
    ),
    content="true",
  )
  inspect(
    @source_write_policy.is_moon_managed_workspace_path(
      "/work", "/work/src/main.mbt",
    ),
    content="false",
  )
  // Outside the root there is nothing for this root to exempt.
  inspect(
    @source_write_policy.is_moon_managed_workspace_path(
      "/work", "/other/_build/gen.mbt",
    ),
    content="false",
  )
}
```

The scan runs over components **relative to the root**, and the root itself is
never Moon-managed. Both rules exist so that pointing a root at a build
directory cannot exempt everything below it:

```mbt check
///|
test "the root is never exempt, and only components below it are scanned" {
  inspect(
    @source_write_policy.is_moon_managed_workspace_path(
      "/work/_build", "/work/_build",
    ),
    content="false",
  )
  // `_build` is the root here, so it is not a component *below* the root and
  // the file is treated as ordinary source.
  inspect(
    @source_write_policy.is_moon_managed_workspace_path(
      "/work/_build", "/work/_build/gen.mbt",
    ),
    content="false",
  )
}
```

## `is_protected_workspace_source_path` — the decision

Combines workspace containment, the build-tree exemption, and protected-name
classification. This is the predicate that gates a write. The root should
already be absolute and canonical when the result is used to mirror sandbox
behavior.

```mbt check
///|
test "protected only when contained, generated-exempt, and source-named" {
  inspect(
    @source_write_policy.is_protected_workspace_source_path(
      "/work", "/work/src/main.mbt",
    ),
    content="true",
  )
  // Generated: Moon needs to write here.
  inspect(
    @source_write_policy.is_protected_workspace_source_path(
      "/work", "/work/_build/gen.mbt",
    ),
    content="false",
  )
  // Not source-named: notes and data are the agent's to edit.
  inspect(
    @source_write_policy.is_protected_workspace_source_path(
      "/work", "/work/notes.md",
    ),
    content="false",
  )
  // Not contained: outside the workspace this policy has no opinion, and a
  // caller must not read `false` as "safe to write".
  inspect(
    @source_write_policy.is_protected_workspace_source_path(
      "/work", "/etc/cron.d/payload.mbt",
    ),
    content="false",
  )
}
```

Unlike the raw helpers in `internal/workspace_path`, this predicate **normalizes
`.` and `..` before deciding**, so a traversal cannot smuggle a path past
containment in either direction:

```mbt check
///|
test "`..` is resolved before containment is judged" {
  // Normalizes to /work/main.mbt — still inside, still protected.
  inspect(
    @source_write_policy.is_protected_workspace_source_path(
      "/work", "/work/src/../main.mbt",
    ),
    content="true",
  )
  // Normalizes to /etc/passwd.mbt — the escape is caught, where the purely
  // lexical `@workspace_path.is_under_workspace_root` would have said `true`.
  inspect(
    @source_write_policy.is_protected_workspace_source_path(
      "/work", "/work/../etc/passwd.mbt",
    ),
    content="false",
  )
}
```

## `path_is_under_lab` — the scratch-lab exception

The authorization predicate for an opt-in writable subtree. It normalizes both
paths, includes the lab itself, and refuses to authorize everything.

```mbt check
///|
#cfg(not(platform="windows"))
test "the lab and everything under it, and nothing else" {
  inspect(
    @source_write_policy.path_is_under_lab("/work/lab/scratch.mbt", "/work/lab"),
    content="true",
  )
  // The lab directory itself is included.
  inspect(
    @source_write_policy.path_is_under_lab("/work/lab", "/work/lab"),
    content="true",
  )
  // A sibling sharing a name prefix is not under the lab.
  inspect(
    @source_write_policy.path_is_under_lab("/work/lab2/x.mbt", "/work/lab"),
    content="false",
  )
  // Traversal is normalized away before the comparison, in both directions.
  inspect(
    @source_write_policy.path_is_under_lab(
      "/work/lab/../lab/x.mbt", "/work/lab",
    ),
    content="true",
  )
  inspect(
    @source_write_policy.path_is_under_lab(
      "/work/lab/../secret.mbt", "/work/lab",
    ),
    content="false",
  )
}
```

A lab of `/` or of the empty string is rejected outright, so a caller that
forgets to configure one cannot accidentally authorize the whole filesystem:

```mbt check
///|
test "a degenerate lab authorizes nothing" {
  inspect(
    @source_write_policy.path_is_under_lab("/work/src/main.mbt", "/"),
    content="false",
  )
  inspect(
    @source_write_policy.path_is_under_lab("/work/src/main.mbt", ""),
    content="false",
  )
}
```

## What callers still owe

The package uses `internal/workspace_path` for generic path operations. Its
comparisons are lexical and case-sensitive: callers remain responsible for
resolving symlinks and canonicalizing user-controlled paths where filesystem
identity matters. A symlink inside the workspace pointing out of it still tests
as contained here — which is why `agent_tool/internal/sandbox` resolves its root
with `@fs.realpath` before emitting a single rule.
