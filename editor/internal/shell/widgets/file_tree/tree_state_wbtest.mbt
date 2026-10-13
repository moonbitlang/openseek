///|
fn uri(raw : String) -> @base_common.Uri {
  try! @base_common.Uri::parse(raw)
}

///|
fn dir_stat(raw : String, name : String) -> @workspace.WorkspaceStat {
  { uri: uri(raw), name, kind: Directory, children: None, }
}

///|
fn file_stat(raw : String, name : String) -> @workspace.WorkspaceStat {
  { uri: uri(raw), name, kind: File, children: None, }
}

///|
let root_raw : String = "readonly-remote://workspace"

///|
fn TreeNode::find(self : TreeNode, uri : @base_common.Uri) -> TreeNode? {
  if self.uri == uri {
    return Some(self)
  }
  match self.children {
    Some(children) =>
      for child in children {
        match child.find(uri) {
          Some(found) => return Some(found)
          None => ()
        }
      }
    None => ()
  }
  None
}

///|
fn resolved_root() -> TreeNode {
  TreeNode::from_stat(
    {
      uri: uri(root_raw),
      name: "workspace",
      kind: Directory,
      children: Some([
        file_stat("\{root_raw}/moon.mod", "moon.mod"),
        dir_stat("\{root_raw}/src", "src"),
      ]),
    },
    expanded=true,
  )
}

///|
test "orders resolved children directories first" {
  let root = resolved_root()
  let rows = root.visible_rows()
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].node.name, "src")
  assert_true(rows[0].node.kind == Directory)
  assert_eq(rows[1].node.name, "moon.mod")
  assert_eq(rows[0].depth, 0)
}

///|
test "one workspace comparator owns pins kind and lexical name order" {
  let stat : @workspace.WorkspaceStat = {
    uri: uri(root_raw),
    name: "workspace",
    kind: Directory,
    children: Some([
      file_stat("\{root_raw}/z", "z"),
      dir_stat("\{root_raw}/viewer", "viewer"),
      file_stat("\{root_raw}/aa", "aa"),
      dir_stat("\{root_raw}/base", "base"),
      file_stat("\{root_raw}/moon.pkg", "moon.pkg"),
      file_stat("\{root_raw}/pkg.generated.mbti", "pkg.generated.mbti"),
      file_stat("\{root_raw}/README.md", "README.md"),
    ]),
  }
  let ordered = TreeNode::from_stat(stat, expanded=true)
  assert_eq(ordered.visible_rows().map(row => row.node.name), [
    "README.md", "pkg.generated.mbti", "moon.pkg", "base", "viewer", "aa", "z",
  ])
}

///|
test "README pinning is file-only and accepts any extension" {
  let stat : @workspace.WorkspaceStat = {
    uri: uri(root_raw),
    name: "workspace",
    kind: Directory,
    children: Some([
      file_stat("\{root_raw}/other.txt", "other.txt"),
      file_stat("\{root_raw}/readme.md", "readme.md"),
      dir_stat("\{root_raw}/src", "src"),
      file_stat("\{root_raw}/READMEISH.txt", "READMEISH.txt"),
      dir_stat("\{root_raw}/README", "README"),
      file_stat("\{root_raw}/moon.pkg", "moon.pkg"),
      file_stat("\{root_raw}/README.mbt.md", "README.mbt.md"),
      file_stat("\{root_raw}/pkg.generated.mbti", "pkg.generated.mbti"),
      file_stat("\{root_raw}/README-file", "README"),
    ]),
  }
  let ordered = TreeNode::from_stat(stat, expanded=true)
  let rows = ordered.visible_rows()
  assert_eq(rows.map(row => row.node.name), [
    "README", "README.mbt.md", "pkg.generated.mbti", "moon.pkg", "README", "src",
    "READMEISH.txt", "other.txt", "readme.md",
  ])
  assert_eq(rows[0].node.uri.to_string(), "\{root_raw}/README-file")
  assert_eq(rows[4].node.uri.to_string(), "\{root_raw}/README")
}

///|
test "workspace comparison orders entries through Array::sort_by" {
  let stat : @workspace.WorkspaceStat = {
    uri: uri(root_raw),
    name: "workspace",
    kind: Directory,
    children: Some([
      dir_stat("\{root_raw}/z", "z"),
      file_stat("\{root_raw}/z.mbt", "z.mbt"),
      dir_stat("\{root_raw}/aa", "aa"),
      file_stat("\{root_raw}/aa.mbt", "aa.mbt"),
    ]),
  }
  let root = TreeNode::from_stat(stat, expanded=true)
  assert_eq(root.visible_rows().map(row => row.node.name), [
    "aa", "z", "aa.mbt", "z.mbt",
  ])
}

