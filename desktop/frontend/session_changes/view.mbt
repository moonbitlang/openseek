///|
/// Where a pull request stands. A draft is an open pull request that is not
/// ready to merge; the card colors it apart from one that is.
pub(all) enum PullRequestState {
  Open
  Draft
  Merged
  Closed
} derive(Eq, Debug)

///|
pub extend PullRequestState with Eq::{equal, not_equal}

///|
pub extend PullRequestState with Debug::{to_repr}

///|
/// The head commit's checks, bucketed by how they ended.
pub(all) struct Checks {
  passed : Int32
  failed : Int32
  pending : Int32
} derive(Eq, Debug)

///|
pub extend Checks with Eq::{equal, not_equal}

///|
pub extend Checks with Debug::{to_repr}

///|
/// A pull request, as GitHub reported it. `additions` and `deletions` are
/// GitHub's totals against its base; `checks` is absent when GitHub reported
/// none.
pub(all) struct PullRequest {
  number : Int32
  title : String
  state : PullRequestState
  url : String
  additions : Int32
  deletions : Int32
  checks : Checks?
} derive(Eq, Debug)

///|
pub extend PullRequest with Eq::{equal, not_equal}

///|
pub extend PullRequest with Debug::{to_repr}

///|
/// The branch's line delta, measured locally. `partial` marks a count that
/// stopped short of every untracked file, so it is a floor, not a total.
pub(all) struct Diff {
  added : Int32
  removed : Int32
  files : Int32
  partial : Bool
} derive(Eq, Debug)

///|
pub extend Diff with Eq::{equal, not_equal}

///|
pub extend Diff with Debug::{to_repr}

///|
/// The checkout the conversation works in, as the root knows it: always its
/// first row, and never removable — it follows the checkout rather than a
/// saved list.
pub(all) struct Checkout {
  branch : String
  /// The branch's pull request; while there is none, the row is the branch
  /// and its local diff.
  pull_request : PullRequest?
  diff : Diff?
  /// Where GitHub would open a pull request for the branch, while it has
  /// none.
  compare_url : String?
} derive(Eq, Debug)

///|
pub extend Checkout with Eq::{equal, not_equal}

///|
pub extend Checkout with Debug::{to_repr}

///|
/// How many rows the unfolded card shows before it offers the rest.
const VisibleRows : Int32 = 5

///|
/// Menu targets of the card's rows: the checkout's, and an attached item's by
/// its address.
const MenuTarget : String = "conv-changes"

///|
fn checkout_target() -> String {
  MenuTarget + ":checkout"
}

///|
fn attached_target(url : String) -> String {
  MenuTarget + ":attached:" + url
}

///|
/// The attached items worth a row: what the host last listed, without the
/// pull request the checkout row already shows.
fn attached(
  conversation : @interop.ConversationKey,
  checkout : Checkout?,
  state : State,
) -> Array[@protocol.SessionArtifact] {
  let artifacts = match state.phase_for(conversation) {
    Loaded(artifacts) | Reloading(artifacts) => artifacts
    Unchecked | Checking | CheckFailed(_) => []
  }
  let current = checkout.bind(checkout => checkout.pull_request)
  artifacts.filter(artifact => {
    !(artifact.type_ is PullRequest &&
    current is Some(pull_request) &&
    pull_request.url == artifact.url)
  })
}

///|
/// The one line the overview shows for the changes card while it is folded,
/// or `None` when there is nothing to show and the card stays away: no
/// checkout to describe and nothing attached.
pub fn summary(
  locale~ : @i18n.Locale = English,
  conversation : @interop.ConversationKey,
  checkout : Checkout?,
  state : State,
) -> String? {
  let attached = attached(conversation, checkout, state)
  let mut pull_requests = attached
    .filter(artifact => artifact.type_ is PullRequest)
    .length()
  let mut branches = attached.length() - pull_requests
  match checkout {
    Some({ pull_request: Some(_), .. }) => pull_requests += 1
    Some({ pull_request: None, .. }) => branches += 1
    None => ()
  }
  let parts : Array[String] = []
  if pull_requests > 0 {
    parts.push(text(locale, PullRequestCount(pull_requests)))
  }
  if branches > 0 {
    parts.push(text(locale, BranchCount(branches)))
  }
  if parts.is_empty() {
    return if state.phase_for(conversation) is CheckFailed(_) {
      Some(text(locale, CheckFailed))
    } else {
      None
    }
  }
  Some(parts.join(" · "))
}

