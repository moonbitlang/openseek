// The Workspace Settings page as a self-contained rabbita component. The
// root model keeps the authoritative settings mirror — the composer chip,
// new-chat launch mode, and worktree creation all read the same rows — so
// this component owns only page-local UI state: which of the three select
// menus is open. It renders from a projected `Input` and re-emits the
// page's persistence choices through `Actions`.

///|
/// The workspace settings values the page renders. `Unloaded` means the
/// first authoritative read for this workspace has not landed yet; the
/// controls render disabled with display-only placeholder values until a
/// `Loaded` snapshot arrives.
pub(all) enum SettingsSnapshot {
  Unloaded
  Loaded(
    worktree_mode~ : Bool,
    checkout_submodules~ : Bool,
    submodule_checkout_timeout_seconds~ : Int
  )
} derive(Eq)

///|
/// The workspace identity the page renders for. `Inactive` carries no
/// workspace at all, so an inactive input can never be mistaken for a real
/// workspace page: the component is mounted for the app's lifetime, and
/// while another screen is active the view renders nothing.
pub(all) enum WorkspacePage {
  Active(channel~ : @interop.ChannelId, workspace~ : @common.Uri)
  Inactive
} derive(Eq)

///|
/// What the component needs to render one workspace's settings page. The
/// value is projected from the root model once per app frame; it changes
/// whenever the mirror row, the focused workspace, or the active screen
/// does.
pub(all) struct Input {
  page : WorkspacePage
  settings : SettingsSnapshot
} derive(Eq)

///|
/// The inert input the root projects while another screen is active: it
/// carries no workspace identity, and the view renders nothing for it.
pub fn Input::inactive() -> Input {
  { page: Inactive, settings: Unloaded, }
}

///|
/// Parent-owned persistence messages this component re-emits. Captured at
/// construction and never stored in the component Model, so a workspace
/// switch under a mounted component cannot leak an old identity.
pub(all) struct Actions {
  choose_default_mode : (@interop.ChannelId, @common.Uri, String) -> @cmd.Cmd
  choose_submodules : (@interop.ChannelId, @common.Uri, String) -> @cmd.Cmd
  choose_submodule_timeout : (@interop.ChannelId, @common.Uri, String) -> @cmd.Cmd
}

///|
/// The page's three select menus. Identity is local to the component: the
/// root model's `select_menu` keeps the composer and Settings-page menus,
/// this one keeps the Workspace Settings menus.
priv enum Menu {
  DefaultMode
  Submodules
  Timeout
} derive(Eq)

///|
priv struct Model {
  /// The page identity the menu state belongs to, so a menu opened for one
  /// workspace is neither shown nor toggled for another. A local invariant
  /// rather than a mechanism the page leans on — see the note on `open` in
  /// `setting_select`.
  key : WorkspacePage
  menu : Menu?
} derive(Eq)

///|
priv enum Msg {
  ToggleMenu(Menu)
  CloseMenu
}

///|
fn Model::update(
  self : Model,
  input : Input,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let key = input.page
  let self = if self.key == key { self } else { { key, menu: None, } }
  match msg {
    ToggleMenu(menu) =>
      (
        {
          ..self,
          menu: if self.menu == Some(menu) {
            None
          } else {
            Some(menu)
          },
        },
        @cmd.none,
      )
    CloseMenu => ({ ..self, menu: None, }, @cmd.none)
  }
}

///|
/// Build one full-width settings select from the shared custom control,
/// bound to this component's local menu state. Choosing a value closes the
/// menu immediately and hands the choice to the root-owned action, which
/// applies the optimistic mirror update and persists it.
fn setting_select(
  menu : Menu,
  input : Input,
  state : Model,
  emit : @cmd.Emit[Msg],
  id~ : String,
  options~ : Array[@select_control.Option],
  selected~ : String,
  aria_label~ : String,
  change~ : (@interop.ChannelId, @common.Uri, String) -> @cmd.Cmd,
) -> @select_control.Control {
  // The change command names the workspace it came from. `Inactive` never
  // renders, so the fallback arm is unreachable in practice.
  let change = match input.page {
    Active(channel~, workspace~) =>
      (value : String) => {
        @cmd.batch([emit(CloseMenu), change(channel, workspace, value)])
      }
    Inactive => (_ : String) => @cmd.none
  }
  @select_control.Control::{
    id,
    groups: [{ label: aria_label, options, }],
    selected,
    disabled: input.settings is Unloaded,
    // A menu is only shown for the page it was opened under. Nothing
    // observed depends on this today: opening a menu focuses its trigger,
    // and the shared select dismisses on blur, so a page change takes the
    // trigger out of the DOM and closes the menu on the way. This keeps the
    // view honest if that ever stops holding.
    open: state.menu == Some(menu) && state.key == input.page,
    toggle: emit(ToggleMenu(menu)),
    dismiss: emit(CloseMenu),
    change,
    title: aria_label,
    aria_label,
    presentation: Setting,
  }
}

