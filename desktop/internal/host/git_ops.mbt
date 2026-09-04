// The composer's branch chip: report the git branch of a conversation's
// working directory, and how much uncommitted work sits on it. Display only —
// a missing repository (or a machine without git) simply reads as "no
// branch", never an error.

///|
async fn git_branch_op(payload : GitBranchPayload) -> GitBranchReply {
  // A live run hands us its cwd; a resumed conversation has none, so fall
  // back to the directory the session's engine runs in (mirrors
  // `host.open_path`).
  let base = match payload.cwd {
    Some(cwd) => @pathx.Absolute::from_uri_path(cwd)
    None => @work_dir.session_cwd(payload.session)
  }
  guard base is Some(base) else { return { branch: None, diffstat: None, } }
  guard git_branch(base.0) is Some(branch) else {
    // Not a repository, or no git: there is nothing to count either.
    return { branch: None, diffstat: None, }
  }
  let diffstat = git_diffstat(base, hint?=payload.base_hint)
  // The count takes long enough — a diff, plus one subprocess per untracked
  // file — for an agent to check out something else while it runs. The two
  // fields are applied together by the client, so a name from before the move
  // paired with totals from after it would read as one coherent answer while
  // being neither. Report the branch as it stands now, and let the next probe
  // supply totals to match it.
  //
  // What this cannot catch is a checkout that leaves and returns inside the
  // same count: the name matches at both ends while some files were read on
  // the other branch. Catching it needs a repository-mutation marker, and Git
  // offers none that is always there — the reflog can be switched off — so the
  // detection would be as unreliable as the race is rare, and the only remedy
  // it enables is measuring again, possibly without end. The totals are a
  // display figure that every run boundary and every popover opening
  // recomputes; a two-checkout round trip inside one count corrects itself at
  // the next one.
  guard git_branch(base.0) is Some(after) else {
    return { branch: None, diffstat: None, }
  }
  if after != branch {
    return { branch: Some(after), diffstat: None, }
  }
  { branch: Some(branch), diffstat, }
}

///|
/// The branch checked out at `dir` (`git rev-parse --abbrev-ref HEAD`), with
/// a detached HEAD named by its short hash instead of the literal "HEAD".
/// None when `dir` is not a git repository or git is unavailable.
async fn git_branch(dir : String) -> String? {
  let name = git_output(dir, ["rev-parse", "--abbrev-ref", "HEAD"])
  let name = if name == "HEAD" {
    git_output(dir, ["rev-parse", "--short", "HEAD"])
  } else if name.is_empty() {
    // An unborn HEAD has no commit for `rev-parse` to resolve — it fails
    // outright — but the symbolic branch is already there. That is the state a
    // fresh `git init` leaves, where every line is staged or untracked and so
    // is exactly what the diffstat's empty-tree baseline exists to count.
    git_output(dir, ["symbolic-ref", "--short", "HEAD"])
  } else {
    name
  }
  if name.is_empty() {
    None
  } else {
    Some(name)
  }
}

///|
/// The branch `HEAD` points at, and nothing else. Unlike `git_branch` this
/// does not stand in a short hash for a detached checkout: a hash is a fine
/// thing to show a person and a nonsense thing to hand an API that filters by
/// branch name.
async fn git_symbolic_branch(dir : String) -> String? {
  guard git_output_opt(dir, ["symbolic-ref", "--short", "--quiet", "HEAD"])
    is Some(output) else {
    return None
  }
  let name = git_single_line(output)
  if name.is_empty() {
    None
  } else {
    Some(name)
  }
}

///|
/// Whether some remote already has `branch`. Read from the remote-tracking
/// refs, so it answers for the state this checkout last saw — which is exactly
/// the state a push from here updates.
async fn git_branch_on_remote(dir : String, branch : String) -> Bool {
  for remote in git_remotes(dir) {
    if git_output_opt(dir, [
        "rev-parse",
        "--verify",
        "--quiet",
        "refs/remotes/\{remote}/\{branch}",
      ])
      is Some(_) {
      return true
    }
  }
  false
}

///|
/// The configured remotes, in Git's order.
async fn git_remotes(dir : String) -> Array[String] {
  let remotes : Array[String] = []
  guard git_output_opt(dir, ["remote"]) is Some(listing) else { return remotes }
  for line in listing.split("\n") {
    let remote = line.trim_end(chars="\r")
    if !remote.is_empty() {
      remotes.push(remote.to_owned())
    }
  }
  remotes
}

///|
/// Git's empty tree. A repository whose `HEAD` has no commit yet still has an
/// index worth diffing, and every Git version spells this baseline object the
/// same way, so it is a constant rather than something to ask the repository
/// for.
const EmptyTreeObject : String = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

///|
/// How many untracked files the diffstat counts before it settles for
/// `partial`. Each one costs a `git diff` of its own, and a workspace holding
/// hundreds of them has an unignored build directory rather than that much
/// work in progress.
const MaxUntrackedDiffFiles : Int = 100

///|
/// How large an untracked file may be and still be counted. `git diff
/// --no-index` reads the whole file to count its lines — measured at roughly
/// twice the file's size resident — and this runs thirty-two at a time, at
/// every run boundary and every time the popover opens. An unignored dataset
/// or log would turn a decorative chip into gigabytes of repeated reading, so
/// anything this large is left out of the count and marked `partial` instead.
/// The reader's own one-megabyte ceiling is the precedent.
const MaxUntrackedDiffBytes : Int64 = 1048576L

///|
/// How long either half of the diffstat may take. This is a number beside a
/// branch name, refreshed at every run boundary and every time the popover
/// opens, so it answers in about the time a glance takes or it does not
/// answer: a repository slow enough to reach this will be slow again on the
/// next probe, and reporting nothing beats holding a bridge request open.
/// Generous against what the work actually costs — a modified 128 MiB tracked
/// text file measured 1.5s — so only the genuinely pathological trips it.
const DiffstatTimeoutMs : Int = 5000

///|
/// This branch's whole delta, counted locally: from where it left its base
/// straight to the working tree, so a commit and an unsaved edit weigh the
/// same and the number keeps moving as the agent works. Which base is
/// `git_branch_base`'s problem — `hint` carries what the branch's pull request
/// says, when the client has heard from one.
async fn git_diffstat(dir : @pathx.Absolute, hint? : String) -> GitDiffStat? {
  let native = dir.0
  // An unborn HEAD has no commit to diff against, but its index can already
  // hold staged additions, so the empty tree stands in for the missing commit.
  guard git_output_opt(native, ["rev-parse", "--verify", "--quiet", "HEAD"])
    is Some(_) else {
    return git_diffstat_from(dir, EmptyTreeObject, None)
  }
  let (baseline, base) = git_branch_base(native, hint?)
  git_diffstat_from(dir, baseline, base)
}

///|
/// The remote-tracking ref to measure from. A hinted branch is looked for on
/// `origin`, the repository a pull request's base belongs to for every
/// checkout that is not a fork; a hint `origin` does not have falls through to
/// the default rather than measuring from nothing.
async fn git_base_ref(dir : String, hint? : String) -> String? {
  if hint is Some(branch) && !branch.is_empty() {
    let hinted = "origin/\{branch}"
    if git_output_opt(dir, ["rev-parse", "--verify", "--quiet", hinted])
      is Some(_) {
      return Some(hinted)
    }
  }
  guard git_output_opt(dir, [
      "rev-parse", "--abbrev-ref", "--verify", "--quiet", "origin/HEAD",
    ])
    is Some(output) else {
    return None
  }
  let name = git_single_line(output)
  // A dangling `origin/HEAD` abbreviates to itself and names no branch.
  if name.is_empty() || name == "origin/HEAD" {
    None
  } else {
    Some(name)
  }
}

///|
/// Whether `branch` is the repository's own default branch. The symbolic
/// remote-tracking ref is Git's local statement of that identity; comparing
/// names, rather than commits, keeps a feature branch made at the current
/// default-branch tip eligible for its own pull request.
async fn git_is_default_branch(dir : String, branch~ : String) -> Bool {
  git_base_ref(dir) == Some("origin/\{branch}")
}

///|
/// Where this branch's work starts, and the ref that decided it.
///
/// `hint` is the branch the caller already knows this one merges into, taken
/// from its pull request. That is the only exact answer there is: a branch
/// records nothing about where it came from, and a base that is itself a
/// feature branch — a stacked pull request — is not something a local rule
/// could produce, since a local rule can only ever consider default branches.
///
/// Without a hint the answer is `origin/HEAD`, the remote's own statement of
/// its default branch. Being one guess rather than a search it is wrong in the
/// same place every time: a fork checkout with no pull request yet measures
/// against the fork's default, which may sit far behind the upstream the
/// branch was really cut from. Opening the pull request corrects it.
///
/// Falling back to `HEAD` — no origin, no default branch, unrelated histories
/// — leaves the count covering uncommitted work alone, which the absent ref
/// name tells the composer to say out loud instead of implying a comparison
/// never made.
async fn git_branch_base(dir : String, hint? : String) -> (String, String?) {
  guard git_base_ref(dir, hint?) is Some(base_ref) else {
    return ("HEAD", None)
  }
  guard git_output_opt(dir, ["merge-base", "HEAD", base_ref]) is Some(output) else {
    return ("HEAD", None)
  }
  let commit = git_single_line(output)
  if commit.is_empty() {
    ("HEAD", None)
  } else {
    (commit, Some(base_ref))
  }
}

///|
/// The committed branch delta an ordinary (non-worktree) Review should keep
/// visible. `head` is the full identity captured by the surrounding snapshot,
/// rather than the mutable `HEAD` spelling, so a concurrent checkout cannot
/// choose one branch's fork point and publish another branch's rows.
///
/// A branch still at its default-branch fork point returns `None`. That keeps
/// the original porcelain status path — and its separate staged/worktree
/// columns — until there is committed branch work to retain. With no declared
/// default branch there is no defensible historical boundary, so Review also
/// stays HEAD-based instead of guessing from commit ancestry.
async fn git_review_branch_base(dir : String, head : String?) -> String? {
  guard head is Some(head) else { return None }
  guard git_base_ref(dir) is Some(base_ref) else { return None }
  guard git_output_opt(dir, ["merge-base", head, base_ref]) is Some(output) else {
    return None
  }
  let base = git_single_line(output)
  if base.is_empty() || base == head {
    None
  } else {
    Some(base)
  }
}

