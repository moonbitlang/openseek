///|
pub(all) struct CheckoutScope {
  channel : @interop.ChannelId
  cwd : String
  branch : String?
  head : String?
} derive(Eq)

///|
pub fn State::current_url(self : State) -> String? {
  match self.current {
    Some(Ok(status)) => status.pull_request_url
    _ => None
  }
}

///|
pub fn State::has_open_pr(self : State) -> Bool {
  self.current
  is Some(Ok({ has_open_pull_request: true, pull_request_url: Some(_), .. }))
}

///|
pub fn State::invalidate_current(self : State) -> State {
  {
    ..self,
    current_epoch: self.current_epoch + 1,
    current_loading: false,
    current: None,
  }
}

///|
pub extend CheckoutScope with Eq::{equal, not_equal}

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
pub(all) struct Checkout {
  repository_url : String
  number : Int
  url : String
  updating : Bool
  phase : CheckoutPhase
  show_details : Bool
} derive(Eq)

///|
pub(all) enum CheckoutPhase {
  Running
  Confirming
  Failed(String, String?)
} derive(Eq)

///|
pub(all) struct State {
  scope : CheckoutScope?
  active : Bool
  epoch : Int
  pulls_expanded : Bool
  created : Group
  all_open : Group
  issues : Group
  detail : Detail?
  detail_epoch : Int
  checkout : Checkout?
  checkout_epoch : Int
  current : Result[@protocol.GithubCheckoutStatus, String]?
  current_epoch : Int
  current_loading : Bool
  current_active : Bool
  review_pending : Bool
} derive(Eq)

///|
pub fn State::empty() -> State {
  {
    scope: None,
    active: false,
    epoch: 0,
    pulls_expanded: true,
    created: Group::empty(false),
    all_open: Group::empty(true),
    issues: Group::empty(true),
    detail: None,
    detail_epoch: 0,
    checkout: None,
    checkout_epoch: 0,
    current: None,
    current_epoch: 0,
    current_loading: false,
    current_active: false,
    review_pending: false,
  }
}

