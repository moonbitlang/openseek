///|
/// Untruncated, NUL-delimited change parsing and component-wise scope
/// validation — the controller's ground truth about what a worker touched.
/// `git status --porcelain=v1 -z` and `git diff --name-status -z` need
/// SEPARATE parsers: status prints `XY rename_target NUL rename_source`,
/// diff prints `Rnnn NUL source NUL target`.

///|
/// One changed path with how it changed. Renames yield TWO records (source
/// and target) — both sides must be in scope for the change to merge.
struct Change {
  path : String
  kind : String
} derive(Debug, Eq)

///|
/// Parse `git status --porcelain=v1 -z --untracked-files=all` output.
fn parse_status_z(output : String) -> Array[Change] {
  let changes : Array[Change] = []
  let fields = output.split("\u{0}").map(f => f.to_owned()).collect()
  let mut index = 0
  while index < fields.length() {
    let record = fields[index]
    if record.length() < 4 {
      index += 1
      continue
    }
    let xy = record.view(end_offset=2).to_owned()
    let path = record.view(start_offset=3).to_owned()
    changes.push({ path, kind: xy.trim().to_owned(), })
    // A rename/copy consumes the NEXT field as its source path.
    if xy.contains("R") || xy.contains("C") {
      if index + 1 < fields.length() && fields[index + 1] != "" {
        changes.push({ path: fields[index + 1], kind: "\{xy.trim()}-source", })
        index += 1
      }
    }
    index += 1
  }
  changes
}

///|
/// Parse `git diff --name-status -z` output.
fn parse_diff_name_status_z(output : String) -> Array[Change] {
  let changes : Array[Change] = []
  let fields = output.split("\u{0}").map(f => f.to_owned()).collect()
  let mut index = 0
  while index < fields.length() {
    let status = fields[index]
    guard status != "" else {
      index += 1
      continue
    }
    if status.has_prefix("R") || status.has_prefix("C") {
      if index + 2 < fields.length() {
        changes.push({ path: fields[index + 1], kind: "\{status}-source", })
        changes.push({ path: fields[index + 2], kind: status, })
      }
      index += 3
    } else {
      if index + 1 < fields.length() {
        changes.push({ path: fields[index + 1], kind: status, })
      }
      index += 2
    }
  }
  changes
}

///|
/// Every change must fall under one of the allowed component-wise prefixes.
/// Returns the violating paths (empty = in scope).
fn scope_violations(
  changes : Array[Change],
  allowed_paths : Array[String],
) -> Array[String] {
  let allowed = allowed_paths.map(components)
  let violations : Array[String] = []
  for change in changes {
    let parts = components(change.path)
    let admitted = allowed.any(prefix => one_covers(prefix, parts))
    if !admitted && !violations.contains(change.path) {
      violations.push(change.path)
    }
  }
  violations
}

///|
/// Paths that TRANSITION INTO gitlink mode (160000) in a raw -z diff — an
/// embedded repository swallowed as a pointer, whether added over nothing
/// (`:000000 160000 ... A`) or replacing a regular file (`:100644 160000
/// ... T`). Pre-existing gitlinks (source already 160000) pass.
fn gitlink_introductions_in_raw_z(output : String) -> Array[String] {
  let links : Array[String] = []
  let fields = output.split("\u{0}").map(f => f.to_owned()).collect()
  let mut index = 0
  while index < fields.length() {
    let meta = fields[index]
    if meta.has_prefix(":") && index + 1 < fields.length() {
      // :src_mode dst_mode src_oid dst_oid status
      let parts = meta
        .view(start_offset=1)
        .to_owned()
        .split(" ")
        .map(p => p.to_owned())
        .collect()
      if parts.length() >= 5 && parts[1] == "160000" && parts[0] != "160000" {
        links.push(fields[index + 1])
      }
      index += 2
    } else {
      index += 1
    }
  }
  links
}

///|
test "status -z parsing keeps renames' both sides" {
  let raw = " M lib/a.txt\u{0}R  lib/renamed.txt\u{0}lib/original.txt\u{0}?? lib/new.txt\u{0}"
  let changes = parse_status_z(raw)
  assert_eq(changes.length(), 4)
  assert_eq(changes[0], { path: "lib/a.txt", kind: "M", })
  assert_eq(changes[1], { path: "lib/renamed.txt", kind: "R", })
  assert_eq(changes[2], { path: "lib/original.txt", kind: "R-source", })
  assert_eq(changes[3], { path: "lib/new.txt", kind: "??", })
}

///|
test "diff -z parsing reads the opposite rename order" {
  let raw = "M\u{0}lib/a.txt\u{0}R100\u{0}lib/original.txt\u{0}lib/renamed.txt\u{0}D\u{0}lib/gone.txt\u{0}"
  let changes = parse_diff_name_status_z(raw)
  assert_eq(changes.length(), 4)
  assert_eq(changes[0], { path: "lib/a.txt", kind: "M", })
  assert_eq(changes[1], { path: "lib/original.txt", kind: "R100-source", })
  assert_eq(changes[2], { path: "lib/renamed.txt", kind: "R100", })
  assert_eq(changes[3], { path: "lib/gone.txt", kind: "D", })
}

///|
test "scope violations are component-wise over every side" {
  let changes = [
    ({ path: "lib/a.txt", kind: "M", } : Change),
    { path: "lib2/b.txt", kind: "M", },
    { path: "lib/moved.txt", kind: "R", },
    { path: "other/original.txt", kind: "R-source", },
  ]
  let violations = scope_violations(changes, ["lib"])
  assert_eq(violations, ["lib2/b.txt", "other/original.txt"])
  assert_eq(scope_violations(changes, ["lib", "lib2", "other"]).length(), 0)
}

///|
test "gitlink introductions are detected from raw -z records" {
  let raw = ":000000 160000 0000000 abc1234 A\u{0}vendor/embedded\u{0}:000000 100644 0000000 def5678 A\u{0}lib/file.txt\u{0}:100644 160000 aaa1111 bbb2222 T\u{0}lib/swapped\u{0}:160000 160000 ccc3333 ddd4444 M\u{0}vendor/existing\u{0}"
  assert_eq(gitlink_introductions_in_raw_z(raw), [
    "vendor/embedded", "lib/swapped",
  ])
}

///|
pub extend Change with Debug::{to_repr}

///|
pub extend Change with Eq::{equal, not_equal}