///|
/// Sum everything between `baseline` and the working tree: one `git diff
/// --numstat` for what Git tracks, plus the untracked files counted one at a
/// time. None when Git could not answer at all — the branch chip stands on its
/// own.
async fn git_diffstat_from(
  dir : @pathx.Absolute,
  baseline : String,
  base : String?,
) -> GitDiffStat? {
  let native = dir.0
  // `-- .` scopes the diff to the conversation workspace, which may be a
  // subdirectory of the repository, exactly as `git.changes` does. With no
  // second revision the comparison runs to the working tree, so uncommitted
  // edits land in the same total as the commits before them.
  //
  // Nothing bounds what this reads: the per-file caps below cover untracked
  // files, while a tracked one is inside the diff Git computes in one go. A
  // modified 128 MiB tracked text file measured 1.5s locally, so a repository
  // that keeps generated artifacts under version control can run far longer
  // than a glance — hence the deadline rather than a size rule, which would
  // silently score a large file that Git would have counted fine as zero.
  guard @async.with_timeout_opt(DiffstatTimeoutMs, () => {
      git_output_opt(native, ["diff", "--numstat", baseline, "--", "."])
    })
    is Some(Some(tracked)) else {
    // Git failed, or it is still going. Either way nothing is counted, so
    // there is no floor to report and the chip stands on the branch alone.
    return None
  }
  let tracked = { ..parse_numstat(tracked), base, }
  guard git_output_opt(native, [
      "ls-files", "--others", "--exclude-standard", "-z", "--", ".",
    ])
    is Some(listing) else {
    // The listing itself was unreadable — a filename that is not valid UTF-8
    // defeats the text conversion even though Git succeeded. Every untracked
    // file is then missing from the total, which is a floor, not the whole.
    return Some({ ..tracked, partial: true, })
  }
  // `--others` spells its paths from Git's current directory, which is this
  // workspace. Validating each one lexically keeps a path that cannot address
  // a file under the workspace from reaching the command line at all.
  let paths : Array[@pathx.Relative] = []
  let mut partial = false
  for path in listing.split("\u{0}") {
    // The listing is NUL-terminated, so its last field is empty by
    // construction — that is the record separator, not a file left out.
    guard !path.is_empty() else { continue }
    guard git_tree_relative(path.to_owned()) is Some(relative) else {
      partial = true
      continue
    }
    if paths.length() >= MaxUntrackedDiffFiles {
      partial = true
      break
    }
    paths.push(relative)
  }
  // Bounded per file, but a hundred of them on a slow filesystem is still a
  // wait nobody asked for. The tracked side is already counted here, so a
  // deadline reached leaves a floor rather than nothing.
  guard @async.with_timeout_opt(DiffstatTimeoutMs, () => {
      @async.all(
        [
          for path in paths => {
            () => {
              guard untracked_is_countable(dir, path) else { return None }
              git_untracked_numstat(dir, path)
            }
          }
        ],
        max_concurrent=32,
      )
    })
    is Some(counts) else {
    return Some({ ..tracked, partial: true, })
  }
  let mut added = tracked.added
  let mut files = tracked.files
  for count in counts {
    if count is Some(count) {
      added += count.added
      files += count.files
    } else {
      // A file that could not be counted leaves the total a floor, and the
      // chip says so rather than presenting it as the whole.
      partial = true
    }
  }
  Some({ added, removed: tracked.removed, files, base, partial, })
}

///|
/// Whether counting this untracked file is worth handing to Git, decided
/// before any subprocess exists.
///
/// Two things are refused. Anything that is not a regular file: a named pipe
/// in the workspace would leave `git diff --no-index` waiting on a writer that
/// may never come, and the probe has no business blocking on one. And anything
/// past `MaxUntrackedDiffBytes`, since Git reads the whole file to count its
/// lines. The kind is checked first because opening a pipe to size it would
/// block just as surely.
///
/// A refusal is reported as a failure, which the caller already turns into a
/// `partial` total — the file did not vanish, it simply was not counted.
async fn untracked_is_countable(
  dir : @pathx.Absolute,
  path : @pathx.Relative,
) -> Bool {
  let native = dir.join(path).to_string()
  let kind = @fs.kind(native, follow_symlink=false) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  guard kind is Regular else { return false }
  let file = @fs.open(native, mode=ReadOnly) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  defer file.close()
  let size = file.size() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  size <= MaxUntrackedDiffBytes
}

