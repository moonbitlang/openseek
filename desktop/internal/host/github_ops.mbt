// The composer's pull-request chip: report the GitHub pull request for a
// non-default branch a conversation's working directory has checked out.
// Answered through the `gh` CLI, so the desktop inherits the user's own GitHub
// authentication — enterprise hosts, fork remotes, and all — instead of
// holding a token of its own. No `gh`, no authentication, or no GitHub remote
// all read as "nothing to show", never an error: this is decoration beside the
// branch name.

///|
/// Where the composer stops waiting for GitHub. A slow or unreachable API must
/// not hold a bridge request open; the chip simply stays absent until the next
/// refresh.
const GithubRequestTimeoutMs : Int = 10000

///|
/// How many of the branch's pull requests to look at. gh lists newest first,
/// and a branch reused after its pull request merged is ordinary — one page of
/// candidates is enough to prefer the open one.
const PullRequestCandidates : Int = 5

///|
/// The gh fields one `gh pr list` has to return to fill the chip.
/// `isCrossRepository` is not rendered; it separates this checkout's pull
/// request from a fork's that happens to share the branch name.
/// `baseRefName` is not rendered either: it is what the diffstat measures
/// from, and the only exact answer to that question anywhere.
const PullRequestFields : String = "number,title,state,url,baseRefName,isDraft,additions,deletions,changedFiles,statusCheckRollup,isCrossRepository"

///|
#cfg(platform="windows")
const GhExecutable : String = "gh.exe"

///|
#cfg(not(platform="windows"))
const GhExecutable : String = "gh"

///|
async fn git_pull_request_op(
  payload : GitPullRequestPayload,
) -> GitPullRequestReply {
  let nothing : GitPullRequestReply = {
    pull_request: None,
    compare_url: None,
    branch: None,
  }
  // Addressed exactly like `git.branch`, so the two chips can never end up
  // describing different branches.
  let base = match payload.cwd {
    Some(cwd) => @pathx.Absolute::from_uri_path(cwd)
    None => @work_dir.session_cwd(payload.session)
  }
  guard base is Some(base) else { return nothing }
  // Read from `HEAD` rather than blindly trusting the caller. Codex-managed
  // worktrees are normally detached, though, so recover a branch only when it
  // demonstrably names the same commit: first app-server's creation-time hint,
  // then the one unambiguous local branch pointing exactly at HEAD.
  guard git_branch(base.0) is Some(checkout) else { return nothing }
  let mut head = git_symbolic_branch(base.0)
  if head is None && payload.branch_hint is Some(hint) {
    let valid_hint = git_output_opt(base.0, [
      "check-ref-format", "--branch", hint,
    ])
    let current = git_revision_commit(base.0, "HEAD")
    let hinted = git_revision_commit(base.0, "refs/heads/\{hint}")
    if valid_hint is Some(_) && current is Some(_) && current == hinted {
      head = Some(hint)
    }
  }
  if head is None &&
    git_output_opt(base.0, [
      "for-each-ref", "--format=%(refname:short)", "--points-at", "HEAD", "refs/heads",
    ])
    is Some(output) {
    let exact : Array[String] = []
    for line in output.split("\n") {
      let branch = line.trim_end(chars="\r")
      if !branch.is_empty() {
        exact.push(branch.to_owned())
      }
    }
    if exact.length() == 1 {
      head = Some(exact[0])
    }
  }
  let branch = head.unwrap_or(checkout)
  let unanswered : GitPullRequestReply = { ..nothing, branch: Some(branch), }
  // A hash remains useful display text but must never become a gh branch
  // filter when no exact local ref was recovered.
  guard head is Some(head) else { return unanswered }
  // The default branch is the destination of pull requests, not work waiting
  // to become one. In particular, `gh pr list --head main --state all` can
  // return an old cross-repository pull request whose fork branch was also
  // named `main`; showing that merged request here makes the current main
  // branch look like the historical fork. Stop before resolving gh so neither
  // that chip nor a create-pull-request link can appear on the default branch.
  if git_is_default_branch(base.0, branch=head) {
    return unanswered
  }
  guard resolve_gh() is Some(gh) else { return unanswered }
  // One deadline for the whole exchange, however many calls it takes.
  @async.with_timeout_opt(GithubRequestTimeoutMs, () => {
    branch_pull_request(gh, base, head)
  }).unwrap_or(unanswered)
}

