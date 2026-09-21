///|
pub fn toolbar(
  state : State,
  emit : @cmd.Emit[Msg],
  current~ : @github.State,
) -> @html.Html {
  guard current.has_open_pr() else { return @html.nothing }
  @html.div(class="github-review-controls", [
    @html.button(
      class="github-review-toggle",
      type_="button",
      title="Show GitHub pull request comments",
      on_click=emit(Toggle),
      attrs=@html.Attrs::build()
        .role("switch")
        .aria_label("GitHub comments")
        .aria_checked(state.enabled.to_string()),
      [
        @icons.icon_github(),
        @html.span("GitHub comments"),
        @html.span(
          class=if state.enabled {
            "github-review-switch on"
          } else {
            "github-review-switch"
          },
          "",
        ),
      ],
    ),
    if state.enabled {
      @html.button(
        class="github-review-refresh",
        title="Refresh GitHub comments",
        disabled=state.loading || state.busy,
        on_click=emit(Refresh),
        "↻",
      )
    } else {
      @html.nothing
    },
  ])
}

///|
fn comment_view(
  state : State,
  emit : @cmd.Emit[Msg],
  comment : @protocol.GithubReviewComment,
) -> @html.Html {
  @html.article(
    class="github-review-comment",
    attrs=@html.Attrs::build().data_set("comment-id", comment.id),
    [
      @html.header(class="github-review-comment-header", [
        match comment.avatar_url {
          Some(url) if url.has_prefix("https://") =>
            @html.img(
              class="github-review-avatar",
              src=url,
              alt="",
              attrs=@html.Attrs::build().referrerpolicy("no-referrer"),
            )
          _ =>
            @html.span(
              class="github-review-avatar github-review-avatar-fallback",
              @icons.icon_github(),
            )
        },
        @html.strong(comment.author.unwrap_or("Deleted user")),
        @html.a(
          class="github-review-time",
          href=comment.url,
          title=comment.created_at,
          comment.created_at
          .replace_all(old="T", new=" ")
          .replace_all(old="Z", new=" UTC"),
        ),
        if comment.can_delete {
          @html.button(
            class="github-review-delete",
            title="Delete comment",
            disabled=state.busy,
            on_click=emit(DeleteRequested(comment.id)),
            @icons.icon_trash(),
          )
        } else {
          @html.nothing
        },
      ]),
      @html.div(
        class="github-review-markdown markdown",
        @markdown.markdown_nodes(comment.body, web_source=comment.url),
      ),
      if state.deleting == Some(comment.id) {
        @html.div(
          class="github-review-delete-confirm",
          attrs=@html.Attrs::build().role("alert"),
          [
            @html.span("Delete this comment?"),
            @html.button(
              disabled=state.busy,
              on_click=emit(DeleteCancelled),
              "Cancel",
            ),
            @html.button(
              class="danger",
              disabled=state.busy,
              on_click=emit(DeleteConfirmed(comment.id)),
              "Delete",
            ),
          ],
        )
      } else {
        @html.nothing
      },
    ],
  )
}

///|
pub fn composer(
  state : State,
  emit : @cmd.Emit[Msg],
  target : GithubDraftTarget,
  enabled : Bool,
) -> @html.Html {
  let body = state.draft_body(target)
  let expanded = target is Line(..) ||
    state.active == Some(target) ||
    !body.is_empty()
  let title = match target {
    Line(..) => "Write a comment"
    Thread(..) => "Reply"
  }
  @html.div(
    class="github-review-composer",
    attrs=@html.Attrs::build().data_set("draft", target.key()),
    [
      @html.textarea(
        id="github-review-input:" + target.key(),
        class="github-review-input",
        value=body,
        rows=if expanded { 4 } else { 1 },
        placeholder=if target is Thread(..) {
          "Reply…"
        } else {
          "Leave a comment…"
        },
        disabled=state.busy,
        on_input=body => emit(Edit(target, body)),
        attrs=@html.Attrs::build()
          .aria_label(title)
          .on_focus(_ => emit(Compose(target)))
          .on_keydown(event => {
            if (event.meta_key() || event.ctrl_key()) &&
              event.key() == "Enter" &&
              enabled {
              event.prevent_default()
              emit(Send(target))
            } else if event.key() == "Escape" {
              event.stop_propagation()
              @cmd.none
            } else {
              @cmd.none
            }
          }),
        "",
      ),
      if expanded {
        @html.div(class="github-review-composer-actions", [
          @html.button(
            disabled=state.busy,
            on_click=emit(Cancel(target)),
            "Cancel",
          ),
          @html.button(
            class="github-review-send",
            disabled=state.busy || !enabled || body.trim().is_empty(),
            on_click=emit(Send(target)),
            if state.busy {
              "Sending…"
            } else {
              "Send"
            },
          ),
        ])
      } else {
        @html.nothing
      },
    ],
  )
}

