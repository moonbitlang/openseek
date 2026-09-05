///|
/// The controller-owned lifecycle record of one subtask, stored OUTSIDE any
/// worker-writable path at `<common-git-dir>/openseek/subtasks/<file>.json`.
/// It is simultaneously the orphan-discovery record (a later session can
/// enumerate the directory) and the path RESERVATION: entries in
/// non-terminal states hold their `allowed_paths` against overlapping
/// launches until integrated, discarded, or found empty.
///
/// Writes go through temp-file + rename: atomic against torn reads, NOT a
/// cross-process lock — two engines driving one repository can still race
/// silently (documented residual; the single-engine-per-repo assumption).
pub enum SubtaskState {
  Provisioning
  Running
  Captured
  Committed
  Conflicted
  Integrated
  Discarded
  NoChanges
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Terminal states hold no path reservation.
pub fn SubtaskState::is_terminal(self : SubtaskState) -> Bool {
  self is (Integrated | Discarded | NoChanges)
}

///|
/// One subtask's durable lifecycle record; see the file comment.
pub struct SubtaskEntry {
  priv schema_version : Int
  name : String
  priv nonce : String
  branch : String
  state : SubtaskState
  base_oid : String
  worker_root : String
  worker_admin_dir : String
  allowed_paths : Array[String]
  priv parent_session : String?
  commit_oid : String?
  priv origin_head_before : String?
  priv conflict_paths : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
let registry_schema_version : Int = 1

///|
/// Where entries live under the canonical common git dir.
fn registry_dir(common_git_dir : String) -> String {
  "\{common_git_dir}/openseek/subtasks"
}

///|
fn entry_path(common_git_dir : String, entry : SubtaskEntry) -> String {
  "\{registry_dir(common_git_dir)}/\{entry.name}--\{entry.nonce}.json"
}

///|
/// Persist `entry` atomically (temp + rename in the registry directory).
async fn save_entry(
  common_git_dir : String,
  entry : SubtaskEntry,
) -> Result[Unit, String] {
  let dir = registry_dir(common_git_dir)
  @fs.mkdir(dir, recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  let target = entry_path(common_git_dir, entry)
  let temp = "\{target}.tmp"
  @fs.write_file(
    temp,
    ToJson::to_json(entry).stringify(),
    create_mode=CreateOrTruncate,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => return Err("could not write registry entry: \{error}")
  }
  @fs.rename(temp, target) catch {
    error if @async.is_being_cancelled() => raise error
    error => return Err("could not commit registry entry: \{error}")
  }
  Ok(())
}

///|
/// Load every parseable entry. Unparseable files are skipped (a foreign or
/// future-schema record must not wedge provisioning) but their NAMES are
/// reported alongside so a caller can surface them.
pub async fn load_entries(
  common_git_dir : String,
) -> (Array[SubtaskEntry], Array[String]) {
  let entries : Array[SubtaskEntry] = []
  let skipped : Array[String] = []
  let dir = registry_dir(common_git_dir)
  let names = @fs.readdir(dir) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return (entries, skipped)
  }
  for name in names {
    guard name.has_suffix(".json") else { continue }
    let text = @fs.read_file("\{dir}/\{name}").text() catch {
      error if @async.is_being_cancelled() => raise error
      _ => {
        skipped.push(name)
        continue
      }
    }
    let json = @json.parse(text) catch {
      _ => {
        skipped.push(name)
        continue
      }
    }
    let parsed : SubtaskEntry = @json.from_json(json) catch {
      _ =>
        // Entries written before `conflict_paths` existed decode with the
        // field defaulted rather than being skipped: a skipped ACTIVE entry
        // would hide its reservation from provisioning.
        @json.from_json(with_default_conflict_paths(json)) catch {
          _ => {
            skipped.push(name)
            continue
          }
        }
    }
    if parsed.schema_version == registry_schema_version {
      entries.push(parsed)
    } else {
      skipped.push(name)
    }
  }
  (entries, skipped)
}

///|
/// A path split into its slash-separated components. Path containment here
/// is always component-wise, never textual: `src` must not cover `src2`.
fn components(prefix : String) -> Array[String] {
  prefix.split("/").map(part => part.to_owned()).collect()
}

///|
/// Whether `shorter` is a component-wise prefix of `longer` (equal counts as
/// covered).
fn one_covers(shorter : Array[String], longer : Array[String]) -> Bool {
  guard shorter.length() <= longer.length() else { return false }
  for index in 0..<shorter.length() {
    if shorter[index] != longer[index] {
      return false
    }
  }
  true
}

///|
/// Component-wise prefix overlap between two allowed-path sets: `src`
/// overlaps `src/lexer` and `src`, never `src2`.
fn paths_overlap(a : Array[String], b : Array[String]) -> Bool {
  a.any(left => {
    b.any(right => {
      let l = components(left)
      let r = components(right)
      one_covers(l, r) || one_covers(r, l)
    })
  })
}

///|
fn sample_entry() -> SubtaskEntry {
  {
    schema_version: 1,
    name: "fix-warnings",
    nonce: "ab12cd",
    branch: "openseek/fix-warnings--ab12cd",
    state: Running,
    base_oid: "0123456789abcdef0123456789abcdef01234567",
    worker_root: "/repo/.worktrees/fix-warnings",
    worker_admin_dir: "/repo/.git/worktrees/fix-warnings",
    allowed_paths: ["lib", "cmd/tool"],
    parent_session: Some("run-1"),
    commit_oid: None,
    origin_head_before: None,
    conflict_paths: [],
  }
}

///|
test "registry entry round-trips and states classify" {
  let entry = sample_entry()
  let parsed : SubtaskEntry = @json.from_json(ToJson::to_json(entry)) catch {
    e => fail("round-trip failed: \{e}")
  }
  assert_eq(parsed, entry)
  assert_false(Running.is_terminal())
  assert_false(Conflicted.is_terminal())
  assert_true(Integrated.is_terminal())
  assert_true(NoChanges.is_terminal())
}

///|
test "path overlap is component-wise in both directions" {
  assert_true(paths_overlap(["src"], ["src/lexer"]))
  assert_true(paths_overlap(["src/lexer"], ["src"]))
  assert_true(paths_overlap(["a", "b"], ["c", "b/d"]))
  assert_false(paths_overlap(["src"], ["src2"]))
  assert_false(paths_overlap(["a/b"], ["a/c"]))
}

///|
fn with_default_conflict_paths(json : Json) -> Json {
  match json {
    Object(map) => {
      // Mutating the matched map mutates the parsed value in place; the
      // original handle is returned rather than re-wrapped (Json's
      // constructors are read-only outside core).
      if !map.contains("conflict_paths") {
        map["conflict_paths"] = ([] : Array[String]).to_json()
      }
      json
    }
    other => other
  }
}

///|
pub extend SubtaskEntry with Debug::{to_repr}

///|
pub extend SubtaskEntry with FromJson::{from_json}

///|
pub extend SubtaskEntry with Eq::{equal, not_equal}

///|
pub extend SubtaskEntry with ToJson::{to_json}

///|
pub extend SubtaskState with Debug::{to_repr}

///|
pub extend SubtaskState with FromJson::{from_json}

///|
pub extend SubtaskState with Eq::{equal, not_equal}

///|
pub extend SubtaskState with ToJson::{to_json}
