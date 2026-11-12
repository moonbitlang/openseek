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
  // The relay's app download page; None where the page is not served by the
  // relay (the Local Console).
  downloads_url : String?
}

///|
/// Where the page works. A page keeps it for its lifetime.
#derive(Debug, Eq)
pub(all) enum Page {
  CloudPage
  // `name` is None while the roster does not list the device.
  DevicePage(id~ : String, name~ : String?)
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
  // A host's library or a signed-in Cloud account's.
  skills_available : Bool
  notices : Array[String]
  sections : Array[@section.Input]
  update_label : String?
  update_enabled : Bool
  schedules_active : Bool
  skills_active : Bool
  settings_active : Bool
  account : Account?
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
  _id : @section.Id,
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
      for row in group.rows {
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
      if account.downloads_url is Some(url) {
        footer.push(
          @html.a(
            class="sidebar-button",
            href=url,
            target=Blank,
            rel="noopener",
            [
              @html.span(
                class="sidebar-icon",
                @icons.icon(@icons.icon_arrow_down),
              ),
              @html.span(
                class="sidebar-label",
                @messages.text(input.locale, DownloadApps),
              ),
            ],
          ),
        )
      }
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
      footer.push(@html.div(class="console-account", account_row))
      if account.notice is Some(notice) {
        footer.push(@html.div(class="console-notice", notice))
      }
    }
    let tools : Array[@html.Html] = [
      input.search.view(input.locale, actions.search),
    ]
    for section in section_rows {
      tools.push(section.tools)
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
            if input.has_host {
              actions.mode_option(input, WorkMode, ModeWork, @icons.icon_code)
            } else {
              @html.nothing
            },
          ],
        ),
      ]),
      @html.div(class="sidebar-tools", tools),
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

///|
pub extend Page with Debug::{to_repr}

///|
pub extend Page with Eq::{equal, not_equal}