///|
pub fn thread_view(
  state : State,
  emit : @cmd.Emit[Msg],
  thread : @protocol.GithubReviewThread,
) -> @html.Html {
  let collapsed = thread.resolved && !state.expanded.contains(thread.id)
  let location = match
    (match thread.line {
      Some(_) => thread.line
      None => thread.original_line
    }) {
    Some(line) =>
      (if thread.side == "LEFT" { "Original line " } else { "Line " }) +
      line.to_string()
    None => "File conversation"
  }
  @html.section(
    class="github-review-thread" +
      (if thread.resolved { " resolved" } else { "" }),
    attrs=@html.Attrs::build().data_set("thread-id", thread.id),
    [
      @html.div(class="github-review-thread-location", [
        @html.span(location),
        if thread.outdated {
          @html.span(class="github-review-badge", "Outdated")
        } else {
          @html.nothing
        },
        if thread.resolved {
          @html.button(
            class="github-review-resolved-toggle",
            on_click=emit(Expand(thread.id)),
            attrs=@html.Attrs::build().aria_expanded((!collapsed).to_string()),
            if collapsed {
              "Resolved · Show conversation"
            } else {
              "Resolved · Hide conversation"
            },
          )
        } else {
          @html.nothing
        },
      ]),
      if collapsed {
        @html.nothing
      } else {
        @html.div([
          @html.div(
            thread.comments.map(comment => comment_view(state, emit, comment)),
          ),
          @html.div(class="github-review-thread-footer", [
            if thread.can_reply && thread.comments.get(0) is Some(root) {
              composer(
                state,
                emit,
                Thread(thread=thread.id, comment=root.id),
                true,
              )
            } else {
              @html.nothing
            },
            if (!thread.resolved && thread.can_resolve) ||
              (thread.resolved && thread.can_unresolve) {
              @html.button(
                class="github-review-resolve",
                disabled=state.busy,
                on_click=emit(Resolve(thread.id, !thread.resolved)),
                if thread.resolved {
                  "Unresolve conversation"
                } else {
                  "Resolve conversation"
                },
              )
            } else {
              @html.nothing
            },
          ]),
        ])
      },
    ],
  )
}

///|
pub fn status_view(
  state : State,
  emit : @cmd.Emit[Msg],
  matching : Bool,
  unplaced : Array[@protocol.GithubReviewThread],
  drafts : Array[GithubDraftTarget],
  update_pr~ : @cmd.Cmd,
  updating~ : Bool,
  current~ : @github.State,
) -> @html.Html {
  if current.current is Some(Err(error)) {
    return @html.div(class="github-review-status", [
      @html.div(
        class="github-review-error",
        attrs=@html.Attrs::build().role("alert"),
        "Could not check the current GitHub pull request. \{error}",
      ),
      @html.button(
        type_="button",
        disabled=current.current_loading,
        on_click=emit(CheckAvailability),
        "Retry PR check",
      ),
    ])
  }
  if !state.enabled {
    return @html.nothing
  }
  let children : Array[@html.Html] = []
  if state.loading || state.file_loading {
    children.push(
      @html.span(
        attrs=@html.Attrs::build().role("status"),
        "Loading GitHub comments…",
      ),
    )
  }
  for
    error in [
      state.error,
      state.mutation_error,
      state.storage_error,
      match state.file {
        Some(Err(error)) => Some(error)
        _ => None
      },
    ] {
    if error is Some(error) {
      children.push(
        @html.div(
          class="github-review-error",
          attrs=@html.Attrs::build().role("alert"),
          error,
        ),
      )
    }
  }
  if state.review is Some(_) &&
    state.path is Some(_) &&
    !state.loading &&
    !state.file_loading &&
    !matching {
    children.push(
      @html.div(class="github-review-recovery", [
        @html.span(
          "Update this checkout to the latest PR revision to add inline comments. Local edits can also make the comparison differ.",
        ),
        @html.button(
          class="github-review-update",
          type_="button",
          disabled=updating || state.busy,
          on_click=update_pr,
          if updating {
            "Updating checkout…"
          } else {
            "Update checkout"
          },
        ),
      ]),
    )
  }
  if !unplaced.is_empty() || !drafts.is_empty() {
    children.push(
      @html.details(class="github-review-unplaced", [
        @html.summary(
          "Conversations outside the current diff (\{unplaced.length() + drafts.length()})",
        ),
        @html.div(class="github-review-unplaced-body", [
          @html.div(unplaced.map(thread => thread_view(state, emit, thread))),
          @html.div(
            drafts.map(target => {
              @html.section(class="github-review-thread", [
                @html.div(
                  class="github-review-thread-location",
                  "Local draft · earlier or hidden line",
                ),
                composer(state, emit, target, false),
              ])
            }),
          ),
        ]),
      ]),
    )
  }
  @html.div(
    class=if children.is_empty() {
      "github-review-status hidden"
    } else {
      "github-review-status"
    },
    children,
  )
}

///|
pub fn State::comment_count(self : State, path : String) -> Int {
  if !self.enabled {
    return 0
  }
  self.review
  .map(review => {
    review.threads
    .filter(thread => thread.path == path && !thread.resolved)
    .length()
  })
  .unwrap_or(0)
}
