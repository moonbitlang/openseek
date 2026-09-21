///|
fn detail_view(
  locale~ : @i18n.Locale,
  state : State,
  emit : @cmd.Emit[Msg],
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  guard state.detail is Some(detail) else {
    return @html.div(class="github-detail github-detail-placeholder", [
      @icons.icon(@icons.icon_pull_request),
      @html.p(ui(locale, SelectPullRequestHint)),
    ])
  }
  @html.div(class="github-detail", [
    @html.div(class="github-detail-scroll", [
      @html.div(class="github-detail-content", [
        detail_header(locale~, detail, open_link),
        detail_actions(locale~, detail, state.active, emit, open_link),
        if detail.loading && detail.reply is None {
          @html.div(
            class="github-detail-status",
            attrs=@html.Attrs::build().role("status"),
            ui(locale, LoadingPullRequest),
          )
        } else {
          @html.nothing
        },
        if !state.active {
          @html.div(
            class="github-detail-status",
            ui(locale, ConnectPullRequestHint),
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
                  ui(locale, RetryLabel),
                ),
              ],
            )
          None => @html.nothing
        },
        match detail.reply {
          Some(reply) =>
            pull_request_body(locale~, reply, detail.item.avatar_url, open_link)
          None => @html.nothing
        },
      ]),
    ]),
  ])
}

///|
fn detail_header(
  locale~ : @i18n.Locale,
  detail : Detail,
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  let item = detail.reply.map(reply => reply.item).unwrap_or(detail.item)
  @html.header(class="github-pr-header", [
    @html.h1(class="github-detail-title", [
      @html.text(item.title + " "),
      @html.button(
        class="github-detail-link github-title-number",
        title=ui(locale, OpenPullRequest),
        on_click=open_link(item.url),
        "#\{item.number}",
      ),
    ]),
    match detail.reply {
      Some(pr) =>
        @html.div(class="github-detail-meta", [
          pull_request_state(locale~, pr),
          @html.span(
            class="github-merge-description",
            merge_description(
              locale,
              pr.state,
              @html.span(class="github-pr-author", [
                avatar_view(detail.item.avatar_url),
                @html.strong(item.author.unwrap_or(ui(locale, DeletedUser))),
              ]),
              @html.code(pr.base),
              @html.code(pr.head),
            ),
          ),
        ])
      None => @html.nothing
    },
  ])
}

///|
fn detail_actions(
  locale~ : @i18n.Locale,
  detail : Detail,
  active : Bool,
  emit : @cmd.Emit[Msg],
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  @html.div(class="github-detail-actions", [
    @html.button(
      class="github-action-button",
      on_click=open_link(detail.item.url),
      [
        @icons.icon(@icons.icon_link_external),
        @html.text(ui(locale, OpenOnGithub)),
      ],
    ),
    @html.button(
      class="github-action-button",
      attrs=@html.Attrs::build().aria_label(ui(locale, RefreshPullRequest)),
      disabled=!active || detail.loading,
      on_click=emit(RefreshDetail),
      [
        @icons.icon(@icons.icon_sync),
        @html.span(
          attrs=@html.Attrs::build().role("status"),
          if detail.loading {
            if detail.reply is None {
              ui(locale, LoadingLabel)
            } else {
              ui(locale, RefreshingLabel)
            }
          } else {
            ui(locale, RefreshLabel)
          },
        ),
      ],
    ),
    @html.button(
      class="tab-action github-detail-dismiss",
      title=ui(locale, CloseDetails),
      attrs=@html.Attrs::build().aria_label(ui(locale, CloseDetails)),
      on_click=emit(CloseDetail),
      @icons.icon(@icons.icon_close),
    ),
  ])
}

///|
fn pull_request_state(
  locale~ : @i18n.Locale,
  pr : @protocol.GithubPullRequestDetail,
) -> @html.Html {
  let (label, style) = match pr.state {
    "OPEN" if pr.item.draft => (ui(locale, DraftLabel), "draft")
    "OPEN" => (ui(locale, OpenLabel), "open")
    "MERGED" => (ui(locale, MergedLabel), "merged")
    "CLOSED" => (ui(locale, ClosedLabel), "closed")
    state => (state, "unknown")
  }
  @html.span(class="github-pr-state " + style, [
    @icons.icon(@icons.icon_pull_request),
    @html.text(label),
  ])
}