///|
test "workspace comparison orders lazily resolved levels the same way" {
  let src_uri = uri("\{root_raw}/src")
  let (expanded, _) = resolved_root().toggle(src_uri).unwrap()
  let resolved = expanded
    .with_resolved(src_uri, {
      uri: src_uri,
      name: "src",
      kind: Directory,
      children: Some([
        file_stat("\{root_raw}/src/main.mbt", "main.mbt"),
        file_stat("\{root_raw}/src/first.md", "first.md"),
      ]),
    })
    .unwrap()
  assert_eq(resolved.visible_rows().map(row => row.node.name), [
    "src", "first.md", "main.mbt", "moon.mod",
  ])
}

///|
test "directories start collapsed and expansion resolves once" {
  let original = resolved_root()
  let src_uri = uri("\{root_raw}/src")
  assert_false(original.find(src_uri).unwrap().expanded)

  // First expand: unresolved children ask for a provider resolve.
  let (expanded, effect) = original.toggle(src_uri).unwrap()
  match effect {
    ToggleResolve(resolve_uri) =>
      assert_eq(resolve_uri.to_string(), "\{root_raw}/src")
    ToggleNone => fail("expected resolve effect")
  }
  // The original snapshot remains collapsed after producing the new root.
  assert_false(original.find(src_uri).unwrap().expanded)
  assert_true(expanded.find(src_uri).unwrap().expanded)
  let resolved = expanded
    .with_resolved(src_uri, {
      uri: src_uri,
      name: "src",
      kind: Directory,
      children: Some([file_stat("\{root_raw}/src/main.mbt", "main.mbt")]),
    })
    .unwrap()

  // Collapse keeps the cache; the next expand is free.
  let (collapsed, effect) = resolved.toggle(src_uri).unwrap()
  match effect {
    ToggleNone => assert_false(collapsed.find(src_uri).unwrap().expanded)
    ToggleResolve(_) => fail("collapse must not resolve")
  }
  let (reexpanded, effect) = collapsed.toggle(src_uri).unwrap()
  match effect {
    ToggleNone => assert_true(reexpanded.find(src_uri).unwrap().expanded)
    ToggleResolve(_) => fail("cached children must not re-resolve")
  }
  let rows = reexpanded.visible_rows()
  assert_eq(rows.length(), 3)
  assert_eq(rows[1].node.name, "main.mbt")
  assert_eq(rows[1].depth, 1)
}

///|
test "failed resolve is retried on the next expand" {
  let original = resolved_root()
  let src_uri = uri("\{root_raw}/src")
  let (expanded, _) = original.toggle(src_uri).unwrap()
  let failed = expanded.with_resolve_failed(src_uri).unwrap()
  assert_false(original.find(src_uri).unwrap().resolve_failed)
  assert_true(failed.find(src_uri).unwrap().resolve_failed)

  // Collapse, then expand again: children are still None, so the expand
  // retries the resolve and clears the error state.
  let (collapsed, _) = failed.toggle(src_uri).unwrap()
  let (retried, effect) = collapsed.toggle(src_uri).unwrap()
  match effect {
    ToggleResolve(_) =>
      assert_false(retried.find(src_uri).unwrap().resolve_failed)
    ToggleNone => fail("expected resolve retry after failure")
  }
}

///|
test "reveal expands resolved ancestors and stops at unresolved levels" {
  let original = resolved_root()
  let target = uri("\{root_raw}/src/lib/util.mbt")
  let src_uri = uri("\{root_raw}/src")
  let lib_uri = uri("\{root_raw}/src/lib")

  // src is unresolved: the reveal must resolve it first.
  let (src_expanded, step) = original.reveal_step(target)
  match step {
    RevealResolve(resolve_uri) =>
      assert_eq(resolve_uri.to_string(), "\{root_raw}/src")
    _ => fail("expected resolve step for src")
  }
  assert_false(original.find(src_uri).unwrap().expanded)
  assert_true(src_expanded.find(src_uri).unwrap().expanded)
  let src_resolved = src_expanded
    .with_resolved(src_uri, {
      uri: src_uri,
      name: "src",
      kind: Directory,
      children: Some([dir_stat("\{root_raw}/src/lib", "lib")]),
    })
    .unwrap()

  // lib is now reachable but unresolved.
  let (lib_expanded, step) = src_resolved.reveal_step(target)
  match step {
    RevealResolve(resolve_uri) =>
      assert_eq(resolve_uri.to_string(), "\{root_raw}/src/lib")
    _ => fail("expected resolve step for src/lib")
  }
  assert_false(src_resolved.find(lib_uri).unwrap().expanded)
  assert_true(lib_expanded.find(lib_uri).unwrap().expanded)
  let lib_resolved = lib_expanded
    .with_resolved(lib_uri, {
      uri: lib_uri,
      name: "lib",
      kind: Directory,
      children: Some([file_stat("\{root_raw}/src/lib/util.mbt", "util.mbt")]),
    })
    .unwrap()
  let (revealed, step) = lib_resolved.reveal_step(target)
  match step {
    RevealDone => ()
    _ => fail("expected completed reveal")
  }
  let rows = revealed.visible_rows()
  assert_eq(rows.length(), 4)
  assert_eq(rows[2].node.name, "util.mbt")
  assert_eq(rows[2].depth, 2)
}

