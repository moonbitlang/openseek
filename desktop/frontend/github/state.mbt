///|
pub(all) struct Owner {
  channel : @interop.ChannelId
  cwd : String
} derive(Eq)

///|
pub(all) struct Group {
  expanded : Bool
  reply : @protocol.GithubListReply?
  loading : Bool
  error : String?
} derive(Eq)

///|
fn Group::empty(expanded : Bool) -> Group {
  { expanded, reply: None, loading: false, error: None, }
}

///|
pub(all) struct Detail {
  repository_url : String
  item : @protocol.GithubItem
  reply : @protocol.GithubPullRequestDetail?
  loading : Bool
  error : String?
} derive(Eq)

///|
pub(all) struct State {
  owner : Owner?
  active : Bool
  epoch : Int
  pulls_expanded : Bool
  created : Group
  all_open : Group
  issues : Group
  detail : Detail?
  detail_epoch : Int
} derive(Eq)

///|
pub fn State::empty() -> State {
  {
    owner: None,
    active: false,
    epoch: 0,
    pulls_expanded: true,
    created: Group::empty(false),
    all_open: Group::empty(true),
    issues: Group::empty(true),
    detail: None,
    detail_epoch: 0,
  }
}

///|
pub(all) enum Msg {
  TogglePulls
  Toggle(@protocol.GithubListKind)
  Refresh
  Retry(@protocol.GithubListKind)
  More(@protocol.GithubListKind)
  Select(String, @protocol.GithubItem)
  RefreshDetail
  CloseDetail
  DetailLoaded(Int, Result[@protocol.GithubPullRequestDetail, String])
  Listed(
    Int,
    @protocol.GithubListKind,
    Result[@protocol.GithubListReply, String]
  )
}

///|
fn State::group(self : State, kind : @protocol.GithubListKind) -> Group {
  match kind {
    CreatedByMe => self.created
    AllOpen => self.all_open
    Issues => self.issues
  }
}

///|
fn State::with_group(
  self : State,
  kind : @protocol.GithubListKind,
  group : Group,
) -> State {
  match kind {
    CreatedByMe => { ..self, created: group, }
    AllOpen => { ..self, all_open: group, }
    Issues => { ..self, issues: group, }
  }
}

///|
fn request(
  emit : @cmd.Emit[Msg],
  state : State,
  kind : @protocol.GithubListKind,
  limit : Int,
) -> (@cmd.Cmd, State) {
  let group = state.group(kind)
  guard state.active && !group.loading && state.owner is Some(owner) else {
    return (@cmd.none, state)
  }
  let command = @cmd.attempt(
    result => {
      emit(
        Listed(state.epoch, kind, result.map_err(@interop.bridge_error_text)),
      )
    },
    () => {
      @interop.bridge_request(owner.channel, @commands.github_list, {
        cwd: owner.cwd,
        kind,
        limit,
      })
    },
  )
  (command, state.with_group(kind, { ..group, loading: true, error: None, }))
}

///|
fn request_visible(emit : @cmd.Emit[Msg], state : State) -> (@cmd.Cmd, State) {
  let mut state = state
  let commands : Array[@cmd.Cmd] = []
  for kind in [@protocol.CreatedByMe, @protocol.AllOpen, @protocol.Issues] {
    let group = state.group(kind)
    if group.expanded &&
      (kind is Issues || state.pulls_expanded) &&
      group.reply is None &&
      group.error is None {
      let (command, next) = request(emit, state, kind, 30)
      commands.push(command)
      state = next
    }
  }
  (@cmd.batch(commands), state)
}

///|
/// Scope and activation changes invalidate in-flight responses. No background
/// polling: reopening or Refresh fetches the currently expanded lists.
pub fn reconcile(
  emit : @cmd.Emit[Msg],
  state : State,
  owner : Owner?,
  active : Bool,
) -> (@cmd.Cmd, State) {
  if state.owner != owner {
    return request_visible(emit, {
      ..State::empty(),
      owner,
      active,
      epoch: state.epoch + 1,
      detail_epoch: state.detail_epoch + 1,
    })
  }
  if state.active != active {
    let state = { ..state, active, }
    return update(emit, Refresh, state)
  }
  (@cmd.none, state)
}

