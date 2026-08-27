// The composer's git chip and the popover behind it: ask the host for the
// branch of a conversation's workspace through the `git.branch` method, and
// for that branch's GitHub pull request through `git.pull_request`. Probed
// when a run starts (the workspace is created lazily on the first one), when a
// stored session opens, and when a run finishes (the agent may have created
// the repository, switched branches, or opened a pull request mid-turn). Any
// failure just reads as "nothing to show" — the chip hides.

///|
/// This branch's whole line delta, measured locally: from where it left the
/// remote's default branch all the way to the working tree, untracked files
/// included. `base` names the ref it was measured from, absent when the
/// repository offered none — then the count is uncommitted work alone.
/// `partial` marks a count that stopped short of every untracked file, which
/// the chip says out loud rather than under-reporting quietly.
priv struct DiffStat {
  added : Int
  removed : Int
  files : Int
  base : String?
  partial : Bool
} derive(Eq, Debug)

///|
/// Where a conversation's pull-request lookup stands. `branch` is what the
/// answer describes — the branch the host reported looking up, not the one
/// this client asked about — so a checkout that moved makes it stale without
/// needing a separate signal. `probing` stays separate from the answer on
/// purpose: a refresh for the same branch leaves the last answer on screen
/// instead of blanking the chip for the second GitHub takes to reply.
/// `stale` records a refresh that arrived while a lookup was in flight, whose
/// answer therefore predates it; that lookup is followed by another rather
/// than left standing as the last word.
///
/// Which request a probe describes is *not* here — it is the conversation's
/// `pull_request_id`, which outlives this display state and is replaced by a
/// fresh UUID whenever an in-flight lookup must be retired.
priv struct PullRequestProbe {
  branch : String
  probing : Bool
  stale : Bool
  pull_request : PullRequest?
  compare_url : String?
} derive(Eq, Debug)

///|
/// One pull request as GitHub reports it. `additions`/`deletions` are
/// GitHub's own totals against the pull request's base, which is a different
/// question from the locally measured `DiffStat` — and the reason only one of
/// the two is ever on screen at a time.
priv struct PullRequest {
  number : Int
  title : String
  state : PullRequestState
  draft : Bool
  url : String
  // The branch this merges into. Not rendered: it goes back to the host as the
  // diffstat's baseline, which is the only exact answer to "how big is this
  // branch" — and the only one that survives a stacked pull request, whose
  // base is another feature branch no local rule would ever name.
  base : String
  additions : Int
  deletions : Int
  changed_files : Int
  checks : Checks?
} derive(Eq, Debug)

///|
/// A draft is not a fourth state: it is an open pull request that refuses to
/// merge, and the chip says so separately.
priv enum PullRequestState {
  PullRequestOpen
  PullRequestMerged
  PullRequestClosed
} derive(Eq, Debug)

///|
/// The head commit's checks, bucketed into what a chip can show at a glance.
priv struct Checks {
  passed : Int
  failed : Int
  pending : Int
} derive(Eq, Debug)

///|
fn DiffStat::from_reply(reply : @protocol.GitDiffStat) -> DiffStat {
  {
    added: reply.added,
    removed: reply.removed,
    files: reply.files,
    base: reply.base,
    partial: reply.partial,
  }
}

///|
/// Decode one pull request. An unrecognized state is a host speaking a
/// vocabulary this build does not know, which is worth showing nothing for
/// rather than a chip that misreports whether the work has landed.
fn PullRequest::from_reply(reply : @protocol.GitPullRequest) -> PullRequest? {
  let state = match reply.state {
    "open" => PullRequestOpen
    "merged" => PullRequestMerged
    "closed" => PullRequestClosed
    _ => return None
  }
  Some({
    number: reply.number,
    title: reply.title,
    state,
    draft: reply.draft,
    url: reply.url,
    base: reply.base,
    additions: reply.additions,
    deletions: reply.deletions,
    changed_files: reply.changed_files,
    checks: reply.checks.map(checks => {
      passed: checks.passed,
      failed: checks.failed,
      pending: checks.pending,
    }),
  })
}

///|
fn Checks::composer_checks(self : Checks) -> @composer.GitChecks {
  @composer.GitChecks(
    passed=self.passed,
    failed=self.failed,
    pending=self.pending,
  )
}

///|
fn PullRequest::composer_pull_request(
  self : PullRequest,
) -> @composer.GitPullRequest {
  @composer.GitPullRequest(
    number=self.number,
    title=self.title,
    state=match self.state {
      PullRequestOpen => "open"
      PullRequestMerged => "merged"
      PullRequestClosed => "closed"
    },
    draft=self.draft,
    url=self.url,
    checks?=self.checks.map(checks => checks.composer_checks()),
  )
}

///|
fn DiffStat::composer_changes(self : DiffStat) -> @composer.GitChanges {
  @composer.GitChanges(
    added=self.added,
    removed=self.removed,
    files=self.files,
    partial=self.partial,
    base?=self.base,
  )
}

