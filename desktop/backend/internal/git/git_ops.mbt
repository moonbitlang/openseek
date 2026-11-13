// The composer's branch chip: report the git branch of a conversation's
// working directory, and how much uncommitted work sits on it. Display only —
// a missing repository (or a machine without git) simply reads as "no
// branch", never an error.

///|
pub async fn branch(
  payload : @protocol.GitBranchPayload,
) -> @protocol.GitBranchReply {
  let nothing : @protocol.GitBranchReply = { branch: None, diffstat: None, }
  // A live run hands us its cwd; a resumed conversation has none, so fall
  // back to the directory the session's engine runs in (mirrors
  // `host.open_path`).
  let base = if payload.cwd is Some(cwd) {
    @pathx.Absolute::parse_resource_path(cwd) catch {
      InvalidResourcePath => return nothing
    }
  } else {
    guard @work_dir.session_cwd(payload.session) is Some(base) else {
      return nothing
    }
    base
  }
  guard head_branch(base) is Some(branch) else {
    // Not a repository, or no git: there is nothing to count either.
    return nothing
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
  guard head_branch(base) is Some(after) else {
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
pub async fn head_branch(dir : @pathx.Absolute) -> String? {
  let name = match @gitx.probe(dir, ["rev-parse", "--abbrev-ref", "HEAD"]) {
    Some("HEAD") => @gitx.probe(dir, ["rev-parse", "--short", "HEAD"])
    Some(name) if !name.is_empty() => Some(name)
    // An unborn HEAD has no commit for `rev-parse` to resolve — it fails
    // outright — but the symbolic branch is already there. That is the state a
    // fresh `git init` leaves, where every line is staged or untracked and so
    // is exactly what the diffstat's empty-tree baseline exists to count.
    _ => @gitx.probe(dir, ["symbolic-ref", "--short", "HEAD"])
  }
  guard name is Some(name) && !name.is_empty() else { return None }
  Some(name)
}

///|
/// The branch `HEAD` points at, and nothing else. Unlike `branch` this
/// does not stand in a short hash for a detached checkout: a hash is a fine
/// thing to show a person and a nonsense thing to hand an API that filters by
/// branch name.
pub async fn symbolic_branch(dir : @pathx.Absolute) -> String? {
  guard @gitx.probe(dir, ["symbolic-ref", "--short", "--quiet", "HEAD"])
    is Some(output) else {
    return None
  }
  let name = single_line(output)
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
pub async fn branch_on_remote(dir : @pathx.Absolute, branch : String) -> Bool {
  for remote in git_remotes(dir) {
    if @gitx.probe(dir, [
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
async fn git_remotes(dir : @pathx.Absolute) -> Array[String] {
  let remotes : Array[String] = []
  guard @gitx.probe(dir, ["remote"]) is Some(listing) else { return remotes }
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
const MaxUntrackedDiffFiles : Int32 = 100

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
const DiffstatTimeoutMs : Int32 = 5000

///|
/// This branch's whole delta, counted locally: from where it left its base
/// straight to the working tree, so a commit and an unsaved edit weigh the
/// same and the number keeps moving as the agent works. Which base is
/// `git_branch_base`'s problem — `hint` carries what the branch's pull request
/// says, when the client has heard from one.
async fn git_diffstat(
  dir : @pathx.Absolute,
  hint? : String,
) -> @protocol.GitDiffStat? {
  // An unborn HEAD has no commit to diff against, but its index can already
  // hold staged additions, so the empty tree stands in for the missing commit.
  guard @gitx.probe(dir, ["rev-parse", "--verify", "--quiet", "HEAD"])
    is Some(_) else {
    return git_diffstat_from(dir, EmptyTreeObject, None)
  }
  let (baseline, base) = git_branch_base(dir, hint?)
  git_diffstat_from(dir, baseline, base)
}

///|
/// The remote-tracking ref to measure from. A hinted branch is looked for on
/// `origin`, the repository a pull request's base belongs to for every
/// checkout that is not a fork; a hint `origin` does not have falls through to
/// the default rather than measuring from nothing.
async fn git_base_ref(dir : @pathx.Absolute, hint? : String) -> String? {
  if hint is Some(branch) && !branch.is_empty() {
    let hinted = "origin/\{branch}"
    if @gitx.probe(dir, ["rev-parse", "--verify", "--quiet", hinted]) is Some(_) {
      return Some(hinted)
    }
  }
  guard @gitx.probe(dir, [
      "rev-parse", "--abbrev-ref", "--verify", "--quiet", "origin/HEAD",
    ])
    is Some(output) else {
    return None
  }
  let name = single_line(output)
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
pub async fn is_default_branch(dir : @pathx.Absolute, branch~ : String) -> Bool {
  git_base_ref(dir) is Some(base) && base == "origin/\{branch}"
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
async fn git_branch_base(
  dir : @pathx.Absolute,
  hint? : String,
) -> (String, String?) {
  guard git_base_ref(dir, hint?) is Some(base_ref) else {
    return ("HEAD", None)
  }
  guard @gitx.probe(dir, ["merge-base", "HEAD", base_ref]) is Some(output) else {
    return ("HEAD", None)
  }
  let commit = single_line(output)
  if commit.is_empty() {
    ("HEAD", None)
  } else {
    (commit, Some(base_ref))
  }
}

///|
/// The current branch's merge base with the default branch, including HEAD
/// when there are no branch commits beyond it.
/// `head` is the full identity captured by the surrounding snapshot,
/// rather than the mutable `HEAD` spelling, so a concurrent checkout cannot
/// choose one branch's fork point and publish another branch's rows.
///
/// `None` means the boundary could not be determined. The caller chooses
/// whether a valid HEAD boundary should use porcelain status.
async fn git_review_branch_base(
  dir : @pathx.Absolute,
  head : String?,
) -> String? {
  guard head is Some(head) else { return None }
  guard git_base_ref(dir) is Some(base_ref) else { return None }
  guard @gitx.probe(dir, ["merge-base", head, base_ref]) is Some(output) else {
    return None
  }
  let base = single_line(output)
  if base.is_empty() {
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
) -> @protocol.GitDiffStat? {
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
      @gitx.probe(dir, ["diff", "--numstat", baseline, "--", "."])
    })
    is Some(Some(tracked)) else {
    // Git failed, or it is still going. Either way nothing is counted, so
    // there is no floor to report and the chip stands on the branch alone.
    return None
  }
  let tracked = { ..parse_numstat(tracked), base, }
  // Exact output, not `probe`: trimming would eat a leading space of the
  // first NUL-separated path.
  let listing = @gitx.output(dir, [
    "ls-files", "--others", "--exclude-standard", "-z", "--", ".",
  ]) catch {
    // The listing itself was unreadable — a filename that is not valid UTF-8
    // defeats the text conversion even though Git succeeded. Every untracked
    // file is then missing from the total, which is a floor, not the whole.
    _ => return Some({ ..tracked, partial: true, })
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
        max_concurrency=32,
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
  let kind = @fs.kind(native, follow_symlink=false) catch { _ => return false }
  guard kind is Regular else { return false }
  let file = @fs.open(native, mode=ReadOnly) catch { _ => return false }
  defer file.close()
  let size = file.size() catch { _ => return false }
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
) -> @protocol.GitDiffStat? {
  let (code, stdout) = @gitx.output_with_status(dir, [
    "diff",
    "--numstat",
    "--no-index",
    "--",
    "/dev/null",
    path.0,
  ]) catch {
    _ => return None
  }
  let stat = parse_numstat(stdout)
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
fn parse_numstat(output : String) -> @protocol.GitDiffStat {
  let mut added = 0
  let mut removed = 0
  let mut files = 0
  for line in output.split("\n") {
    let line = line.trim_end(chars="\r")
    guard line.split_once("\t") is Some((added_text, rest)) else { continue }
    guard rest.split_once("\t") is Some((removed_text, _)) else { continue }
    files += 1
    added += @string.parse_int(added_text) catch { _ => 0 }
    removed += @string.parse_int(removed_text) catch { _ => 0 }
  }
  { added, removed, files, base: None, partial: false, }
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
fn compare_git_change_path(
  left : @protocol.GitChange,
  right : @protocol.GitChange,
) -> Int32 {
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
fn parse_git_status_z(output : String) -> Array[@protocol.GitChange] {
  let fields = output.split("\u{0}").map(field => field.to_owned()).collect()
  let changes : Array[@protocol.GitChange] = []
  let mut index = 0
  while index < fields.length() {
    let record = fields[index]
    if record.length() < 4 {
      index += 1
      continue
    }
    let index_status = record.exact_view(end=1).to_owned()
    let worktree_status = record.exact_view(start=1, end=2).to_owned()
    let path = record.exact_view(start=3).to_owned()
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
pub fn parse_diff_name_status_z(output : String) -> Array[@protocol.GitChange] {
  if !output.is_empty() && !output.has_suffix("\u{0}") {
    return []
  }
  let fields = output.split("\u{0}").map(field => field.to_owned()).collect()
  let changes : Array[@protocol.GitChange] = []
  let mut index = 0
  while index < fields.length() {
    let status = fields[index]
    index += 1
    if status.is_empty() {
      continue
    }
    let code = status.exact_view(end=1).to_owned()
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
fn parse_git_untracked_z(output : String) -> Array[@protocol.GitChange] {
  if !output.is_empty() && !output.has_suffix("\u{0}") {
    return []
  }
  let changes : Array[@protocol.GitChange] = []
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
  changes : Array[@protocol.GitChange],
  status_changes : Array[@protocol.GitChange],
) -> Array[@protocol.GitChange] {
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
  change : @protocol.GitChange,
  workspace_prefix : String,
) -> @protocol.GitChange? {
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
    path.exact_view(start=workspace_prefix.length()).to_owned()
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
    guard record.has_prefix(prefix) &&
      record.split_once("\t") is Some((_, path)) else {
      continue
    }
    let path = path.to_owned()
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
fn deleted_change_paths(changes : Array[@protocol.GitChange]) -> Array[String] {
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
  change : @protocol.GitChange,
  path_kind : @fs.FileKind,
  known_gitlink : Bool,
  known_symlink : Bool,
) -> @protocol.GitChange {
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
pub fn single_line(output : String) -> String {
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
/// Capture the exact index entries used by one review snapshot. Task mode
/// reads this again after its diff/untracked queries, so an index-only change
/// retries just like a concurrent commit instead of publishing mixed rows.
async fn git_index_metadata(dir : @pathx.Absolute) -> String {
  @gitx.output(dir, ["ls-files", "--full-name", "--stage", "-z", "--", "."])
}

///|
/// Resolve one revision to an immutable commit identity. A missing revision is
/// ordinary (an unborn HEAD or an object that disappeared), so any failure to
/// resolve reads as None.
pub async fn revision_commit(
  dir : @pathx.Absolute,
  revision : String,
) -> String? {
  guard @gitx.probe(dir, ["rev-parse", "--verify", "\{revision}^{commit}"])
    is Some(commit) &&
    !commit.is_empty() else {
    return None
  }
  Some(commit)
}

///|
pub fn valid_commit_identity(revision : String) -> Bool {
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
/// Read the review inventory while HEAD remains the same. PR checkout bases
/// stay pinned; other checkouts prefer their current default-branch fork point
/// and fall back to the task's creation commit or porcelain's HEAD status.
/// Bracket the snapshot with revision reads and retry a concurrent
/// commit/checkout instead of relying on the next poll to self-heal.
async fn git_change_snapshot(
  dir : @pathx.Absolute,
  workspace_prefix : String,
  retries_left~ : Int32,
  pr_base? : String,
  worktree_base? : String,
) -> (
  String?,
  String?,
  Set[String],
  Set[String],
  Set[String],
  Set[String],
  Array[@protocol.GitChange],
) {
  let head = revision_commit(dir, "HEAD")
  let review_base = if pr_base is Some(_) {
    pr_base
  } else if git_review_branch_base(dir, head) is Some(branch_base) {
    // Ordinary checkouts keep porcelain's staged/worktree columns at HEAD.
    // Worktrees retain the valid boundary instead of falling back to an old
    // creation commit and including upstream changes.
    if worktree_base is None && head == Some(branch_base) {
      None
    } else {
      Some(branch_base)
    }
  } else {
    worktree_base
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
      let raw = @gitx.output(dir, [
        "ls-files", "--full-name", "--others", "--exclude-standard", "-z", "--",
        ".",
      ])
      parse_git_untracked_z(raw).filter_map(change => {
        git_change_relative_to_workspace(change, workspace_prefix)
      })
    }
    None => {
      let raw = @gitx.output(dir, [
        "status", "--porcelain=v1", "-z", "--untracked-files=all", "--", ".",
      ])
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
      let diff_raw = @gitx.output(dir, [
        "diff", "--name-status", "-z", "--no-ext-diff", "--find-renames", base, "--",
        ".",
      ])
      let task_changes = parse_diff_name_status_z(diff_raw).filter_map(change => {
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
      let comparison_metadata = @gitx.output(dir, tree_args)
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
        retries_left=retries_left - 1,
        pr_base?,
        worktree_base?,
      )
    }
    raise Stale("Git index kept changing while task changes were read")
  }
  let confirmed_head = revision_commit(dir, "HEAD")
  if confirmed_head != head {
    if retries_left > 0 {
      return git_change_snapshot(
        dir,
        workspace_prefix,
        retries_left=retries_left - 1,
        pr_base?,
        worktree_base?,
      )
    }
    raise Stale("HEAD kept changing while Git changes were read")
  }
  (
    head, review_base, known_gitlinks, known_symlinks, deleted_gitlinks, deleted_symlinks,
    changes,
  )
}

///|
pub async fn changes(
  payload : @protocol.GitChangesPayload,
) -> @protocol.GitChangesReply {
  let workspace = @pathx.Absolute::parse_resource_path(payload.workspace)
  guard @work_dir.resolve_in_workspace(
      payload.session,
      "",
      workspace=payload.workspace,
    )
    is Some(root) else {
    raise InvalidRequest("could not resolve the conversation workspace")
  }
  if !@gitx.is_work_tree(root) {
    return { repository: false, head: None, baseline: None, changes: [], }
  }
  // Strip only the line ending: a workspace directory may begin with a space.
  let workspace_prefix = single_line(
    @gitx.output(root, ["rev-parse", "--show-prefix"]),
  )
  let pr_base = pr_association(root).map(pr => pr.base)
  let worktree_base = if pr_base is Some(_) {
    None
  } else {
    let recorded_base = @work_dir.session_review_base(
      payload.session,
      workspace,
    )
    if recorded_base is Some(base) {
      guard valid_commit_identity(base) else {
        raise Failed("recorded Git task baseline is invalid")
      }
      guard revision_commit(root, base) is Some(commit) else {
        raise Failed("recorded Git task baseline is unavailable")
      }
      Some(commit)
    } else {
      None
    }
  }
  let (
    head,
    baseline,
    known_gitlinks,
    known_symlinks,
    deleted_gitlinks,
    deleted_symlinks,
    changes,
  ) = git_change_snapshot(
    root,
    workspace_prefix,
    retries_left=2,
    pr_base?,
    worktree_base?,
  )
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
    max_concurrency=32,
  )
  { repository: true, head, baseline, changes, }
}

///|
fn push_history_ref(
  refs : Array[@protocol.GitHistoryRef],
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
async fn git_history_upstream(dir : @pathx.Absolute) -> String? {
  guard @gitx.probe(dir, [
      "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}",
    ])
    is Some(output) else {
    return None
  }
  let upstream = single_line(output)
  if upstream.is_empty() || upstream == "@{upstream}" {
    None
  } else {
    Some(upstream)
  }
}

///|
/// Prefer the configured upstream remote's symbolic default, then the
/// repository's ordinary origin/HEAD declaration. No branch-name guessing.
async fn git_history_default_ref(
  dir : @pathx.Absolute,
  upstream : String?,
) -> String? {
  if upstream is Some(upstream) && upstream.split_once("/") is Some((remote, _)) {
    let symbolic = "refs/remotes/\{remote}/HEAD"
    if @gitx.probe(dir, ["symbolic-ref", "--quiet", "--short", symbolic])
      is Some(output) {
      let name = single_line(output)
      if !name.is_empty() && name != symbolic {
        return Some(name)
      }
    }
  }
  git_base_ref(dir)
}

///|
async fn capture_git_history_snapshot(
  dir : @pathx.Absolute,
  review_base : String?,
) -> @protocol.GitHistorySnapshot {
  let head = revision_commit(dir, "HEAD")
  let branch = match
    @gitx.probe(dir, ["symbolic-ref", "--quiet", "--short", "HEAD"]) {
    Some(output) => {
      let name = single_line(output)
      if name.is_empty() {
        None
      } else {
        Some(name)
      }
    }
    None => None
  }
  let refs : Array[@protocol.GitHistoryRef] = []
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
    revision_commit(dir, upstream) is Some(upstream_commit) {
    push_history_ref(refs, tips, upstream, upstream_commit, "upstream")
  }
  match review_base {
    Some(base) => push_history_ref(refs, tips, "Review base", base, "base")
    None =>
      if git_history_default_ref(dir, upstream) is Some(base_ref) &&
        revision_commit(dir, base_ref) is Some(base) {
        push_history_ref(refs, tips, base_ref, base, "base")
      }
  }
  { head, branch, refs, tips, }
}

///|
/// The client echoes only values previously produced by this host. Validate
/// every object identity again before it can become a Git argv entry.
async fn validate_git_history_snapshot(
  dir : @pathx.Absolute,
  snapshot : @protocol.GitHistorySnapshot,
) -> @protocol.GitHistorySnapshot {
  if snapshot.refs.length() > 16 || snapshot.tips.length() > 16 {
    raise Failed("Git history snapshot contains too many refs")
  }
  for tip in snapshot.tips {
    guard valid_commit_identity(tip) &&
      revision_commit(dir, tip) is Some(resolved) &&
      resolved == tip else {
      raise Failed("Git history snapshot contains an unavailable commit")
    }
  }
  for ref_ in snapshot.refs {
    guard ref_.name.length() <= 512 &&
      ["current", "upstream", "base", "head"].contains(ref_.kind) &&
      valid_commit_identity(ref_.revision) &&
      revision_commit(dir, ref_.revision) is Some(resolved) &&
      resolved == ref_.revision &&
      snapshot.tips.contains(ref_.revision) else {
      raise Failed("Git history snapshot contains an invalid ref")
    }
  }
  if snapshot.head is Some(head) {
    guard valid_commit_identity(head) &&
      revision_commit(dir, head) is Some(resolved) &&
      resolved == head else {
      raise Failed("Git history snapshot contains an unavailable HEAD")
    }
  }
  snapshot
}

///|
fn parse_git_history_z(output : String) -> Array[@protocol.GitHistoryCommit] {
  let fields = output.split("\u{0}").map(field => field.to_owned()).collect()
  let commits : Array[@protocol.GitHistoryCommit] = []
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
  dir : @pathx.Absolute,
  snapshot : @protocol.GitHistorySnapshot,
  skip : Int32,
  limit : Int32,
) -> (Array[@protocol.GitHistoryCommit], Bool) {
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
  let commits = parse_git_history_z(@gitx.output(dir, args))
  let has_more = commits.length() > limit
  if has_more {
    ignore(commits.pop())
  }
  (commits, has_more)
}

///|
pub async fn history(
  payload : @protocol.GitHistoryPayload,
) -> @protocol.GitHistoryReply {
  let workspace = @pathx.Absolute::parse_resource_path(payload.workspace)
  guard payload.skip >= 0 &&
    @work_dir.resolve_in_workspace(
      payload.session,
      "",
      workspace=payload.workspace,
    )
    is Some(root) else {
    raise InvalidRequest("could not resolve the conversation workspace")
  }
  let empty : @protocol.GitHistorySnapshot = {
    head: None,
    branch: None,
    refs: [],
    tips: [],
  }
  if !@gitx.is_work_tree(root) {
    return { repository: false, snapshot: empty, commits: [], has_more: false, }
  }
  let recorded_base = @work_dir.session_review_base(payload.session, workspace)
  let review_base = match recorded_base {
    Some(base) => {
      guard valid_commit_identity(base) &&
        revision_commit(root, base) is Some(commit) else {
        raise Failed("recorded Git task baseline is unavailable")
      }
      Some(commit)
    }
    None => None
  }
  let snapshot = match payload.snapshot {
    Some(snapshot) => validate_git_history_snapshot(root, snapshot)
    None => capture_git_history_snapshot(root, review_base)
  }
  let limit = if payload.limit <= 0 {
    50
  } else if payload.limit > 100 {
    100
  } else {
    payload.limit
  }
  let (commits, has_more) = git_history_page(
    root,
    snapshot,
    payload.skip,
    limit,
  )
  { repository: true, snapshot, commits, has_more, }
}

///|
async fn git_tree_object_modes(
  dir : @pathx.Absolute,
  workspace_prefix : String,
  revision : String,
) -> (Set[String], Set[String]) {
  let output = @gitx.output(dir, [
    "ls-tree", "-r", "--full-name", "-z", revision, "--", ".",
  ])
  (
    parse_git_mode_paths(output, workspace_prefix, "160000"),
    parse_git_mode_paths(output, workspace_prefix, "120000"),
  )
}

///|
async fn git_commit_changes_at(
  dir : @pathx.Absolute,
  workspace_prefix : String,
  commit : String,
) -> @protocol.GitCommitChangesReply {
  guard revision_commit(dir, commit) is Some(commit) else {
    raise Failed("Git commit is unavailable")
  }
  let parents = @gitx.run(dir, ["show", "-s", "--format=%P", commit])
  let parent = if parents.is_empty() {
    None
  } else {
    Some(
      match parents.split_once(" ") {
        Some((first, _)) => first.to_owned()
        None => parents
      },
    )
  }
  let base = parent.unwrap_or(EmptyTreeObject)
  let raw = @gitx.output(dir, [
    "diff", "--name-status", "-z", "--no-ext-diff", "--find-renames", "--find-copies-harder",
    base, commit, "--", ".",
  ])
  let parsed = parse_diff_name_status_z(raw).filter_map(change => {
    git_change_relative_to_workspace(change, workspace_prefix)
  })
  let (new_gitlinks, new_symlinks) = git_tree_object_modes(
    dir, workspace_prefix, commit,
  )
  let (old_gitlinks, old_symlinks) = git_tree_object_modes(
    dir, workspace_prefix, base,
  )
  let changes : Array[@protocol.GitHistoricalChange] = []
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
pub async fn commit_changes(
  payload : @protocol.GitCommitChangesPayload,
) -> @protocol.GitCommitChangesReply {
  guard valid_commit_identity(payload.commit) &&
    @work_dir.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(root) else {
    raise InvalidRequest("invalid Git commit request")
  }
  if !@gitx.is_work_tree(root) {
    raise InvalidRequest("workspace is not a Git repository")
  }
  // Strip only the line ending: a workspace directory may begin with a space.
  let workspace_prefix = single_line(
    @gitx.output(root, ["rev-parse", "--show-prefix"]),
  )
  git_commit_changes_at(root, workspace_prefix, payload.commit)
}

///|
async fn git_original_file_at(
  dir : @pathx.Absolute,
  relative : @pathx.Relative,
  revision : String,
) -> @protocol.GitOriginalFileReply {
  // Resolve the requested revision to an immutable commit before addressing
  // its path. The caller has already validated the workspace and tree path.
  guard revision_commit(dir, revision) is Some(commit) else { return Missing }
  // `./` makes the tree path relative to Git's current directory, which is
  // the conversation workspace even when that workspace is a repository
  // subdirectory. Resolve the commit:path name once; all following checks and
  // the read use the immutable blob ID.
  let object = "\{commit}:./\{relative.0}"
  guard @gitx.probe(dir, ["rev-parse", "--verify", object]) is Some(oid) &&
    !oid.is_empty() else {
    return Missing
  }
  if @gitx.run(dir, ["cat-file", "-t", oid]) != "blob" {
    return BinaryOriginal
  }
  let size_text = @gitx.run(dir, ["cat-file", "-s", oid])
  let size : Int64 = @string.parse_int64(size_text) catch {
    _ => raise Failed("Git returned an invalid blob size")
  }
  if size > @files.MaxEditorFileBytes.to_int64() {
    return OversizedOriginal
  }
  let content = @gitx.output_bytes(dir, ["cat-file", "-p", oid])
  // Use the same content policy as working-tree reads so a tab cannot treat
  // its current file and Git baseline as different kinds of content.
  match @filekind.classify(content) {
    Utf8Text(text) => OriginalContent(text)
    Pdf | Image(_) | UnknownBinary => BinaryOriginal
  }
}

///|
pub async fn original_file(
  payload : @protocol.GitOriginalFilePayload,
) -> @protocol.GitOriginalFileReply {
  guard @work_dir.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(root) &&
    git_tree_relative(payload.path) is Some(relative) else {
    raise InvalidRequest("path is outside the conversation workspace")
  }
  if !@gitx.is_work_tree(root) {
    return Missing
  }
  // New clients pass the exact HEAD identity returned with their change
  // snapshot; the fallback keeps older clients compatible.
  let revision = match payload.revision {
    Some(revision) => {
      guard valid_commit_identity(revision) else {
        raise InvalidRequest("invalid Git revision identity")
      }
      revision
    }
    None => "HEAD"
  }
  git_original_file_at(root, relative, revision)
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
  let changes = parse_diff_name_status_z(
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
  assert_true(parse_diff_name_status_z("M\u{0}").is_empty())
  assert_true(parse_diff_name_status_z("R100\u{0}old.mbt\u{0}").is_empty())
  assert_true(
    parse_diff_name_status_z("C100\u{0}\u{0}copy.mbt\u{0}").is_empty(),
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
test "Git tree paths are lexically contained without resolving symlinks" {
  assert_eq(git_tree_relative("src/link"), Some(Relative("src/link")))
  assert_eq(git_tree_relative("src/../link"), Some(Relative("link")))
  assert_true(git_tree_relative("../secret") is None)
  assert_true(git_tree_relative("src/../../secret") is None)
}

///|
test "Git single-line output preserves significant path whitespace" {
  assert_eq(single_line(" spaced/\n"), " spaced/")
  assert_eq(single_line("trailing /\r\n"), "trailing /")
  assert_eq(single_line("\n"), "")
}

///|
test "Git non-file changes are classified without following symlinks" {
  let change : @protocol.GitChange = {
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
  let deleted : @protocol.GitChange = {
    path: "same",
    original_path: None,
    index_status: "D",
    worktree_status: " ",
    kind: "deleted",
  }
  let untracked : @protocol.GitChange = {
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
  let deleted : @protocol.GitChange = {
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
  let renamed : @protocol.GitChange = {
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