///|
pub fn update(
  emit : @cmd.Emit[Msg],
  msg : Msg,
  state : State,
) -> (@cmd.Cmd, State) {
  match msg {
    TogglePulls =>
      request_visible(emit, { ..state, pulls_expanded: !state.pulls_expanded, })
    Toggle(kind) => {
      let group = state.group(kind)
      request_visible(
        emit,
        state.with_group(kind, { ..group, expanded: !group.expanded, }),
      )
    }
    Refresh =>
      refresh(emit, {
        ..state,
        epoch: state.epoch + 1,
        created: Group::empty(state.created.expanded),
        all_open: Group::empty(state.all_open.expanded),
        issues: Group::empty(state.issues.expanded),
      })
    Select(repository_url, item) => {
      guard state.active else { return (@cmd.none, state) }
      request_detail(emit, {
        ..state,
        detail: Some({
          repository_url,
          item,
          reply: None,
          loading: false,
          error: None,
        }),
      })
    }
    RefreshDetail => request_detail(emit, state)
    CloseDetail =>
      (
        @cmd.none,
        { ..state, detail: None, detail_epoch: state.detail_epoch + 1, },
      )
    DetailLoaded(epoch, result) => {
      guard epoch == state.detail_epoch &&
        state.detail is Some(detail) &&
        detail.loading else {
        return (@cmd.none, state)
      }
      let detail = match result {
        Ok(reply) =>
          { ..detail, reply: Some(reply), loading: false, error: None, }
        Err(error) => { ..detail, loading: false, error: Some(error), }
      }
      (@cmd.none, { ..state, detail: Some(detail), })
    }
    Retry(kind) =>
      request(
        emit,
        state,
        kind,
        state.group(kind).reply
        .map(reply => reply.items.length().max(30))
        .unwrap_or(30),
      )
    More(kind) => {
      guard state.group(kind).reply is Some(reply) &&
        reply.has_more &&
        reply.items.length() < 1000 else {
        return (@cmd.none, state)
      }
      // gh handles its API pagination. Replace the growing prefix atomically
      // so insertions/closures between clicks cannot duplicate old rows.
      request(emit, state, kind, (reply.items.length() + 30).min(1000))
    }
    Listed(epoch, kind, result) => {
      guard epoch == state.epoch && state.group(kind).loading else {
        return (@cmd.none, state)
      }
      let group = state.group(kind)
      let group = match result {
        Ok(reply) =>
          { ..group, loading: false, reply: Some(reply), error: None, }
        Err(error) => { ..group, loading: false, error: Some(error), }
      }
      (@cmd.none, state.with_group(kind, group))
    }
  }
}

///|
fn request_detail(emit : @cmd.Emit[Msg], state : State) -> (@cmd.Cmd, State) {
  guard state.active &&
    state.owner is Some(owner) &&
    state.detail is Some(detail) else {
    return (@cmd.none, state)
  }
  let epoch = state.detail_epoch + 1
  let command = @cmd.attempt(
    result => {
      emit(DetailLoaded(epoch, result.map_err(@interop.bridge_error_text)))
    },
    () => {
      @interop.bridge_request(owner.channel, @commands.github_pull_request, {
        cwd: owner.cwd,
        repository_url: detail.repository_url,
        number: detail.item.number,
      })
    },
  )
  (
    command,
    {
      ..state,
      detail_epoch: epoch,
      detail: Some({ ..detail, loading: true, error: None, }),
    },
  )
}

///|
/// Keep the last loaded description readable during refresh or a temporary
/// disconnection. A separate generation fences selection, close and host changes
/// without invalidating the inventory's independent requests.
fn refresh(emit : @cmd.Emit[Msg], state : State) -> (@cmd.Cmd, State) {
  let (lists, state) = request_visible(emit, state)
  if !state.active {
    return (
      lists,
      {
        ..state,
        detail_epoch: state.detail_epoch + 1,
        detail: state.detail.map(detail => { ..detail, loading: false, }),
      },
    )
  }
  let (details, state) = request_detail(emit, state)
  (@cmd.batch([lists, details]), state)
}

///|
pub extend Owner with Eq::{equal, not_equal}

///|
pub extend Group with Eq::{equal, not_equal}

///|
pub extend State with Eq::{equal, not_equal}

///|
pub extend Detail with Eq::{equal, not_equal}
