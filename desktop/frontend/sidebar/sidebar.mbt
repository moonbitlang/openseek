///|
#derive(Debug, Eq)
pub(all) struct Account {
  login : String
  avatar : String
}

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
  open_account : @cmd.Cmd
  open_downloads : @cmd.Cmd
  select_mode : (Mode) -> @cmd.Cmd
  section : @section.Actions
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
  input.map3(chat_list, work_list, (input, chat_list, work_list) => {
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
    footer.push(
      @html.button(
        class="sidebar-button console-account",
        on_click=actions.open_account,
        [
          @html.span(
            class="sidebar-icon",
            if input.account is Some(account) && !account.avatar.is_empty() {
              @html.img(class="console-avatar", src=account.avatar, alt="")
            } else {
              @icons.icon(@icons.icon_account)
            },
          ),
          @html.span(
            class="sidebar-label console-login",
            if input.account is Some(account) {
              account.login
            } else {
              @settings.text(input.locale, SignIn)
            },
          ),
        ],
      ),
    )
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
