///|
fn detail_view(
  state : State,
  emit : @cmd.Emit[Msg],
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  guard state.detail is Some(detail) else {
    return @html.div(class="github-detail github-detail-placeholder", [
      @icons.icon(@icons.icon_pull_request),
      @html.p("Select a pull request to view its description and discussion."),
    ])
  }
  @html.div(class="github-detail", [
    @html.div(class="github-detail-scroll", [
      @html.div(class="github-detail-content", [
        detail_header(detail, open_link),
        detail_actions(detail, state.active, emit, open_link),
        if detail.loading && detail.reply is None {
          @html.div(
            class="github-detail-status",
            attrs=@html.Attrs::build().role("status"),
            "Loading pull request…",
          )
        } else {
          @html.nothing
        },
        if !state.active {
          @html.div(
            class="github-detail-status",
            "Connect to the workspace host to refresh this pull request.",
          )
        } else {
          @html.nothing
        },
        match detail.error {
          Some(error) =>
            @html.div(
              class="github-error",
              attrs=@html.Attrs::build().role("alert"),
              [
                @html.div(error),
                @html.button(
                  class="github-more",
                  disabled=!state.active,
                  on_click=emit(RefreshDetail),
                  "Retry",
                ),
              ],
            )
          None => @html.nothing
        },
        match detail.reply {
          Some(reply) =>
            pull_request_body(reply, detail.item.avatar_url, open_link)
          None => @html.nothing
        },
      ]),
    ]),
  ])
}

///|
fn detail_header(
  detail : Detail,
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  let item = detail.reply.map(reply => reply.item).unwrap_or(detail.item)
  @html.header(class="github-pr-header", [
    @html.h1(class="github-detail-title", [
      @html.text(item.title + " "),
      @html.button(
        class="github-detail-link github-title-number",
        title="Open pull request on GitHub",
        on_click=open_link(item.url),
        "#\{item.number}",
      ),
    ]),
    match detail.reply {
      Some(pr) =>
        @html.div(class="github-detail-meta", [
          pull_request_state(pr),
          @html.span(class="github-merge-description", [
            @html.span(class="github-pr-author", [
              avatar_view(detail.item.avatar_url),
              @html.strong(item.author.unwrap_or("Deleted user")),
            ]),
            @html.text(
              match pr.state {
                "MERGED" => " merged changes into "
                "CLOSED" => " proposed changes into "
                _ => " wants to merge changes into "
              },
            ),
            @html.code(pr.base),
            @html.text(" from "),
            @html.code(pr.head),
          ]),
        ])
      None => @html.nothing
    },
  ])
}

///|
fn detail_actions(
  detail : Detail,
  active : Bool,
  emit : @cmd.Emit[Msg],
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  @html.div(class="github-detail-actions", [
    @html.button(
      class="github-action-button",
      on_click=open_link(detail.item.url),
      [@icons.icon(@icons.icon_link_external), @html.text("Open on GitHub")],
    ),
    @html.button(
      class="github-action-button",
      attrs=@html.Attrs::build().aria_label("Refresh pull request"),
      disabled=!active || detail.loading,
      on_click=emit(RefreshDetail),
      [
        @icons.icon(@icons.icon_sync),
        @html.span(
          attrs=@html.Attrs::build().role("status"),
          if detail.loading {
            if detail.reply is None {
              "Loading…"
            } else {
              "Refreshing…"
            }
          } else {
            "Refresh"
          },
        ),
      ],
    ),
    @html.button(
      class="tab-action github-detail-dismiss",
      title="Close pull request details",
      attrs=@html.Attrs::build().aria_label("Close pull request details"),
      on_click=emit(CloseDetail),
      @icons.icon(@icons.icon_close),
    ),
  ])
}

///|
fn pull_request_state(pr : @protocol.GithubPullRequestDetail) -> @html.Html {
  let (label, style) = match pr.state {
    "OPEN" if pr.item.draft => ("Draft", "draft")
    "OPEN" => ("Open", "open")
    "MERGED" => ("Merged", "merged")
    "CLOSED" => ("Closed", "closed")
    state => (state, "unknown")
  }
  @html.span(class="github-pr-state " + style, [
    @icons.icon(@icons.icon_pull_request),
    @html.text(label),
  ])
}

///|
fn pull_request_body(
  pr : @protocol.GithubPullRequestDetail,
  author_avatar : String?,
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  let conversation : Array[@html.Html] = [
    comment_card(
      pr.item.author,
      author_avatar,
      pr.created_at,
      pr.item.url,
      pr.body,
      description=true,
      open_link,
    ),
  ]
  for comment in pr.comments {
    conversation.push(
      comment_card(
        comment.author,
        if comment.author == pr.item.author {
          author_avatar
        } else {
          None
        },
        comment.created_at,
        comment.url,
        comment.body,
        open_link,
      ),
    )
  }
  conversation.push(checks_view(pr, open_link))
  @html.div(class="github-pr-layout", [
    @html.section(
      class="github-conversation",
      attrs=@html.Attrs::build().aria_label("Pull request conversation"),
      conversation,
    ),
    metadata_view(pr),
  ])
}

