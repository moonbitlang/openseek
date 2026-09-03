///|
pub(all) struct Account {
  login : String
  avatar : String
  busy : Bool
  notice : String?
} derive(Debug, Eq)

///|
/// The id of the grab strip the sidebar renders on its right edge. The
/// shell's sidebar resize (desktop/frontend/sidebar_resize.mbt) finds the
/// handle by this id to install its drag listeners.
pub const ResizeHandleId : String = "sidebar-resize-handle"

///|
/// The complete plain input of the left sidebar component. Commands are kept
/// in `Actions`, so this value remains comparable and can drive incremental
/// Rabbita branches without embedding emitters in application data.
pub(all) struct Input {
  notices : Array[String]
  sections : Array[@section.Input]
  update_label : String?
  update_enabled : Bool
  skills_active : Bool
  settings_active : Bool
  account : Account?
} derive(Debug, Eq)

///|
pub(all) struct Actions {
  update : @cmd.Cmd
  open_skills : @cmd.Cmd
  open_settings : @cmd.Cmd
  refresh_account : @cmd.Cmd
  sign_out : @cmd.Cmd
  section : @section.Actions
}

///|
fn Input::find_project(self : Input, key : String) -> @project.Input? {
  for section in self.sections {
    for entry in section.entries {
      if entry is @section.Project(project) && project.id().key() == key {
        return Some(project)
      }
    }
  }
  None
}

///|
fn find_conversation_in(
  rows : Array[@conversation.Input],
  key : String,
) -> @conversation.Input? {
  for row in rows {
    if row.id().key() == key {
      return Some(row)
    }
    if find_conversation_in(row.children, key) is Some(found) {
      return Some(found)
    }
  }
  None
}

///|
fn Input::find_conversation(self : Input, key : String) -> @conversation.Input? {
  for section in self.sections {
    for entry in section.entries {
      match entry {
        @section.Project(project) =>
          if find_conversation_in(project.conversations, key) is Some(found) {
            return Some(found)
          }
        @section.Conversation(row) =>
          if find_conversation_in([row], key) is Some(found) {
            return Some(found)
          }
        @section.Placeholder(_) => ()
      }
    }
  }
  None
}

///|
fn Input::menu_definition(
  self : Input,
  target : String,
  actions : Actions,
) -> @action_menu.Definition? {
  if self.find_project(target) is Some(project) {
    return Some({
      label: "Workspace actions",
      entries: project.menu_entries(actions.section.project),
    })
  }
  guard self.find_conversation(target) is Some(row) &&
    row.menu_entries(actions.section.conversation) is Some(entries) else {
    return None
  }
  Some({ label: "Conversation actions", entries, })
}

///|
fn Actions::section_component(
  self : Actions,
  _id : @section.Id,
  input : @rabbita.Val[@section.Input],
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  @section.component(input, self.section)
}

///|
/// The whole left column is one Rabbita component. Its section vector is
/// associated by stable section identity; each Section then associates its
/// own Project and Conversation children in their packages.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
) -> @rabbita.Val[@html.Html] {
  let section_inputs = input.map(input => @vector.from_array(input.sections))
  let section_rows = section_inputs.assoc_by(
    (id, section) => actions.section_component(id, section),
    by=section => section.id(),
  )
  let overlay = @action_menu.component(input, (input, target) => {
    input.menu_definition(target, actions)
  })
  input.map3(section_rows, overlay, (input, section_rows, overlay) => {
    // One keyed container holds every row. Child components cache their
    // (key, node) output; keyed diffing re-pairs each cached node with its
    // own element when neighbours appear or leave, so a row's event slots
    // can never be re-bound to another row's element.
    let rows : Map[String, @html.Html] = Map([])
    for index, notice in input.notices {
      rows["notice:\{index}"] = @html.div(
        class="conversation-row placeholder",
        [@html.span(class="sidebar-label", notice)],
      )
    }
    for group in section_rows {
      for row in group {
        rows[row.0] = row.1
      }
    }
    let footer : Array[@html.Html] = []
    if input.update_label is Some(label) {
      footer.push(
        @html.button(
          class="sidebar-button primary",
          disabled=!input.update_enabled,
          on_click=actions.update,
          [
            @html.span(class="sidebar-icon", @icons.icon(@icons.icon_arrow_up)),
            @html.span(class="sidebar-label", label),
          ],
        ),
      )
    }
    footer.push(
      @html.button(
        class=if input.skills_active {
          "sidebar-button active"
        } else {
          "sidebar-button"
        },
        on_click=actions.open_skills,
        [
          @html.span(class="sidebar-icon", @icons.icon(@icons.icon_extensions)),
          @html.span(class="sidebar-label", "Skills"),
        ],
      ),
    )
    footer.push(
      @html.button(
        class=if input.settings_active {
          "sidebar-button active"
        } else {
          "sidebar-button"
        },
        on_click=actions.open_settings,
        [
          @html.span(
            class="sidebar-icon",
            @icons.icon(@icons.icon_settings_gear),
          ),
          @html.span(class="sidebar-label", "Settings"),
        ],
      ),
    )
    if input.account is Some(account) {
      let account_row : Array[@html.Html] = []
      if !account.avatar.is_empty() {
        account_row.push(
          @html.img(
            class="console-avatar",
            src=account.avatar,
            alt=account.login,
          ),
        )
      }
      account_row.push(@html.span(class="console-login", "@\{account.login}"))
      account_row.push(
        @html.button(
          class="console-account-action",
          disabled=account.busy,
          title="Refresh the device list",
          on_click=actions.refresh_account,
          "Refresh",
        ),
      )
      account_row.push(
        @html.button(
          class="console-account-action",
          disabled=account.busy,
          on_click=actions.sign_out,
          "Sign out",
        ),
      )
      footer.push(@html.div(class="console-account", account_row))
      if account.notice is Some(notice) {
        footer.push(@html.div(class="console-notice", notice))
      }
    }
    @html.aside([
      // Navigation actions live with the hierarchy they affect. This empty
      // strip exists only under the macOS overlay titlebar, where it protects
      // the traffic-light controls and remains a native drag region.
      @html.div(class="sidebar-header", @html.nothing),
      @html.div(class="sidebar-main", [
        @html.div(class="sidebar-section sessions", rows),
      ]),
      @html.div(class="sidebar-footer", footer),
      // The action-menu component owns open/replace/position/dismiss state;
      // the Sidebar contributes only stable targets and current definitions.
      overlay,
      // Grab strip for drag-to-resize; wired imperatively by the shell's
      // sidebar_resize. Absolutely positioned, so it is not a grid item and
      // never disturbs the aside's rows.
      @html.div(
        attrs=@html.Attrs::build()
          .id(ResizeHandleId)
          .class("sidebar-resize-handle"),
        ([] : Array[@html.Html]),
      ),
    ])
  })
}

///|
pub extend Account with Debug::{to_repr}

///|
pub extend Account with Eq::{equal, not_equal}

///|
pub extend Input with Debug::{to_repr}

///|
pub extend Input with Eq::{equal, not_equal}