///|
fn pull_request_body(
  locale~ : @i18n.Locale,
  pr : @protocol.GithubPullRequestDetail,
  author_avatar : String?,
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  let conversation : Array[@html.Html] = [
    comment_card(
      locale~,
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
        locale~,
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
  conversation.push(checks_view(locale~, pr, open_link))
  @html.div(class="github-pr-layout", [
    @html.section(
      class="github-conversation",
      attrs=@html.Attrs::build().aria_label(ui(locale, ConversationLabel)),
      conversation,
    ),
    metadata_view(locale~, pr),
  ])
}

///|
fn comment_card(
  locale~ : @i18n.Locale,
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
          @html.strong(author.unwrap_or(ui(locale, DeletedUser))),
          @html.button(
            class="github-detail-link github-comment-date",
            title=created_at,
            on_click=open_link(url),
            @html.time(
              datetime=created_at,
              ui(locale, CommentedAt(relative_date(created_at, locale.tag()))),
            ),
          ),
        ]),
        if description {
          @html.span(class="github-author-badge", ui(locale, AuthorLabel))
        } else {
          @html.nothing
        },
      ]),
      @html.div(class="github-comment-body", [
        if body.is_empty() {
          @html.p(class="github-detail-status", ui(locale, NoDescription))
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
extern "js" fn relative_date(value : String, locale : String) -> String =
  #| (value, locale) => {
  #|   const date = new Date(value);
  #|   if (!Number.isFinite(date.getTime())) return value;
  #|   const seconds = Math.max(0, (Date.now() - date.getTime()) / 1000);
  #|   if (seconds < 60) return new Intl.RelativeTimeFormat(locale, { numeric: "auto" }).format(0, "second");
  #|   if (seconds < 3600) return new Intl.RelativeTimeFormat(locale).format(-Math.floor(seconds / 60), "minute");
  #|   if (seconds < 86400) return new Intl.RelativeTimeFormat(locale).format(-Math.floor(seconds / 3600), "hour");
  #|   if (seconds < 604800) return new Intl.RelativeTimeFormat(locale).format(-Math.floor(seconds / 86400), "day");
  #|   return new Intl.DateTimeFormat(locale, { month: "short", day: "numeric", year: "numeric" }).format(date);
  #| }

///|
fn metadata_section(title : String, children : Array[@html.Html]) -> @html.Html {
  @html.section(class="github-metadata-section", [
    @html.h2(title),
    @html.div(children),
  ])
}

///|
fn metadata_view(
  locale~ : @i18n.Locale,
  pr : @protocol.GithubPullRequestDetail,
) -> @html.Html {
  @html.div(
    class="github-metadata",
    attrs=@html.Attrs::build()
      .role("complementary")
      .aria_label(ui(locale, DetailsLabel)),
    [
      metadata_section(
        ui(locale, ReviewersLabel),
        if pr.reviewers.is_empty() {
          [@html.p(class="github-metadata-empty", ui(locale, NoReviews))]
        } else {
          pr.reviewers.map(reviewer => {
            let (label, style) = match reviewer.state {
              "APPROVED" => (ui(locale, ApprovedLabel), "passed")
              "CHANGES_REQUESTED" => (ui(locale, ChangesRequested), "failed")
              "REQUESTED" => (ui(locale, ReviewRequested), "pending")
              "COMMENTED" => (ui(locale, CommentedLabel), "other")
              "DISMISSED" => (ui(locale, DismissedLabel), "other")
              "PENDING" => (ui(locale, PendingLabel), "pending")
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
        ui(locale, AssigneesLabel),
        if pr.assignees.is_empty() {
          [@html.p(class="github-metadata-empty", ui(locale, NoAssignees))]
        } else {
          pr.assignees.map(name => @html.p(name))
        },
      ),
      metadata_section(
        ui(locale, LabelsLabel),
        if pr.labels.is_empty() {
          [@html.p(class="github-metadata-empty", ui(locale, NoLabels))]
        } else {
          [
            @html.div(
              class="github-labels",
              pr.labels.map(label => @html.span(class="github-label", label)),
            ),
          ]
        },
      ),
      metadata_section(ui(locale, MilestoneLabel), [
        @html.p(
          class=if pr.milestone is None { "github-metadata-empty" } else { "" },
          pr.milestone.unwrap_or(ui(locale, NoMilestone)),
        ),
      ]),
      metadata_section(ui(locale, ChangesLabel), [
        @html.p(ui(locale, ChangedFiles(pr.changed_files))),
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
  locale~ : @i18n.Locale,
  pr : @protocol.GithubPullRequestDetail,
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  let (summary, style) = checks_summary(locale~, pr.checks)
  let rows : Array[@html.Html] = []
  // Keep the provider's order within each group, with actionable checks first.
  for group in ["failed", "pending", "other", "passed"] {
    for check in pr.checks {
      if check_style(check.state) == group {
        rows.push(check_row(locale~, check, open_link))
      }
    }
  }
  @html.section(
    class="github-checks-card",
    attrs=@html.Attrs::build().aria_label(ui(locale, ChecksLabel)),
    [
      if pr.checks.is_empty() {
        @html.div(class="github-checks-summary", [
          check_icon("other", ui(locale, NoChecks)),
          @html.span(class="github-check-summary", summary),
        ])
      } else {
        @html.details(
          class="github-checks-details",
          open=style == "failed" || style == "pending",
          [
            @html.summary(class="github-checks-summary", [
              check_icon(style, ui(locale, CheckStatus)),
              @html.span(class="github-check-summary", summary),
              @html.span(class="github-check-toggle", [
                @html.span(class="github-check-show", ui(locale, ShowLabel)),
                @html.span(class="github-check-hide", ui(locale, HideLabel)),
              ]),
            ]),
            @html.div(
              class="github-checks",
              attrs=@html.Attrs::build()
                .role("region")
                .aria_label(ui(locale, CheckResults))
                .tabindex(0),
              rows,
            ),
          ],
        )
      },
      mergeability_view(locale~, pr),
    ],
  )
}

///|
fn checks_summary(
  locale~ : @i18n.Locale,
  checks : Array[@protocol.GithubCheck],
) -> (String, String) {
  if checks.is_empty() {
    return (ui(locale, NoChecksReported), "other")
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
      (passed, ui(locale, SuccessfulChecks(passed))),
      (pending, ui(locale, PendingChecks(pending))),
      (failed, ui(locale, FailedChecks(failed))),
      (cancelled, ui(locale, CancelledChecks(cancelled))),
      (skipped, ui(locale, SkippedChecks(skipped))),
      (neutral, ui(locale, NeutralChecks(neutral))),
      (other, ui(locale, OtherChecks(other))),
    ] {
    if count > 0 {
      phrases.push(label)
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
  (
    phrases.join(
      match locale {
        English => " and "
        SimplifiedChinese | TraditionalChinese => "，"
        Japanese => "、"
        Spanish => " y "
      },
    ),
    style,
  )
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
  locale~ : @i18n.Locale,
  check : @protocol.GithubCheck,
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  let name = check.workflow.map(workflow => workflow + " / ").unwrap_or("") +
    check.name
  let label = match check.state {
    "SUCCESS" => ui(locale, SuccessfulLabel)
    "FAILURE" => ui(locale, FailedLabel)
    "ERROR" => ui(locale, FailedLabel)
    "CANCELLED" => ui(locale, CancelledLabel)
    "SKIPPED" => ui(locale, SkippedLabel)
    "NEUTRAL" => ui(locale, NeutralLabel)
    "QUEUED" => ui(locale, QueuedLabel)
    "IN_PROGRESS" => ui(locale, InProgressLabel)
    "PENDING" => ui(locale, PendingLabel)
    "EXPECTED" => ui(locale, ExpectedLabel)
    "WAITING" => ui(locale, WaitingLabel)
    "REQUESTED" => ui(locale, RequestedLabel)
    "TIMED_OUT" => ui(locale, TimedOutLabel)
    "ACTION_REQUIRED" => ui(locale, ActionRequiredLabel)
    "STARTUP_FAILURE" => ui(locale, StartupFailureLabel)
    "STALE" => ui(locale, StaleLabel)
    state => state
  }
  @html.div(class="github-check", [
    check_icon(check_style(check.state), label),
    @html.span(
      class="github-check-provider",
      title=if check.workflow is Some(_) {
        "GitHub Actions"
      } else {
        ui(locale, StatusCheck)
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
          attrs=@html.Attrs::build().aria_label(ui(locale, CheckDetails(name))),
          on_click=open_link(url),
          ui(locale, ViewDetails),
        )
      None => @html.nothing
    },
  ])
}

///|
fn mergeability_view(
  locale~ : @i18n.Locale,
  pr : @protocol.GithubPullRequestDetail,
) -> @html.Html {
  let (text, style) = match (pr.state, pr.mergeable) {
    ("MERGED", _) => (ui(locale, MergeSucceeded), "passed")
    ("CLOSED", _) => (ui(locale, PullRequestClosed), "other")
    (_, "MERGEABLE") => (ui(locale, NoConflicts), "passed")
    (_, "CONFLICTING") => (ui(locale, HasConflicts), "failed")
    _ => (ui(locale, ConflictsUnavailable), "other")
  }
  @html.div(class="github-mergeability", [
    check_icon(style, ui(locale, MergeConflictStatus)),
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