///|
/// Ask GitHub what it knows about `branch`.
async fn branch_pull_request(
  gh : @pathx.Absolute,
  dir : @pathx.Absolute,
  branch : String,
) -> GitPullRequestReply {
  let listing = gh_json(gh, dir, [
    "pr",
    "list",
    "--head",
    branch,
    "--state",
    "all",
    "--limit",
    "\{PullRequestCandidates}",
    "--json",
    PullRequestFields,
  ])
  let nothing : GitPullRequestReply = {
    pull_request: None,
    compare_url: None,
    branch: Some(branch),
  }
  guard listing is Some(Array(candidates)) else { return nothing }
  if pick_pull_request(candidates) is Some(pull_request) {
    return { ..nothing, pull_request: Some(pull_request), }
  }
  // The branch has no pull request *in the repository gh resolved*. Which
  // repository that is stays gh's decision — its `repo.default`, the parent it
  // infers for a fork, `GH_REPO` — rather than something a remote-URL parser
  // here would have to guess for enterprise hosts and fork remotes. The known
  // gap: a fork checkout whose default resolves to the fork misses a pull
  // request that targets upstream, and reads as "no pull request yet".
  //
  // A branch no remote has yet gets no link at all: GitHub cannot compare a
  // ref it has never seen, so the offer would open a page that can do nothing
  // with the commits. That is the ordinary state of a branch an agent just
  // made, which is exactly when the offer would be most tempting to click —
  // and the remote-tracking refs settle it without touching the network.
  guard git_branch_on_remote(dir.0, branch) else { return nothing }
  // Some remote having it is not enough. The link names one repository, and
  // gh's pick is not always the one that was pushed to: gh prefers a remote
  // called `upstream` over `origin`, so a fork checkout resolves to the parent
  // while the branch only ever reached the fork, and an unqualified compare
  // there names a ref the parent has never seen. Asking through gh's own
  // `{owner}`/`{repo}` placeholders is what keeps this question and the URL
  // below from disagreeing about which repository they mean.
  guard gh_json(gh, dir, [
      "api",
      "repos/{owner}/{repo}/branches/\{encode_url_path(branch)}",
    ])
    is Some(Object(_)) else {
    return nothing
  }
  // Only this branch pays for the two extra calls.
  guard gh_json(gh, dir, ["repo", "view", "--json", "url"])
    is Some(Object(repo)) &&
    repo.get("url") is Some(String(url)) else {
    return nothing
  }
  {
    ..nothing,
    compare_url: Some("\{url}/compare/\{encode_url_path(branch)}?expand=1"),
  }
}

///|
/// The pull request the chip should show: an open one when the branch has one,
/// otherwise the most recent. A branch whose pull request already merged still
/// deserves to say so rather than show nothing.
///
/// `--head` filters by branch name alone — gh does not accept `owner:branch` —
/// so a busy repository can answer with several forks' pull requests that
/// happen to share the name. One whose head lives in another repository is
/// someone else's work; those are dropped unless dropping them leaves nothing,
/// which is exactly what a fork checkout looks like, every pull request in it
/// being cross-repository.
fn pick_pull_request(candidates : Array[Json]) -> GitPullRequest? {
  let own = candidates.filter(candidate => {
    candidate is Object(fields) &&
    fields.get("isCrossRepository") is Some(False)
  })
  let candidates = if own.is_empty() { candidates } else { own }
  let parsed = candidates.filter_map(parse_pull_request)
  for candidate in parsed {
    if candidate.state == "open" {
      return Some(candidate)
    }
  }
  parsed.get(0)
}

///|
/// Decode one `gh pr list` element. Every field the chip renders is required:
/// a record missing one is a gh version whose output this does not understand,
/// which is worth showing nothing for rather than a half-filled chip.
fn parse_pull_request(json : Json) -> GitPullRequest? {
  guard json is Object(fields) else { return None }
  guard fields.get("title") is Some(String(title)) else { return None }
  guard fields.get("url") is Some(String(url)) else { return None }
  guard fields.get("baseRefName") is Some(String(base)) else { return None }
  guard json_count(fields, "number") is Some(number) else { return None }
  guard json_count(fields, "additions") is Some(additions) else { return None }
  guard json_count(fields, "deletions") is Some(deletions) else { return None }
  guard json_count(fields, "changedFiles") is Some(changed_files) else {
    return None
  }
  // A draft is an open pull request that merely refuses to merge, so the two
  // stay separate fields rather than a fourth state.
  let state = match fields.get("state") {
    Some(String("OPEN")) => "open"
    Some(String("MERGED")) => "merged"
    Some(String("CLOSED")) => "closed"
    _ => return None
  }
  Some({
    number,
    title,
    state,
    draft: fields.get("isDraft") is Some(True),
    url,
    base,
    additions,
    deletions,
    changed_files,
    checks: parse_checks(fields.get("statusCheckRollup")),
  })
}

