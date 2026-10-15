///|
pub(all) struct SessionPrRow {
  url : String
  urls : Array[String]
  pull_request : @protocol.GitPullRequest?
  head_url : String?
  error : String?
} derive(Eq)

///|
pub extend SessionPrRow with Eq::{equal, not_equal}

///|
fn render_session_prs(
  locale~ : @i18n.Locale,
  rows : Array[SessionPrRow],
  error : String?,
  collapsed~ : Bool,
  checks_url~ : String?,
  identity : Identity,
  emit : @cmd.Emit[Action],
) -> @html.Html {
  let children : Array[@html.Html] = []
  for row in rows {
    if collapsed {
      break
    }
    let tone = match row.pull_request {
      Some(pr) if pr.state == "open" && pr.draft => "draft"
      Some(pr) => pr.state
      None => "branch"
    }
    let (number, repo, branch) = match row.url.split("/").collect() {
      ["https:", "", _, _, repo, "pull", number] =>
        (Some(number.to_owned()), Some(repo.to_owned()), None)
      ["https:", "", _, _, repo, "tree", .. branch] =>
        (None, Some(repo.to_owned()), Some(branch.join("/")))
      _ => (None, None, None)
    }
    let branch = match row.head_url {
      Some(url) =>
        match url.split("/tree/").collect() {
          [_, branch] => Some(branch.to_owned())
          _ => branch
        }
      None => branch
    }
    let label : Array[@html.Html] = [
      @html.span(
        class="session-pr-icon",
        title=if tone == "closed" { ui(locale, PrClosed) } else { row.url },
        @icons.icon(
          match tone {
            "merged" => @icons.icon_pull_request_merged
            "closed" => @icons.icon_pull_request_closed
            _ => @icons.icon_pull_request
          },
        ),
      ),
    ]
    if number is Some(number) {
      label.push(@html.span(class="session-pr-number", "#" + number))
    }
    if repo is Some(repo) {
      label.push(@html.span(class="session-pr-repo", repo))
    }
    if branch is Some(branch) {
      label.push(@html.span(class="session-pr-branch", branch))
    } else if repo is None {
      label.push(@html.span(class="session-pr-branch", row.url))
    }
    let content : Array[@html.Html] = [
      @html.a(
        class="session-pr-link",
        href=row.url,
        title=row.url,
        target=Blank,
        rel="noopener noreferrer",
        label,
      ),
    ]
    if row.pull_request is Some(pr) {
      if pr.state == "merged" {
        content.push(@html.span(class="session-pr-state", ui(locale, PrMerged)))
      } else {
        if pr.draft {
          content.push(
            @html.span(class="session-pr-state", ui(locale, PrDraft)),
          )
        }
        content.push(
          @html.span(class="session-pr-diff session-pr-badge", [
            @html.span(class="added", "+" + pr_count(pr.additions)),
            @html.span(class="removed", "−" + pr_count(pr.deletions)),
          ]),
        )
        if pr.checks is Some(checks) {
          let checks = GitChecks::GitChecks(
            passed=checks.passed,
            failed=checks.failed,
            pending=checks.pending,
          )
          let checks_content : Array[@html.Html] = [
            @html.button(
              class="session-pr-checks session-pr-badge " + checks.tone(),
              type_="button",
              title=checks.summary(locale~),
              attrs=@html.Attrs::build().aria_expanded(
                if checks_url == Some(row.url) {
                  "true"
                } else {
                  "false"
                },
              ),
              on_click=emit(PrChecksToggled(identity~, url=row.url)),
              [
                @html.span(class="session-pr-check-dot", @html.nothing),
                @html.span("CI"),
                @icons.icon(@icons.icon_chevron_down),
              ],
            ),
          ]
          if checks_url == Some(row.url) {
            checks_content.push(
              @html.div(class="session-pr-check-menu", [
                @html.a(
                  href=pr.url + "/checks",
                  target=Blank,
                  rel="noopener noreferrer",
                  checks.summary(locale~),
                ),
              ]),
            )
          }
          content.push(
            @html.div(class="session-pr-check-control", checks_content),
          )
        }
      }
    }
    if row.error is Some(message) {
      content.push(
        @html.span(
          class="session-pr-error",
          title=message,
          ui(locale, PrStatusUnavailable),
        ),
      )
    }
    content.push(
      @html.button(
        class="session-pr-remove",
        type_="button",
        title=ui(locale, RemoveLabel),
        on_click=emit(PrBindingRemoved(identity~, urls=row.urls)),
        @icons.icon(@icons.icon_close),
      ),
    )
    children.push(@html.div(class="session-pr-row " + tone, content))
  }
  if rows.length() > 1 || (collapsed && !rows.is_empty()) {
    children.push(
      @html.button(
        class="session-pr-toggle",
        type_="button",
        on_click=emit(PrBindingsToggled(identity~)),
        ui(locale, if collapsed { PrExpand } else { PrCollapse }),
      ),
    )
  }
  if error is Some(message) {
    children.push(@html.div(class="session-pr-error", message))
  }
  @html.div(class="session-pr-bindings", children)
}

///|
fn pr_count(value : Int32) -> String {
  let digits = value.to_string()
  let parts : Array[String] = []
  let chars = digits.iter().collect()
  for i, c in chars {
    if i > 0 && (digits.length() - i) % 3 == 0 {
      parts.push(",")
    }
    parts.push(c.to_string())
  }
  parts.join("")
}
