///|
/// One device the account can switch the page to.
#derive(Debug, Eq)
pub(all) struct DeviceChoice {
  id : String
  name : String
}

///|
#derive(Debug, Eq)
pub(all) struct Account {
  login : String
  avatar : String
  busy : Bool
  notice : String?
  page : Page
  // The account's online devices, in roster order; the selector offers these.
  online_devices : Array[DeviceChoice]
  // This browser's Web Push row; None hides it (still checking, or the relay
  // has no push).
  notifications : Notifications?
}

///|
/// Where the page works.
#derive(Debug, Eq)
pub(all) enum Page {
  CloudPage
  // `name` is None while the roster does not list the device.
  DevicePage(id~ : String, name~ : String?)
}

///|
/// What the account area says about this browser's push notifications.
#derive(Debug, Eq)
pub(all) enum Notifications {
  // No Push API here; on iOS that means the page is not installed.
  NeedsInstall
  Off(error~ : String?)
  Busy
  On(error~ : String?)
  // Denied for this site; only the browser's settings can undo it.
  Blocked
}

///|
/// The action-menu target of the footer's device selector.
const DeviceSelectorTarget : String = "sidebar:device-selector"

///|
/// The id of the grab strip the sidebar renders on its right edge. The
/// shell's sidebar resize (desktop/frontend/sidebar_resize.mbt) finds the
/// handle by this id to install its drag listeners.
pub const ResizeHandleId : String = "sidebar-resize-handle"

///|
/// Chats are Cloud conversations; Work conversations belong to registered projects.
#derive(Debug, Eq)
pub(all) enum Mode {
  ChatMode
  WorkMode
}

///|
/// The complete plain input of the left sidebar component. Commands are kept
/// in `Actions`, so this value remains comparable and can drive incremental
/// Rabbita branches without embedding emitters in application data.
#derive(Debug, Eq)
pub(all) struct Input {
  search : @session_search.Model
  locale : @i18n.Locale
  mode : Mode
  has_host : Bool
  // Whether the Work list has a device to show: the page's own, or any
  // device a browser page holds before it works on one.
  work_available : Bool
  // A host's library or a signed-in Cloud account's.
  skills_available : Bool
  notices : Array[String]
  chat_sections : Array[@section.Input]
  work_sections : Array[@section.Input]
  update_label : String?
  update_enabled : Bool
  schedules_active : Bool
  skills_active : Bool
  settings_active : Bool
  // Whether the page's relay publishes the apps the footer offers to
  // download, signed in or not.
  downloads : Bool
  account : Account?
}

///|
fn Input::sections(self : Input, mode : Mode) -> Array[@section.Input] {
  match mode {
    ChatMode => self.chat_sections
    WorkMode => self.work_sections
  }
}

///|
pub(all) struct Actions {
  update : @cmd.Cmd
  search : @cmd.Emit[@session_search.Msg]
  open_schedules : @cmd.Cmd
  open_skills : @cmd.Cmd
  open_settings : @cmd.Cmd
  refresh_account : @cmd.Cmd
  sign_out : @cmd.Cmd
  open_downloads : @cmd.Cmd
  turn_on_notifications : @cmd.Cmd
  turn_off_notifications : @cmd.Cmd
  // Switch the page to the device with this id, or to Cloud with None.
  select_device : (String?) -> @cmd.Cmd
  select_mode : (Mode) -> @cmd.Cmd
  section : @section.Actions
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
  None
}

