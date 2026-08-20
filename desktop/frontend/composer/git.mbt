// Shared branch and pull-request presentation. Owners translate their host or
// app-server replies into these opaque values; this package alone decides the
// chip label, CI tone, tooltip, popover rows, and external links.

///|
struct GitChecks {
  passed : Int
  failed : Int
  pending : Int
} derive(Eq)

///|
pub fn GitChecks::GitChecks(
  passed~ : Int,
  failed~ : Int,
  pending~ : Int,
) -> GitChecks {
  { passed, failed, pending }
}

///|
pub fn GitChecks::tone(self : GitChecks) -> String {
  if self.failed > 0 {
    "failed"
  } else if self.pending > 0 {
    "pending"
  } else {
    "passed"
  }
}

///|
pub fn GitChecks::summary(self : GitChecks) -> String {
  let parts : Array[String] = []
  if self.failed > 0 {
    parts.push("\{self.failed} failed")
  }
  if self.pending > 0 {
    parts.push("\{self.pending} running")
  }
  if self.passed > 0 {
    parts.push("\{self.passed} passed")
  }
  if parts.is_empty() {
    "no checks"
  } else {
    parts.join(" · ")
  }
}

///|
struct GitPullRequest {
  number : Int
  title : String
  state : String
  draft : Bool
  url : String
  checks : GitChecks?
} derive(Eq)

///|
pub fn GitPullRequest::GitPullRequest(
  number~ : Int,
  title~ : String,
  state~ : String,
  draft~ : Bool,
  url~ : String,
  checks? : GitChecks,
) -> GitPullRequest {
  { number, title, state, draft, url, checks }
}

///|
pub fn GitPullRequest::label(self : GitPullRequest) -> String {
  let suffix = match self.state {
    "open" => if self.draft { " Draft" } else { "" }
    "merged" => " Merged"
    "closed" => " Closed"
    _ => ""
  }
  "#\{self.number}\{suffix}"
}

///|
struct GitChanges {
  added : Int
  removed : Int
  files : Int
  partial : Bool
  base : String?
} derive(Eq)

///|
pub fn GitChanges::GitChanges(
  added~ : Int,
  removed~ : Int,
  files~ : Int,
  partial~ : Bool,
  base? : String,
) -> GitChanges {
  { added, removed, files, partial, base }
}

///|
fn GitChanges::file_count(self : GitChanges) -> String {
  if self.files == 1 {
    "1 file"
  } else {
    "\{self.files} files"
  }
}

///|
struct GitPresentation {
  branch : String
  changes : GitChanges?
  pull_request : GitPullRequest?
  compare_url : String?
  missing_pull_request : String?
} derive(Eq)

///|
pub fn GitPresentation::GitPresentation(
  branch~ : String,
  changes? : GitChanges,
  pull_request? : GitPullRequest,
  compare_url? : String,
  missing_pull_request? : String,
) -> GitPresentation {
  { branch, changes, pull_request, compare_url, missing_pull_request }
}

///|
pub fn GitPresentation::tone(self : GitPresentation) -> String {
  self.pull_request
  .bind(pull_request => pull_request.checks)
  .map(checks => checks.tone())
  .unwrap_or("none")
}

///|
pub fn GitPresentation::label(self : GitPresentation) -> String {
  self.pull_request
  .map(pull_request => pull_request.label())
  .unwrap_or(self.branch)
}

///|
pub fn GitPresentation::summary(self : GitPresentation) -> String {
  if self.pull_request is Some(pull_request) {
    pull_request.checks
    .map(checks => pull_request.title + " — CI " + checks.summary())
    .unwrap_or(pull_request.title)
  } else {
    "On branch \{self.branch}"
  }
}

///|
/// Render the complete Git affordance. Conditional popover content is appended
/// after the stable button so opening it never replaces the node under the
/// pointer in Rabbita's positional renderer.
pub fn GitPresentation::render(
  self : GitPresentation,
  open~ : Bool,
  toggle~ : @cmd.Cmd,
) -> @html.Html {
  let opened = if open { " open" } else { "" }
  let children : Array[@html.Html] = [
    @html.button(
      class="composer-git-button \{self.tone()}\{opened}",
      type_="button",
      title=self.summary(),
      on_click=toggle,
      [
        @html.span(
          class="composer-git-glyph",
          @icons.icon(@icons.icon_pull_request),
        ),
        @html.span(class="composer-git-label", self.label()),
      ],
    ),
  ]
  if open {
    children.push(self.render_details())
  }
  @html.div(class="composer-git", children)
}