///|
/// One untracked file's line count, which `git diff --numstat` cannot report:
/// numstat only sees what Git tracks, and `git add --intent-to-add` would
/// write to the user's index to answer a display question. Diffing against
/// `/dev/null` — a magic path name in Git's no-index mode on every platform,
/// not a device file — buys Git's own counting, binary detection included.
/// `--no-index` reports "there are differences" as exit status 1, the way
/// `diff` does, so only a higher status is a failure.
async fn git_untracked_numstat(
  dir : @pathx.Absolute,
  path : @pathx.Relative,
) -> GitDiffStat? {
  let (code, stdout, _) = @processx.collect_output_no_stdin(
    "git",
    ["diff", "--numstat", "--no-index", "--", "/dev/null", path.0],
    cwd=dir.0,
    extra_env=git_environment(),
    inherit_env=false,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  guard code <= 1 else { return None }
  let stat = parse_numstat(stdout.text() catch { _ => return None })
  // Status 1 is `--no-index`'s "there were differences", but it is also what a
  // path Git could not read exits with — a file the agent deleted between
  // `ls-files` and this command, which is an ordinary race in a live
  // workspace. The two are told apart by the output: a real difference always
  // produces a record, so status 1 with none is the failure.
  guard !(code == 1 && stat.files == 0) else { return None }
  Some(stat)
}

///|
/// Sum `git diff --numstat` output. Only the two leading counts are read: the
/// path field is quoted, escaped, and respelled for renames, and nothing here
/// needs it. A binary file reports `-` for both counts, contributing a changed
/// file with no lines rather than a parse failure. The caller supplies the
/// baseline this was measured from; the numbers alone do not know it.
fn parse_numstat(output : String) -> GitDiffStat {
  let mut added = 0
  let mut removed = 0
  let mut files = 0
  for line in output.split("\n") {
    let line = line.trim_end(chars="\r")
    guard line.find("\t") is Some(first) else { continue }
    let rest = line.view(start_offset=first + 1)
    guard rest.find("\t") is Some(second) else { continue }
    files += 1
    added += @string.parse_int(line.view(end_offset=first)) catch { _ => 0 }
    removed += @string.parse_int(rest.view(end_offset=second)) catch { _ => 0 }
  }
  { added, removed, files, base: None, partial: false, }
}

///|
/// Run Git for a result that may legitimately be empty. Unlike `git_output`, a
/// command that failed reads as None rather than an empty string, so a caller
/// whose empty output means "nothing changed" can tell the two apart.
async fn git_output_opt(dir : String, args : Array[String]) -> String? {
  let (code, stdout, _) = @processx.collect_output_no_stdin(
    "git",
    args,
    cwd=dir,
    extra_env=git_environment(),
    inherit_env=false,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  guard code == 0 else { return None }
  Some(stdout.text() catch { _ => return None })
}

///|
/// Remove Git subprocess overrides while retaining PATH, identity, locale, and
/// the user's ordinary Git configuration through HOME/XDG_CONFIG_HOME. Hooks
/// and nested Git commands export repository-local variables, and explicit
/// config/quarantine overrides can redirect object and hook lookup too. The
/// desktop host must instead discover everything from its validated workspace
/// `cwd`. Matching is case-insensitive because Windows preserves arbitrary key
/// casing; removing the whole namespace also covers future Git overrides.
fn sanitize_git_environment(env : Map[String, String]) -> Unit {
  let remove : Array[String] = []
  for name, _ in env {
    if name.to_upper().has_prefix("GIT_") {
      remove.push(name)
    }
  }
  for name in remove {
    env.remove(name)
  }
}

///|
fn git_environment() -> Map[String, String] {
  let env = @sys.get_env_vars()
  sanitize_git_environment(env)
  env
}

///|
async fn git_output(dir : String, args : Array[String]) -> String {
  let (code, stdout, _) = @processx.collect_output_no_stdin(
    "git",
    args,
    cwd=dir,
    extra_env=git_environment(),
    inherit_env=false,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return ""
  }
  guard code == 0 else { return "" }
  (stdout.text() catch { _ => "" }).trim().to_owned()
}

///|
/// The presentation category for Git's two porcelain status columns.
fn git_change_kind(index_status : String, worktree_status : String) -> String {
  let pair = index_status + worktree_status
  if ["DD", "AU", "UD", "UA", "DU", "AA", "UU"].contains(pair) {
    "unmerged"
  } else if index_status == "U" || worktree_status == "U" {
    // `git diff --name-status` uses one column rather than porcelain's
    // two-column conflict pairs.
    "unmerged"
  } else if pair == "??" {
    "untracked"
  } else if index_status == "R" || worktree_status == "R" {
    "renamed"
  } else if index_status == "C" || worktree_status == "C" {
    "copied"
  } else if index_status == "D" || worktree_status == "D" {
    "deleted"
  } else if index_status == "A" || worktree_status == "A" {
    "added"
  } else if index_status == "T" || worktree_status == "T" {
    "type-changed"
  } else {
    "modified"
  }
}

///|
/// Stable display order for duplicate current paths. A baseline deletion must
/// precede its untracked recreation even though `Array::sort_by` is unstable.
fn compare_git_change_path(left : GitChange, right : GitChange) -> Int {
  let path_order = left.path.lexical_compare(right.path)
  if path_order != 0 {
    return path_order
  }
  let left_untracked = if left.kind == "untracked" { 1 } else { 0 }
  let right_untracked = if right.kind == "untracked" { 1 } else { 0 }
  left_untracked - right_untracked
}

///|
/// Parse `git status --porcelain=v1 -z`. In `-z` mode rename/copy rows spell
/// the destination in the status record and consume the following NUL field
/// as their source, without the human-facing ` -> ` separator.
fn parse_git_status_z(output : String) -> Array[GitChange] {
  let fields = output.split("\u{0}").map(field => field.to_owned()).collect()
  let changes : Array[GitChange] = []
  let mut index = 0
  while index < fields.length() {
    let record = fields[index]
    if record.length() < 4 {
      index += 1
      continue
    }
    let index_status = record.view(end_offset=1).to_owned()
    let worktree_status = record.view(start_offset=1, end_offset=2).to_owned()
    let path = record.view(start_offset=3).to_owned()
    let has_source = index_status == "R" ||
      worktree_status == "R" ||
      index_status == "C" ||
      worktree_status == "C"
    let original_path = if has_source &&
      index + 1 < fields.length() &&
      !fields[index + 1].is_empty() {
      index += 1
      Some(fields[index])
    } else {
      None
    }
    changes.push({
      path,
      original_path,
      index_status,
      worktree_status,
      kind: git_change_kind(index_status, worktree_status),
    })
    index += 1
  }
  changes.sort_by(compare_git_change_path)
  changes
}

///|
/// Parse `git diff --name-status -z`. NUL mode emits the status as its own
/// field, followed by one path for ordinary changes or source + destination
/// for renames and copies. Task comparisons are one logical working-tree
/// column; unlike porcelain status, they intentionally do not claim anything
/// about what is currently staged.
fn parse_git_diff_name_status_z(output : String) -> Array[GitChange] {
  if !output.is_empty() && !output.has_suffix("\u{0}") {
    return []
  }
  let fields = output.split("\u{0}").map(field => field.to_owned()).collect()
  let changes : Array[GitChange] = []
  let mut index = 0
  while index < fields.length() {
    let status = fields[index]
    index += 1
    if status.is_empty() {
      continue
    }
    let code = status.view(end_offset=1).to_owned()
    let has_source = code == "R" || code == "C"
    let field_count = if has_source { 2 } else { 1 }
    if index + field_count > fields.length() {
      break
    }
    let original_path = if has_source { Some(fields[index]) } else { None }
    let path_offset = if has_source { 1 } else { 0 }
    let path = fields[index + path_offset]
    index += field_count
    if path.is_empty() || original_path is Some("") {
      break
    }
    changes.push({
      path,
      original_path,
      index_status: " ",
      worktree_status: code,
      kind: git_change_kind(" ", code),
    })
  }
  changes.sort_by(compare_git_change_path)
  changes
}

///|
/// `git ls-files --others -z` emits bare NUL-delimited paths. Task review uses
/// this cheaper index query instead of running full porcelain status only to
/// discard every tracked row.
fn parse_git_untracked_z(output : String) -> Array[GitChange] {
  if !output.is_empty() && !output.has_suffix("\u{0}") {
    return []
  }
  let changes : Array[GitChange] = []
  for path in output.split("\u{0}") {
    if !path.is_empty() {
      changes.push({
        path: path.to_owned(),
        original_path: None,
        index_status: "?",
        worktree_status: "?",
        kind: "untracked",
      })
    }
  }
  changes.sort_by(compare_git_change_path)
  changes
}

///|
/// `git diff <base>` includes committed, staged, and unstaged tracked paths
/// but omits untracked files. Add those porcelain rows without duplicating an
/// ordinary task row. A deleted baseline path recreated as untracked keeps
/// both rows, matching porcelain's existing delete + recreate representation.
fn git_task_changes_with_untracked(
  changes : Array[GitChange],
  status_changes : Array[GitChange],
) -> Array[GitChange] {
  let seen : Set[String] = Set([])
  let deleted : Set[String] = Set([])
  for change in changes {
    seen.add(change.path)
    if change.kind == "deleted" {
      deleted.add(change.path)
    }
  }
  for change in status_changes {
    if change.kind == "untracked" &&
      (!seen.contains(change.path) || deleted.contains(change.path)) {
      changes.push(change)
    }
  }
  changes.sort_by(compare_git_change_path)
  changes
}

///|
/// Porcelain v1 always spells paths from the repository root. Convert one
/// row back to the conversation workspace, which may itself be an attached
/// repository subdirectory. `git status -- .` guarantees the current path is
/// inside that prefix; defensively drop any row that violates that boundary.
/// A rename source outside the attached subdirectory is not addressable by
/// the workspace-scoped baseline endpoint, so omit only that source metadata.
fn git_change_relative_to_workspace(
  change : GitChange,
  workspace_prefix : String,
) -> GitChange? {
  guard git_path_relative_to_workspace(change.path, workspace_prefix)
    is Some(path) else {
    return None
  }
  let original_path = match change.original_path {
    Some(original) => git_path_relative_to_workspace(original, workspace_prefix)
    _ => None
  }
  Some({ ..change, path, original_path, })
}

///|
fn git_path_relative_to_workspace(
  path : String,
  workspace_prefix : String,
) -> String? {
  let path = if workspace_prefix.is_empty() {
    path
  } else {
    guard path.has_prefix(workspace_prefix) else { return None }
    path.view(start_offset=workspace_prefix.length()).to_owned()
  }
  if path.is_empty() {
    None
  } else {
    Some(path)
  }
}

///|
/// Extract one entry mode from `git ls-files --stage -z` or `git ls-tree -z`.
/// Index/HEAD metadata keeps gitlinks and symlinks identifiable even when a
/// sparse checkout or deletion leaves no path to inspect. Both formats start
/// with the six-digit mode and keep the byte-exact path after a tab.
fn parse_git_mode_paths(
  output : String,
  workspace_prefix : String,
  mode : String,
) -> Set[String] {
  let paths : Set[String] = Set([])
  let prefix = mode + " "
  for record in output.split("\u{0}") {
    guard record.has_prefix(prefix) && record.find("\t") is Some(tab) else {
      continue
    }
    let path = record.view(start_offset=tab + 1).to_owned()
    if git_path_relative_to_workspace(path, workspace_prefix) is Some(relative) {
      paths.add(relative)
    }
  }
  paths
}

///|
/// Keep targeted `ls-tree` argv comfortably below Windows' command-line limit
/// (and every supported Unix ARG_MAX). An individually over-limit path asks
/// the caller to use one recursive workspace tree walk instead.
const MaxGitTreePathBatchBytes = 16_384

///|
/// Targeted HEAD mode discovery is cheaper than walking the full workspace
/// tree only while it needs a small, bounded number of Git subprocesses.
/// Beyond this cap one recursive `ls-tree` has lower fixed overhead.
const MaxTargetedGitTreeQueries = 8

///|
fn git_tree_path_batches(paths : Array[String]) -> Array[Array[String]] {
  let batches : Array[Array[String]] = []
  let mut batch : Array[String] = []
  let mut bytes = 0
  for path in paths {
    // Git argv is UTF-8 on Unix and the byte bound is deliberately also
    // conservative for Windows' UTF-16 command line. Character count would
    // under-budget non-ASCII repository paths by up to four times.
    let path_bytes = @utf8.encode(path).length() + 1
    if path_bytes > MaxGitTreePathBatchBytes {
      return []
    }
    if !batch.is_empty() && bytes + path_bytes > MaxGitTreePathBatchBytes {
      if batches.length() >= MaxTargetedGitTreeQueries {
        return []
      }
      batches.push(batch)
      batch = []
      bytes = 0
    }
    batch.push(path)
    bytes += path_bytes
  }
  if !batch.is_empty() {
    if batches.length() >= MaxTargetedGitTreeQueries {
      return []
    }
    batches.push(batch)
  }
  batches
}

///|
/// Collect each deleted status path once without repeatedly scanning the
/// growing result during a bulk deletion.
fn deleted_change_paths(changes : Array[GitChange]) -> Array[String] {
  let paths : Array[String] = []
  let seen : Set[String] = Set([])
  for change in changes {
    if change.kind == "deleted" && !seen.contains(change.path) {
      seen.add(change.path)
      paths.push(change.path)
    }
  }
  paths
}

///|
/// Git's ordinary porcelain columns do not distinguish a changed gitlink from
/// a changed regular file or expose the working tree's symlink kind. Preserve
/// the raw columns while keeping both non-file kinds out of ordinary readers.
fn git_change_with_path_kind(
  change : GitChange,
  path_kind : @fs.FileKind,
  known_gitlink : Bool,
  known_symlink : Bool,
) -> GitChange {
  match path_kind {
    SymLink => { ..change, kind: "symlink", }
    Directory if change.kind != "untracked" => { ..change, kind: "submodule", }
    Unknown if known_gitlink => { ..change, kind: "submodule", }
    Unknown if known_symlink => { ..change, kind: "symlink", }
    _ => change
  }
}

///|
/// Git's textual plumbing commands terminate their single-line output with a
/// line ending. Remove only that terminator: leading or trailing spaces can be
/// significant in repository paths.
fn git_single_line(output : String) -> String {
  output.trim_end(chars="\r\n").to_owned()
}

///|
/// Validate an untrusted Git tree path lexically. Unlike ordinary file reads,
/// this must not follow the current working-tree symlink: `HEAD:path` reads a
/// repository object and is safe even when that symlink now points outside.
fn git_tree_relative(path : String) -> @pathx.Relative? {
  guard @pathx.Path(path).to_relative() is Some(relative) else { return None }
  let relative = relative.normalize()
  guard relative.0 != ".." && !relative.0.has_prefix("../") else { return None }
  Some(relative)
}

///|
/// Run Git without trimming or merging stdout: porcelain `-z` and blob bytes
/// are byte-sensitive. Cancellation remains observable to the connection;
/// other spawn failures become ordinary request errors.
async fn git_collect(
  dir : String,
  args : Array[String],
) -> (Int, &@io.Data, &@io.Data) {
  @processx.collect_output_no_stdin(
    "git",
    args,
    cwd=dir,
    extra_env=git_environment(),
    inherit_env=false,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to run Git: \{error}")
  }
}

///|
/// Capture the exact index entries used by one review snapshot. Task mode
/// reads this again after its diff/untracked queries, so an index-only change
/// retries just like a concurrent commit instead of publishing mixed rows.
async fn git_index_metadata(dir : String) -> String {
  let (code, stdout, stderr) = git_collect(dir, [
    "ls-files", "--full-name", "--stage", "-z", "--", ".",
  ])
  guard code == 0 else {
    let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
    raise HostError(
      if detail.is_empty() {
        "failed to inspect Git index"
      } else {
        detail
      },
    )
  }
  stdout.text() catch {
    _ => raise HostError("Git returned a non-UTF-8 index path")
  }
}

///|
/// Resolve one revision to an immutable commit identity. A missing revision is
/// ordinary (an unborn HEAD or an object that disappeared); malformed command
/// output is a host failure rather than an ambiguous missing baseline.
async fn git_revision_commit(dir : String, revision : String) -> String? {
  let (code, stdout, _) = git_collect(dir, [
    "rev-parse",
    "--verify",
    "\{revision}^{commit}",
  ])
  if code != 0 {
    return None
  }
  let commit = git_single_line(
    stdout.text() catch {
      _ => raise HostError("Git returned a non-UTF-8 revision identity")
    },
  )
  if commit.is_empty() {
    None
  } else {
    Some(commit)
  }
}

///|
fn valid_commit_identity(revision : String) -> Bool {
  if revision.length() != 40 && revision.length() != 64 {
    return false
  }
  for character in revision {
    let code = character.to_int()
    let digit = code >= '0'.to_int() && code <= '9'.to_int()
    let lower = code >= 'a'.to_int() && code <= 'f'.to_int()
    let upper = code >= 'A'.to_int() && code <= 'F'.to_int()
    if !(digit || lower || upper) {
      return false
    }
  }
  true
}

///|
test "Git review revisions accept only full hexadecimal object identities" {
  assert_true(valid_commit_identity("0123456789abcdef0123456789abcdef01234567"))
  assert_true(
    valid_commit_identity(
      "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF",
    ),
  )
  assert_false(valid_commit_identity("HEAD"))
  assert_false(valid_commit_identity("--all"))
  assert_false(
    valid_commit_identity("0123456789abcdef0123456789abcdef0123456g"),
  )
}

///|
/// Read the review inventory while HEAD remains the same. A worktree task uses
/// its immutable creation commit; an ordinary checkout with committed branch
/// work uses its default-branch fork point; otherwise Review retains
/// porcelain's HEAD status. Bracket the snapshot with revision reads and retry
/// a concurrent commit/checkout instead of relying on the next poll to
/// self-heal.
async fn git_change_snapshot(
  dir : String,
  workspace_prefix : String,
  pinned_review_base : String?,
  retries_left : Int,
) -> (
  String?,
  String?,
  Set[String],
  Set[String],
  Set[String],
  Set[String],
  Array[GitChange],
) {
  let head = git_revision_commit(dir, "HEAD")
  let review_base = match pinned_review_base {
    Some(base) => Some(base)
    None => git_review_branch_base(dir, head)
  }
  let index_metadata = git_index_metadata(dir)
  let known_gitlinks = parse_git_mode_paths(
    index_metadata, workspace_prefix, "160000",
  )
  let known_symlinks = parse_git_mode_paths(
    index_metadata, workspace_prefix, "120000",
  )
  let status_changes = match review_base {
    Some(_) => {
      let (code, stdout, stderr) = git_collect(dir, [
        "ls-files", "--full-name", "--others", "--exclude-standard", "-z", "--",
        ".",
      ])
      guard code == 0 else {
        let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
        raise HostError(
          if detail.is_empty() {
            "failed to read untracked Git paths"
          } else {
            detail
          },
        )
      }
      let raw = stdout.text() catch {
        _ => raise HostError("Git returned a non-UTF-8 untracked path")
      }
      parse_git_untracked_z(raw).filter_map(change => {
        git_change_relative_to_workspace(change, workspace_prefix)
      })
    }
    None => {
      let (code, stdout, stderr) = git_collect(dir, [
        "status", "--porcelain=v1", "-z", "--untracked-files=all", "--", ".",
      ])
      guard code == 0 else {
        let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
        raise HostError(
          if detail.is_empty() {
            "failed to read Git changes"
          } else {
            detail
          },
        )
      }
      let raw = stdout.text() catch {
        _ => raise HostError("Git returned a non-UTF-8 changed path")
      }
      parse_git_status_z(raw).filter_map(change => {
        git_change_relative_to_workspace(change, workspace_prefix)
      })
    }
  }
  let changes = match review_base {
    Some(base) => {
      // Exhaustive copy discovery scans unchanged sources and is too costly
      // for a three-second poll. Copies without cheap Git evidence remain
      // correct additions with an empty baseline.
      let (diff_code, diff_stdout, diff_stderr) = git_collect(dir, [
        "diff", "--name-status", "-z", "--no-ext-diff", "--find-renames", base, "--",
        ".",
      ])
      guard diff_code == 0 else {
        let detail = (diff_stderr.text() catch { _ => "" }).trim().to_owned()
        raise HostError(
          if detail.is_empty() {
            "failed to read Git task changes"
          } else {
            detail
          },
        )
      }
      let diff_raw = diff_stdout.text() catch {
        _ => raise HostError("Git returned a non-UTF-8 task path")
      }
      let task_changes = parse_git_diff_name_status_z(diff_raw).filter_map(change => {
        git_change_relative_to_workspace(change, workspace_prefix)
      })
      git_task_changes_with_untracked(task_changes, status_changes)
    }
    None => status_changes
  }
  // Deleted paths no longer exist in the index. Query only those paths in the
  // pinned comparison tree instead of walking the full workspace on each
  // three-second poll; this keeps gitlinks and symlinks inert cheaply.
  let deleted_paths = deleted_change_paths(changes)
  let comparison = match review_base {
    Some(base) => Some(base)
    None => head
  }
  let deleted_gitlinks : Set[String] = Set([])
  let deleted_symlinks : Set[String] = Set([])
  if comparison is Some(commit) && !deleted_paths.is_empty() {
    let path_batches = git_tree_path_batches(deleted_paths)
    let full_tree = path_batches.is_empty()
    let batches = if full_tree { [["."]] } else { path_batches }
    for batch in batches {
      let tree_args = ["--literal-pathspecs", "ls-tree"]
      if full_tree {
        tree_args.push("-r")
      }
      tree_args.push("--full-name")
      tree_args.push("-z")
      tree_args.push(commit)
      tree_args.push("--")
      for path in batch {
        tree_args.push(path)
      }
      let (tree_code, tree_stdout, tree_stderr) = git_collect(dir, tree_args)
      guard tree_code == 0 else {
        let detail = (tree_stderr.text() catch { _ => "" }).trim().to_owned()
        raise HostError(
          if detail.is_empty() {
            "failed to inspect Git review tree"
          } else {
            detail
          },
        )
      }
      let comparison_metadata = tree_stdout.text() catch {
        _ => raise HostError("Git returned a non-UTF-8 review tree path")
      }
      let comparison_gitlinks = parse_git_mode_paths(
        comparison_metadata, workspace_prefix, "160000",
      )
      for path in comparison_gitlinks {
        deleted_gitlinks.add(path)
      }
      let comparison_symlinks = parse_git_mode_paths(
        comparison_metadata, workspace_prefix, "120000",
      )
      for path in comparison_symlinks {
        deleted_symlinks.add(path)
      }
    }
  }
  if review_base is Some(_) && git_index_metadata(dir) != index_metadata {
    if retries_left > 0 {
      return git_change_snapshot(
        dir,
        workspace_prefix,
        pinned_review_base,
        retries_left - 1,
      )
    }
    raise HostError("Git index kept changing while task changes were read")
  }
  let confirmed_head = git_revision_commit(dir, "HEAD")
  if confirmed_head != head {
    if retries_left > 0 {
      return git_change_snapshot(
        dir,
        workspace_prefix,
        pinned_review_base,
        retries_left - 1,
      )
    }
    raise HostError("HEAD kept changing while Git changes were read")
  }
  (
    head, review_base, known_gitlinks, known_symlinks, deleted_gitlinks, deleted_symlinks,
    changes,
  )
}

///|
async fn git_changes_op(payload : GitChangesPayload) -> GitChangesReply {
  guard @work_dir.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(root) else {
    raise HostError("could not resolve the conversation workspace")
  }
  let dir = root.to_string()
  if git_output(dir, ["rev-parse", "--is-inside-work-tree"]) != "true" {
    return { repository: false, head: None, baseline: None, changes: [], }
  }
  let (prefix_code, prefix_stdout, prefix_stderr) = git_collect(dir, [
    "rev-parse", "--show-prefix",
  ])
  guard prefix_code == 0 else {
    let detail = (prefix_stderr.text() catch { _ => "" }).trim().to_owned()
    raise HostError(
      if detail.is_empty() {
        "failed to resolve Git workspace prefix"
      } else {
        detail
      },
    )
  }
  let workspace_prefix = git_single_line(
    prefix_stdout.text() catch {
      _ => raise HostError("Git returned a non-UTF-8 workspace prefix")
    },
  )
  let recorded_base = @work_dir.session_review_base(
    payload.session,
    workspace?=payload.workspace,
  )
  let pinned_base = match recorded_base {
    Some(base) => {
      guard valid_commit_identity(base) else {
        raise HostError("recorded Git task baseline is invalid")
      }
      guard git_revision_commit(dir, base) is Some(commit) else {
        raise HostError("recorded Git task baseline is unavailable")
      }
      Some(commit)
    }
    None => None
  }
  let (
    head,
    baseline,
    known_gitlinks,
    known_symlinks,
    deleted_gitlinks,
    deleted_symlinks,
    changes,
  ) = git_change_snapshot(dir, workspace_prefix, pinned_base, 2)
  let changes = @async.all(
    [
      for change in changes => {
        () => {
          // Deleted rows have no current kind. A trailing-slash untracked row
          // is Git's collapsed nested checkout/directory spelling, not a
          // symlink. Avoid filesystem work for both common inert cases.
          if change.kind == "deleted" {
            git_change_with_path_kind(
              change,
              Unknown,
              deleted_gitlinks.contains(change.path),
              deleted_symlinks.contains(change.path),
            )
          } else if change.kind == "untracked" && change.path.has_suffix("/") {
            change
          } else {
            let path = root.join((change.path : @pathx.Relative)).to_string()
            let path_kind = @fs.kind(path, follow_symlink=false) catch {
              error if @async.is_being_cancelled() => raise error
              _ => Unknown
            }
            git_change_with_path_kind(
              change,
              path_kind,
              known_gitlinks.contains(change.path),
              known_symlinks.contains(change.path),
            )
          }
        }
      }
    ],
    max_concurrent=32,
  )
  { repository: true, head, baseline, changes, }
}

///|
fn push_history_ref(
  refs : Array[GitHistoryRef],
  tips : Array[String],
  name : String,
  revision : String,
  kind : String,
) -> Unit {
  refs.push({ name, revision, kind, })
  if !tips.contains(revision) {
    tips.push(revision)
  }
}

///|
async fn git_history_upstream(dir : String) -> String? {
  guard git_output_opt(dir, [
      "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}",
    ])
    is Some(output) else {
    return None
  }
  let upstream = git_single_line(output)
  if upstream.is_empty() || upstream == "@{upstream}" {
    None
  } else {
    Some(upstream)
  }
}

///|
/// Prefer the configured upstream remote's symbolic default, then the
/// repository's ordinary origin/HEAD declaration. No branch-name guessing.
async fn git_history_default_ref(dir : String, upstream : String?) -> String? {
  if upstream is Some(upstream) && upstream.split_once("/") is Some((remote, _)) {
    let symbolic = "refs/remotes/\{remote}/HEAD"
    if git_output_opt(dir, ["symbolic-ref", "--quiet", "--short", symbolic])
      is Some(output) {
      let name = git_single_line(output)
      if !name.is_empty() && name != symbolic {
        return Some(name)
      }
    }
  }
  git_base_ref(dir)
}

///|
async fn capture_git_history_snapshot(
  dir : String,
  review_base : String?,
) -> GitHistorySnapshot {
  let head = git_revision_commit(dir, "HEAD")
  let branch = match
    git_output_opt(dir, ["symbolic-ref", "--quiet", "--short", "HEAD"]) {
    Some(output) => {
      let name = git_single_line(output)
      if name.is_empty() {
        None
      } else {
        Some(name)
      }
    }
    None => None
  }
  let refs : Array[GitHistoryRef] = []
  let tips : Array[String] = []
  if head is Some(head) {
    push_history_ref(
      refs,
      tips,
      branch.unwrap_or("HEAD"),
      head,
      if branch is Some(_) {
        "current"
      } else {
        "head"
      },
    )
  }
  let upstream = git_history_upstream(dir)
  if upstream is Some(upstream) &&
    git_revision_commit(dir, upstream) is Some(upstream_commit) {
    push_history_ref(refs, tips, upstream, upstream_commit, "upstream")
  }
  match review_base {
    Some(base) => push_history_ref(refs, tips, "Review base", base, "base")
    None =>
      if git_history_default_ref(dir, upstream) is Some(base_ref) &&
        git_revision_commit(dir, base_ref) is Some(base) {
        push_history_ref(refs, tips, base_ref, base, "base")
      }
  }
  { head, branch, refs, tips, }
}

///|
/// The client echoes only values previously produced by this host. Validate
/// every object identity again before it can become a Git argv entry.
async fn validate_git_history_snapshot(
  dir : String,
  snapshot : GitHistorySnapshot,
) -> GitHistorySnapshot {
  if snapshot.refs.length() > 16 || snapshot.tips.length() > 16 {
    raise HostError("Git history snapshot contains too many refs")
  }
  for tip in snapshot.tips {
    guard valid_commit_identity(tip) &&
      git_revision_commit(dir, tip) == Some(tip) else {
      raise HostError("Git history snapshot contains an unavailable commit")
    }
  }
  for ref_ in snapshot.refs {
    guard ref_.name.length() <= 512 &&
      ["current", "upstream", "base", "head"].contains(ref_.kind) &&
      valid_commit_identity(ref_.revision) &&
      git_revision_commit(dir, ref_.revision) == Some(ref_.revision) &&
      snapshot.tips.contains(ref_.revision) else {
      raise HostError("Git history snapshot contains an invalid ref")
    }
  }
  if snapshot.head is Some(head) {
    guard valid_commit_identity(head) &&
      git_revision_commit(dir, head) == Some(head) else {
      raise HostError("Git history snapshot contains an unavailable HEAD")
    }
  }
  snapshot
}

///|
fn parse_git_history_z(output : String) -> Array[GitHistoryCommit] {
  let fields = output.split("\u{0}").map(field => field.to_owned()).collect()
  let commits : Array[GitHistoryCommit] = []
  let mut index = 0
  while index + 5 < fields.length() {
    let id = fields[index]
    let parents = fields[index + 1]
    let subject = fields[index + 2]
    let author = fields[index + 3]
    let authored_at = fields[index + 4]
    let separator = fields[index + 5]
    if id.is_empty() || !separator.is_empty() {
      break
    }
    commits.push({
      id,
      parent_ids: if parents.is_empty() {
        []
      } else {
        parents.split(" ").map(parent => parent.to_owned()).collect()
      },
      subject,
      author,
      authored_at,
    })
    index += 6
  }
  commits
}

///|
async fn git_history_page(
  dir : String,
  snapshot : GitHistorySnapshot,
  skip : Int,
  limit : Int,
) -> (Array[GitHistoryCommit], Bool) {
  if snapshot.tips.is_empty() {
    return ([], false)
  }
  let args = [
    "log",
    "--topo-order",
    "-z",
    "--format=%H%x00%P%x00%s%x00%an%x00%aI%x00",
    "--skip=\{skip}",
    "-n",
    (limit + 1).to_string(),
  ]
  for tip in snapshot.tips {
    args.push(tip)
  }
  args.push("--")
  let (code, stdout, stderr) = git_collect(dir, args)
  guard code == 0 else {
    let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
    raise HostError(
      if detail.is_empty() {
        "failed to read Git history"
      } else {
        detail
      },
    )
  }
  let raw = stdout.text() catch {
    _ => raise HostError("Git returned non-UTF-8 history metadata")
  }
  let commits = parse_git_history_z(raw)
  let has_more = commits.length() > limit
  if has_more {
    ignore(commits.pop())
  }
  (commits, has_more)
}

///|
async fn git_history_op(payload : GitHistoryPayload) -> GitHistoryReply {
  guard payload.skip >= 0 &&
    @work_dir.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(root) else {
    raise HostError("could not resolve the conversation workspace")
  }
  let dir = root.to_string()
  let empty : GitHistorySnapshot = {
    head: None,
    branch: None,
    refs: [],
    tips: [],
  }
  if git_output(dir, ["rev-parse", "--is-inside-work-tree"]) != "true" {
    return { repository: false, snapshot: empty, commits: [], has_more: false, }
  }
  let recorded_base = @work_dir.session_review_base(
    payload.session,
    workspace?=payload.workspace,
  )
  let review_base = match recorded_base {
    Some(base) => {
      guard valid_commit_identity(base) &&
        git_revision_commit(dir, base) is Some(commit) else {
        raise HostError("recorded Git task baseline is unavailable")
      }
      Some(commit)
    }
    None => None
  }
  let snapshot = match payload.snapshot {
    Some(snapshot) => validate_git_history_snapshot(dir, snapshot)
    None => capture_git_history_snapshot(dir, review_base)
  }
  let limit = if payload.limit <= 0 {
    50
  } else if payload.limit > 100 {
    100
  } else {
    payload.limit
  }
  let (commits, has_more) = git_history_page(dir, snapshot, payload.skip, limit)
  { repository: true, snapshot, commits, has_more, }
}

///|
async fn git_tree_object_modes(
  dir : String,
  workspace_prefix : String,
  revision : String,
) -> (Set[String], Set[String]) {
  let (code, stdout, stderr) = git_collect(dir, [
    "ls-tree", "-r", "--full-name", "-z", revision, "--", ".",
  ])
  guard code == 0 else {
    let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
    raise HostError(
      if detail.is_empty() {
        "failed to inspect Git commit tree"
      } else {
        detail
      },
    )
  }
  let output = stdout.text() catch {
    _ => raise HostError("Git returned a non-UTF-8 commit tree path")
  }
  (
    parse_git_mode_paths(output, workspace_prefix, "160000"),
    parse_git_mode_paths(output, workspace_prefix, "120000"),
  )
}

///|
async fn git_commit_changes_at(
  dir : String,
  workspace_prefix : String,
  commit : String,
) -> GitCommitChangesReply {
  guard git_revision_commit(dir, commit) is Some(commit) else {
    raise HostError("Git commit is unavailable")
  }
  let parent = match
    git_output_opt(dir, ["show", "-s", "--format=%P", commit]) {
    Some(output) => {
      let parents = git_single_line(output)
      if parents.is_empty() {
        None
      } else {
        Some(
          match parents.split_once(" ") {
            Some((first, _)) => first.to_owned()
            None => parents
          },
        )
      }
    }
    None => raise HostError("failed to inspect Git commit parents")
  }
  let base = parent.unwrap_or(EmptyTreeObject)
  let (code, stdout, stderr) = git_collect(dir, [
    "diff", "--name-status", "-z", "--no-ext-diff", "--find-renames", "--find-copies-harder",
    base, commit, "--", ".",
  ])
  guard code == 0 else {
    let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
    raise HostError(
      if detail.is_empty() {
        "failed to read Git commit changes"
      } else {
        detail
      },
    )
  }
  let raw = stdout.text() catch {
    _ => raise HostError("Git returned a non-UTF-8 commit path")
  }
  let parsed = parse_git_diff_name_status_z(raw).filter_map(change => {
    git_change_relative_to_workspace(change, workspace_prefix)
  })
  let (new_gitlinks, new_symlinks) = git_tree_object_modes(
    dir, workspace_prefix, commit,
  )
  let (old_gitlinks, old_symlinks) = git_tree_object_modes(
    dir, workspace_prefix, base,
  )
  let changes : Array[GitHistoricalChange] = []
  for change in parsed {
    let old_path = change.original_path.unwrap_or(change.path)
    let kind = if old_gitlinks.contains(old_path) ||
      new_gitlinks.contains(change.path) {
      "submodule"
    } else if old_symlinks.contains(old_path) ||
      new_symlinks.contains(change.path) {
      "symlink"
    } else {
      "file"
    }
    changes.push({
      path: change.path,
      original_path: change.original_path,
      status: change.kind,
      kind,
    })
  }
  { commit, parent, changes, }
}

///|
async fn git_commit_changes_op(
  payload : GitCommitChangesPayload,
) -> GitCommitChangesReply {
  guard valid_commit_identity(payload.commit) &&
    @work_dir.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(root) else {
    raise HostError("invalid Git commit request")
  }
  let dir = root.to_string()
  if git_output(dir, ["rev-parse", "--is-inside-work-tree"]) != "true" {
    raise HostError("workspace is not a Git repository")
  }
  let (prefix_code, prefix_stdout, prefix_stderr) = git_collect(dir, [
    "rev-parse", "--show-prefix",
  ])
  guard prefix_code == 0 else {
    let detail = (prefix_stderr.text() catch { _ => "" }).trim().to_owned()
    raise HostError(
      if detail.is_empty() {
        "failed to resolve Git workspace prefix"
      } else {
        detail
      },
    )
  }
  let workspace_prefix = git_single_line(
    prefix_stdout.text() catch {
      _ => raise HostError("Git returned a non-UTF-8 workspace prefix")
    },
  )
  git_commit_changes_at(dir, workspace_prefix, payload.commit)
}

///|
async fn git_original_file_at(
  dir : String,
  relative : @pathx.Relative,
  revision : String,
) -> GitOriginalFileReply {
  // Resolve the requested revision to an immutable commit before addressing
  // its path. The caller has already validated the workspace and tree path.
  guard git_revision_commit(dir, revision) is Some(commit) else {
    return Missing
  }
  // `./` makes the tree path relative to Git's current directory, which is
  // the conversation workspace even when that workspace is a repository
  // subdirectory. Resolve the commit:path name once; all following checks and
  // the read use the immutable blob ID.
  let object = "\{commit}:./\{relative.0}"
  let (oid_code, oid_stdout, _) = git_collect(dir, [
    "rev-parse", "--verify", object,
  ])
  if oid_code != 0 {
    return Missing
  }
  let oid = git_single_line(oid_stdout.text() catch { _ => return Missing })
  if oid.is_empty() {
    return Missing
  }
  let (type_code, type_stdout, type_stderr) = git_collect(dir, [
    "cat-file", "-t", oid,
  ])
  guard type_code == 0 else {
    let detail = (type_stderr.text() catch { _ => "" }).trim().to_owned()
    raise HostError(
      if detail.is_empty() {
        "failed to inspect Git baseline"
      } else {
        detail
      },
    )
  }
  let object_type = git_single_line(type_stdout.text() catch { _ => "" })
  if object_type != "blob" {
    return BinaryOriginal
  }
  let (size_code, size_stdout, size_stderr) = git_collect(dir, [
    "cat-file", "-s", oid,
  ])
  guard size_code == 0 else {
    let detail = (size_stderr.text() catch { _ => "" }).trim().to_owned()
    raise HostError(
      if detail.is_empty() {
        "failed to size Git baseline"
      } else {
        detail
      },
    )
  }
  let size_text = git_single_line(size_stdout.text() catch { _ => "" })
  let size : Int64 = @string.parse_int64(size_text) catch {
    _ => raise HostError("Git returned an invalid blob size")
  }
  if size > @openpath.MaxEditorFileBytes.to_int64() {
    return OversizedOriginal
  }
  let (content_code, content, stderr) = git_collect(dir, ["cat-file", "-p", oid])
  guard content_code == 0 else {
    let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
    raise HostError(
      if detail.is_empty() {
        "failed to read Git baseline"
      } else {
        detail
      },
    )
  }
  // Use the same content policy as working-tree reads so a tab cannot treat
  // its current file and Git baseline as different kinds of content.
  match @filekind.classify(content.binary()) {
    Utf8Text(text) => OriginalContent(text)
    RasterImage(_) | Binary => BinaryOriginal
  }
}

///|
async fn git_original_file_op(
  payload : GitOriginalFilePayload,
) -> GitOriginalFileReply {
  guard @work_dir.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(root) &&
    git_tree_relative(payload.path) is Some(relative) else {
    raise HostError("path is outside the conversation workspace")
  }
  let dir = root.to_string()
  if git_output(dir, ["rev-parse", "--is-inside-work-tree"]) != "true" {
    return Missing
  }
  // New clients pass the exact HEAD identity returned with their change
  // snapshot; the fallback keeps older clients compatible.
  let revision = match payload.revision {
    Some(revision) => {
      guard valid_commit_identity(revision) else {
        raise HostError("invalid Git revision identity")
      }
      revision
    }
    None => "HEAD"
  }
  git_original_file_at(dir, relative, revision)
}

///|
test "Git porcelain parser keeps status columns and rename source" {
  let changes = parse_git_status_z(
    " M src/modified.mbt\u{0}A  src/added.mbt\u{0}R  src/new.mbt\u{0}src/old.mbt\u{0}?? src/untracked.mbt\u{0}",
  )
  assert_eq(changes, [
    {
      path: "src/added.mbt",
      original_path: None,
      index_status: "A",
      worktree_status: " ",
      kind: "added",
    },
    {
      path: "src/modified.mbt",
      original_path: None,
      index_status: " ",
      worktree_status: "M",
      kind: "modified",
    },
    {
      path: "src/new.mbt",
      original_path: Some("src/old.mbt"),
      index_status: "R",
      worktree_status: " ",
      kind: "renamed",
    },
    {
      path: "src/untracked.mbt",
      original_path: None,
      index_status: "?",
      worktree_status: "?",
      kind: "untracked",
    },
  ])
}

///|
test "Git task-diff parser keeps scored rename sources and untracked rows" {
  let changes = parse_git_diff_name_status_z(
    "M\u{0}src/modified.mbt\u{0}A\u{0}src/added.mbt\u{0}R100\u{0}src/old.mbt\u{0}src/new.mbt\u{0}C075\u{0}src/source.mbt\u{0}src/copy.mbt\u{0}",
  )
  assert_true(
    changes
    is [
      { path: "src/added.mbt", worktree_status: "A", kind: "added", .. },
      {
        path: "src/copy.mbt",
        original_path: Some("src/source.mbt"),
        kind: "copied",
        ..
      },
      { path: "src/modified.mbt", worktree_status: "M", .. },
      {
        path: "src/new.mbt",
        original_path: Some("src/old.mbt"),
        kind: "renamed",
        ..
      },
    ],
  )
  let untracked = parse_git_untracked_z("new.mbt\u{0}recreated.mbt\u{0}")
  let merged = git_task_changes_with_untracked(
    [
      {
        ..untracked[0],
        path: "recreated.mbt",
        worktree_status: "D",
        kind: "deleted",
      },
    ],
    untracked,
  )
  assert_true(
    merged
    is [
      { path: "new.mbt", kind: "untracked", .. },
      { path: "recreated.mbt", kind: "deleted", .. },
      { path: "recreated.mbt", kind: "untracked", .. },
    ],
  )
  assert_true(parse_git_diff_name_status_z("M\u{0}").is_empty())
  assert_true(parse_git_diff_name_status_z("R100\u{0}old.mbt\u{0}").is_empty())
  assert_true(
    parse_git_diff_name_status_z("C100\u{0}\u{0}copy.mbt\u{0}").is_empty(),
  )
  assert_true(parse_git_untracked_z("unterminated.mbt").is_empty())
}

///|
test "Git history parser keeps parents subjects authors and ISO dates" {
  let commits = parse_git_history_z(
    "1111111111111111111111111111111111111111\u{0}0000000000000000000000000000000000000000 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\u{0}Merge topic\u{0}OpenSeek Test\u{0}2026-08-19T10:00:00+08:00\u{0}\u{0}",
  )
  assert_true(
    commits
    is [
      {
        id: "1111111111111111111111111111111111111111",
        parent_ids: [
          "0000000000000000000000000000000000000000",
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        ],
        subject: "Merge topic",
        author: "OpenSeek Test",
        authored_at: "2026-08-19T10:00:00+08:00",
      },
    ],
  )
}

///|
test "Git change categories cover conflicts deletions and type changes" {
  assert_eq(git_change_kind("U", "U"), "unmerged")
  assert_eq(git_change_kind(" ", "D"), "deleted")
  assert_eq(git_change_kind("T", " "), "type-changed")
  assert_eq(git_change_kind("C", " "), "copied")
}

///|
test "Git subprocess environment cannot redirect the workspace repository" {
  let env : Map[String, String] = {
    "PATH": "/usr/bin",
    "Git_Dir": "/elsewhere/.git",
    "git_work_tree": "/elsewhere",
    "GIT_CONFIG_COUNT": "1",
    "GIT_CONFIG_GLOBAL": "/elsewhere/gitconfig",
    "GIT_QUARANTINE_PATH": "/elsewhere/quarantine",
    "HOME": "/home/test",
  }
  sanitize_git_environment(env)
  assert_eq(env.get("PATH"), Some("/usr/bin"))
  assert_eq(env.get("HOME"), Some("/home/test"))
  assert_false(env.contains("Git_Dir"))
  assert_false(env.contains("git_work_tree"))
  assert_false(env.contains("GIT_CONFIG_COUNT"))
  assert_false(env.contains("GIT_CONFIG_GLOBAL"))
  assert_false(env.contains("GIT_QUARANTINE_PATH"))
}

///|
test "Git tree paths are lexically contained without resolving symlinks" {
  assert_eq(git_tree_relative("src/link"), Some(Relative("src/link")))
  assert_eq(git_tree_relative("src/../link"), Some(Relative("link")))
  assert_true(git_tree_relative("../secret") is None)
  assert_true(git_tree_relative("src/../../secret") is None)
}

///|
test "Git single-line output preserves significant path whitespace" {
  assert_eq(git_single_line(" spaced/\n"), " spaced/")
  assert_eq(git_single_line("trailing /\r\n"), "trailing /")
  assert_eq(git_single_line("\n"), "")
}

///|
async fn git_test_run(dir : String, args : Array[String]) -> Unit {
  let (code, _, stderr) = git_collect(dir, args)
  guard code == 0 else {
    let detail = (stderr.text() catch { _ => "non-UTF-8 stderr" }).trim()
    fail("Git fixture command failed: \{detail}")
  }
}

///|
async fn git_test_commit(dir : String, message : String) -> Unit {
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", message,
  ])
}

