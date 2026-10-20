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
/// The checked-out branch's pull request, as GitHub reported it.
pub(all) struct PullRequest {
  number : Int32
  title : String
  state : PullRequestState
  url : String
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
} derive(Eq, Debug)

///|
pub extend Checkout with Eq::{equal, not_equal}

///|
pub extend Checkout with Debug::{to_repr}

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
/// them. Each pull request or branch with a page opens it.
pub fn rows(
  locale~ : @i18n.Locale = English,
  conversation : @interop.ConversationKey,
  checkout : Checkout?,
  state : State,
  emit : @cmd.Emit[Msg],
) -> Array[@html.Html] {
  let rows : Array[@html.Html] = []
  if checkout is Some(checkout) {
    rows.push(checkout_row(locale, checkout))
  }
  for artifact in attached(conversation, checkout, state) {
    let remove = if state.removing.contains(artifact) {
      None
    } else {
      Some(emit(Remove(conversation, artifact)))
    }
    let pull_request = if artifact.type_ is PullRequest {
      state.summary(artifact.url)
    } else {
      None
    }
    rows.push(attached_row(locale, artifact, pull_request, remove))
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
fn checkout_row(locale : @i18n.Locale, checkout : Checkout) -> @html.Html {
  let current = @html.span(class="conv-overview-tag", text(locale, Current))
  match checkout.pull_request {
    Some(pull_request) => {
      let (tone, image, state) = pull_request.state.look(locale)
      item(
        tone~,
        image~,
        href=Some(pull_request.url),
        title="#\{pull_request.number} \{pull_request.title}\n\{state}\n\{pull_request.url}",
        [
          @html.span(class="conv-changes-number", "#\{pull_request.number}"),
          @html.span(class="conv-changes-name", pull_request.title),
        ],
        aside=[current],
        remove=None,
        locale~,
      )
    }
    None => {
      let aside : Array[@html.Html] = []
      if checkout.diff is Some(diff) && (diff.files > 0 || diff.partial) {
        let counts : Array[@html.Html] = []
        if diff.files > 0 {
          counts.push(@html.span(class="added", "+\{diff.added}"))
          counts.push(@html.span(class="removed", "−\{diff.removed}"))
        }
        if diff.partial {
          counts.push(@html.span(class="partial", "…"))
        }
        aside.push(
          @html.span(
            class="conv-changes-diff",
            title?=if diff.partial {
              Some(text(locale, PartialCount))
            } else {
              None
            },
            counts,
          ),
        )
      }
      aside.push(current)
      item(
        tone="",
        image=@icons.icon_git_branch,
        href=None,
        title=checkout.branch,
        [@html.span(class="conv-changes-name branch", checkout.branch)],
        aside~,
        remove=None,
        locale~,
      )
    }
  }
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
/// An attached item. The host keeps only its kind and address, so a pull
/// request reads as its repository and number, and a branch as its name. Once
/// GitHub has summarized a pull request, `pull_request` puts its title and
/// state in place of the repository, as the checkout row shows its own.
fn attached_row(
  locale : @i18n.Locale,
  artifact : @protocol.SessionArtifact,
  pull_request : PullRequest?,
  remove : @cmd.Cmd?,
) -> @html.Html {
  if pull_request is Some(pull_request) {
    let (tone, image, state) = pull_request.state.look(locale)
    return item(
      tone~,
      image~,
      href=Some(artifact.url),
      title="#\{pull_request.number} \{pull_request.title}\n\{state}\n\{artifact.url}",
      [
        @html.span(class="conv-changes-number", "#\{pull_request.number}"),
        @html.span(class="conv-changes-name", pull_request.title),
      ],
      aside=[],
      remove=Some(remove),
      locale~,
    )
  }
  let place = match artifact.url.strip_prefix("https://") {
    Some(rest) => rest.to_owned()
    None => artifact.url
  }
  let parts = place.split("/").map(part => part.to_owned()).collect()
  let (image, label) : (() -> @html.Html, Array[@html.Html]) = match
    (artifact.type_, parts) {
    (PullRequest, [_, owner, repo, "pull", number, ..]) =>
      (
        @icons.icon_git_pull_request,
        [
          @html.span(class="conv-changes-number", "#\{number}"),
          @html.span(class="conv-changes-name", "\{owner}/\{repo}"),
        ],
      )
    (PullRequest, _) =>
      (
        @icons.icon_git_pull_request,
        [@html.span(class="conv-changes-name", place)],
      )
    (Branch, [_, owner, repo, "tree", .. branch]) if !branch.is_empty() =>
      (
        @icons.icon_git_branch,
        [
          @html.span(class="conv-changes-name branch", branch.join("/")),
          @html.span(class="conv-overview-row-sub", "\{owner}/\{repo}"),
        ],
      )
    (Branch, _) =>
      (@icons.icon_git_branch, [@html.span(class="conv-changes-name", place)])
  }
  item(
    tone="",
    image~,
    href=Some(artifact.url),
    title=artifact.url,
    label,
    aside=[],
    remove=Some(remove),
    locale~,
  )
}

///|
/// One row: the item's icon tinted by its state, its label, and what follows
/// it. With a page, the icon and label are a link to it. `remove` is `None`
/// for a row that cannot be removed, and `Some(None)` while its removal is
/// out.
fn item(
  locale~ : @i18n.Locale,
  tone~ : String,
  image~ : () -> @html.Html,
  href~ : String?,
  title~ : String,
  label : Array[@html.Html],
  aside~ : Array[@html.Html],
  remove~ : @cmd.Cmd??,
) -> @html.Html {
  let body = [
    @html.span(class="conv-changes-icon \{tone}", @icons.icon(image)),
    @html.span(class="conv-changes-text", label),
    ..aside,
  ]
  let children : Array[@html.Html] = [
    match href {
      Some(href) =>
        @html.a(
          class="conv-changes-link",
          href~,
          target=Blank,
          rel="noopener noreferrer",
          title~,
          body,
        )
      None => @html.div(class="conv-changes-link", title~, body)
    },
  ]
  if remove is Some(remove) {
    let label = text(locale, Remove)
    children.push(
      @html.button(
        class="conv-overview-mini conv-changes-remove",
        type_="button",
        title=label,
        disabled=remove is None,
        attrs=@html.Attrs::build().aria_label(label),
        on_click=remove.unwrap_or(@cmd.none),
        @icons.icon(@icons.icon_close),
      ),
    )
  }
  @html.div(class="conv-changes-row", children)
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
