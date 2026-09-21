///|
fn disclosure(
  label : String,
  expanded : Bool,
  action : @cmd.Cmd,
  section? : Bool = false,
) -> @html.Html {
  @html.button(
    class=if section { "github-heading" } else { "github-group-heading" },
    attrs=@html.Attrs::build()
      .aria_expanded(expanded.to_string())
      .aria_label(label),
    on_click=action,
    [
      @html.span(
        class=if expanded {
          "github-chevron expanded"
        } else {
          "github-chevron"
        },
        @icons.icon(@icons.icon_chevron_down),
      ),
      @html.span(label),
    ],
  )
}

///|
fn list_view(
  locale~ : @i18n.Locale,
  state : State,
  kind : @protocol.GithubListKind,
  emit : @cmd.Emit[Msg],
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  let group = state.group(kind)
  let children : Array[@html.Html] = []
  if group.reply is Some(reply) {
    if reply.avatar_error is Some(error) {
      children.push(
        @html.div(
          class="github-error",
          attrs=@html.Attrs::build().role("alert"),
          [
            @html.div(error),
            @html.button(
              class="github-more",
              disabled=group.loading,
              on_click=emit(Retry(kind)),
              ui(locale, RetryAvatars),
            ),
          ],
        ),
      )
    }
    for item in reply.items {
      let selected = !(kind is Issues) &&
        state.detail is Some({ item: { url, .. }, .. }) &&
        url == item.url
      let meta = "#\{item.number}" +
        item.author.map(author => " · \{author}").unwrap_or("") +
        (if item.draft { " · " + ui(locale, DraftLabel) } else { "" }) +
        (if !(kind is Issues) && state.is_current(item) {
          " · " + ui(locale, CurrentCheckout)
        } else {
          ""
        })
      children.push(
        @html.div(
          class="github-item" +
            (if item.draft { " draft" } else { "" }) +
            (if selected { " selected" } else { "" }),
          [
            @html.button(
              class="github-item-open",
              title="\{item.title}\n\{meta}",
              attrs=@html.Attrs::build()
                .aria_label("\{item.title}, \{meta}")
                .aria_current(if selected { "true" } else { "false" }),
              on_click=if kind is Issues {
                open_link(item.url)
              } else {
                emit(Select(reply.repository_url, item))
              },
              [
                avatar_view(item.avatar_url),
                if !(kind is Issues) && state.is_current(item) {
                  @html.span(
                    class="github-current",
                    title=ui(locale, CurrentCheckout),
                    @icons.icon(@icons.icon_check),
                  )
                } else {
                  @html.nothing
                },
                @html.span(class="github-item-title", item.title),
              ],
            ),
            if kind is Issues {
              @html.nothing
            } else {
              checkout_button(locale~, state, reply.repository_url, item, emit)
            },
          ],
        ),
      )
    }
    if reply.items.is_empty() && !group.loading && group.error is None {
      children.push(
        @html.div(
          class="github-empty",
          match kind {
            CreatedByMe => ui(locale, NoCreatedPulls)
            AllOpen => ui(locale, NoOpenPulls)
            Issues => ui(locale, NoOpenIssues)
          },
        ),
      )
    }
    if reply.has_more && !group.loading {
      children.push(
        @html.button(
          class="github-more",
          on_click=if reply.items.length() < 1000 {
            emit(More(kind))
          } else {
            open_link(
              reply.repository_url +
              (if kind is Issues { "/issues" } else { "/pulls" }),
            )
          },
          if reply.items.length() < 1000 {
            ui(locale, LoadMore)
          } else {
            ui(locale, ViewAll)
          },
        ),
      )
    }
  }
  if group.loading {
    children.push(
      @html.div(
        class="github-empty",
        attrs=@html.Attrs::build().role("status"),
        ui(locale, LoadingLabel),
      ),
    )
  }
  if group.error is Some(error) {
    children.push(
      @html.div(
        class="github-error",
        attrs=@html.Attrs::build().role("alert"),
        [
          @html.div(error),
          @html.button(
            class="github-more",
            on_click=emit(Retry(kind)),
            ui(locale, RetryLabel),
          ),
        ],
      ),
    )
  }
  @html.div(class="github-list", children)
}