///|
fn comment_card(
  author : String?,
  avatar : String?,
  created_at : String,
  url : String,
  body : String,
  description? : Bool = false,
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  @html.article(
    class="github-comment" +
      (if description { " github-description" } else { "" }),
    [
      @html.header(class="github-comment-header", [
        avatar_view(avatar),
        @html.div(class="github-comment-meta", [
          @html.strong(author.unwrap_or("Deleted user")),
          @html.button(
            class="github-detail-link github-comment-date",
            title=created_at,
            on_click=open_link(url),
            [
              @html.text("commented "),
              @html.time(datetime=created_at, relative_date(created_at)),
            ],
          ),
        ]),
        if description {
          @html.span(class="github-author-badge", "Author")
        } else {
          @html.nothing
        },
      ]),
      @html.div(class="github-comment-body", [
        if body.is_empty() {
          @html.p(class="github-detail-status", "No description provided.")
        } else {
          @html.div(
            class="msg-content markdown",
            @markdown.markdown_nodes(body, web_source=url),
          )
        },
      ]),
    ],
  )
}

///|
extern "js" fn relative_date(value : String) -> String =
  #| (value) => {
  #|   const date = new Date(value);
  #|   if (!Number.isFinite(date.getTime())) return value;
  #|   const seconds = Math.max(0, (Date.now() - date.getTime()) / 1000);
  #|   if (seconds < 60) return "just now";
  #|   if (seconds < 3600) return new Intl.RelativeTimeFormat("en").format(-Math.floor(seconds / 60), "minute");
  #|   if (seconds < 86400) return new Intl.RelativeTimeFormat("en").format(-Math.floor(seconds / 3600), "hour");
  #|   if (seconds < 604800) return new Intl.RelativeTimeFormat("en").format(-Math.floor(seconds / 86400), "day");
  #|   return "on " + new Intl.DateTimeFormat("en", { month: "short", day: "numeric", year: "numeric" }).format(date);
  #| }

///|
fn metadata_section(title : String, children : Array[@html.Html]) -> @html.Html {
  @html.section(class="github-metadata-section", [
    @html.h2(title),
    @html.div(children),
  ])
}

///|
fn metadata_view(pr : @protocol.GithubPullRequestDetail) -> @html.Html {
  @html.div(
    class="github-metadata",
    attrs=@html.Attrs::build()
      .role("complementary")
      .aria_label("Pull request details"),
    [
      metadata_section(
        "Reviewers",
        if pr.reviewers.is_empty() {
          [@html.p(class="github-metadata-empty", "No reviews yet")]
        } else {
          pr.reviewers.map(reviewer => {
            let (label, style) = match reviewer.state {
              "APPROVED" => ("Approved", "passed")
              "CHANGES_REQUESTED" => ("Changes requested", "failed")
              "REQUESTED" => ("Review requested", "pending")
              "COMMENTED" => ("Commented", "other")
              "DISMISSED" => ("Dismissed", "other")
              _ =>
                (
                  reviewer.state.to_lower().replace_all(old="_", new=" "),
                  "other",
                )
            }
            @html.div(class="github-reviewer", [
              @html.strong(reviewer.name),
              @html.span(class="github-review-state " + style, label),
            ])
          })
        },
      ),
      metadata_section(
        "Assignees",
        if pr.assignees.is_empty() {
          [@html.p(class="github-metadata-empty", "No one assigned")]
        } else {
          pr.assignees.map(name => @html.p(name))
        },
      ),
      metadata_section(
        "Labels",
        if pr.labels.is_empty() {
          [@html.p(class="github-metadata-empty", "None yet")]
        } else {
          [
            @html.div(
              class="github-labels",
              pr.labels.map(label => @html.span(class="github-label", label)),
            ),
          ]
        },
      ),
      metadata_section("Milestone", [
        @html.p(
          class=if pr.milestone is None { "github-metadata-empty" } else { "" },
          pr.milestone.unwrap_or("No milestone"),
        ),
      ]),
      metadata_section("Changes", [
        @html.p("\{pr.changed_files} changed files"),
        @html.div(class="github-diffstat", [
          @html.span(class="github-additions", "+\{pr.additions}"),
          @html.span(class="github-deletions", "−\{pr.deletions}"),
        ]),
      ]),
    ],
  )
}

