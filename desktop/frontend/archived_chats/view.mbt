// The Settings page that lists archived conversations, grouped like the
// sidebar: chats first, then one group per project. Rows are the same
// conversation inputs the sidebar draws, so their identities route through
// the root's sidebar dispatcher; this package only lays them out.

///|
/// Which list a group of archived rows belongs to.
#derive(Eq, Debug)
pub(all) enum GroupKind {
  Chats
  // The project's name, prefixed with its host's when the desktop window
  // lists a remote project beside local ones.
  Project(String)
  // Rows whose project could not be resolved, such as a Codex task whose
  // worktree is gone.
  Other
}

///|
#derive(Eq, Debug)
pub(all) struct Group {
  kind : GroupKind
  rows : Array[@conversation.Input]
}

///|
pub(all) struct Actions {
  back : @cmd.Cmd
  open : (@conversation.Id) -> @cmd.Cmd
  restore : (@conversation.Id) -> @cmd.Cmd
  delete : (@conversation.Id) -> @cmd.Cmd
}

///|
/// Every archived row the groups hold.
pub fn count(groups : Array[Group]) -> Int32 {
  groups.fold(init=0, (total, group) => total + group.rows.length())
}

///|
/// The groups narrowed to rows whose title or group name contains `query`
/// (case-insensitive). A blank query keeps everything; groups left without
/// rows disappear.
pub fn filtered(
  locale : @i18n.Locale,
  groups : Array[Group],
  query : String,
) -> Array[Group] {
  let query = query.trim().to_lower()
  if query.is_empty() {
    return groups
  }
  groups.filter_map(group => {
    let rows = if group_label(locale, group.kind).to_lower().contains(query) {
      group.rows
    } else {
      group.rows.filter(row => row.label.to_lower().contains(query))
    }
    if rows.is_empty() {
      None
    } else {
      Some({ ..group, rows, })
    }
  })
}

///|
fn group_label(locale : @i18n.Locale, kind : GroupKind) -> String {
  match kind {
    Chats => text(locale, Chats)
    Project(label) => label
    Other => text(locale, Other)
  }
}

///|
fn row_view(
  locale : @i18n.Locale,
  row : @conversation.Input,
  actions : Actions,
) -> @html.Html {
  let badge = match row.id.source() {
    CloudArchived => Some(text(locale, CloudBadge))
    CodexArchived => Some(text(locale, CodexBadge))
    _ => None
  }
  let name : Array[@html.Html] = [
    @html.span(class="archived-chat-title", row.label),
  ]
  if badge is Some(badge) {
    name.push(@html.span(class="pill", badge))
  }
  let title = if row.openable {
    @html.button(
      class="archived-chat-open",
      attrs=@html.Attrs::build().data_set("action", "open"),
      type_="button",
      title=row.title,
      on_click=(actions.open)(row.id),
      name,
    )
  } else {
    @html.span(class="archived-chat-open", title=row.title, name)
  }
  // A Cloud conversation that is still generating cannot be moved yet; the
  // sidebar row has always disabled its actions for the same reason.
  let enabled = !(row.id.source() is CloudArchived && row.running)
  let buttons : Array[@html.Html] = []
  for action in row.trailing {
    match action {
      Restore(title~) =>
        buttons.push(
          @html.button(
            class="button secondary compact",
            type_="button",
            title~,
            disabled=!enabled,
            attrs=@html.Attrs::build().data_set("action", "restore"),
            on_click=(actions.restore)(row.id),
            text(locale, Restore),
          ),
        )
      Delete(title~) =>
        buttons.push(
          @html.button(
            class="button danger compact",
            type_="button",
            title~,
            disabled=!enabled,
            attrs=@html.Attrs::build().data_set("action", "delete"),
            on_click=(actions.delete)(row.id),
            text(locale, Delete),
          ),
        )
      Archive(..) => ()
    }
  }
  @html.div(id="archived-chat:" + row.id.key(), class="archived-chat-row", [
    title,
    @html.div(class="archived-chat-actions", buttons),
  ])
}

///|
/// The page body: a way back to Settings, the filter, then each group as a
/// settings card.
fn view(
  locale : @i18n.Locale,
  groups : Array[Group],
  state : State,
  emit : @cmd.Emit[Msg],
  actions : Actions,
) -> @html.Html {
  let content : Array[@html.Html] = [
    @html.div(class="settings-header", [
      @html.button(
        class="button compact archived-chats-back",
        type_="button",
        on_click=actions.back,
        [
          @icons.icon(@icons.icon_arrow_left),
          @html.text(text(locale, BackToSettings)),
        ],
      ),
      @html.div(class="settings-subtitle", text(locale, Description)),
    ]),
  ]
  if groups.is_empty() {
    content.push(@html.div(class="archived-chats-empty", text(locale, Empty)))
    return @page_shell.body(class="archived-chats-page", content)
  }
  content.push(
    @html.div(
      class="archived-chats-search",
      attrs=@html.Attrs::build().data_set("focus-owner", ""),
      [
        @icons.icon(@icons.icon_search),
        @html.input(
          input_type=@html.InputType::Search,
          value=state.query,
          placeholder=text(locale, Filter),
          on_input=emit.map(query => QueryChanged(query)),
          attrs=@html.Attrs::build()
            .aria_label(text(locale, Filter))
            .data_set("focus-target", ""),
        ),
      ],
    ),
  )
  let shown = filtered(locale, groups, state.query)
  if shown.is_empty() {
    content.push(
      @html.div(class="archived-chats-empty", text(locale, NoMatches)),
    )
  }
  for group in shown {
    let icon = match group.kind {
      Project(_) => @icons.icon_folder
      Chats | Other => @icons.icon_archive
    }
    content.push(
      @settings.group(
        icon,
        group_label(locale, group.kind),
        group.rows.map(row => row_view(locale, row, actions)),
      ),
    )
  }
  @page_shell.body(class="archived-chats-page", content)
}

///|
pub extend GroupKind with Debug::{to_repr}

///|
pub extend GroupKind with Eq::{equal, not_equal}

///|
pub extend Group with Debug::{to_repr}

///|
pub extend Group with Eq::{equal, not_equal}
