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
  decode_package_graph(output.text)
}

///|
/// Decode moon's `tree --package --json` document. The shape (version 2):
/// `nodes[i] = { module, rel, source: { kind, path? } }` and
/// `edges[j] = { from, to, kinds }`, indices into `nodes`. A local node's
/// directory is `source.path` joined with `rel` (empty `rel` = the module
/// root). Anything malformed yields `None` rather than a partial graph.
fn decode_package_graph(text : String) -> PackageGraph? {
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
  let dirs : Array[String?] = []
  for node in nodes {
    match node {
      {
        "rel": String(rel),
        "source": { "kind": String("local"), "path": String(root), .. },
        ..
      } => dirs.push(Some(if rel == "" { root } else { "\{root}/\{rel}" }))
      { "source": { "kind": String(_), .. }, .. } => dirs.push(None)
      _ => return None
    }
  }
  let pairs : Array[(Int, Int)] = []
  for edge in edges {
    guard edge is { "from": Number(from, ..), "to": Number(to, ..), .. } else {
      return None
    }
    let (from, to) = (from.to_int(), to.to_int())
    if from < 0 || from >= dirs.length() || to < 0 || to >= dirs.length() {
      return None
    }
    pairs.push((from, to))
  }
  Some({ dirs, edges: pairs, })
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
test "decode_package_graph keeps directories, registry placeholders, and edges" {
  guard decode_package_graph(sample_graph_json()) is Some(graph) else {
    fail("expected a graph")
  }
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
  guard decode_package_graph(sample_graph_json()) is Some(graph) else {
    fail("expected a graph")
  }
  assert_eq(graph.package_of("/private/tmp/reach/a/a.mbt"), Some(0))
  assert_eq(graph.package_of("/private/tmp/reach/b/moon.pkg"), Some(1))
  // The directory itself, and a same-prefix sibling that is not inside it.
  assert_eq(graph.package_of("/private/tmp/reach/c"), Some(2))
  assert_eq(graph.package_of("/private/tmp/reach/cc/x.mbt"), None)
  assert_eq(graph.package_of("/elsewhere/x.mbt"), None)
}

///|
test "depends_on follows imports transitively and counts a package as its own dependent" {
  guard decode_package_graph(sample_graph_json()) is Some(graph) else {
    fail("expected a graph")
  }
  assert_true(graph.depends_on(1, [0])) // b imports a
  assert_false(graph.depends_on(0, [1])) // a does not import b
  assert_false(graph.depends_on(2, [0])) // c is independent of a
  assert_true(graph.depends_on(2, [4])) // via a test import
  assert_true(graph.depends_on(3, [3]))
  assert_false(graph.depends_on(3, []))
}
