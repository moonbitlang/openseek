// Workspace settings is a stable native dialog. The root owns its target
// and persistence; this component owns the three select menus.

///|
/// The workspace settings values the dialog renders. `Unloaded` means the
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
/// The workspace being configured, independent of the conversation underneath.
pub(all) struct Target {
  channel : @interop.ChannelId
  workspace : @common.Uri
} derive(Eq)

///|
pub(all) struct Input {
  target : Target?
  settings : SettingsSnapshot
  error : String?
} derive(Eq)

///|
pub fn Input::inactive() -> Input {
  { target: None, settings: Unloaded, error: None, }
}

///|
const DialogId = "workspace-settings-dialog"

///|
pub fn show() -> @cmd.Cmd {
  @dialog.show(DialogId)
}

///|
pub fn close() -> @cmd.Cmd {
  @dialog.close(DialogId)
}

///|
/// Parent-owned persistence messages this component re-emits. Captured at
/// construction and never stored in the component Model, so a workspace
/// switch under a mounted component cannot leak an old identity.
pub(all) struct Actions {
  dismiss : @cmd.Cmd
  choose_default_mode : (@interop.ChannelId, @common.Uri, String) -> @cmd.Cmd
  choose_submodules : (@interop.ChannelId, @common.Uri, String) -> @cmd.Cmd
  choose_submodule_timeout : (@interop.ChannelId, @common.Uri, String) -> @cmd.Cmd
}

///|
/// The dialog's three select menus. Identity is local to the component: the
/// root model's `select_menu` keeps the composer and Settings-page menus,
/// this one keeps the Workspace Settings menus.
priv enum Menu {
  DefaultMode
  Submodules
  Timeout
} derive(Eq)