///|
test "reveal of targets outside the tree is unreachable" {
  let root = resolved_root()
  let (outside, step) = root.reveal_step(uri("memory://other/file.mbt"))
  match step {
    RevealUnreachable => ()
    _ => fail("expected unreachable target outside the root")
  }
  assert_true(outside == root)
  let (missing, step) = root.reveal_step(uri("\{root_raw}/gone/file.mbt"))
  match step {
    RevealUnreachable => ()
    _ => fail("expected unreachable target in a missing directory")
  }
  assert_true(missing == root)
}

///|
struct MemoryTreeProvider {
  root_uri : @base_common.Uri
  directories : Map[String, Array[@workspace.WorkspaceStat]]
  resolve_counts : Map[String, Int32]
}

///|
impl @workspace.WorkspaceTreeProvider for MemoryTreeProvider with fn root(self) {
  self.root_uri
}

///|
impl @workspace.WorkspaceTreeProvider for MemoryTreeProvider with fn resolve(
  self,
  uri,
) {
  let key = uri.to_string()
  self.resolve_counts[key] = self.resolve_counts.get(key).unwrap_or(0) + 1
  match self.directories.get(key) {
    Some(children) =>
      WorkspaceResolved({
        uri,
        name: @base_common.basename_or_authority(uri),
        kind: Directory,
        children: Some(children),
      })
    None =>
      WorkspaceResolveError(
        FileSystemProviderError(FileNotFound, "Directory does not exist.", uri~),
      )
  }
}

///|
extend MemoryTreeProvider with @workspace.WorkspaceTreeProvider::{root, resolve}

///|
async test "in-memory provider resolves one level per request" {
  let directories : Map[String, Array[@workspace.WorkspaceStat]] = Map([])
  directories[root_raw] = [
    file_stat("\{root_raw}/moon.mod", "moon.mod"),
    dir_stat("\{root_raw}/src", "src"),
  ]
  directories["\{root_raw}/src"] = [
    file_stat("\{root_raw}/src/main.mbt", "main.mbt"),
  ]
  let provider : MemoryTreeProvider = {
    root_uri: uri(root_raw),
    directories,
    resolve_counts: Map([]),
  }
  match provider.resolve(provider.root()) {
    WorkspaceResolved(stat) => {
      let root = TreeNode::from_stat(stat, expanded=true)
      let src_uri = uri("\{root_raw}/src")
      let src = root.find(src_uri).unwrap()
      // The resolved level carries unresolved directory children.
      assert_true(src.children is None)
      let (expanded, effect) = root.toggle(src_uri).unwrap()
      let resolved = match effect {
        ToggleResolve(resolve_uri) =>
          match provider.resolve(resolve_uri) {
            WorkspaceResolved(stat) =>
              expanded.with_resolved(src_uri, stat).unwrap()
            WorkspaceResolveError(error) => fail(error.message)
          }
        ToggleNone => fail("expected resolve effect")
      }
      let rows = resolved.visible_rows()
      assert_eq(rows.length(), 3)
      assert_eq(rows[1].node.name, "main.mbt")
    }
    WorkspaceResolveError(error) => fail(error.message)
  }
  match provider.resolve(uri("\{root_raw}/missing")) {
    WorkspaceResolveError(error) => assert_true(error.code == FileNotFound)
    WorkspaceResolved(_) => fail("expected missing directory error")
  }
  assert_true(provider.resolve_counts.get(root_raw) is Some(1))
  assert_true(provider.resolve_counts.get("\{root_raw}/src") is Some(1))
}