///|
pub(all) enum Msg {
  TogglePulls
  Toggle(@protocol.GithubListKind)
  Refresh
  RefreshCurrent
  Retry(@protocol.GithubListKind)
  More(@protocol.GithubListKind)
  Select(String, @protocol.GithubItem)
  RefreshDetail
  CloseDetail
  Checkout(String, @protocol.GithubItem)
  UpdatePullRequest(String)
  CheckedOut(Int, Result[@protocol.GithubCheckoutReply, String])
  ConfirmCheckout(@protocol.GithubCheckoutChanges)
  DismissCheckout
  ToggleCheckoutDetails
  CurrentLoaded(Int, Result[@protocol.GithubCheckoutStatus, String])
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
  guard state.active && !group.loading && state.scope is Some(owner) else {
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
/// Lists follow panel visibility. Current PR discovery is shared with Review,
/// so switching surfaces neither repeats the lookup nor retires its response.
pub fn reconcile(
  emit : @cmd.Emit[Msg],
  state : State,
  checkout : CheckoutScope?,
  active : Bool,
  review_active? : Bool = false,
  review_busy? : Bool = false,
) -> (@cmd.Cmd, State) {
  let owner_changed = state.scope.map(scope => (scope.channel, scope.cwd)) !=
    checkout.map(scope => (scope.channel, scope.cwd))
  let changed = state.scope != checkout
  let current_active = active || review_active
  let reopened = current_active && !state.current_active
  let next = if owner_changed {
    {
      ..State::empty(),
      epoch: state.epoch,
      detail_epoch: state.detail_epoch + 1,
      checkout_epoch: state.checkout_epoch + 1,
      current_epoch: state.current_epoch,
    }
  } else {
    state
  }
  let next = {
    ..(if changed { next.invalidate_current() } else { next }),
    scope: checkout,
    current_active,
  }
  let (panel_cmd, next) = if owner_changed || next.active != active {
    refresh(emit, { ..next, active, })
  } else {
    (@cmd.none, next)
  }
  if next.checkout_busy() || review_busy {
    // Preserve the known PR during confirmation, but retire earlier reads.
    return (
      panel_cmd,
      if next.current_loading {
        {
          ..next,
          current_epoch: next.current_epoch + 1,
          current_loading: false,
        }
      } else {
        next
      },
    )
  }
  if reopened || changed || next.current is None {
    let (lookup, next) = request_current(emit, next)
    (@cmd.batch([panel_cmd, lookup]), next)
  } else {
    (panel_cmd, next)
  }
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
    Refresh => refresh(emit, state.invalidate_current())
    RefreshCurrent => (@cmd.none, state.invalidate_current())
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
    Checkout(repository_url, item) => {
      guard state.active && !state.checkout_busy() && !state.is_current(item) else {
        return (@cmd.none, state)
      }
      request_checkout(
        emit,
        state,
        {
          repository_url,
          number: item.number,
          url: item.url,
          updating: false,
          phase: Running,
          show_details: false,
        },
        Ask,
      )
    }
    UpdatePullRequest(url) => {
      guard !state.checkout_busy() else { return (@cmd.none, state) }
      let parts = url.split("/").map(part => part.to_owned()).collect()
      guard parts is ["https:", "", host, owner, repo, "pull", number] &&
        !host.is_empty() &&
        !owner.is_empty() &&
        !repo.is_empty() else {
        return (@cmd.none, state)
      }
      let number = @string.parse_int(number) catch {
        _ => return (@cmd.none, state)
      }
      guard number > 0 else { return (@cmd.none, state) }
      request_checkout(
        emit,
        state,
        {
          repository_url: "https://\{host}/\{owner}/\{repo}",
          number,
          url,
          updating: true,
          phase: Running,
          show_details: false,
        },
        Ask,
      )
    }
    ConfirmCheckout(changes) => {
      guard state.checkout is Some(checkout) &&
        checkout.phase is Confirming &&
        !(changes is Ask) else {
        return (@cmd.none, state)
      }
      request_checkout(emit, state, checkout, changes)
    }
    DismissCheckout => {
      guard !state.checking_out() else { return (@cmd.none, state) }
      let focus = match state.checkout {
        Some(checkout) => focus_checkout_action(checkout.number)
        None => @cmd.none
      }
      (focus, { ..state, checkout: None, })
    }
    ToggleCheckoutDetails => {
      guard state.checkout is Some(checkout) else { return (@cmd.none, state) }
      (
        @cmd.none,
        {
          ..state,
          checkout: Some({ ..checkout, show_details: !checkout.show_details, }),
        },
      )
    }
    CurrentLoaded(epoch, result) => {
      guard epoch == state.current_epoch && state.current_loading else {
        return (@cmd.none, state)
      }
      (@cmd.none, { ..state, current_loading: false, current: Some(result), })
    }
    CheckedOut(epoch, result) => {
      guard epoch == state.checkout_epoch &&
        state.checkout is Some(checkout) &&
        checkout.phase is Running else {
        return (@cmd.none, state)
      }
      // Refreshing or hiding the panel must not forget an ongoing mutation.
      // Owner changes use their own generation and reject the old completion.
      let state = if result is Ok(CheckoutNeedsConfirmation) {
        state
      } else {
        state.invalidate_current()
      }
      let phase = match result {
        Ok(CheckoutSuccess(_)) =>
          return (@cmd.none, { ..state, review_pending: true, checkout: None, })
        Ok(CheckoutNeedsConfirmation) => Confirming
        Ok(CheckoutFailure(message, details)) => Failed(message, details)
        Err(error) => Failed(error, None)
      }
      let state = { ..state, checkout: Some({ ..checkout, phase, }), }
      if phase is Failed(_, _) {
        (@cmd.none, state)
      } else {
        (focus_checkout_dialog(), state)
      }
    }
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
    state.scope is Some(owner) &&
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
  let state = {
    ..state,
    epoch: state.epoch + 1,
    created: Group::empty(state.created.expanded),
    all_open: Group::empty(state.all_open.expanded),
    issues: Group::empty(state.issues.expanded),
  }
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
pub extend Group with Eq::{equal, not_equal}

///|
pub extend State with Eq::{equal, not_equal}

///|
pub extend Detail with Eq::{equal, not_equal}

///|
pub fn State::checking_out(self : State) -> Bool {
  self.checkout is Some({ phase: Running, .. })
}

///|
pub fn State::checkout_busy(self : State) -> Bool {
  self.checkout is Some({ phase: Running | Confirming, .. })
}

///|
pub fn State::is_current(self : State, item : @protocol.GithubItem) -> Bool {
  self.current_url() == Some(item.url)
}

///|
fn request_checkout(
  emit : @cmd.Emit[Msg],
  state : State,
  checkout : Checkout,
  changes : @protocol.GithubCheckoutChanges,
) -> (@cmd.Cmd, State) {
  guard state.scope is Some(owner) else { return (@cmd.none, state) }
  let epoch = state.checkout_epoch + 1
  let command = @cmd.attempt(
    result => {
      emit(CheckedOut(epoch, result.map_err(@interop.bridge_error_text)))
    },
    () => {
      @interop.bridge_request(owner.channel, @commands.github_checkout, {
        cwd: owner.cwd,
        repository_url: checkout.repository_url,
        number: checkout.number,
        changes,
        update: checkout.updating,
      })
    },
  )
  (
    command,
    {
      ..state,
      checkout_epoch: epoch,
      review_pending: false,
      checkout: Some({ ..checkout, phase: Running, show_details: false, }),
    },
  )
}

///|
fn request_current(emit : @cmd.Emit[Msg], state : State) -> (@cmd.Cmd, State) {
  guard state.current_active &&
    !state.current_loading &&
    state.scope is Some(checkout) else {
    return (@cmd.none, state)
  }
  let epoch = state.current_epoch + 1
  let command = @cmd.attempt(
    result => {
      emit(CurrentLoaded(epoch, result.map_err(@interop.bridge_error_text)))
    },
    () => {
      @interop.bridge_request(
        checkout.channel,
        @commands.github_checkout_status,
        { cwd: checkout.cwd, },
      )
    },
  )
  (command, { ..state, current_epoch: epoch, current_loading: true, })
}

///|
pub extend CheckoutPhase with Eq::{equal, not_equal}

///|
pub extend Checkout with Eq::{equal, not_equal}