///|
fn GitPresentation::render_details(self : GitPresentation) -> @html.Html {
  let rows : Array[@html.Html] = [
    GitPopoverRow::{
      key: "Branch",
      value: @html.span(class="composer-git-value", self.branch),
      note: self.changes.bind(changes => {
        changes.base.map(base => "from \{base}")
      }),
    }.render(),
  ]
  if self.changes is Some(changes) {
    rows.push(changes.render())
  }
  if self.pull_request is Some(pull_request) {
    rows.push(@html.div(class="composer-git-rule", @html.nothing))
    rows.push(
      GitPopoverLink::{
        label: pull_request.label(),
        note: Some(pull_request.title),
        href: pull_request.url,
        tone: "none",
      }.render(),
    )
    if pull_request.checks is Some(checks) {
      rows.push(
        GitPopoverLink::{
          label: "CI",
          note: Some(checks.summary()),
          href: "\{pull_request.url}/checks",
          tone: checks.tone(),
        }.render(),
      )
    }
  } else if self.compare_url is Some(url) {
    rows.push(@html.div(class="composer-git-rule", @html.nothing))
    rows.push(
      GitPopoverLink::{
        label: "Create pull request",
        note: None,
        href: url,
        tone: "none",
      }.render(),
    )
  } else if self.missing_pull_request is Some(label) {
    rows.push(
      GitPopoverRow::{
        key: "PR",
        value: @html.span(class="composer-git-value", label),
        note: None,
      }.render(),
    )
  }
  @html.div(class="composer-git-menu", rows)
}

///|
fn GitChanges::render(self : GitChanges) -> @html.Html {
  let value = if self.files > 0 {
    @html.span(class="composer-git-diff", [
      @html.span(class="composer-diff-added", "+\{self.added}"),
      @html.span(class="composer-diff-removed", "−\{self.removed}"),
    ])
  } else if self.partial {
    @html.span(class="composer-git-clean", "Not counted")
  } else {
    @html.span(class="composer-git-clean", "No changes")
  }
  let counted = if self.files == 0 { None } else { Some(self.file_count()) }
  let note = if !self.partial {
    counted
  } else if counted is Some(counted) {
    Some("\{counted}, untracked tail uncounted")
  } else {
    Some("untracked tail uncounted")
  }
  GitPopoverRow::{ key: "Changes", value, note }.render()
}

///|
priv struct GitPopoverRow {
  key : String
  value : @html.Html
  note : String?
}

///|
fn GitPopoverRow::render(self : GitPopoverRow) -> @html.Html {
  let children : Array[@html.Html] = [
    @html.span(class="composer-git-key", self.key),
    self.value,
  ]
  if self.note is Some(note) {
    children.push(@html.span(class="composer-git-note", note))
  }
  @html.div(class="composer-git-row", children)
}

///|
priv struct GitPopoverLink {
  label : String
  note : String?
  href : String
  tone : String
}

///|
fn GitPopoverLink::render(self : GitPopoverLink) -> @html.Html {
  let children : Array[@html.Html] = [
    @html.span(
      class="composer-git-glyph \{self.tone}",
      @icons.icon(@icons.icon_pull_request),
    ),
    @html.span(class="composer-git-value", self.label),
  ]
  if self.note is Some(note) {
    children.push(@html.span(class="composer-git-note", note))
  }
  children.push(
    @html.span(class="composer-git-out", @icons.icon(@icons.icon_link_external)),
  )
  @html.a(
    class="composer-git-link",
    href=self.href,
    target=Blank,
    rel="noopener noreferrer",
    children,
  )
}

///|
pub extend GitChanges with Eq::{equal, not_equal}

///|
pub extend GitChecks with Eq::{equal, not_equal}

///|
pub extend GitPresentation with Eq::{equal, not_equal}

///|
pub extend GitPullRequest with Eq::{equal, not_equal}
