///|
/// The package dependency graph moon itself reports for a project
/// (`moon tree --package --json`), reduced to what a caller comparing two
/// check runs needs: each local package's absolute directory, and the
/// dependency edges between packages. Registry packages keep a place in the
/// node list (edges index into it) but have no directory.
pub(all) struct PackageGraph {
  // Absolute package directory per node; `None` for a registry package.
  dirs : Array[String?]
  // `(from, to)`: package `from` imports package `to`, in any import kind
  // (source, blackbox-test, whitebox-test) — a test import can break too.
  edges : Array[(Int, Int)]
} derive(Debug)

///|
/// Output budget for the graph JSON. This repository's workspace graph is
/// ~300 KB (700 packages, 3 300 edges); a 4 MB budget leaves an order of
/// magnitude for larger workspaces before the result is dropped.
const PackageGraphMaxOutputChars : Int = 4000000

///|
/// The project directory `count_errors` would check `path` from — the nearest
/// ancestor holding a `moon.mod` or `moon.work` — or `None` when `path` is not
/// a MoonBit source or manifest inside a project. A caller pairing a check with
/// a package graph runs both from here.
pub async fn check_cwd(path : String) -> String? {
  moon_check_cwd(path)
}

///|
/// Ask moon for the package graph of the project at `cwd`. `None` when moon
/// could not produce one (failed to spawn, timed out, output over budget, or a
/// status other than success) — a caller must then treat any graph-based
/// conclusion as unavailable rather than assume no dependencies.
pub async fn package_graph(cwd : String) -> PackageGraph? {
  let result = @async.with_timeout_opt(@moon_check.TimeoutMs, () => {
    collect_process_output(
      "moon",
      ["tree", "--package", "--json"],
      cwd~,
      max_output_chars=PackageGraphMaxOutputChars,
    )
  }) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  guard result is Some(output) && !output.output_limit_reached else {
    return None
  }
  guard decode_package_graph(output.text) is Some(raw) else { return None }
  // moon reports each local package's `rel` relative to its module's SOURCE
  // root (`source = "src"` in moon.mod), but `source.path` is the module
  // root; read every module's setting once.
  let source_dirs : Map[String, String] = Map([])
  for node in raw.nodes {
    guard node is Some((root, _)) else { continue }
    if !source_dirs.contains(root) {
      source_dirs[root] = module_source_dir(root)
    }
  }
  Some(resolve_package_graph(raw, source_dirs))
}

///|
/// The graph as moon reports it, before package directories are resolved:
/// each local node's `(module root, rel)`, `None` for a registry package.
priv struct RawPackageGraph {
  nodes : Array[(String, String)?]
  edges : Array[(Int, Int)]
}

///|
/// Decode moon's `tree --package --json` document. The shape (version 2):
/// `nodes[i] = { module, rel, source: { kind, path? } }` and
/// `edges[j] = { from, to, kinds }`, indices into `nodes`. Anything malformed
/// yields `None` rather than a partial graph.
fn decode_package_graph(text : String) -> RawPackageGraph? {
  let json = @json.parse(text) catch { _ => return None }
  guard json
    is {
      "status": String("success"),
      "nodes": Array(nodes),
      "edges": Array(edges),
      ..
    } else {
    return None
  }
  let raw_nodes : Array[(String, String)?] = []
  for node in nodes {
    match node {
      {
        "rel": String(rel),
        "source": { "kind": String("local"), "path": String(root), .. },
        ..
      } => raw_nodes.push(Some((root, rel)))
      { "source": { "kind": String(_), .. }, .. } => raw_nodes.push(None)
      _ => return None
    }
  }
  let pairs : Array[(Int, Int)] = []
  for edge in edges {
    guard edge is { "from": Number(from, ..), "to": Number(to, ..), .. } else {
      return None
    }
    let (from, to) = (from.to_int(), to.to_int())
    if from < 0 ||
      from >= raw_nodes.length() ||
      to < 0 ||
      to >= raw_nodes.length() {
      return None
    }
    pairs.push((from, to))
  }
  Some({ nodes: raw_nodes, edges: pairs, })
}

///|
/// Turn raw nodes into package directories: module root, then the module's
/// source subdirectory (if any), then `rel` (empty = the source root itself).
fn resolve_package_graph(
  raw : RawPackageGraph,
  source_dirs : Map[String, String],
) -> PackageGraph {
  let dirs = raw.nodes.map(node => {
    node.map(node => {
      let (root, rel) = node
      let mut dir = root
      for part in [source_dirs.get(root).unwrap_or(""), rel] {
        if part != "" {
          dir = "\{dir}/\{part}"
        }
      }
      normalize_dir(dir)
    })
  })
  { dirs, edges: raw.edges, }
}