///|
fn Conversation::git_presentation(
  self : Conversation,
) -> @composer.GitPresentation? {
  guard self.shows_git_chip() && self.branch is Some(branch) else {
    return None
  }
  let probe = self.settled_probe()
  Some(
    @composer.GitPresentation(
      branch~,
      changes?=self.diffstat.map(stat => stat.composer_changes()),
      pull_request?=probe.bind(current => {
        current.pull_request.map(pull_request => {
          pull_request.composer_pull_request()
        })
      }),
      compare_url?=probe.bind(current => current.compare_url),
    ),
  )
}

///|
/// Whether the composer has a git chip for this conversation at all — it needs
/// a branch, and `Some("")` is how the host says the workspace is not a
/// repository. `update` fences the popover on this too: an open popover with
/// no chip to close it is unreachable.
fn Conversation::shows_git_chip(self : Conversation) -> Bool {
  self.branch is Some(branch) && !branch.is_empty()
}

///|
/// The pull request for the branch this conversation has checked out, if the
/// last answer still describes that branch. An answer about a branch the
/// workspace has left is not shown against the branch now checked out, even
/// for the moment before the refresh lands.
fn Conversation::settled_probe(self : Conversation) -> PullRequestProbe? {
  guard self.branch is Some(branch) &&
    self.pull_request is Some(probe) &&
    probe.branch == branch else {
    return None
  }
  Some(probe)
}

///|
fn fetch_branch(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  cwd : @common.Uri?,
  request_id~ : String,
  base_hint? : String,
) -> @cmd.Cmd {
  match cwd {
    Some(resource) if !@resource.belongs_to(resource, channel) =>
      return @cmd.none
    _ => ()
  }
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(channel, @commands.git_branch, {
        session,
        cwd: cwd.map(resource => resource.path),
        base_hint,
      }) catch {
        _ => {
          scheduler.add(
            dispatch(
              BranchLoaded(branch=None, diffstat=None, request_id~, base_hint~),
            ),
          )
          return
        }
      }
      scheduler.add(
        dispatch(
          BranchLoaded(
            branch=reply.branch,
            diffstat=reply.diffstat.map(DiffStat::from_reply),
            request_id~,
            base_hint~,
          ),
        ),
      )
    })
  })
}

///|
/// Issue a branch probe, stamped with a fresh UUID so an earlier one
/// still counting untracked files cannot land on top of this answer. Two are
/// ordinarily in flight — a run's start and its finish, or either of those and
/// the popover being opened — and the untracked pass is what makes the older
/// one slow.
fn probe_branch(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  channel : @interop.ChannelId,
  session : String,
  cwd : @common.Uri?,
) -> (@cmd.Cmd, Model) {
  guard model.find_conversation(channel, session) is Some(conv) else {
    return (@cmd.none, model)
  }
  let request_id = @uuid.mint()
  // The branch's pull request, once one has answered, is the only exact word
  // on what this work is measured from. The first probe has none and the host
  // guesses; every one after it does not have to.
  let base_hint = conv
    .settled_probe()
    .bind(probe => probe.pull_request)
    .map(pull_request => pull_request.base)
  (
    fetch_branch(dispatch, channel, session, cwd, request_id~, base_hint?),
    model.replace_conversation({ ..conv, branch_request_id: Some(request_id) }),
  )
}

///|
test "a settled pull request supplies the baseline the next probe measures from" {
  // Where the branch's work starts is not recorded anywhere in Git — and for a
  // stacked pull request, whose base is another feature branch, no local rule
  // could name it. The pull request is the only exact answer, so it is what
  // later probes carry back to the host.
  let conv = empty_conversation(
    @interop.ChannelId::Local,
    "s",
    @interop.ChannelId::Local.test_project(),
  )
  fn hint_of(conv : Conversation) {
    conv.settled_probe().bind(probe => probe.pull_request).map(pr => pr.base)
  }

  // Nothing answered yet: the host is left to guess at `origin/HEAD`.
  assert_eq(hint_of(conv), None)
  let stacked : PullRequest = {
    number: 717,
    title: "Dismiss menus with a listener",
    state: PullRequestOpen,
    draft: false,
    url: "https://github.test/acme/app/pull/717",
    base: "feature/x",
    additions: 1,
    deletions: 0,
    changed_files: 1,
    checks: None,
  }
  let answered = {
    ..conv,
    branch: Some("feature/y"),
    pull_request: Some({
      branch: "feature/y",
      probing: false,
      stale: false,
      pull_request: Some(stacked),
      compare_url: None,
    }),
  }
  assert_eq(hint_of(answered), Some("feature/x"))
  // An answer describing a branch the checkout has left is not one to measure
  // from either — `settled_probe` withholds it, as it does from the chip.
  assert_eq(hint_of({ ..answered, branch: Some("feature/z"), }), None)
}

