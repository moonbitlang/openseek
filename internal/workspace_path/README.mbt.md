# internal/workspace_path

Lexical path helpers shared by every agent tool that has to interpret a path
the model wrote. `read`, `write`, `edit`, `multi_edit`, `remove`, `shell`,
`mbtx`, `moon_check`, `source_write_policy`, `sandbox`, and the
`cmd/openseek` entry point all resolve and compare paths through this package,
so they agree on what "inside the workspace" means.

Every function here is a pure string operation. Nothing in this package opens,
stats, or resolves anything on disk.

## The contract

These properties hold for all seven functions, and the tests below are the
specification:

- **No filesystem.** No `stat`, no `realpath`, no symlink resolution. A path
  that does not exist behaves exactly like one that does.
- **Backslashes are separators.** `C:\work\main.mbt` and `C:/work/main.mbt` are
  the same path, so Windows input from a tool call needs no pre-cleaning.
- **Trailing slashes are insignificant, but roots survive.** `/work/` and
  `/work` are the same directory; `/` stays `/`.
- **Comparison is case-sensitive**, on every platform.
- **`.` and `..` are not interpreted**, with the single exception of `resolve`.
  See [Lexical means lexical](#lexical-means-lexical) — this is the sharp edge.

## Trimming and naming

`strip_trailing_slash` removes trailing separators without ever collapsing a
path to nothing, and `path_basename` takes the last component.

```mbt check
///|
test "trailing separators collapse, filesystem roots do not" {
  inspect(@workspace_path.strip_trailing_slash("/work///"), content="/work")
  inspect(@workspace_path.strip_trailing_slash("/work"), content="/work")
  // A lone root is already minimal — stripping it would produce "".
  inspect(@workspace_path.strip_trailing_slash("/"), content="/")
}

///|
test "basename takes the last component, either separator" {
  inspect(
    @workspace_path.path_basename("/work/pkg/main.mbt"),
    content="main.mbt",
  )
  // Trailing slash first, so a directory reports its own name.
  inspect(@workspace_path.path_basename("/work/pkg/"), content="pkg")
  inspect(
    @workspace_path.path_basename("C:\\work\\main.mbt"),
    content="main.mbt",
  )
  // No separator at all: the path is already a basename.
  inspect(@workspace_path.path_basename("moon.mod"), content="moon.mod")
}
```

## Walking up and building down

`parent_dir` returns `None` exactly at the points where there is nowhere left
to go — a filesystem root, a bare Windows drive, or an empty path — which makes
it safe to drive a loop that walks toward the root.

```mbt check
///|
test "parent_dir stops at the roots" {
  debug_inspect(
    @workspace_path.parent_dir("/work/pkg"),
    content="Some(\"/work\")",
  )
  // One level below the root reports the root itself, not "".
  debug_inspect(@workspace_path.parent_dir("/work"), content="Some(\"/\")")
  debug_inspect(@workspace_path.parent_dir("/"), content="None")
  // A relative name's parent is the current directory.
  debug_inspect(@workspace_path.parent_dir("moon.mod"), content="Some(\".\")")
  // Windows drives terminate too, with or without the separator.
  debug_inspect(@workspace_path.parent_dir("C:/work"), content="Some(\"C:\")")
  debug_inspect(@workspace_path.parent_dir("C:/"), content="None")
  debug_inspect(@workspace_path.parent_dir("C:"), content="None")
}

///|
test "join_child never doubles or drops a separator" {
  inspect(
    @workspace_path.join_child("/work", "moon.mod"),
    content="/work/moon.mod",
  )
  inspect(
    @workspace_path.join_child("/work/", "moon.mod"),
    content="/work/moon.mod",
  )
  // The default root contributes no prefix at all.
  inspect(@workspace_path.join_child(".", "moon.mod"), content="moon.mod")
  inspect(@workspace_path.join_child("", "moon.mod"), content="moon.mod")
}
```

Walking up terminates, which is the property callers depend on when searching
upward for a `moon.mod`:

```mbt check
///|
test "parent_dir drives a terminating upward walk" {
  let seen = []
  let mut at = Some("/work/pkg/internal")
  while at is Some(dir) {
    seen.push(dir)
    at = @workspace_path.parent_dir(dir)
  }
  inspect(
    seen.join(" -> "),
    content="/work/pkg/internal -> /work/pkg -> /work -> /",
  )
}
```

## Containment

`is_under_workspace_root` answers "is this path the root or below it". It is
the predicate behind the source-write protection in
`agent_tool/internal/source_write_policy`, so its prefix handling matters: a
sibling directory whose name merely starts with the root must not count.

```mbt check
///|
test "containment includes the root and excludes name-prefix siblings" {
  // The root is under itself.
  inspect(
    @workspace_path.is_under_workspace_root("/work", "/work"),
    content="true",
  )
  inspect(
    @workspace_path.is_under_workspace_root("/work/", "/work/pkg/main.mbt"),
    content="true",
  )
  // Not a sibling that merely shares a name prefix.
  inspect(
    @workspace_path.is_under_workspace_root("/work", "/workspace/main.mbt"),
    content="false",
  )
  // Separators are normalized on both sides.
  inspect(
    @workspace_path.is_under_workspace_root("C:\\work", "C:/work/main.mbt"),
    content="true",
  )
  // Case-sensitive, including on Windows-shaped paths.
  inspect(
    @workspace_path.is_under_workspace_root("/work", "/WORK/main.mbt"),
    content="false",
  )
}
```

## Resolution against a workspace root

`resolve` turns a tool-supplied path into one rooted at the workspace.
Two inputs pass through untouched: an absolute path is already unambiguous, and
the **default root** — `""` or `"."` — means "no workspace", preserving the
behavior and output text from before workspaces existed.

```mbt check
///|
#cfg(not(platform="windows"))
test "resolve joins relative paths and passes the rest through" {
  inspect(
    @workspace_path.resolve("/tmp/work", "src/main.mbt"),
    content="/tmp/work/src/main.mbt",
  )
  // Absolute input is already explicit.
  inspect(
    @workspace_path.resolve("/tmp/work", "/var/log/file"),
    content="/var/log/file",
  )
  // The default root is a deliberate passthrough, not an error.
  inspect(@workspace_path.resolve(".", "src/main.mbt"), content="src/main.mbt")
  inspect(@workspace_path.resolve("", "src/main.mbt"), content="src/main.mbt")
  // Unlike the helpers above, resolve does normalize `.` and `..`.
  inspect(
    @workspace_path.resolve("/tmp/work", "src/../README.md"),
    content="/tmp/work/README.md",
  )
}

///|
#cfg(not(platform="windows"))
test "resolve_cwd maps a missing cwd onto the root" {
  // No cwd means the workspace root...
  debug_inspect(
    @workspace_path.resolve_cwd("/tmp/work", None),
    content="Some(\"/tmp/work\")",
  )
  // ...except under the default root, where None preserves the old
  // current-directory behavior and the caller spawns without a cwd.
  debug_inspect(@workspace_path.resolve_cwd(".", None), content="None")
  debug_inspect(
    @workspace_path.resolve_cwd("/tmp/work", Some("subdir")),
    content="Some(\"/tmp/work/subdir\")",
  )
  // An empty cwd is treated as absent, not as a relative path.
  debug_inspect(
    @workspace_path.resolve_cwd("/tmp/work", Some("")),
    content="Some(\"/tmp/work\")",
  )
}
```

## Lexical means lexical

The one thing to get right when calling this package: **containment is decided
on the text**, so a `..` component defeats it. The following is not a bug, it
is the documented contract, and it is why callers must normalize or resolve
untrusted input first:

```mbt check
///|
#cfg(not(platform="windows"))
test "a `..` component escapes the root while still looking contained" {
  // `..` is not interpreted, so this reads as "under /work" on the text alone
  // even though it names /etc/passwd.
  inspect(
    @workspace_path.is_under_workspace_root("/work", "/work/../etc/passwd"),
    content="true",
  )
  // `resolve` does normalize, and will happily produce a path outside the root.
  inspect(
    @workspace_path.resolve("/work", "../etc/passwd"),
    content="/etc/passwd",
  )
  // Normalizing first makes containment answer the real question.
  inspect(
    @workspace_path.is_under_workspace_root(
      "/work",
      @workspace_path.resolve("/work", "../etc/passwd"),
    ),
    content="false",
  )
}
```

Symlinks are the same story one level down: this package cannot see them, so a
symlink inside the workspace pointing out of it still tests as contained. Where
that matters — the sandbox source-write profile — the caller resolves the root
with `@fs.realpath` before building any rule, and compares real paths only.