///|
fn checkout_button(
  locale~ : @i18n.Locale,
  state : State,
  repository_url : String,
  item : @protocol.GithubItem,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let pending = state.checkout is Some({ url, phase: Running, .. }) &&
    url == item.url
  let updating = state.is_current(item)
  let label = if pending {
    if updating {
      ui(locale, UpdatingCheckout(item.number))
    } else {
      ui(locale, CheckingOut(item.number))
    }
  } else if updating {
    ui(locale, UpdateCheckout(item.number))
  } else {
    ui(locale, CheckoutLocally(item.number))
  }
  @html.button(
    class="github-checkout" + (if pending { " pending" } else { "" }),
    title=label,
    attrs=@html.Attrs::build()
      .aria_label(label)
      .data_set("pr-number", item.number.to_string()),
    disabled=!state.active || state.checkout_busy(),
    on_click=emit(
      if updating {
        UpdatePullRequest(item.url)
      } else {
        Checkout(repository_url, item)
      },
    ),
    if pending || updating {
      @icons.icon(@icons.icon_sync)
    } else {
      @html.span(
        class="github-checkout-arrow",
        @icons.icon(@icons.icon_arrow_up),
      )
    },
  )
}

///|
fn avatar_view(url : String?) -> @html.Html {
  // A background layer leaves the GitHub glyph visible if the image cannot
  // load, without a broken-image marker or imperative DOM error handler.
  @html.span(
    class="github-avatar",
    attrs=@html.Attrs::build().aria_hidden("true"),
    [
      @icons.icon(@icons.icon_github),
      match url {
        Some(url) =>
          @html.span(
            class="github-avatar-image",
            attrs=@html.Attrs::build().style(
              "background-image",
              "url(\"\{url.replace_all(old="\"", new="%22")}\")",
            ),
            ([] : Array[@html.Html]),
          )
        None => @html.nothing
      },
    ],
  )
}

///|
fn inventory(
  locale~ : @i18n.Locale,
  state : State,
  emit : @cmd.Emit[Msg],
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  let repository = match
    (state.all_open.reply, state.created.reply, state.issues.reply) {
    (Some(reply), _, _) | (_, Some(reply), _) | (_, _, Some(reply)) =>
      Some(reply)
    _ => None
  }
  let pulls : Array[@html.Html] = [
    disclosure(
      ui(locale, PullRequestsLabel),
      state.pulls_expanded,
      emit(TogglePulls),
      section=true,
    ),
  ]
  if state.pulls_expanded {
    let groups : Array[@html.Html] = []
    for
      (kind, label) in [
        (@protocol.CreatedByMe, ui(locale, CreatedByMeLabel)),
        (@protocol.AllOpen, ui(locale, AllOpenLabel)),
      ] {
      let group = state.group(kind)
      groups.push(
        @html.div(class="github-group", [
          disclosure(label, group.expanded, emit(Toggle(kind))),
          if group.expanded {
            list_view(locale~, state, kind, emit, open_link)
          } else {
            @html.nothing
          },
        ]),
      )
    }
    pulls.push(@html.div(class="github-section-body", groups))
  }
  @html.div(class="github-inventory", [
    @html.div(class="github-toolbar", [
      @html.span(
        class="github-repository",
        title=state.scope.map(owner => owner.cwd).unwrap_or("GitHub"),
        repository.map(reply => reply.repository).unwrap_or("GitHub"),
      ),
      @html.button(
        class="tab-action",
        title=ui(locale, RefreshGithub),
        attrs=@html.Attrs::build().aria_label(ui(locale, RefreshGithub)),
        disabled=!state.active || state.scope is None,
        on_click=emit(Refresh),
        @icons.icon(@icons.icon_sync),
      ),
    ]),
    if state.scope is None {
      @html.div(class="github-empty", ui(locale, OpenRepositoryHint))
    } else if !state.active {
      @html.div(class="github-empty", ui(locale, ConnectGithubHint))
    } else {
      @html.nothing
    },
    @html.div(
      class="github-section github-pulls" +
        (if state.pulls_expanded { " expanded" } else { "" }),
      pulls,
    ),
    @html.div(
      class="github-section github-issues" +
        (if state.issues.expanded { " expanded" } else { "" }),
      [
        disclosure(
          ui(locale, IssuesLabel),
          state.issues.expanded,
          emit(Toggle(@protocol.Issues)),
          section=true,
        ),
        if state.issues.expanded {
          @html.div(class="github-section-body", [
            list_view(locale~, state, @protocol.Issues, emit, open_link),
          ])
        } else {
          @html.nothing
        },
      ],
    ),
  ])
}

///|
pub fn panel(
  locale~ : @i18n.Locale,
  state : State,
  emit : @cmd.Emit[Msg],
  open_link : (String) -> @cmd.Cmd,
) -> @html.Html {
  // Replacing the selected PR resets its scroll position. Refreshing the same
  // PR keeps the keyed subtree, so a reader does not lose their place.
  let detail_key = state.detail
    .map(detail => detail.item.url)
    .unwrap_or("placeholder")
  let details : Map[String, @html.Html] = Map([
    (detail_key, detail_view(locale~, state, emit, open_link)),
  ])
  @html.div(class="github-panel", [
    @html.div(class="github-detail-host", details),
    inventory(locale~, state, emit, open_link),
  ])
}