///|
#cfg(not(platform="windows"))
async test "Git history pages stay pinned and commit changes use first parent" {
  let dir = @fs.tmpdir(prefix="openseek-git-history-")
  async fn cleanup() {
    @fs.rmdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
  let _ = {
    defer cleanup()
    git_test_run(dir, ["init", "--quiet"])
    @fs.write_file("\{dir}/old.mbt", "first\n", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "old.mbt"])
    git_test_commit(dir, "first")
    git_test_run(dir, ["branch", "-M", "feature/graph"])
    let first = git_revision_commit(dir, "HEAD").unwrap()
    git_test_run(dir, ["update-ref", "refs/remotes/origin/main", first])
    git_test_run(dir, [
      "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main",
    ])
    git_test_run(dir, ["mv", "old.mbt", "new.mbt"])
    git_test_commit(dir, "rename")
    let second = git_revision_commit(dir, "HEAD").unwrap()
    git_test_run(dir, [
      "update-ref", "refs/remotes/origin/feature/graph", second,
    ])
    git_test_run(dir, ["config", "branch.feature/graph.remote", "origin"])
    git_test_run(dir, [
      "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*",
    ])
    git_test_run(dir, [
      "config", "branch.feature/graph.merge", "refs/heads/feature/graph",
    ])
    let snapshot = capture_git_history_snapshot(dir, Some(first))
    assert_eq(snapshot.head, Some(second))
    assert_eq(snapshot.branch, Some("feature/graph"))
    assert_true(snapshot.refs.any(ref_ => ref_.kind == "current"))
    assert_true(snapshot.refs.any(ref_ => ref_.kind == "upstream"))
    assert_true(snapshot.refs.any(ref_ => ref_.kind == "base"))
    let (first_page, has_more) = git_history_page(dir, snapshot, 0, 1)
    assert_true(has_more)
    assert_true(first_page is [{ id, subject: "rename", .. }] && id == second)
    @fs.write_file("\{dir}/third.mbt", "third\n", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "third.mbt"])
    git_test_commit(dir, "third")
    let third = git_revision_commit(dir, "HEAD").unwrap()
    assert_true(third != second)
    // The next page still walks the captured second-commit tips.
    let (second_page, _) = git_history_page(dir, snapshot, 1, 1)
    assert_true(second_page is [{ id, subject: "first", .. }] && id == first)
    let renamed = git_commit_changes_at(dir, "", second)
    assert_eq(renamed.parent, Some(first))
    assert_true(
      renamed.changes
      is [
        {
          path: "new.mbt",
          original_path: Some("old.mbt"),
          status: "renamed",
          kind: "file",
        },
      ],
    )
    let root = git_commit_changes_at(dir, "", first)
    assert_eq(root.parent, None)
    assert_true(root.changes is [{ path: "old.mbt", status: "added", .. }])

    // A merge comparison follows Git's ordinary history-provider semantics:
    // only the first parent's delta appears below the merge row.
    git_test_run(dir, ["branch", "side", first])
    git_test_run(dir, ["checkout", "--quiet", "side"])
    @fs.write_file("\{dir}/side.mbt", "side\n", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "side.mbt"])
    git_test_commit(dir, "side")
    git_test_run(dir, ["checkout", "--quiet", "feature/graph"])
    git_test_run(dir, [
      "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
      "-c", "commit.gpgSign=false", "merge", "--quiet", "--no-ff", "-m", "merge side",
      "side",
    ])
    let merge = git_revision_commit(dir, "HEAD").unwrap()
    let merged = git_commit_changes_at(dir, "", merge)
    assert_eq(merged.parent, Some(third))
    assert_true(
      merged.changes
      is [{ path: "side.mbt", status: "added", kind: "file", .. }],
    )

    // Exhaustive copy discovery and tree modes are properties of historical
    // inspection, not the cheaper working-tree poll.
    @fs.write_file("\{dir}/copy.mbt", "first\n", create_mode=CreateOrTruncate)
    @fs.symlink(target="new.mbt", "\{dir}/link")
    git_test_run(dir, ["add", "copy.mbt", "link"])
    git_test_run(dir, [
      "update-index",
      "--add",
      "--cacheinfo",
      "160000,\{first},vendor/lib",
    ])
    git_test_commit(dir, "copy and modes")
    let modes_commit = git_revision_commit(dir, "HEAD").unwrap()
    let mode_changes = git_commit_changes_at(dir, "", modes_commit).changes
    assert_true(
      mode_changes.any(change => {
        change.path == "copy.mbt" &&
        change.original_path == Some("new.mbt") &&
        change.status == "copied" &&
        change.kind == "file"
      }),
    )
    assert_true(
      mode_changes.any(change => {
        change.path == "link" && change.kind == "symlink"
      }),
    )
    assert_true(
      mode_changes.any(change => {
        change.path == "vendor/lib" && change.kind == "submodule"
      }),
    )

    // A type change stays inert when either revision is a special Git object,
    // including the less obvious symlink-to-regular-file direction.
    @fs.remove("\{dir}/link")
    @fs.write_file("\{dir}/link", "regular\n", create_mode=CreateOrTruncate)
    git_test_run(dir, ["add", "link"])
    git_test_commit(dir, "replace symlink")
    let type_commit = git_revision_commit(dir, "HEAD").unwrap()
    assert_true(
      git_commit_changes_at(dir, "", type_commit).changes.any(change => {
        change.path == "link" &&
        change.status == "type-changed" &&
        change.kind == "symlink"
      }),
    )

    @fs.write_file(
      "\{dir}/binary.dat",
      "binary\u{0}payload",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/oversized.txt",
      "x".repeat(@openpath.MaxEditorFileBytes + 1),
      create_mode=CreateOrTruncate,
    )
    git_test_run(dir, ["add", "binary.dat", "oversized.txt"])
    git_test_commit(dir, "binary content policies")
    let content_commit = git_revision_commit(dir, "HEAD").unwrap()
    assert_eq(
      git_original_file_at(dir, Relative("binary.dat"), content_commit),
      BinaryOriginal,
    )
    assert_eq(
      git_original_file_at(dir, Relative("oversized.txt"), content_commit),
      OversizedOriginal,
    )
  }
}

