///|
/// The pull requests and branches the conversation works on: a one-line
/// summary for the folded card and the rows for the unfolded one, drawn by
/// the package that owns the attached list. The rows are drawn only while the
/// card is open.
pub(all) struct Changes {
  summary : String
  rows : () -> Array[@html.Html]
}

///|
/// A side panel the background tasks card can show: whether it is on screen,
/// and the command that shows it, or hides it when it is.
pub(all) struct PanelLink {
  shown : Bool
  toggle : @cmd.Cmd
}

///|
/// The background tasks card's input: what runs, and the panels that list it
/// in full.
pub(all) struct Background {
  tasks : BackgroundTasks
  /// Now, in milliseconds since the epoch, for the commands' elapsed time.
  now_ms : Double
  jobs : PanelLink
  workflows : PanelLink
}

///|
/// The titlebar control that shows and hides the overview. One control owns
/// both states, whether the overview is a rail or a panel over the
/// conversation.
pub fn toggle(
  locale~ : @i18n.Locale = English,
  open : Bool,
  on_click : @cmd.Cmd,
) -> @html.Html {
  let label = if open {
    text(locale, HideOverview)
  } else {
    text(locale, ShowOverview)
  }
  @html.button(
    class=if open {
      "panel-toggle conv-overview-toggle active"
    } else {
      "panel-toggle conv-overview-toggle"
    },
    type_="button",
    title=label,
    attrs=@html.Attrs::build().aria_label(label).aria_pressed(open.to_string()),
    on_click~,
    @icons.icon(@icons.icon_preview),
  )
}

///|
/// The overview's cards. The stylesheet places it: a rail beside the
/// conversation when the main pane has room for both, otherwise a panel over
/// the transcript's right edge.
pub fn view(
  locale~ : @i18n.Locale = English,
  state : State,
  changes~ : Changes?,
  background? : Background,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  @html.aside(
    class="conv-overview",
    attrs=@html.Attrs::build().aria_label(text(locale, Overview)),
    [
      // With no checkout to describe and nothing attached, there is no card.
      if changes is Some(changes) {
        card(
          locale,
          Changes,
          state,
          emit,
          summary=changes.summary,
          changes.rows,
        )
      } else {
        @html.nothing
      },
      // Last, so the card coming and going never moves the others.
      if background is Some(background) {
        background_card(locale, state, background, emit)
      } else {
        @html.nothing
      },
    ],
  )
}

///|
/// The background tasks card. Folded, it says how many tasks run; unfolded,
/// what each is. Its button shows the panel that lists them in full, and
/// hides it again like the titlebar's panel toggles: Jobs, unless every
/// running task is a subagent only a workflow knows about.
fn background_card(
  locale : @i18n.Locale,
  state : State,
  background : Background,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let tasks = background.tasks
  let (link, hide, show) = if tasks.in_jobs {
    (background.jobs, HideJobs, OpenJobs)
  } else {
    (background.workflows, HideWorkflows, OpenWorkflows)
  }
  let label = text(locale, if link.shown { hide } else { show })
  card(
    locale,
    BackgroundTasks,
    state,
    emit,
    summary=running_text(locale, tasks.running()),
    aside=[
      @html.button(
        class=if link.shown {
          "conv-overview-mini active"
        } else {
          "conv-overview-mini"
        },
        type_="button",
        title=label,
        attrs=@html.Attrs::build()
          .aria_label(label)
          .aria_pressed(link.shown.to_string()),
        on_click=link.toggle,
        @icons.icon(@icons.icon_layout_sidebar_right),
      ),
    ],
    () => {
      [
        ..tasks.jobs.map(job => {
          row(@icons.icon_terminal, title=job.command, [
            @html.span(
              class="conv-overview-row-text conv-overview-command",
              job.command,
            ),
            @html.span(
              class="conv-overview-row-sub",
              @labels.duration(
                background.now_ms - job.started_at_ms.to_double(),
              ),
            ),
          ])
        }),
        ..tasks.subagents.map(title => {
          row(@icons.icon_robot, title~, [
            @html.span(class="conv-overview-row-text", title),
          ])
        }),
        if tasks.finished > 0 {
          row(@icons.icon_check, [
            @html.span(class="conv-overview-row-text", [
              @html.span(
                class="conv-overview-row-sub",
                finished_text(locale, tasks.finished, tasks.more_finished),
              ),
            ]),
          ])
        } else {
          @html.nothing
        },
      ]
    },
  )
}

///|
/// One card: its title folds and unfolds it, the summary stands in for the
/// rows while it is folded, the aside stays visible either way, and the rows
/// come last so folding never moves the title's button.
fn card(
  locale : @i18n.Locale,
  section : Section,
  state : State,
  emit : @cmd.Emit[Msg],
  summary? : String,
  aside~ : Array[@html.Html] = [],
  rows : () -> Array[@html.Html],
) -> @html.Html {
  let open = state.is_open(section)
  let title = match section {
    Changes => text(locale, ChangesTitle)
    BackgroundTasks => text(locale, BackgroundTasksTitle)
  }
  @html.div(class="conv-overview-card", [
    @html.div(class="conv-overview-card-head", [
      @html.button(
        class=if open {
          "conv-overview-card-title open"
        } else {
          "conv-overview-card-title"
        },
        type_="button",
        attrs=@html.Attrs::build().aria_expanded(open.to_string()),
        on_click=emit(Toggled(section)),
        [@html.span(title), @icons.icon(@icons.icon_chevron_down)],
      ),
      @html.div(
        class="conv-overview-card-aside",
        [
          if !open && summary is Some(summary) {
            @html.span(class="conv-overview-summary", summary)
          } else {
            @html.nothing
          },
          ..aside,
        ],
      ),
    ]),
    if open {
      @html.div(class="conv-overview-card-rows", rows())
    } else {
      @html.nothing
    },
  ])
}

///|
fn row(
  image : () -> @html.Html,
  title? : String,
  children : Array[@html.Html],
) -> @html.Html {
  @html.div(class="conv-overview-row", title?, [@icons.icon(image), ..children])
}