///|
/// JSON has one number type; every count GitHub reports here is an integer.
fn json_count(fields : Map[String, Json], key : String) -> Int? {
  guard fields.get(key) is Some(Number(value, ..)) else { return None }
  Some(value.to_int())
}

///|
/// Summarize the head commit's checks. None when the commit reports none at
/// all — no checks configured is not the same as checks that have not run.
fn parse_checks(rollup : Json?) -> GitChecks? {
  guard rollup is Some(Array(entries)) && !entries.is_empty() else {
    return None
  }
  let (passed, failed, pending) = for
    entry in entries
    passed = 0, failed = 0, pending = 0 {
    guard entry is Object(fields) else { continue passed, failed, pending }
    match check_state(fields) {
      Passed => continue passed + 1, failed, pending
      Failed => continue passed, failed + 1, pending
      Pending => continue passed, failed, pending + 1
    }
  } nobreak {
    (passed, failed, pending)
  }
  Some({ passed, failed, pending, })
}

///|
priv enum CheckState {
  Passed
  Failed
  Pending
}

///|
/// Bucket one `statusCheckRollup` entry. GitHub reports Actions checks as
/// check runs — a status, plus a conclusion once that status is `COMPLETED` —
/// and older integrations as commit statuses carrying a single state; only
/// check runs have a `status` field. Skipped, neutral, and cancelled
/// conclusions count as passed: they are finished and not something to act on.
fn check_state(fields : Map[String, Json]) -> CheckState {
  if fields.get("status") is Some(String(status)) {
    guard status == "COMPLETED" else { return Pending }
    return match fields.get("conclusion") {
      Some(
        String(
          "FAILURE"
          | "TIMED_OUT"
          | "ACTION_REQUIRED"
          | "STARTUP_FAILURE"
          | "STALE"
        )
      ) => Failed
      _ => Passed
    }
  }
  match fields.get("state") {
    Some(String("FAILURE" | "ERROR")) => Failed
    Some(String("PENDING" | "EXPECTED")) => Pending
    _ => Passed
  }
}

