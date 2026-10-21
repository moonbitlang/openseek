///|
/// One device the account can switch the page to.
pub(all) struct DeviceChoice {
  id : String
  name : String
} derive(Debug, Eq)

///|
pub(all) struct Account {
  login : String
  avatar : String
  busy : Bool
  notice : String?
  // The page's device, when it has one; a Cloud page has none.
  device : DeviceChoice?
  // The account's online devices, in roster order; the selector offers these.
  online_devices : Array[DeviceChoice]
} derive(Debug, Eq)

///|
/// The action-menu target of the footer's device selector.
const DeviceSelectorTarget : String = "sidebar:device-selector"

///|
/// The id of the grab strip the sidebar renders on its right edge. The
/// shell's sidebar resize (desktop/frontend/sidebar_resize.mbt) finds the
/// handle by this id to install its drag listeners.
pub const ResizeHandleId : String = "sidebar-resize-handle"

///|
/// Which conversations the list shows. Chats live in host-managed scratch
/// workspaces; Work conversations belong to a project the user registered.
pub(all) enum Mode {
  ChatMode
  WorkMode
} derive(Debug, Eq)

///|
/// The complete plain input of the left sidebar component. Commands are kept
/// in `Actions`, so this value remains comparable and can drive incremental
/// Rabbita branches without embedding emitters in application data.
pub(all) struct Input {
  search : @session_search.Model
  locale : @i18n.Locale
  mode : Mode
  notices : Array[String]
  sections : Array[@section.Input]
  update_label : String?
  update_enabled : Bool
  schedules_active : Bool
  skills_active : Bool
  settings_active : Bool
  account : Account?
} derive(Debug, Eq)

///|
pub(all) struct Actions {
  update : @cmd.Cmd
  search : @cmd.Emit[@session_search.Msg]
  open_schedules : @cmd.Cmd
  open_skills : @cmd.Cmd
  open_settings : @cmd.Cmd
  refresh_account : @cmd.Cmd
  sign_out : @cmd.Cmd
  // Switch the page to the device with this id.
  select_device : (String) -> @cmd.Cmd
  select_mode : (Mode) -> @cmd.Cmd
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
  if target == DeviceSelectorTarget && self.account is Some(account) {
    return Some(account.device_menu(actions.select_device, locale=self.locale))
  }
  if self.find_project(target) is Some(project) {
    return Some({
      label: @messages.text(self.locale, WorkspaceActions),
      entries: project.menu_entries(actions.section.project, locale=self.locale),
    })
  }
  guard self.find_conversation(target) is Some(row) &&
    row.menu_entries(locale=self.locale, actions.section.conversation)
    is Some(entries) else {
    return None
  }
  Some({ label: @messages.text(self.locale, ConversationActions), entries, })
}

///|
/// The selector's menu: online devices only, the page's own one checked and
/// inert. With none online, one inert row says so.
fn Account::device_menu(
  self : Account,
  select_device : (String) -> @cmd.Cmd,
  locale~ : @i18n.Locale,
) -> @action_menu.Definition {
  let entries : Array[@action_menu.Entry] = self.online_devices.map(choice => {
    let current = self.device.map(device => device.id) == Some(choice.id)
    Action({
      label: choice.name,
      title: choice.name,
      icon: if current {
        Some(@icons.icon(@icons.icon_check))
      } else {
        None
      },
      enabled: !current,
      destructive: false,
      command: select_device(choice.id),
    })
  })
  if entries.is_empty() {
    let label = @messages.text(locale, NoDevicesOnline)
    entries.push(
      Action({
        label,
        title: label,
        icon: None,
        enabled: false,
        destructive: false,
        command: @cmd.none,
      }),
    )
  }
  { label: @messages.text(locale, ChooseDevice), entries, }
}

///|
fn Actions::section_component(
  self : Actions,
  _id : @section.Id,
  input : @rabbita.Val[@section.Input],
  locale : @rabbita.Val[@i18n.Locale],
  search : @rabbita.Val[@conversation.Search],
) -> @rabbita.Val[Array[(String, @html.Html)]] {
  @section.component(input, self.section, locale, search)
}

///|
/// One segment of the header's Chat/Work switch. The glyph carries no text,
/// so the mode name is both the tooltip and the accessible name.
fn Actions::mode_option(
  self : Actions,
  input : Input,
  mode : Mode,
  label : @messages.Message,
  image : () -> @html.Html,
) -> @html.Html {
  let title = @messages.text(input.locale, label)
  let selected = input.mode == mode
  @html.button(
    class=if selected {
      "sidebar-mode-option active"
    } else {
      "sidebar-mode-option"
    },
    type_="button",
    title~,
    attrs=@html.Attrs::build()
      .aria_label(title)
      .aria_pressed(selected.to_string()),
    on_click=(self.select_mode)(mode),
    @icons.icon(image),
  )
}