///|
async test "Git history paginates fifty commits and describes detached HEAD" {
  let dir = @fs.tmpdir(prefix="openseek-git-history-page-")
  async fn cleanup() {
    @fs.rmdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
  let _ = {
    defer cleanup()
    git_test_run(dir, ["init", "--quiet"])
    let unborn = capture_git_history_snapshot(dir, None)
    assert_eq(unborn.head, None)
    assert_true(unborn.refs.is_empty())
    assert_true(unborn.tips.is_empty())
    for index in 0..<52 {
      @fs.write_file(
        "\{dir}/history.txt",
        "\{index}\n",
        create_mode=CreateOrTruncate,
      )
      git_test_run(dir, ["add", "history.txt"])
      git_test_commit(dir, "history \{index}")
    }
    git_test_run(dir, ["checkout", "--quiet", "--detach"])
    let snapshot = capture_git_history_snapshot(dir, None)
    assert_true(snapshot.head is Some(_))
    assert_eq(snapshot.branch, None)
    assert_true(snapshot.refs is [{ name: "HEAD", kind: "head", .. }])
    let (first_page, has_more) = git_history_page(dir, snapshot, 0, 50)
    assert_eq(first_page.length(), 50)
    assert_true(has_more)
    let (last_page, last_has_more) = git_history_page(dir, snapshot, 50, 50)
    assert_eq(last_page.length(), 2)
    assert_false(last_has_more)
  }
}

///|
async test "Git recognizes only origin HEAD's branch as the default" {
  let dir = @fs.tmpdir(prefix="openseek-git-default-branch-")
  async fn cleanup() {
    @fs.rmdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
  defer cleanup()
  git_test_run(dir, ["init", "--quiet"])
  @fs.write_file("\{dir}/tracked.txt", "first\n", create_mode=CreateOrTruncate)
  git_test_run(dir, ["add", "tracked.txt"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "first",
  ])
  // A branch spelling alone proves nothing until the remote declares its
  // default. Once it does, only that exact name is suppressed from PR lookup.
  assert_false(git_is_default_branch(dir, branch="main"))
  git_test_run(dir, ["update-ref", "refs/remotes/origin/main", "HEAD"])
  git_test_run(dir, [
    "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main",
  ])
  assert_true(git_is_default_branch(dir, branch="main"))
  assert_false(git_is_default_branch(dir, branch="feature/from-main"))
}

///|
async test "ordinary checkout reviews retain committed branch changes" {
  let dir = @fs.tmpdir(prefix="openseek-git-root-review-")
  async fn cleanup() {
    @fs.rmdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
  defer cleanup()
  git_test_run(dir, ["init", "--quiet"])
  @fs.write_file("\{dir}/review.txt", "first\n", create_mode=CreateOrTruncate)
  git_test_run(dir, ["add", "review.txt"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "first",
  ])
  let first = git_revision_commit(dir, "HEAD").unwrap()
  git_test_run(dir, ["update-ref", "refs/remotes/origin/main", first])
  git_test_run(dir, [
    "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main",
  ])
  @fs.write_file("\{dir}/review.txt", "working\n", create_mode=CreateOrTruncate)
  let (before_head, before_base, _, _, _, _, before_changes) = git_change_snapshot(
    dir,
    "",
    None,
    2,
  )
  assert_eq(before_head, Some(first))
  // At the fork point, preserve porcelain's staged/worktree distinction.
  assert_eq(before_base, None)
  assert_true(
    before_changes
    is [{ path: "review.txt", index_status: " ", worktree_status: "M", .. }],
  )
  git_test_run(dir, ["add", "review.txt"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "-c", "commit.gpgSign=false", "commit", "--quiet", "-m", "second",
  ])
  let second = git_revision_commit(dir, "HEAD").unwrap()
  let (after_head, after_base, _, _, _, _, after_changes) = git_change_snapshot(
    dir,
    "",
    None,
    2,
  )
  assert_eq(after_head, Some(second))
  assert_eq(after_base, Some(first))
  // Committing must not make an ordinary checkout's Review turn empty.
  assert_eq(after_changes, before_changes)
}

///|
#cfg(not(platform="windows"))
async test "Git snapshots pair status with HEAD and supplied revisions stay pinned" {
  let dir = @fs.tmpdir(prefix="openseek-git-review-")
  async fn cleanup() {
    @fs.rmdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
  defer cleanup()
  git_test_run(dir, ["init", "--quiet"])
  assert_eq(git_revision_commit(dir, "HEAD"), None)
  @fs.mkdir("\{dir}/desktop", recursive=true)
  @fs.write_file("\{dir}/review.txt", "first\n", create_mode=CreateOrTruncate)
  @fs.write_file(
    "\{dir}/desktop/keep.txt",
    "keep\n",
    create_mode=CreateOrTruncate,
  )
  git_test_run(dir, ["add", "review.txt", "desktop/keep.txt"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "commit", "--quiet", "-m", "first",
  ])
  let first = git_revision_commit(dir, "HEAD").unwrap()
  // A task deletion must use the comparison tree's mode, not a staged type
  // change that no longer exists in the working tree.
  @fs.remove("\{dir}/desktop/keep.txt")
  @fs.symlink(target="../review.txt", "\{dir}/desktop/keep.txt")
  git_test_run(dir, ["add", "desktop/keep.txt"])
  @fs.remove("\{dir}/desktop/keep.txt")
  let (_, _, _, current_symlinks, _, deleted_symlinks, type_changes) = git_change_snapshot(
    dir,
    "",
    Some(first),
    2,
  )
  assert_true(current_symlinks.contains("desktop/keep.txt"))
  assert_false(deleted_symlinks.contains("desktop/keep.txt"))
  guard type_changes is [deleted] else {
    fail("expected the staged type-change deletion")
  }
  assert_eq(
    git_change_with_path_kind(
      deleted,
      Unknown,
      false,
      deleted_symlinks.contains(deleted.path),
    ).kind,
    "deleted",
  )
  git_test_run(dir, ["restore", "--staged", "desktop/keep.txt"])
  git_test_run(dir, ["restore", "desktop/keep.txt"])
  @fs.write_file("\{dir}/review.txt", "working\n", create_mode=CreateOrTruncate)
  let (snapshot_head, snapshot_base, _, _, _, _, changes) = git_change_snapshot(
    dir,
    "",
    None,
    2,
  )
  assert_eq(snapshot_head, Some(first))
  assert_eq(snapshot_base, None)
  assert_true(changes is [{ path: "review.txt", kind: "modified", .. }])
  let (_, task_base, _, _, _, _, task_before_commit) = git_change_snapshot(
    dir,
    "",
    Some(first),
    2,
  )
  assert_eq(task_base, Some(first))
  git_test_run(dir, ["add", "review.txt"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "commit", "--quiet", "-m", "second",
  ])
  let second = git_revision_commit(dir, "HEAD").unwrap()
  assert_true(second != first)
  let (_, head_base, _, _, _, _, head_changes) = git_change_snapshot(
    dir,
    "",
    None,
    2,
  )
  assert_eq(head_base, None)
  assert_true(head_changes.is_empty())
  let (_, _, _, _, _, _, task_changes) = git_change_snapshot(
    dir,
    "",
    Some(first),
    2,
  )
  assert_eq(task_changes, task_before_commit)
  assert_eq(git_revision_commit(dir, first), Some(first))
  assert_eq(git_revision_commit(dir, "missing-review-revision"), None)
  assert_eq(
    git_original_file_at(dir, Relative("review.txt"), first),
    OriginalContent("first\n"),
  )
  assert_eq(
    git_original_file_at(dir, Relative("review.txt"), second),
    OriginalContent("working\n"),
  )
  // Populate a gitlink directly so the test stays offline, add a symlink,
  // then stage both deletions from a workspace rooted below the repository.
  // Targeted HEAD discovery must retain the repository-root path spelling
  // emitted by --full-name and both non-text entry modes.
  git_test_run(dir, [
    "update-index",
    "--add",
    "--cacheinfo",
    "160000,\{second},desktop/vendor/lib",
  ])
  @fs.symlink(target="keep.txt", "\{dir}/desktop/link")
  git_test_run(dir, ["add", "desktop/link"])
  git_test_run(dir, [
    "-c", "user.name=OpenSeek Test", "-c", "user.email=openseek@example.invalid",
    "commit", "--quiet", "-m", "gitlink",
  ])
  let gitlink_head = git_revision_commit(dir, "HEAD").unwrap()
  @fs.remove("\{dir}/desktop/link")
  git_test_run(dir, [
    "update-index", "--force-remove", "desktop/link", "desktop/vendor/lib",
  ])
  let (nested_head, _, _, _, deleted_gitlinks, deleted_symlinks, nested_changes) = git_change_snapshot(
    "\{dir}/desktop",
    "desktop/",
    None,
    2,
  )
  assert_eq(nested_head, Some(gitlink_head))
  assert_eq(deleted_gitlinks.length(), 1)
  assert_true(deleted_gitlinks.contains("vendor/lib"))
  assert_eq(deleted_symlinks.length(), 1)
  assert_true(deleted_symlinks.contains("link"))
  assert_true(
    nested_changes
    is [
      { path: "link", index_status: "D", kind: "deleted", .. },
      { path: "vendor/lib", index_status: "D", kind: "deleted", .. },
    ],
  )
  let classified = nested_changes.map(change => {
    git_change_with_path_kind(
      change,
      Unknown,
      deleted_gitlinks.contains(change.path),
      deleted_symlinks.contains(change.path),
    )
  })
  assert_true(
    classified
    is [
      { path: "link", kind: "symlink", .. },
      { path: "vendor/lib", kind: "submodule", .. },
    ],
  )
}

///|
test "Git non-file changes are classified without following symlinks" {
  let change : GitChange = {
    path: "vendor/library",
    original_path: None,
    index_status: " ",
    worktree_status: "M",
    kind: "modified",
  }
  assert_eq(git_change_with_path_kind(change, Directory, false, false), {
    ..change,
    kind: "submodule",
  })
  assert_eq(git_change_with_path_kind(change, Unknown, true, false), {
    ..change,
    kind: "submodule",
  })
  let deleted = {
    ..change,
    index_status: "D",
    worktree_status: " ",
    kind: "deleted",
  }
  assert_eq(git_change_with_path_kind(deleted, Unknown, true, false), {
    ..deleted,
    kind: "submodule",
  })
  assert_eq(git_change_with_path_kind(deleted, Unknown, false, true), {
    ..deleted,
    kind: "symlink",
  })
  assert_eq(git_change_with_path_kind(change, Regular, false, false), change)
  assert_eq(git_change_with_path_kind(change, SymLink, false, false), {
    ..change,
    kind: "symlink",
  })
  assert_eq(
    git_change_with_path_kind(
      { ..change, index_status: "?", worktree_status: "?", kind: "untracked", },
      Directory,
      false,
      false,
    ),
    { ..change, index_status: "?", worktree_status: "?", kind: "untracked", },
  )
}

///|
test "duplicate deletion and recreation rows keep their own path kinds" {
  let deleted : GitChange = {
    path: "same",
    original_path: None,
    index_status: "D",
    worktree_status: " ",
    kind: "deleted",
  }
  let untracked : GitChange = {
    path: "same",
    original_path: None,
    index_status: "?",
    worktree_status: "?",
    kind: "untracked",
  }
  // Production classifies deletion rows with Unknown plus the pinned HEAD
  // modes, and classifies every untracked row from the working filesystem.
  // An old symlink recreated as a regular file therefore keeps both sides.
  assert_eq(git_change_with_path_kind(deleted, Unknown, false, true), {
    ..deleted,
    kind: "symlink",
  })
  assert_eq(
    git_change_with_path_kind(untracked, Regular, false, true),
    untracked,
  )
  // The inverse transition is likewise side-specific.
  assert_eq(git_change_with_path_kind(deleted, Unknown, false, false), deleted)
  assert_eq(git_change_with_path_kind(untracked, SymLink, false, false), {
    ..untracked,
    kind: "symlink",
  })
}

///|
test "Git full-name metadata finds entry modes in a nested workspace" {
  let output = "100644 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0\tdesktop/src/main.mbt\u{0}120000 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0\tdesktop/link\u{0}160000 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 0\tdesktop/vendor/lib\u{0}160000 cccccccccccccccccccccccccccccccccccccccc 2\tdesktop/vendor/lib\u{0}160000 commit dddddddddddddddddddddddddddddddddddddddd\tdesktop/vendor/tree\u{0}160000 eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee 0\toutside/lib\u{0}"
  let gitlinks = parse_git_mode_paths(output, "desktop/", "160000")
  assert_eq(gitlinks.length(), 2)
  assert_true(gitlinks.contains("vendor/lib"))
  assert_true(gitlinks.contains("vendor/tree"))
  let symlinks = parse_git_mode_paths(output, "desktop/", "120000")
  assert_eq(symlinks.length(), 1)
  assert_true(symlinks.contains("link"))
}

///|
test "Git HEAD path queries stay in bounded argument batches" {
  let first = "a".repeat(9_000)
  let second = "b".repeat(9_000)
  let batches = git_tree_path_batches([first, second, "short"])
  assert_eq(batches.length(), 2)
  for batch in batches {
    let mut bytes = 0
    for path in batch {
      bytes += @utf8.encode(path).length() + 1
    }
    assert_true(bytes <= MaxGitTreePathBatchBytes)
  }
  // One path that cannot fit the conservative cross-platform command-line
  // budget selects the recursive workspace-tree fallback.
  assert_true(
    git_tree_path_batches(["x".repeat(MaxGitTreePathBatchBytes + 1)]).is_empty(),
  )
  // The limit is a byte limit, not a Unicode scalar-value limit.
  assert_true(
    git_tree_path_batches(["界".repeat(MaxGitTreePathBatchBytes / 3 + 1)]).is_empty(),
  )
  // Enough individually valid batches to exceed the subprocess budget also
  // select one recursive tree walk.
  let many : Array[String] = []
  for index in 0..<(MaxTargetedGitTreeQueries + 1) {
    many.push(
      index.to_string() + "-" + "x".repeat(MaxGitTreePathBatchBytes / 2),
    )
  }
  assert_true(git_tree_path_batches(many).is_empty())
}

///|
test "bulk deleted-path collection deduplicates in first-seen order" {
  let deleted : GitChange = {
    path: "first.mbt",
    original_path: None,
    index_status: "D",
    worktree_status: " ",
    kind: "deleted",
  }
  assert_eq(
    deleted_change_paths([
      deleted,
      { ..deleted, path: "kept.mbt", kind: "modified", },
      { ..deleted, path: "second.mbt", },
      deleted,
    ]),
    ["first.mbt", "second.mbt"],
  )
}

///|
test "Git changes are relative to an attached repository subdirectory" {
  let renamed : GitChange = {
    path: "desktop/src/new.mbt",
    original_path: Some("desktop/src/old.mbt"),
    index_status: "R",
    worktree_status: " ",
    kind: "renamed",
  }
  assert_eq(
    git_change_relative_to_workspace(renamed, "desktop/"),
    Some({ ..renamed, path: "src/new.mbt", original_path: Some("src/old.mbt"), }),
  )
  assert_eq(git_change_relative_to_workspace(renamed, ""), Some(renamed))
  assert_true(
    git_change_relative_to_workspace(
      { ..renamed, path: "outside/new.mbt", },
      "desktop/",
    )
    is None,
  )
  assert_eq(
    git_change_relative_to_workspace(
      { ..renamed, original_path: Some("outside/old.mbt"), },
      "desktop/",
    ),
    Some({ ..renamed, path: "src/new.mbt", original_path: None, }),
  )
}

///|
test "Numstat sums lines and counts a binary file without any" {
  assert_eq(parse_numstat(""), {
    added: 0,
    removed: 0,
    files: 0,
    base: None,
    partial: false,
  })
  assert_eq(
    parse_numstat("12\t3\tsrc/a.mbt\n-\t-\tassets/logo.png\n0\t7\tsrc/b.mbt\n"),
    { added: 12, removed: 10, files: 3, base: None, partial: false, },
  )
}

///|
test "Numstat reads a respelled path field without parsing it" {
  // Rename detection and `--no-index` both rewrite the path field into a
  // `{old => new}` form; only the two counts are ever read.
  assert_eq(parse_numstat("3\t0\t/{dev/null => src/new.mbt}\r\n"), {
    added: 3,
    removed: 0,
    files: 1,
    base: None,
    partial: false,
  })
  // A line Git never emits still must not be counted as a changed file.
  assert_eq(parse_numstat("garbage\n"), {
    added: 0,
    removed: 0,
    files: 0,
    base: None,
    partial: false,
  })
}

///|
test "Git porcelain parser accepts clean, conflicted, and UTF-8 paths" {
  assert_eq(parse_git_status_z(""), [])
  assert_eq(
    parse_git_status_z(
      "UU src/with space.mbt\u{0} M src/你好.mbt\u{0}R  src/new name.mbt\u{0}src/old name.mbt\u{0}",
    ),
    [
      {
        path: "src/new name.mbt",
        original_path: Some("src/old name.mbt"),
        index_status: "R",
        worktree_status: " ",
        kind: "renamed",
      },
      {
        path: "src/with space.mbt",
        original_path: None,
        index_status: "U",
        worktree_status: "U",
        kind: "unmerged",
      },
      {
        path: "src/你好.mbt",
        original_path: None,
        index_status: " ",
        worktree_status: "M",
        kind: "modified",
      },
    ],
  )
}