///|
fn page_view(
  input : Input,
  state : Model,
  emit : @cmd.Emit[Msg],
  actions : Actions,
) -> @html.Html {
  match input.page {
    Inactive => @html.nothing
    Active(workspace~, channel~) => {
      let _ = channel
      // Unloaded pages render with display-only placeholders; the controls
      // stay disabled so these values are never acted on.
      let (
        worktree_mode,
        checkout_submodules,
        submodule_checkout_timeout_seconds,
      ) = match input.settings {
        Loaded(
          worktree_mode~,
          checkout_submodules~,
          submodule_checkout_timeout_seconds~
        ) =>
          (
            worktree_mode, checkout_submodules, submodule_checkout_timeout_seconds,
          )
        Unloaded => (false, true, 10)
      }
      let conversation_rows : Array[@html.Html] = [
        @settings.row(
          "New chats",
          [
            setting_select(
              DefaultMode,
              input,
              state,
              emit,
              id="workspace-default-mode-select",
              options=[
                { value: "local", label: "Local", },
                { value: "worktree", label: "Worktree", },
              ],
              selected=if worktree_mode { "worktree" } else { "local" },
              aria_label="New chats",
              change=actions.choose_default_mode,
            ).render(),
          ],
          desc="Where a new chat starts: the workspace itself, or a fresh git worktree bound to that chat. The composer's chip still changes a single chat.",
        ),
      ]
      let worktree_rows : Array[@html.Html] = [
        @settings.row(
          "Submodules",
          [
            setting_select(
              Submodules,
              input,
              state,
              emit,
              id="workspace-submodules-select",
              options=[
                { value: "checkout", label: "Initialize", },
                { value: "skip", label: "Leave uninitialized", },
              ],
              selected=if checkout_submodules { "checkout" } else { "skip" },
              aria_label="Submodules in worktrees",
              change=actions.choose_submodules,
            ).render(),
          ],
          desc="For new or repaired worktrees in this workspace, mirror the top-level submodules already initialized in its main checkout.",
        ),
        @settings.row(
          "Checkout timeout",
          [
            setting_select(
              Timeout,
              input,
              state,
              emit,
              id="workspace-submodule-timeout-select",
              options=[
                { value: "5", label: "5 seconds", },
                { value: "10", label: "10 seconds", },
                { value: "30", label: "30 seconds", },
                { value: "60", label: "60 seconds", },
              ],
              selected=submodule_checkout_timeout_seconds.to_string(),
              aria_label="Submodule checkout timeout",
              change=actions.choose_submodule_timeout,
            ).render(),
          ],
          desc="Stop initializing submodules if Git has not finished within this time.",
        ),
      ]
      @html.section(class="settings-page", [
        @html.div(class="settings-page-inner", [
          @html.div(class="settings-header", [
            @html.div(class="page-eyebrow", "Workspace"),
            @html.h1(@resource.label(workspace)),
            @html.div(class="settings-subtitle", workspace.path),
          ]),
          @html.div(class="settings", [
            @settings.group(
              @icons.icon_worktree, "Conversations", conversation_rows,
            ),
            @settings.group(@icons.icon_worktree, "Worktrees", worktree_rows),
          ]),
        ]),
      ])
    }
  }
}

///|
/// Build the workspace-settings page state and return its independently
/// updating Html. Mounted once for the app's lifetime; while another screen
/// is active the projected input is inactive and the view renders nothing.
pub fn component(
  input : @rabbita.Val[Input],
  actions : Actions,
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, input) => ({ key: input.page, menu: None, }, @cmd.none),
    update=(state, input, msg, emit) => state.update(input, msg, emit),
    subscriptions=(state, input, emit) => {
      // Gated on the page identity too: an input change without a message
      // (workspace detach, screen switch) unloads the click-away listener
      // even though the menu state itself resets on the next update.
      if state.menu is Some(_) && state.key == input.page {
        @dismiss.on_outside_click(
          "workspace-settings-select-dismiss",
          trigger=".custom-select-button",
          emit.map(_ => CloseMenu),
        )
      } else {
        @sub.none
      }
    },
  )
  state.view2(input, (state, input) => page_view(input, state, emit, actions))
}

///|
/// The component's exported `Eq` methods are promoted explicitly, keeping
/// the package's public interface stable across toolchain upgrades.
pub extend Input with Eq::{equal, not_equal}

///|
pub extend SettingsSnapshot with Eq::{equal, not_equal}

///|
pub extend WorkspacePage with Eq::{equal, not_equal}