///|
/// The whole left column is one Rabbita component. Its section vector is
/// associated by stable section identity; each Section then associates its
/// own Project and Conversation children in their packages.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
) -> @rabbita.Val[@html.Html] {
  // Locale and search presentation travel with the keyed section data.
  // Separate global dependencies can render a child before its input updates.
  let section_inputs = input.map(input => {
    let results = input.search_results()
    let search : @conversation.Search = {
      query: input.search.query(),
      selected: if input.search.query().is_blank() {
        None
      } else {
        results.get(input.search.selected(results.length()))
      },
    }
    @vector.from_array(
      input.sections.map(section => (input.locale, section, search)),
    )
  })
  let section_rows = section_inputs.assoc_by(
    (id, section) => {
      actions.section_component(
        id,
        section.map(pair => pair.1),
        section.map(pair => pair.0),
        section.map(parts => parts.2),
      )
    },
    by=section => section.1.id(),
  )
  let overlay = @action_menu.component(input, (input, target) => {
    input.menu_definition(target, actions)
  })
  input.map3(section_rows, overlay, (input, section_rows, overlay) => {
    // Key each section in the outer container; sections key their own content
    // rows so insertions and reordering keep each row's DOM and event slots.
    let rows : Map[String, @html.Html] = Map([])
    for index, notice in input.notices {
      rows["notice:\{index}"] = @html.div(
        class="conversation-row placeholder",
        [@html.span(class="sidebar-label sidebar-notice", title=notice, notice)],
      )
    }
    for group in section_rows {
      for row in group {
        rows[row.0] = row.1
      }
    }
    if !input.search.query().is_blank() && input.search_results().is_empty() {
      rows["search:empty"] = @html.div(
        class="conversation-row placeholder",
        @html.span(
          class="sidebar-label sidebar-notice",
          @messages.text(input.locale, NoMatchingConversations),
        ),
      )
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
          @html.span(
            class="sidebar-label",
            @messages.text(input.locale, Skills),
          ),
        ],
      ),
    )
    footer.push(
      @html.button(
        class=if input.schedules_active {
          "sidebar-button active"
        } else {
          "sidebar-button"
        },
        on_click=actions.open_schedules,
        [
          @html.span(class="sidebar-icon", @icons.icon(@icons.icon_clockface)),
          @html.span(
            class="sidebar-label",
            @messages.text(input.locale, Scheduled),
          ),
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
          @html.span(
            class="sidebar-label",
            @messages.text(input.locale, Settings),
          ),
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
          title=@messages.text(input.locale, RefreshDevices),
          on_click=actions.refresh_account,
          @messages.text(input.locale, Refresh),
        ),
      )
      account_row.push(
        @html.button(
          class="console-account-action",
          disabled=account.busy,
          on_click=actions.sign_out,
          @messages.text(input.locale, SignOut),
        ),
      )
      let choose = @messages.text(input.locale, ChooseDevice)
      footer.push(
        @html.button(
          class="sidebar-button device-selector",
          type_="button",
          title=choose,
          // The footer sits at the bottom edge, so the menu opens upward.
          attrs=@action_menu.button_attrs(
            DeviceSelectorTarget,
            align_right=false,
            open_upward=true,
          ).aria_label(choose),
          [
            @html.span(class="sidebar-icon", @icons.icon(@icons.icon_vm)),
            @html.span(
              class="sidebar-label",
              match account.device {
                Some(device) => device.name
                None => choose
              },
            ),
            @html.span(
              class="sidebar-icon device-selector-chevron",
              @icons.icon(@icons.icon_chevron_down),
            ),
          ],
        ),
      )
      footer.push(@html.div(class="console-account", account_row))
      if account.notice is Some(notice) {
        footer.push(@html.div(class="console-notice", notice))
      }
    }
    @html.aside([
      // The leading edge stays clear for the shell-owned fixed toggle and
      // native controls; the mode switch sits at the trailing edge.
      @html.div(class="sidebar-header", [
        @html.div(
          class="sidebar-mode",
          attrs=@html.Attrs::build()
            .role("group")
            .aria_label(@messages.text(input.locale, ModeGroup)),
          [
            actions.mode_option(
              input,
              ChatMode,
              ModeChat,
              @icons.icon_comment_discussion,
            ),
            actions.mode_option(input, WorkMode, ModeWork, @icons.icon_code),
          ],
        ),
      ]),
      input.search.view(input.locale, actions.search),
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
pub extend Mode with Debug::{to_repr}

///|
pub extend Mode with Eq::{equal, not_equal}

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend DeviceChoice with Debug::{to_repr}

///|
pub extend DeviceChoice with Eq::{equal, not_equal}