///|
/// Collapse `.` and `..` segments lexically (`/m/src/../a` → `/m/a`), so a
/// directory assembled from a `source = "src/.."` setting compares equal to
/// the canonical paths moon puts in diagnostics. Leading `..` above the root
/// is kept as written; a leading `/` is preserved.
fn normalize_dir(path : String) -> String {
  let absolute = path.has_prefix("/")
  let parts : Array[String] = []
  for segment in path.split("/") {
    match segment {
      "" | "." => continue
      ".." =>
        match parts {
          [.., last] if last != ".." => ignore(parts.pop())
          _ => if absolute { () } else { parts.push("..") }
        }
      segment => parts.push(segment.to_owned())
    }
  }
  let joined = parts.join("/")
  if absolute {
    "/\{joined}"
  } else if joined == "" {
    "."
  } else {
    joined
  }
}

///|
/// A module's configured source subdirectory, read from its `moon.mod`
/// (`source = "src"`) or legacy `moon.mod.json` (`"source": "src"`); `""`
/// when unset or unreadable, meaning packages live under the module root.
async fn module_source_dir(root : String) -> String {
  let modern = @fs.read_file("\{root}/moon.mod").text() catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      let legacy = @fs.read_file("\{root}/moon.mod.json").text() catch {
        error if @async.is_being_cancelled() => raise error
        _ => return ""
      }
      return parse_module_source(legacy, json=true)
    }
  }
  parse_module_source(modern, json=false)
}

///|
/// Extract the `source` setting from a manifest's text. The modern manifest
/// is line-oriented (`source = "src"`); the legacy one is JSON. A leading
/// `./` and trailing `/` are dropped so the value joins cleanly.
fn parse_module_source(text : String, json~ : Bool) -> String {
  let raw = if json {
    match (@json.parse(text) catch { _ => return "" }) {
      { "source": String(source), .. } => source
      _ => return ""
    }
  } else {
    let mut found = ""
    for line in text.split("\n") {
      let line = line.trim()
      guard line.has_prefix("source") else { continue }
      let rest = line[6:].trim()
      guard rest.has_prefix("=") else { continue }
      let value = rest[1:].trim()
      guard value.has_prefix("\"") && value.length() >= 2 else { continue }
      match value[1:].find("\"") {
        Some(end) => {
          found = value[1:1 + end].to_owned()
          break
        }
        None => continue
      }
    }
    found
  }
  let mut source = raw[:]
  if source.has_prefix("./") {
    source = source[2:]
  }
  while source.has_suffix("/") {
    source = source[:source.length() - 1]
  }
  if source == "." {
    ""
  } else {
    source.to_owned()
  }
}

///|
/// The package holding an absolute path: the local node whose directory is
/// the longest one that contains it. `None` when no local package does — the
/// path lies outside every package moon knows about from this cwd.
pub fn PackageGraph::package_of(self : PackageGraph, path : String) -> Int? {
  let mut best : (Int, Int)? = None
  for index, dir in self.dirs {
    guard dir is Some(dir) else { continue }
    if path == dir || path.has_prefix("\{dir}/") {
      if best is Some((_, length)) && length >= dir.length() {
        continue
      }
      best = Some((index, dir.length()))
    }
  }
  best.map(found => found.0)
}

///|
/// Whether package `from` transitively imports any package in `targets`
/// (a package counts as depending on itself). Breadth-first over the edge
/// list; the graph is small enough that no adjacency index is built.
pub fn PackageGraph::depends_on(
  self : PackageGraph,
  from : Int,
  targets : Array[Int],
) -> Bool {
  if targets.contains(from) {
    return true
  }
  let seen : Set[Int] = Set([from])
  let queue : Array[Int] = [from]
  while queue.pop() is Some(current) {
    for edge in self.edges {
      let (source, target) = edge
      if source != current || seen.contains(target) {
        continue
      }
      if targets.contains(target) {
        return true
      }
      seen.add(target)
      queue.push(target)
    }
  }
  false
}

///|
#doc(hidden)
#deprecated
pub extend PackageGraph with Debug::{to_repr}

///|
/// A four-package graph in moon's own shape: `b` imports `a`, `c` imports
/// `d`, plus a registry dependency without a directory.
fn sample_graph_json() -> String {
  (
    #|{"version":2,"status":"success","error":null,"root":[0,1,2,3],"nodes":[{"module":"tmp/reach","version":"0.0.0","source":{"kind":"local","path":"/private/tmp/reach"},"rel":"a"},{"module":"tmp/reach","version":"0.0.0","source":{"kind":"local","path":"/private/tmp/reach"},"rel":"b"},{"module":"tmp/reach","version":"0.0.0","source":{"kind":"local","path":"/private/tmp/reach"},"rel":"c"},{"module":"tmp/reach","version":"0.0.0","source":{"kind":"local","path":"/private/tmp/reach"},"rel":"d"},{"module":"x/registry","version":"0.3.0","source":{"kind":"registry"},"rel":""}],"edges":[{"from":1,"to":0,"alias":"a","kinds":["source"]},{"from":2,"to":3,"alias":"d","kinds":["source"]},{"from":2,"to":4,"alias":"registry","kinds":["blackbox-test"]}],"logs":[]}
  )
}