///|
/// Run gh for JSON output in the conversation's checkout. Everything that can
/// go wrong — no authentication, no network, a repository gh does not
/// recognize, output from a gh whose schema changed — reads the same way here:
/// there is nothing to show. The Git environment scrub applies to gh too, so a
/// stray `GIT_DIR` cannot redirect which repository it answers about.
async fn gh_json(
  gh : @pathx.Absolute,
  dir : @pathx.Absolute,
  args : Array[String],
) -> Json? {
  let (code, stdout, _) = @processx.collect_output_no_stdin(
    gh.0,
    args,
    cwd=dir.0,
    extra_env=git_environment(),
    inherit_env=false,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  guard code == 0 else { return None }
  let output = stdout.text() catch { _ => return None }
  Some(@json.parse(output)) catch {
    _ => None
  }
}

///|
/// Where `gh` lives, probed the way a shell would: the path variable in order,
/// then the package managers' default prefixes. A desktop launched from Finder
/// or launchd inherits a path that has never seen the user's shell
/// configuration, so those constants are the rescue — the same shape the
/// MoonBit toolchain resolver uses for `~/.moon/bin`.
async fn resolve_gh() -> @pathx.Absolute? {
  let candidates : Array[@pathx.Path] = []
  if @env.get("PATH") is Some(value) {
    for entry in value.split(@env.path_sep) {
      if !entry.is_empty() {
        candidates.push(Path(entry.to_owned()))
      }
    }
  }
  candidates.push(Path("/opt/homebrew/bin"))
  candidates.push(Path("/usr/local/bin"))
  if @home.dir() is Some(home) {
    candidates.push(home.join(Relative(".local/bin")))
  }
  for candidate in candidates {
    // A relative path entry names something only from this process's own
    // working directory, which is not where gh would run.
    guard candidate.to_absolute() is Some(dir) else { continue }
    let executable = dir.join(Relative(GhExecutable))
    if @fsx.is_executable_file(executable.to_path()) {
      return Some(executable)
    }
  }
  None
}

///|
/// Percent-encode a branch name for a URL path. Git allows `#`, `%`, `&`, and
/// `+` in branch names, each of which means something else in a URL, while `/`
/// is left alone because a namespaced branch really is a multi-segment path.
fn encode_url_path(path : String) -> String {
  let encoded = StringBuilder()
  for char in path {
    if is_url_path_plain(char) {
      encoded <+ "\{char}"
    } else {
      for byte in @utf8.encode("\{char}") {
        let value = byte.to_int()
        encoded <+ "%"
        if value < 16 {
          encoded <+ "0"
        }
        encoded <+ "\{value.to_string(radix=16).to_upper()}"
      }
    }
  }
  encoded.to_string()
}

///|
/// RFC 3986's unreserved set, plus the separator a branch path uses.
fn is_url_path_plain(char : Char) -> Bool {
  char is ('a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '.' | '_' | '~' | '/')
}

///|
/// One `gh pr list` element, spelled the way gh spells it, for the tests to
/// vary field by field.
fn pull_request_json(
  number~ : Int,
  state~ : String,
  draft~ : Bool,
  checks? : Json = Json::null(),
  cross? : Bool = false,
) -> Json {
  {
    "number": Json(number.to_double()),
    "title": "Add a changed-files explorer",
    "state": "\{state}",
    "url": "https://github.test/acme/app/pull/\{number}",
    "isDraft": Json(draft),
    "baseRefName": "main",
    "additions": 2972,
    "deletions": 287,
    "changedFiles": 18,
    "statusCheckRollup": checks,
    "isCrossRepository": Json(cross),
  }
}

///|
test "An open pull request outranks the branch's older merged one" {
  let candidates = [
    pull_request_json(number=712, state="OPEN", draft=true),
    pull_request_json(number=700, state="MERGED", draft=false),
  ]
  guard pick_pull_request(candidates) is Some(picked) else {
    fail("expected a pull request")
  }
  assert_eq(picked.number, 712)
  assert_eq(picked.state, "open")
  // A draft stays open — it is a pull request that refuses to merge, not a
  // fourth state — and GitHub's own totals come through unrounded.
  assert_true(picked.draft)
  assert_eq(
    (picked.additions, picked.deletions, picked.changed_files),
    (2972, 287, 18),
  )
  // Order still decides once no candidate is open.
  guard pick_pull_request(candidates[1:].to_owned()) is Some(merged) else {
    fail("expected the merged pull request")
  }
  assert_eq(merged.state, "merged")
}

///|
test "A fork's pull request does not answer for this checkout's branch" {
  // `--head` matches the branch name in every repository that forked this one,
  // so an open pull request from someone else's fork can arrive first.
  let outsider = pull_request_json(
    number=900,
    state="OPEN",
    draft=false,
    cross=true,
  )
  let mine = pull_request_json(number=712, state="MERGED", draft=false)
  guard pick_pull_request([outsider, mine]) is Some(picked) else {
    fail("expected a pull request")
  }
  // Merged and second in the list, but the only one whose head is here.
  assert_eq(picked.number, 712)
  // A fork checkout has nothing but cross-repository pull requests; dropping
  // them all would leave the chip blank, so there the filter stands down.
  guard pick_pull_request([outsider]) is Some(only) else {
    fail("a fork checkout still has its own pull request")
  }
  assert_eq(only.number, 900)
}

///|
test "A pull request record missing a rendered field is not shown at all" {
  assert_eq(pick_pull_request([]), None)
  // An unknown state is a gh whose output this does not understand.
  assert_eq(
    pick_pull_request([pull_request_json(number=1, state="LOCKED", draft=false)]),
    None,
  )
  let json = pull_request_json(number=1, state="OPEN", draft=false)
  guard json is Object(fields) else { fail("expected an object") }
  for absent in ["title", "url", "number", "additions", "changedFiles"] {
    let entries : Map[String, Json] = Map([])
    for key, value in fields {
      if key != absent {
        entries[key] = value
      }
    }
    assert_eq(parse_pull_request(Json(entries)), None)
  }
}

///|
test "Check rollup separates running checks from failed and finished ones" {
  let rollup : Json = [
    { "__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SUCCESS" },
    { "__typename": "CheckRun", "status": "IN_PROGRESS", "conclusion": "" },
    { "__typename": "CheckRun", "status": "COMPLETED", "conclusion": "FAILURE" },
    // Skipped work is finished and not something to act on.
    { "__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SKIPPED" },
    // Older integrations report a commit status instead, with no `status`.
    { "__typename": "StatusContext", "state": "PENDING" },
    { "__typename": "StatusContext", "state": "ERROR" },
  ]
  assert_eq(
    parse_checks(Some(rollup)),
    Some({ passed: 2, failed: 2, pending: 2, }),
  )
  // No checks configured is not the same as checks that have not run.
  assert_eq(parse_checks(Some(Json(([] : Array[Json])))), None)
  assert_eq(parse_checks(None), None)
}

///|
test "Branch names reach the compare URL intact" {
  assert_eq(encode_url_path("feature/add-git-info"), "feature/add-git-info")
  // Git allows these; a URL reads them as fragment, escape, and separator.
  assert_eq(encode_url_path("fix/#123 %&+"), "fix/%23123%20%25%26%2B")
  assert_eq(encode_url_path("功能/新"), "%E5%8A%9F%E8%83%BD/%E6%96%B0")
}