///|
priv struct Model {
  key : Target?
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
  let key = input.target
  let self = if self.key == key { self } else { { key, menu: None, } }
  match msg {
    ToggleMenu(menu) =>
      (
        {
          ..self,
          menu: if self.menu is Some(current) && current == menu {
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
  target : Target,
  input : Input,
  state : Model,
  emit : @cmd.Emit[Msg],
  id~ : String,
  options~ : Array[@select_control.Option],
  selected~ : String,
  aria_label~ : String,
  change~ : (@interop.ChannelId, @common.Uri, String) -> @cmd.Cmd,
) -> @select_control.Control {
  let change = (value : String) => {
    @cmd.batch([
      emit(CloseMenu),
      change(target.channel, target.workspace, value),
    ])
  }
  @select_control.Control::{
    id,
    groups: [{ label: aria_label, options, }],
    selected,
    disabled: input.settings is Unloaded,
    open: state.menu is Some(current) &&
    current == menu &&
    state.key == input.target,
    toggle: emit(ToggleMenu(menu)),
    dismiss: emit(CloseMenu),
    change,
    title: aria_label,
    aria_label,
    presentation: Setting,
  }
}

///|
fn dialog_contents(
  locale? : @i18n.Locale = English,
  input : Input,
  state : Model,
  emit : @cmd.Emit[Msg],
  actions : Actions,
) -> Array[@html.Html] {
  guard input.target is Some(target) else { return [] }
  let workspace = target.workspace
  // Unloaded settings render with display-only placeholders; the controls
  // stay disabled so these values are never acted on.
  let (worktree_mode, checkout_submodules, submodule_checkout_timeout_seconds) = match
    input.settings {
    Loaded(
      worktree_mode~,
      checkout_submodules~,
      submodule_checkout_timeout_seconds~
    ) =>
      (worktree_mode, checkout_submodules, submodule_checkout_timeout_seconds)
    Unloaded => (false, true, 10)
  }
  let conversation_rows : Array[@html.Html] = [
    @settings.row(
      ui(locale, NewChatsLabel),
      [
        setting_select(
          DefaultMode,
          target,
          input,
          state,
          emit,
          id="workspace-default-mode-select",
          options=[
            { value: "local", label: ui(locale, LocalLabel), },
            { value: "worktree", label: ui(locale, WorktreeLabel), },
          ],
          selected=if worktree_mode { "worktree" } else { "local" },
          aria_label=ui(locale, NewChatsLabel),
          change=actions.choose_default_mode,
        ).render(),
      ],
      desc=ui(locale, NewChatsDescription),
    ),
  ]
  let worktree_rows : Array[@html.Html] = [
    @settings.row(
      ui(locale, SubmodulesLabel),
      [
        setting_select(
          Submodules,
          target,
          input,
          state,
          emit,
          id="workspace-submodules-select",
          options=[
            { value: "checkout", label: ui(locale, InitializeLabel), },
            { value: "skip", label: ui(locale, LeaveUninitialized), },
          ],
          selected=if checkout_submodules { "checkout" } else { "skip" },
          aria_label=ui(locale, WorktreeSubmodules),
          change=actions.choose_submodules,
        ).render(),
      ],
      desc=ui(locale, SubmodulesDescription),
    ),
    @settings.row(
      ui(locale, CheckoutTimeout),
      [
        setting_select(
          Timeout,
          target,
          input,
          state,
          emit,
          id="workspace-submodule-timeout-select",
          options=[
            { value: "5", label: ui(locale, FiveSeconds), },
            { value: "10", label: ui(locale, TenSeconds), },
            { value: "30", label: ui(locale, ThirtySeconds), },
            { value: "60", label: ui(locale, SixtySeconds), },
          ],
          selected=submodule_checkout_timeout_seconds.to_string(),
          aria_label=ui(locale, SubmoduleTimeout),
          change=actions.choose_submodule_timeout,
        ).render(),
      ],
      desc=ui(locale, TimeoutDescription),
    ),
  ]
  let dismiss = @cmd.batch([emit(CloseMenu), actions.dismiss])
  [
    @html.div(class="workspace-settings-header", [
      @html.h2(
        id="workspace-settings-title",
        class="modal-title",
        ui(locale, WorkspaceSettingsLabel),
      ),
      @html.button(
        class="workspace-settings-close",
        type_="button",
        title=ui(locale, CloseLabel),
        attrs=@html.Attrs::build().aria_label(ui(locale, CloseLabel)),
        on_click=dismiss,
        @icons.icon(@icons.icon_close),
      ),
    ]),
    @html.div(
      id="workspace-settings-description",
      class="workspace-settings-identity",
      [
        @html.div(class="workspace-settings-name", @resource.label(workspace)),
        @html.div(class="settings-subtitle", workspace.path),
      ],
    ),
    @html.div(class="settings", [
      @settings.group(
        @icons.icon_worktree,
        ui(locale, ConversationsLabel),
        conversation_rows,
      ),
      @settings.group(
        @icons.icon_worktree,
        ui(locale, WorktreesLabel),
        worktree_rows,
      ),
    ]),
    if input.error is Some(message) {
      @html.div(
        class="workspace-settings-error",
        attrs=@html.Attrs::build().role("alert"),
        message,
      )
    } else {
      @html.nothing
    },
  ]
}

///|
/// Keep the dialog mounted so incremental renders preserve showModal state.
/// The native modal contains keyboard focus and restores it when closed.
pub fn component(
  locale : @rabbita.Val[@i18n.Locale],
  input : @rabbita.Val[Input],
  actions : Actions,
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, input) => ({ key: input.target, menu: None, }, @cmd.none),
    update=(state, input, msg, emit) => state.update(input, msg, emit),
    subscriptions=(state, input, emit) => {
      // Gated on the dialog identity too: an input change without a message
      // (workspace detach or device removal) unloads the click-away listener.
      // The dialog's close event clears any remaining local menu state.
      if state.menu is Some(_) && state.key == input.target {
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
  state.view3(input, locale, (state, input, locale) => {
    @html.dialog(
      id=DialogId,
      class="modal workspace-settings-dialog",
      closedby="any",
      on_cancel=@cmd.batch([emit(CloseMenu), actions.dismiss]),
      on_close=_ => emit(CloseMenu),
      attrs=@html.Attrs::build()
        .role("dialog")
        .aria_labelledby("workspace-settings-title")
        .aria_describedby("workspace-settings-description"),
      dialog_contents(locale~, input, state, emit, actions),
    )
  })
}

///|
/// The component's exported `Eq` methods are promoted explicitly, keeping
/// the package's public interface stable across toolchain upgrades.
pub extend Input with Eq::{equal, not_equal}

///|
pub extend SettingsSnapshot with Eq::{equal, not_equal}

///|
pub extend Target with Eq::{equal, not_equal}