///|
test "the chip's tint follows CI, and its label follows the pull request" {
  // Failures outrank running work, which outranks a clean sweep: the chip has
  // one color and it should be the one worth acting on.
  assert_eq(
    Checks::{ passed: 4, failed: 2, pending: 1, }.composer_checks().tone(),
    "failed",
  )
  assert_eq(
    Checks::{ passed: 4, failed: 0, pending: 1, }.composer_checks().tone(),
    "pending",
  )
  assert_eq(
    Checks::{ passed: 4, failed: 0, pending: 0, }.composer_checks().tone(),
    "passed",
  )
  // No checks and no pull request are both "nothing to say", not "passed".
  assert_eq(@composer.GitPresentation(branch="feature").tone(), "none")
  assert_eq(
    Checks::{ passed: 4, failed: 2, pending: 1, }.composer_checks().summary(),
    "2 failed · 1 running · 4 passed",
  )
  assert_eq(
    Checks::{ passed: 0, failed: 0, pending: 0, }.composer_checks().summary(),
    "no checks",
  )
  let open : PullRequest = {
    number: 697,
    title: "Add a changed-files explorer",
    state: PullRequestOpen,
    draft: false,
    url: "https://github.test/acme/app/pull/697",
    base: "main",
    additions: 447,
    deletions: 397,
    changed_files: 18,
    checks: None,
  }
  // A plainly open pull request spends no width on the word; only the states
  // that need one carry it.
  assert_eq(open.composer_pull_request().label(), "#697")
  assert_eq(
    { ..open, draft: true, }.composer_pull_request().label(),
    "#697 Draft",
  )
  assert_eq(
    { ..open, state: PullRequestMerged, }.composer_pull_request().label(),
    "#697 Merged",
  )
  assert_eq(
    { ..open, state: PullRequestClosed, }.composer_pull_request().label(),
    "#697 Closed",
  )
}

///|
/// Start a pull-request lookup for `branch`, stamped with a fresh UUID.
/// The answer already on screen is carried when it describes that branch, so
/// the chip does not blank while the lookup runs; one about any other branch
/// is dropped rather than relabelled, which is the mislabelling the reply's
/// own branch exists to prevent.
///
/// Both callers — a branch answer, and the retry a stale probe queues — go
/// through here. They drifted apart once, and the drift was that bug.
fn probe_pull_request(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  channel : @interop.ChannelId,
  conv : Conversation,
  branch : String,
) -> (@cmd.Cmd, Model) {
  let request_id = @uuid.mint()
  let fresh : PullRequestProbe = {
    branch,
    probing: true,
    stale: false,
    pull_request: None,
    compare_url: None,
  }
  let probe = match conv.pull_request {
    Some(previous) if previous.branch == branch =>
      { ..previous, probing: true, stale: false, }
    _ => fresh
  }
  (
    fetch_pull_request(
      dispatch,
      channel,
      conv.session_id,
      branch,
      model.conversation_root(conv),
      request_id~,
    ),
    model.replace_conversation({
      ..conv,
      pull_request: Some(probe),
      pull_request_id: Some(request_id),
    }),
  )
}

///|
/// Drop what GitHub said about this conversation's branch and clear the
/// accepted request UUID. Any reply already in flight carries a different,
/// retired UUID and cannot match a later lookup.
fn Conversation::forget_pull_request(self : Conversation) -> Conversation {
  { ..self, pull_request: None, pull_request_id: None }
}

///|
/// Forget the whole git side of a conversation — the branch, its diffstat, and
/// its pull request — fencing off every probe still in flight for it. For a
/// checkout that has gone away, where anything still arriving describes a
/// directory that no longer exists.
fn Conversation::forget_git(self : Conversation) -> Conversation {
  {
    ..self.forget_pull_request(),
    branch: None,
    diffstat: None,
    diffstat_hint: None,
    branch_request_id: None,
  }
}

///|
/// Look up `branch`'s pull request. The branch travels with the request so the
/// reply can be matched against the checkout it described: a run that switches
/// branches mid-flight must not have an old answer land on the new branch.
fn fetch_pull_request(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  branch : String,
  cwd : @common.Uri?,
  request_id~ : String,
) -> @cmd.Cmd {
  match cwd {
    Some(resource) if !@resource.belongs_to(resource, channel) =>
      return @cmd.none
    _ => ()
  }
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let empty = PullRequestLoaded(
        branch~,
        request_id~,
        queried=None,
        pull_request=None,
        compare_url=None,
      )
      let reply = @interop.bridge_request(channel, @commands.git_pull_request, {
        session,
        cwd: cwd.map(resource => resource.path),
        branch_hint: None,
      }) catch {
        _ => {
          scheduler.add(dispatch(empty))
          return
        }
      }
      scheduler.add(
        dispatch(
          PullRequestLoaded(
            branch~,
            request_id~,
            queried=reply.branch,
            pull_request=reply.pull_request.bind(PullRequest::from_reply),
            compare_url=reply.compare_url,
          ),
        ),
      )
    })
  })
}