///|
fn sample_graph() -> PackageGraph {
  guard decode_package_graph(sample_graph_json()) is Some(raw) else {
    abort("sample graph must decode")
  }
  resolve_package_graph(raw, Map([]))
}

///|
test "decode_package_graph keeps directories, registry placeholders, and edges" {
  let graph = sample_graph()
  assert_eq(graph.dirs, [
    Some("/private/tmp/reach/a"),
    Some("/private/tmp/reach/b"),
    Some("/private/tmp/reach/c"),
    Some("/private/tmp/reach/d"),
    None,
  ])
  assert_eq(graph.edges, [(1, 0), (2, 3), (2, 4)])
}

///|
test "resolve_package_graph inserts a module's source subdirectory" {
  guard decode_package_graph(sample_graph_json()) is Some(raw) else {
    fail("expected a graph")
  }
  // moon reports `rel` relative to the source root but `source.path` as the
  // module root, so a `source = "src"` module lives one level down.
  let graph = resolve_package_graph(raw, { "/private/tmp/reach": "src" })
  assert_eq(graph.dirs[0], Some("/private/tmp/reach/src/a"))
  assert_eq(graph.dirs[4], None)
  // A package at the source root itself.
  let root_only : RawPackageGraph = { nodes: [Some(("/m", ""))], edges: [], }
  assert_eq(resolve_package_graph(root_only, { "/m": "src" }).dirs, [
    Some("/m/src"),
  ])
  assert_eq(resolve_package_graph(root_only, Map([])).dirs, [Some("/m")])
  // A setting moon resolves back to the root must compare equal to the
  // canonical paths in diagnostics.
  assert_eq(
    resolve_package_graph(raw, { "/private/tmp/reach": "src/.." }).dirs[0],
    Some("/private/tmp/reach/a"),
  )
}

///|
test "normalize_dir collapses dot segments lexically" {
  assert_eq(normalize_dir("/m/src/../a"), "/m/a")
  assert_eq(normalize_dir("/m/./a//b/"), "/m/a/b")
  assert_eq(normalize_dir("/m/a/../.."), "/")
  assert_eq(normalize_dir("/../m"), "/m")
  assert_eq(normalize_dir("a/../../b"), "../b")
  assert_eq(normalize_dir("a/.."), ".")
}

///|
test "parse_module_source reads modern and legacy manifests" {
  assert_eq(
    parse_module_source("name = \"a/b\"\nsource = \"src\"\n", json=false),
    "src",
  )
  assert_eq(
    parse_module_source("name = \"a/b\"\nsource=\"./lib/\"\n", json=false),
    "lib",
  )
  assert_eq(parse_module_source("name = \"a/b\"\n", json=false), "")
  // A `source` inside another key's value is not the setting.
  assert_eq(
    parse_module_source("description = \"source = \\\"x\\\"\"\n", json=false),
    "",
  )
  assert_eq(
    parse_module_source("{\"name\":\"a/b\",\"source\":\"src\"}", json=true),
    "src",
  )
  assert_eq(parse_module_source("{\"name\":\"a/b\"}", json=true), "")
  assert_eq(parse_module_source("not json", json=true), "")
}

///|
test "decode_package_graph refuses a failed status or a malformed edge" {
  let failed =
    #|{"version":2,"status":"error","error":"boom","nodes":[],"edges":[]}
  assert_true(decode_package_graph(failed) is None)
  let dangling =
    #|{"status":"success","nodes":[{"rel":"a","source":{"kind":"local","path":"/r"}}],"edges":[{"from":0,"to":7}]}
  assert_true(decode_package_graph(dangling) is None)
  assert_true(decode_package_graph("not json") is None)
}

///|
test "package_of picks the longest containing package directory" {
  let graph = sample_graph()
  assert_eq(graph.package_of("/private/tmp/reach/a/a.mbt"), Some(0))
  assert_eq(graph.package_of("/private/tmp/reach/b/moon.pkg"), Some(1))
  // The directory itself, and a same-prefix sibling that is not inside it.
  assert_eq(graph.package_of("/private/tmp/reach/c"), Some(2))
  assert_eq(graph.package_of("/private/tmp/reach/cc/x.mbt"), None)
  assert_eq(graph.package_of("/elsewhere/x.mbt"), None)
}

///|
test "depends_on follows imports transitively and counts a package as its own dependent" {
  let graph = sample_graph()
  assert_true(graph.depends_on(1, [0])) // b imports a
  assert_false(graph.depends_on(0, [1])) // a does not import b
  assert_false(graph.depends_on(2, [0])) // c is independent of a
  assert_true(graph.depends_on(2, [4])) // via a test import
  assert_true(graph.depends_on(3, [3]))
  assert_false(graph.depends_on(3, []))
}