///|
fn checks_view(
  pr : @protocol.GithubPullRequestDetail,
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  let (summary, style) = checks_summary(pr.checks)
  let rows : Array[@html.Html] = []
  // Keep the provider's order within each group, with actionable checks first.
  for group in ["failed", "pending", "other", "passed"] {
    for check in pr.checks {
      if check_style(check.state) == group {
        rows.push(check_row(check, open_link))
      }
    }
  }
  @html.section(
    class="github-checks-card",
    attrs=@html.Attrs::build().aria_label("Checks"),
    [
      if pr.checks.is_empty() {
        @html.div(class="github-checks-summary", [
          check_icon("other", "No checks"),
          @html.span(class="github-check-summary", summary),
        ])
      } else {
        @html.details(
          class="github-checks-details",
          open=style == "failed" || style == "pending",
          [
            @html.summary(class="github-checks-summary", [
              check_icon(style, "Check status"),
              @html.span(class="github-check-summary", summary),
              @html.span(class="github-check-toggle", [
                @html.span(class="github-check-show", "Show"),
                @html.span(class="github-check-hide", "Hide"),
              ]),
            ]),
            @html.div(
              class="github-checks",
              attrs=@html.Attrs::build()
                .role("region")
                .aria_label("Check results")
                .tabindex(0),
              rows,
            ),
          ],
        )
      },
      mergeability_view(pr),
    ],
  )
}

///|
fn checks_summary(checks : Array[@protocol.GithubCheck]) -> (String, String) {
  if checks.is_empty() {
    return ("No checks reported", "other")
  }
  let passed = checks
    .filter(check => check_style(check.state) == "passed")
    .length()
  let pending = checks
    .filter(check => check_style(check.state) == "pending")
    .length()
  let failed = checks
    .filter(check => check_style(check.state) == "failed")
    .length()
  let cancelled = checks.filter(check => check.state == "CANCELLED").length()
  let skipped = checks.filter(check => check.state == "SKIPPED").length()
  let neutral = checks.filter(check => check.state == "NEUTRAL").length()
  let other = checks.length() -
    passed -
    pending -
    failed -
    cancelled -
    skipped -
    neutral
  let phrases : Array[String] = []
  for
    (count, label) in [
      (passed, "successful"),
      (pending, "pending"),
      (failed, "failed"),
      (cancelled, "cancelled"),
      (skipped, "skipped"),
      (neutral, "neutral"),
      (other, "other"),
    ] {
    if count > 0 {
      phrases.push(
        "\{count} \{label} " + (if count == 1 { "check" } else { "checks" }),
      )
    }
  }
  let style = if failed > 0 {
    "failed"
  } else if pending > 0 {
    "pending"
  } else if cancelled + skipped + neutral + other > 0 {
    "other"
  } else {
    "passed"
  }
  (phrases.join(" and "), style)
}

///|
fn check_icon(style : String, label : String) -> @html.Html {
  @html.span(
    class="github-check-icon " + style,
    title=label,
    attrs=@html.Attrs::build().role("img").aria_label(label),
    if style == "pending" {
      @html.span(
        class="github-check-dot",
        attrs=@html.Attrs::build().aria_hidden("true"),
        "",
      )
    } else {
      @icons.icon(
        match style {
          "passed" => @icons.icon_check
          "failed" => @icons.icon_close
          _ => @icons.icon_circle
        },
      )
    },
  )
}

///|
fn check_row(
  check : @protocol.GithubCheck,
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  let name = check.workflow.map(workflow => workflow + " / ").unwrap_or("") +
    check.name
  let label = match check.state {
    "SUCCESS" => "Successful"
    "FAILURE" | "ERROR" => "Failed"
    state => state.to_lower().replace_all(old="_", new=" ")
  }
  @html.div(class="github-check", [
    check_icon(check_style(check.state), label),
    @html.span(
      class="github-check-provider",
      title=if check.workflow is Some(_) {
        "GitHub Actions"
      } else {
        "Status check"
      },
      @icons.icon(
        if check.workflow is Some(_) {
          @icons.icon_github
        } else {
          @icons.icon_extensions
        },
      ),
    ),
    @html.span(class="github-check-name", title=name, name),
    match check.url {
      Some(url) =>
        @html.button(
          class="github-detail-link github-check-details",
          title=url,
          attrs=@html.Attrs::build().aria_label("Details for " + name),
          on_click=open_link(url),
          "Details",
        )
      None => @html.nothing
    },
  ])
}

///|
fn mergeability_view(pr : @protocol.GithubPullRequestDetail) -> @html.Html {
  let (text, style) = match (pr.state, pr.mergeable) {
    ("MERGED", _) => ("Pull request successfully merged.", "passed")
    ("CLOSED", _) => ("This pull request is closed.", "other")
    (_, "MERGEABLE") =>
      ("This branch has no conflicts with the base branch.", "passed")
    (_, "CONFLICTING") =>
      ("This branch has conflicts with the base branch.", "failed")
    _ => ("Merge conflict status is not available yet.", "other")
  }
  @html.div(class="github-mergeability", [
    check_icon(style, "Merge conflict status"),
    @html.span(text),
  ])
}

///|
fn check_style(state : String) -> String {
  match state {
    "SUCCESS" => "passed"
    "FAILURE"
    | "ERROR"
    | "TIMED_OUT"
    | "ACTION_REQUIRED"
    | "STARTUP_FAILURE"
    | "STALE" => "failed"
    "QUEUED"
    | "IN_PROGRESS"
    | "PENDING"
    | "EXPECTED"
    | "WAITING"
    | "REQUESTED" => "pending"
    // Cancelled, skipped, neutral and future states retain their own labels.
    _ => "other"
  }
}