///|
/// The rows the overview shows for the changes card when it is unfolded: the
/// checkout first, then what the agent attached, in the order it attached
/// them. Each pull request or branch with a page opens it, and its menu is
/// `menu`'s. Past a handful of rows the rest wait behind "Show more".
pub fn rows(
  locale~ : @i18n.Locale = English,
  conversation : @interop.ConversationKey,
  checkout : Checkout?,
  state : State,
  emit : @cmd.Emit[Msg],
) -> Array[@html.Html] {
  let items : Array[@html.Html] = []
  if checkout is Some(checkout) {
    items.push(checkout_row(locale, checkout))
  }
  for artifact in attached(conversation, checkout, state) {
    items.push(attached_row(locale, artifact, state.summary_of(artifact)))
  }
  let expanded = state.conversation == Some(conversation) && state.expanded
  let hidden = items.length() - VisibleRows
  let rows = if hidden > 0 && !expanded {
    let rows = items[:VisibleRows].to_owned()
    rows.push(more_button(text(locale, ShowMore(hidden)), emit(ShowAll(true))))
    rows
  } else if hidden > 0 {
    items.push(more_button(text(locale, ShowLess), emit(ShowAll(false))))
    items
  } else {
    items
  }
  if state.phase_for(conversation) is CheckFailed(error) {
    rows.push(failure(text(locale, CheckFailed), error))
  }
  if state.conversation == Some(conversation) &&
    state.remove_error is Some(error) {
    rows.push(failure(text(locale, RemoveFailed), error))
  }
  rows
}

///|
/// The menu of the row behind `target`, or `None` once that row is gone. The
/// checkout's row can be opened and its address copied; an attached item can
/// also be taken off the conversation's list.
pub fn menu(
  locale~ : @i18n.Locale = English,
  conversation : @interop.ConversationKey,
  checkout : Checkout?,
  state : State,
  emit : @cmd.Emit[Msg],
  open_link~ : (String) -> @cmd.Cmd,
  target : String,
) -> @action_menu.Definition? {
  if target == checkout_target() {
    guard checkout.bind(checkout => checkout.pull_request) is Some(pull_request) else {
      return None
    }
    return Some({
      label: text(locale, MoreActions),
      entries: link_entries(locale, pull_request.url, open_link~),
    })
  }
  let found = attached(conversation, checkout, state).filter(artifact => {
    attached_target(artifact.url) == target
  })
  guard found is [artifact, ..] else { return None }
  let entries = link_entries(locale, artifact.url, open_link~)
  entries.push(Separator)
  entries.push(
    Action({
      label: text(locale, Remove),
      title: text(locale, Remove),
      icon: Some(@icons.icon(@icons.icon_close)),
      enabled: !state.removing.contains(artifact),
      destructive: true,
      command: emit(Remove(conversation, artifact)),
    }),
  )
  Some({ label: text(locale, MoreActions), entries, })
}

///|
fn link_entries(
  locale : @i18n.Locale,
  url : String,
  open_link~ : (String) -> @cmd.Cmd,
) -> Array[@action_menu.Entry] {
  [
    Action({
      label: text(locale, OpenOnGitHub),
      title: url,
      icon: Some(@icons.icon(@icons.icon_link_external)),
      enabled: true,
      destructive: false,
      command: open_link(url),
    }),
    Action({
      label: text(locale, CopyLink),
      title: url,
      icon: Some(@icons.icon_copy()),
      enabled: true,
      destructive: false,
      command: @clipboard.copy(Text(url)),
    }),
  ]
}

///|
fn checkout_row(locale : @i18n.Locale, checkout : Checkout) -> @html.Html {
  let current = @html.span(class="conv-overview-tag", text(locale, Current))
  match checkout.pull_request {
    Some(pull_request) =>
      pull_request_row(
        locale,
        pull_request,
        url=pull_request.url,
        target=checkout_target(),
        extra=[current],
      )
    None => {
      let aside : Array[@html.Html] = [current]
      if checkout.compare_url is Some(href) {
        aside.push(
          @html.a(
            class="conv-changes-create",
            href~,
            target=Blank,
            rel="noopener noreferrer",
            title=href,
            text(locale, CreatePullRequest),
          ),
        )
      }
      item(
        tone="",
        image=@icons.icon_git_branch,
        href=None,
        title=checkout.branch,
        [@html.span(class="conv-changes-name branch", checkout.branch)],
        meta=checkout.diff.map(diff => diff_counts(locale, diff)).unwrap_or([]),
        aside~,
        menu=None,
      )
    }
  }
}