///|
/// The selector's menu: Cloud, then online devices only, the page's own place
/// checked and inert. With no device online, one inert row says so.
fn Account::device_menu(
  self : Account,
  select_device : (String?) -> @cmd.Cmd,
  locale~ : @i18n.Locale,
) -> @action_menu.Definition {
  fn choice(label : String, current : Bool, command : @cmd.Cmd) {
    @action_menu.Entry::Action({
      label,
      title: label,
      icon: if current {
        Some(@icons.icon(@icons.icon_check))
      } else {
        None
      },
      enabled: !current,
      destructive: false,
      command,
    })
  }
  let cloud = @messages.text(locale, Cloud)
  let entries = [
    choice(cloud, self.page is CloudPage, select_device(None)),
    Separator,
  ]
  for device in self.online_devices {
    let current = self.page is DevicePage(id~, ..) && id == device.id
    entries.push(choice(device.name, current, select_device(Some(device.id))))
  }
  if self.online_devices.is_empty() {
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
  _source : String,
  input : @rabbita.Val[@section.Input],
  locale : @rabbita.Val[@i18n.Locale],
  search : @rabbita.Val[@conversation.Search],
) -> @rabbita.Val[@section.RenderedSection] {
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
#derive(Eq)
priv struct RenderedList {
  tools : @html.Html
  content : @html.Html
}

///|
fn Actions::list_component(
  self : Actions,
  input : @rabbita.Val[Input],
  mode : Mode,
) -> @rabbita.Val[RenderedList] {
  // Locale and search presentation travel with the keyed section data.
  // The hidden list keeps its catalog and receives no search presentation.
  let section_inputs = input.map(input => {
    let results = input.search_results()
    let query = if input.mode == mode { input.search.query() } else { "" }
    let search : @conversation.Search = {
      query,
      selected: if query.is_blank() {
        None
      } else {
        results.get(input.search.selected(results.length()))
      },
    }
    @vector.from_array(
      input.sections(mode).map(section => (input.locale, section, search)),
    )
  })
  let section_rows = section_inputs.assoc_by(
    (id, section) => {
      self.section_component(
        id,
        section.map(pair => pair.1),
        section.map(pair => pair.0),
        section.map(parts => parts.2),
      )
    },
    // One list merges same-source sections across devices, so the source
    // keys a section's component: its id's channel follows the device its
    // actions name without remounting the projects inside it.
    by=section => section.1.id().source(),
  )
  input.map2(section_rows, (input, section_rows) => {
    let hidden = input.mode != mode
    // Sections key their own content rows; retain their DOM on reordering.
    let rows : Map[String, @html.Html] = Map([])
    let tools : Array[@html.Html] = []
    for section in section_rows {
      tools.push(section.tools)
      for row in section.rows {
        rows[row.0] = row.1
      }
    }
    if !hidden &&
      !input.search.query().is_blank() &&
      input.search_results().is_empty() {
      rows["search:empty"] = @html.div(
        class="conversation-row placeholder",
        @html.span(
          class="sidebar-label sidebar-notice",
          @messages.text(input.locale, NoMatchingConversations),
        ),
      )
    }
    {
      tools: @html.div(class="sidebar-list-tools", hidden~, tools),
      content: @html.div(class="sidebar-section sessions", hidden~, rows),
    }
  })
}

///|
/// Both lists stay mounted: selecting a mode only hides the other list,
/// preserving its keyed Project and Conversation component state.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
) -> @rabbita.Val[@html.Html] {
  let chat_list = actions.list_component(input, ChatMode)
  let work_list = actions.list_component(input, WorkMode)
  let overlay = @action_menu.component(input, (input, target) => {
    input.menu_definition(target, actions)
  })
  input.map4(chat_list, work_list, overlay, (
    input,
    chat_list,
    work_list,
    overlay,
  ) => {
    let rows : Map[String, @html.Html] = Map([])
    for index, notice in input.notices {
      rows["notice:\{index}"] = @html.div(
        class="conversation-row placeholder",
        [@html.span(class="sidebar-label sidebar-notice", title=notice, notice)],
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
    if input.skills_available {
      footer.push(
        @html.button(
          class=if input.skills_active {
            "sidebar-button active"
          } else {
            "sidebar-button"
          },
          on_click=actions.open_skills,
          [
            @html.span(
              class="sidebar-icon",
              @icons.icon(@icons.icon_extensions),
            ),
            @html.span(
              class="sidebar-label",
              @messages.text(input.locale, Skills),
            ),
          ],
        ),
      )
    }
    if input.has_host {
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
    }
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
    if input.downloads {
      footer.push(
        @html.button(class="sidebar-button", on_click=actions.open_downloads, [
          @html.span(class="sidebar-icon", @icons.icon(@icons.icon_arrow_down)),
          @html.span(
            class="sidebar-label",
            @messages.text(input.locale, DownloadApps),
          ),
        ]),
      )
    }
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
        @rui.popover_trigger(
          id=DeviceSelectorTarget + ":actions-trigger",
          target_id=DeviceSelectorTarget + ":actions-content",
          class="sidebar-button device-selector",
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
              match account.page {
                CloudPage => @messages.text(input.locale, Cloud)
                DevicePage(name=Some(name), ..) => name
                DevicePage(name=None, ..) => choose
              },
            ),
            @html.span(
              class="sidebar-icon device-selector-chevron",
              @icons.icon(@icons.icon_chevron_down),
            ),
          ],
        ),
      )
      if account.notifications is Some(notifications) {
        footer.push(notifications_row(input.locale, notifications, actions))
        if notifications is (Off(error=Some(error)) | On(error=Some(error))) {
          footer.push(@html.div(class="console-notice", error))
        }
      }
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
            if input.work_available {
              actions.mode_option(input, WorkMode, ModeWork, @icons.icon_code)
            } else {
              @html.nothing
            },
          ],
        ),
      ]),
      @html.div(class="sidebar-tools", [
        input.search.view(input.locale, actions.search),
        chat_list.tools,
        work_list.tools,
      ]),
      @html.div(class="sidebar-main", [
        if input.notices.is_empty() {
          @html.nothing
        } else {
          @html.div(class="sidebar-section", rows)
        },
        chat_list.content,
        work_list.content,
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
/// The account area's push row: what this browser receives, and the
/// actions its state allows.
fn notifications_row(
  locale : @i18n.Locale,
  notifications : Notifications,
  actions : Actions,
) -> @html.Html {
  // Every button passes `disabled`, so a slot that turns into another
  // button never keeps a stale property.
  let action = (label : @messages.Message, on_click : @cmd.Cmd, disabled : Bool) => {
    @html.button(
      class="console-account-action",
      type_="button",
      disabled~,
      on_click~,
      @messages.text(locale, label),
    )
  }
  let (status, buttons) : (@messages.Message, Array[@html.Html]) = match
    notifications {
    NeedsInstall => (NotificationsNeedInstall, [])
    Off(..) =>
      (NotificationsOff, [action(TurnOn, actions.turn_on_notifications, false)])
    Busy | On(..) =>
      (
        NotificationsOn,
        [action(TurnOff, actions.turn_off_notifications, notifications is Busy)],
      )
    Blocked => (NotificationsBlocked, [])
  }
  @html.div(
    class="console-account console-notifications",
    [
      @html.span(class="console-login", @messages.text(locale, status)),
      ..buttons,
    ],
  )
}

///|
pub extend Notifications with Debug::{to_repr}

///|
pub extend Notifications with Eq::{equal, not_equal}

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

///|
pub extend Page with Debug::{to_repr}

///|
pub extend Page with Eq::{equal, not_equal}