///|
/// An attached item. The host keeps only its kind and address, so a pull
/// request reads as its repository and number, and a branch as its name, until
/// GitHub has summarized the pull request.
fn attached_row(
  locale : @i18n.Locale,
  artifact : @protocol.SessionArtifact,
  pull_request : PullRequest?,
) -> @html.Html {
  let target = attached_target(artifact.url)
  if pull_request is Some(pull_request) {
    return pull_request_row(locale, pull_request, url=artifact.url, target~, extra=[])
  }
  let place = match artifact.url.strip_prefix("https://") {
    Some(rest) => rest.to_owned()
    None => artifact.url
  }
  let parts = place.split("/").map(part => part.to_owned()).collect()
  let (image, label, meta) : (
    () -> @html.Html,
    Array[@html.Html],
    Array[@html.Html],
  ) = match (artifact.type_, parts) {
    (PullRequest, [_, owner, repo, "pull", number, ..]) =>
      (
        @icons.icon_git_pull_request,
        [@html.span(class="conv-changes-name", "\{owner}/\{repo}")],
        [@html.span("#\{number}")],
      )
    (PullRequest, _) =>
      (
        @icons.icon_git_pull_request,
        [@html.span(class="conv-changes-name", place)],
        [],
      )
    (Branch, [_, owner, repo, "tree", .. branch]) if !branch.is_empty() =>
      (
        @icons.icon_git_branch,
        [@html.span(class="conv-changes-name branch", branch.join("/"))],
        [@html.span("\{owner}/\{repo}")],
      )
    (Branch, _) =>
      (
        @icons.icon_git_branch,
        [@html.span(class="conv-changes-name", place)],
        [],
      )
  }
  item(
    tone="",
    image~,
    href=Some(artifact.url),
    title=artifact.url,
    label,
    meta~,
    aside=[],
    menu=Some((locale, target)),
  )
}

///|
/// A pull request GitHub described: its title, then its repository and
/// number with GitHub's line totals, and its checks at the end.
fn pull_request_row(
  locale : @i18n.Locale,
  pull_request : PullRequest,
  url~ : String,
  target~ : String,
  extra~ : Array[@html.Html],
) -> @html.Html {
  let (tone, image, state) = pull_request.state.look(locale)
  // The repository gives way before the number does.
  let meta = match repository_name(url) {
    Some(repo) => [@html.span(repo)]
    None => []
  }
  meta.append([
    @html.span(class="number", "#\{pull_request.number}"),
    @html.span(class="added", "+\{pull_request.additions}"),
    @html.span(class="removed", "−\{pull_request.deletions}"),
  ])
  let aside : Array[@html.Html] = []
  if pull_request.checks is Some(checks) {
    aside.push(checks_badge(locale, checks, url))
  }
  aside.append(extra)
  item(
    tone~,
    image~,
    href=Some(url),
    title="#\{pull_request.number} \{pull_request.title}\n\{state}\n\{url}",
    [@html.span(class="conv-changes-name", pull_request.title)],
    meta~,
    aside~,
    menu=Some((locale, target)),
  )
}

///|
/// The repository a GitHub address names, without its owner.
fn repository_name(url : String) -> String? {
  guard url.split("/").map(part => part.to_owned()).collect()
    is ["https:", "", _, _, repo, ..] &&
    !repo.is_empty() else {
    return None
  }
  Some(repo)
}

///|
fn diff_counts(locale : @i18n.Locale, diff : Diff) -> Array[@html.Html] {
  let counts : Array[@html.Html] = []
  if diff.files > 0 {
    counts.push(@html.span(class="added", "+\{diff.added}"))
    counts.push(@html.span(class="removed", "−\{diff.removed}"))
  }
  if diff.partial {
    counts.push(
      @html.span(class="partial", title=text(locale, PartialCount), "…"),
    )
  }
  counts
}

///|
/// The head commit's checks at a glance, opening GitHub's checks page: how
/// many failed when any did, how many of all passed while some still run, and
/// a quiet mark once every one passed.
fn checks_badge(
  locale : @i18n.Locale,
  checks : Checks,
  url : String,
) -> @html.Html {
  let total = checks.passed + checks.failed + checks.pending
  let parts : Array[String] = []
  if checks.failed > 0 {
    parts.push(text(locale, ChecksFailedCount(checks.failed)))
  }
  if checks.pending > 0 {
    parts.push(text(locale, ChecksPendingCount(checks.pending)))
  }
  if checks.passed > 0 {
    parts.push(text(locale, ChecksPassedCount(checks.passed)))
  }
  let (tone, content) : (String, Array[@html.Html]) = if checks.failed > 0 {
    ("failed", [@html.text(text(locale, ChecksFailing(checks.failed)))])
  } else if checks.pending > 0 {
    (
      "pending",
      [
        @html.span(class="conv-changes-dot", ""),
        @html.text("\{checks.passed}/\{total}"),
      ],
    )
  } else {
    ("passed", [@html.span(class="conv-changes-dot", "")])
  }
  @html.a(
    class="conv-changes-checks \{tone}",
    href="\{url}/checks",
    target=Blank,
    rel="noopener noreferrer",
    title="CI · " + parts.join(" · "),
    attrs=@html.Attrs::build().aria_label("CI · " + parts.join(" · ")),
    content,
  )
}

///|
/// How a pull request in `self` state looks: its icon's tone, the icon, and
/// the state's name.
fn PullRequestState::look(
  self : PullRequestState,
  locale : @i18n.Locale,
) -> (String, () -> @html.Html, String) {
  match self {
    Open => ("open", @icons.icon_git_pull_request, text(locale, StateOpen))
    Draft =>
      ("draft", @icons.icon_git_pull_request_draft, text(locale, StateDraft))
    Merged => ("merged", @icons.icon_git_merge, text(locale, StateMerged))
    Closed =>
      ("closed", @icons.icon_git_pull_request_closed, text(locale, StateClosed))
  }
}

///|
/// One row: the item's icon tinted by its state, then its name with its menu
/// over its details with its checks or tags. With a page, the name is a link
/// that covers the whole row; the menu and the links at the end stay above
/// it. `menu` names the row's menu target, for a row that has one.
fn item(
  tone~ : String,
  image~ : () -> @html.Html,
  href~ : String?,
  title~ : String,
  label : Array[@html.Html],
  meta~ : Array[@html.Html],
  aside~ : Array[@html.Html],
  menu~ : (@i18n.Locale, String)?,
) -> @html.Html {
  let heading : Array[@html.Html] = [
    match href {
      Some(href) =>
        @html.a(
          class="conv-changes-link",
          href~,
          target=Blank,
          rel="noopener noreferrer",
          title~,
          label,
        )
      None => @html.span(class="conv-changes-link", title~, label)
    },
  ]
  if menu is Some((locale, target)) {
    let label = text(locale, MoreActions)
    heading.push(
      @html.button(
        class="conv-overview-mini conv-changes-more",
        type_="button",
        title=label,
        attrs=@action_menu.button_attrs(target).aria_label(label),
        @icons.icon(@icons.icon_more),
      ),
    )
  }
  let lines = [@html.div(class="conv-changes-title", heading)]
  if !meta.is_empty() || !aside.is_empty() {
    lines.push(
      @html.div(class="conv-changes-details", [
        @html.span(class="conv-changes-meta", meta),
        @html.span(class="conv-changes-aside", aside),
      ]),
    )
  }
  @html.div(class="conv-changes-row", [
    @html.span(class="conv-changes-icon \{tone}", @icons.icon(image)),
    @html.div(class="conv-changes-text", lines),
  ])
}

///|
fn more_button(label : String, command : @cmd.Cmd) -> @html.Html {
  @html.button(
    class="conv-changes-toggle",
    type_="button",
    on_click=command,
    label,
  )
}

///|
fn failure(message : String, error : String) -> @html.Html {
  @html.div(class="conv-changes-error", title=error, [
    @html.span(class="run-dot danger", ""),
    @html.span(class="conv-changes-text", [
      @html.span(class="conv-changes-name", message),
      @html.span(class="conv-overview-row-sub", error),
    ]),
  ])
}
