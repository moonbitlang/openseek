// Port of the registration surface of
// `vscode/src/vs/editor/browser/editorExtensions.ts` (vscode submodule
// checked-in source): the editor-contribution
// registry (`EditorContributionRegistry`, `registerEditorContribution`,
// `codeEditorContributions.ts`'s per-editor instantiation) and the
// command + keybinding registration (`Command.register` →
// `KeybindingsRegistry.registerKeybindingRule` + `CommandsRegistry`,
// `EditorCommand.runEditorCommand`).
//
// Structural deviation: contribution glue stays with the root-owned `CodeEditorWidget`
// state, and there is no DI/services collection to port, so the registry
// inverts *dispatch and lifecycle* (who instantiates contributions, who routes
// commands/keys) — not file placement. The `*_host.mbt` files stay here as the
// contribution ctors this registry instantiates, preconditions are live
// predicates over the `CodeEditorWidget` instead of `ContextKeyExpression`s, and
// registration happens in one initializer (`build_editor_registry`) because
// MoonBit has no import-time side effects.

///|
/// `EditorContributionInstantiation` (`editorExtensions.ts:34-65`). The
/// readonly viewer has no idle scheduler, interaction tracker, or on-demand
/// `getContribution`, so every mode instantiates eagerly at `CodeEditorWidget`
/// construction; the deferred modes exist so a registration can carry its
/// source's declared mode (content hover is `BeforeFirstInteraction`,
/// comments `AfterFirstRender`).
priv enum EditorContributionInstantiation {
  Eager
  AfterFirstRender
  BeforeFirstInteraction
  Eventually
  Lazy
}

///|
/// Retain the complete upstream policy vocabulary even though this readonly
/// viewer currently registers no contribution in the lazy mode.
let _unused_contribution_modes : Array[EditorContributionInstantiation] = [Lazy]

///|
/// The concrete live contribution state stored in the per-CodeEditorWidget registry.
/// The product registry is closed and statically populated, so adding another
/// contribution deliberately requires exhaustive construction, typed-access,
/// and disposal updates here.
priv enum EditorContributionInstance {
  ContentHover(ContentHoverContributionState)
  Folding(@folding_browser.FoldingController)
  AgentFeedbackInput(
    @agent_feedback_browser.AgentFeedbackEditorInputContribution
  )
  AgentFeedbackWidget(
    @agent_feedback_browser.AgentFeedbackEditorWidgetContribution
  )
  QuickDiff(QuickDiffContributionState)
  MarkdownComments(MarkdownCommentContributionState)
  ContextMenu(ContextMenuContributionState)
  Definition(DefinitionContributionState)
  References(ReferencesContributionState)
}

///|
/// CodeEditorWidget-lifetime content-hover state. The controller, lazily mounted widget,
/// logical widget cache, and host scheduling policy form one contribution
/// owner and survive model replacement together.
priv struct ContentHoverContributionState {
  controller : @hover_browser.ContentHoverController
  mut widget : @hover_browser.ContentHoverWidget?
  mut widget_view : @hover.HoverWidgetView?
  mut schedule_timeout : (() -> Unit, Int) -> @base_common.Disposable
  mut launch_async_task : (async () -> Unit noraise) -> Unit
}

///|
fn ContentHoverContributionState::ContentHoverContributionState() -> ContentHoverContributionState {
  {
    controller: ContentHoverController(),
    widget: None,
    widget_view: None,
    schedule_timeout: @base_browser.schedule_timeout,
    launch_async_task,
  }
}

///|
/// The contribution-behavior disposal phase intentionally leaves the retained
/// browser widget alive for the later root disposal slot.
fn ContentHoverContributionState::dispose_behavior(
  self : ContentHoverContributionState,
) -> Unit {
  self.controller.cancel_all_timers()
  self.controller.cancel_request()
}

///|
/// Releases the retained browser resource at the root hover-widget cleanup
/// slot, then clears its paired logical cache.
fn ContentHoverContributionState::dispose_retained_browser_resources(
  self : ContentHoverContributionState,
) -> Unit {
  match self.widget {
    Some(widget) => widget.dispose()
    None => ()
  }
  self.widget = None
  self.widget_view = None
}

///|
/// The quick-diff decorator's per-editor state. Its collection and all three
/// subscriptions are retained by the same central contribution entry rather
/// than captured by a lifecycle-only facade closure.
priv struct QuickDiffContributionState {
  collection : EditorDecorationsCollection
  listeners : Array[@base_common.Disposable]
}

///|
fn QuickDiffContributionState::QuickDiffContributionState(
  collection : EditorDecorationsCollection,
) -> QuickDiffContributionState {
  { collection, listeners: [], }
}

///|
/// Entry lifecycle keeps the temporary public `dispose` facade idempotent and
/// makes typed lookup unavailable after teardown. `ContributionDisposing`
/// remains readable so synchronous feature cleanup can use central accessors
/// while the complete map is still installed.
priv enum EditorContributionLifecycle {
  ContributionLive
  ContributionDisposing
  ContributionDisposed
} derive(Eq)

///|
/// One live row in Monaco `CodeEditorContributions._instances`. `listeners`
/// owns the root-package subscriptions for folding and agent feedback; hover
/// owns its cancellable work directly, while quick diff and Markdown comments
/// own subscriptions in their concrete contribution states.
priv struct EditorContributionEntry {
  instance : EditorContributionInstance
  listeners : Array[@base_common.Disposable]
  mut lifecycle : EditorContributionLifecycle
}

///|
fn EditorContributionEntry::EditorContributionEntry(
  instance : EditorContributionInstance,
) -> EditorContributionEntry {
  { instance, listeners: [], lifecycle: ContributionLive, }
}

///|
fn EditorContributionEntry::typed_lookup_available(
  self : EditorContributionEntry,
) -> Bool {
  self.lifecycle != ContributionDisposed
}

///|
/// Disposes every retained subscription in `listeners` and empties the list.
fn dispose_and_clear_listeners(
  listeners : Array[@base_common.Disposable],
) -> Unit {
  for listener in listeners {
    listener.dispose()
  }
  listeners.clear()
}

///|
/// Direct typed lifecycle dispatch. The complete CodeEditorWidget map remains installed
/// while every row tears down, so feature cleanup can still use typed central
/// accessors. The explicit lifecycle state rejects recursive/repeated teardown
/// and makes later typed lookup return `None` without removing the row before
/// the full ordered disposal pass finishes.
fn EditorContributionEntry::dispose(
  self : EditorContributionEntry,
  viewer : CodeEditorWidget,
) -> Unit {
  guard self.lifecycle == ContributionLive else { return }
  self.lifecycle = ContributionDisposing
  match self.instance {
    AgentFeedbackInput(_) => dispose_and_clear_listeners(self.listeners)
    AgentFeedbackWidget(controller) => {
      viewer.clear_agent_feedback_widgets_from(controller) |> ignore
      dispose_and_clear_listeners(self.listeners)
    }
    Folding(controller) => {
      controller.clear_local()
      dispose_and_clear_listeners(self.listeners)
    }
    ContentHover(state) => state.dispose_behavior()
    QuickDiff(state) => {
      state.collection.clear()
      dispose_and_clear_listeners(state.listeners)
    }
    MarkdownComments(state) => state.dispose(viewer)
    ContextMenu(state) => {
      state.dispose()
      dispose_and_clear_listeners(self.listeners)
    }
    Definition(state) => {
      state.dispose(viewer)
      dispose_and_clear_listeners(self.listeners)
    }
    References(state) => {
      state.dispose(viewer)
      dispose_and_clear_listeners(self.listeners)
    }
  }
  self.lifecycle = ContributionDisposed
}

///|
/// Wrapper lifecycle separates ordered contribution behavior disposal from
/// the later retained browser-resource cleanup. The sole instance map remains
/// allocated but is not lookuppable while disposal is between those phases.
priv enum EditorContributionsLifecycle {
  ContributionsLive
  ContributionsDisposing
  ContributionsDisposed
} derive(Eq)

///|
/// Monaco `CodeEditorContributions._instances`: the sole per-CodeEditorWidget concrete
/// contribution store and its two-phase disposal state.
priv struct EditorContributions {
  instances : Map[String, EditorContributionEntry]
  mut lifecycle : EditorContributionsLifecycle
}

///|
fn EditorContributions::EditorContributions() -> EditorContributions {
  { instances: Map([]), lifecycle: ContributionsLive, }
}

///|
/// Typed-access entry point. Individual rows stay readable during their own
/// synchronous behavior cleanup; after the complete behavior pass the wrapper
/// becomes non-lookuppable until retained-resource cleanup clears storage.
fn EditorContributions::lookup(
  self : EditorContributions,
  id : String,
) -> EditorContributionEntry? {
  guard self.lifecycle == ContributionsLive else { return None }
  match self.instances.get(id) {
    Some(entry) if entry.typed_lookup_available() => Some(entry)
    _ => None
  }
}

///|
/// Instantiates one description with the reviewed ordering: reject a duplicate
/// before construction side effects, install the actual row, then initialize
/// listeners through typed lookup of that installed row.
fn EditorContributions::instantiate(
  self : EditorContributions,
  description : EditorContributionDescription,
  viewer : CodeEditorWidget,
) -> Unit {
  guard self.lifecycle == ContributionsLive else { return }
  if self.instances.contains(description.id) {
    return
  }
  // Every mode instantiates eagerly (no idle/interaction schedulers exist);
  // the declared mode is carried for source fidelity only.
  match description.instantiation {
    Eager | AfterFirstRender | BeforeFirstInteraction | Eventually | Lazy => ()
  }
  let entry = EditorContributionEntry((description.ctor)(viewer))
  self.instances.set(description.id, entry)
  for listener in (description.initialize)(viewer) {
    entry.listeners.push(listener)
  }
}

///|
/// Runs the ordered contribution-behavior phase while the wrapper remains
/// live. Each entry's `ContributionDisposing` state is therefore readable by
/// its own synchronous cleanup. Only after the full pass does lookup retire.
fn EditorContributions::dispose_behavior(
  self : EditorContributions,
  viewer : CodeEditorWidget,
) -> Unit {
  guard self.lifecycle == ContributionsLive else { return }
  for _, contribution in self.instances {
    contribution.dispose(viewer)
  }
  self.lifecycle = ContributionsDisposing
}

///|
/// Finishes the later retained browser-resource phase, then clears the sole
/// storage map and permanently retires the wrapper.
fn EditorContributions::dispose_retained_browser_resources(
  self : EditorContributions,
) -> Unit {
  guard self.lifecycle == ContributionsDisposing else { return }
  match self.instances.get("editor.contrib.contentHover") {
    Some(contribution) =>
      match contribution.instance {
        ContentHover(state) => state.dispose_retained_browser_resources()
        _ => ()
      }
    None => ()
  }
  self.instances.clear()
  self.lifecycle = ContributionsDisposed
}

///|
/// `IEditorContributionDescription` (`editorExtensions.ts:68-72`): id + ctor
/// closure, instantiated once per `CodeEditorWidget`. Construction and initialization
/// are split so the concrete entry can be installed before any synchronous
/// typed lookup made by the initializer.
priv struct EditorContributionDescription {
  id : String
  kind : CodeEditorContributionKind
  instantiation : EditorContributionInstantiation
  ctor : (CodeEditorWidget) -> EditorContributionInstance
  initialize : (CodeEditorWidget) -> Array[@base_common.Disposable]
}

///|
fn EditorContributionDescription::EditorContributionDescription(
  id : String,
  kind : CodeEditorContributionKind,
  instantiation : EditorContributionInstantiation,
  ctor : (CodeEditorWidget) -> EditorContributionInstance,
  initialize : (CodeEditorWidget) -> Array[@base_common.Disposable],
) -> EditorContributionDescription {
  { id, kind, instantiation, ctor, initialize, }
}

///|
/// The closed editor-context menu id supported by the command registry.
priv enum EditorMenuId {
  EditorContext
} derive(Eq)

///|
/// One command placement in a menu group. The live command precondition is
/// ANDed into visibility when the menu is resolved.
priv struct EditorMenuPlacement {
  menu_id : EditorMenuId
  group : String
  order : Double
}

///|
/// One already-filtered sortable menu candidate.
priv struct ResolvedEditorMenuCandidate {
  group : String
  order : Double
  registration_order : Int
  entry : @contextmenu_browser.ContextMenuEntry
}

///|
/// `EditorCommand` (`editorExtensions.ts:104-183,270+`) reduced: id/title,
/// the precondition (`ContextKeyExpression` → live predicate over the viewer),
/// menu/keybinding display metadata, and the run body (`runEditorCommand`
/// bound to the owning editor).
priv struct EditorCommand {
  id : String
  title : String
  menu_keybinding_label : String?
  menu_placements : Array[EditorMenuPlacement]
  registration_order : Int
  precondition : (CodeEditorWidget) -> Bool
  run : (CodeEditorWidget) -> Unit
}

///|
/// `CoreEditorCommand<T>` (`coreCommands.ts:38-49`) with its abstract member
/// represented by a stored closure. `precondition=None` is the source's
/// `undefined`; keybinding `kbExpr` remains a separate rule predicate.
priv struct CoreEditorCommand {
  id : String
  precondition : ((CodeEditorWidget) -> Bool)?
  default_args : CursorCoreCommandArgs
  run_core_editor_command : (
    CodeEditorWidget,
    @view_model.ViewModel,
    CursorCoreCommandArgs,
  ) -> Bool
}

///|
/// The heterogeneous command table stores ordinary contribution commands and
/// typed cursor core commands under their real IDs.
priv enum RegisteredEditorCommand {
  RegisteredEditor(EditorCommand)
  RegisteredCore(CoreEditorCommand)
}

///|
/// One keybinding rule (`KeybindingsRegistry.registerKeybindingRule` row):
/// a `KeyboardEvent.key` value plus the three modifier axes the viewer's
/// bindings use (`KeyMod.Alt`, `KeyMod.CtrlCmd`, `KeyMod.Shift`). The
/// rule's `when` is the command's precondition (`Command.register` ANDs
/// `kbExpr` with the precondition; the viewer's rules carry no extra
/// `kbExpr`). Chords match exactly: a rule with `alt=false` does not fire
/// while Alt is held. Monaco matches layout-independent key codes; `key` is
/// layout-transformed, so a Shift rule for a punctuation key registers both
/// the base and the shifted character (synthetic events carry the base,
/// hardware events the shifted one).
priv struct KeybindingRule {
  key : String
  alt : Bool
  ctrl_cmd : Bool
  shift : Bool
  command_id : String
  when : (CodeEditorWidget) -> Bool
}

///|
/// The process-wide registry singleton
/// (`EditorContributionRegistry.INSTANCE`).
priv struct EditorContributionRegistry {
  contributions : Array[EditorContributionDescription]
  commands : Map[String, RegisteredEditorCommand]
  keybindings : Array[KeybindingRule]
}

///|
/// `registerEditorContribution` (`editorExtensions.ts:552-554`).
fn EditorContributionRegistry::register_editor_contribution(
  self : EditorContributionRegistry,
  id : String,
  kind : CodeEditorContributionKind,
  instantiation : EditorContributionInstantiation,
  ctor : (CodeEditorWidget) -> EditorContributionInstance,
  initialize : (CodeEditorWidget) -> Array[@base_common.Disposable],
) -> Unit {
  // Monaco's description registry is first-wins. Reject the later row before
  // its constructor, initializer, listener, or dispose path can exist.
  for description in self.contributions {
    if description.id == id {
      return
    }
  }
  self.contributions.push(
    EditorContributionDescription(id, kind, instantiation, ctor, initialize),
  )
}

///|
/// Adds one keybinding rule per `(key, alt, ctrl_cmd)` row, all sharing the
/// command id and live `when` predicate.
fn EditorContributionRegistry::push_keybinding_rules(
  self : EditorContributionRegistry,
  bindings : Array[(String, Bool, Bool)],
  command_id : String,
  when : (CodeEditorWidget) -> Bool,
  shift~ : Bool,
) -> Unit {
  for binding in bindings {
    let (key, alt, ctrl_cmd) = binding
    self.keybindings.push({ key, alt, ctrl_cmd, shift, command_id, when, })
  }
}

///|
/// `registerEditorCommand` + the keybinding rows of `Command.register`
/// (`editorExtensions.ts:528-531`, `:124-156`).
fn EditorContributionRegistry::register_editor_command(
  self : EditorContributionRegistry,
  id : String,
  precondition : (CodeEditorWidget) -> Bool,
  run : (CodeEditorWidget) -> Unit,
  keybindings : Array[(String, Bool, Bool)],
  shift_keybindings? : Array[(String, Bool, Bool)] = [],
  title? : String,
  menu_keybinding_label? : String,
  menu_placements? : Array[EditorMenuPlacement] = [],
) -> Unit {
  let command : EditorCommand = {
    id,
    title: title.unwrap_or(id),
    menu_keybinding_label,
    menu_placements,
    registration_order: self.commands.length(),
    precondition,
    run,
  }
  self.commands.set(command.id, RegisteredEditor(command))
  self.push_keybinding_rules(keybindings, id, precondition, shift=false)
  self.push_keybinding_rules(shift_keybindings, id, precondition, shift=true)
}

///|
/// Resolves live command preconditions. Separators are inserted only between
/// nonempty groups.
fn EditorContributionRegistry::resolve_editor_menu(
  self : EditorContributionRegistry,
  viewer : CodeEditorWidget,
  menu_id : EditorMenuId,
) -> Array[@contextmenu_browser.ContextMenuEntry] {
  let candidates : Array[ResolvedEditorMenuCandidate] = []
  for _, registered in self.commands {
    match registered {
      RegisteredEditor(command) if (command.precondition)(viewer) =>
        for placement in command.menu_placements {
          if placement.menu_id == menu_id {
            candidates.push({
              group: placement.group,
              order: placement.order,
              registration_order: command.registration_order,
              entry: ContextMenuAction(
                id=command.id,
                label=command.title,
                keybinding_label=command.menu_keybinding_label,
              ),
            })
          }
        }
      _ => ()
    }
  }
  candidates.sort_by(compare_resolved_editor_menu_candidate)
  let result : Array[@contextmenu_browser.ContextMenuEntry] = []
  let mut previous_group : String? = None
  for candidate in candidates {
    match previous_group {
      Some(group) if group != candidate.group =>
        result.push(ContextMenuSeparator)
      _ => ()
    }
    result.push(candidate.entry)
    previous_group = Some(candidate.group)
  }
  result
}

///|
fn compare_resolved_editor_menu_candidate(
  left : ResolvedEditorMenuCandidate,
  right : ResolvedEditorMenuCandidate,
) -> Int {
  let group_order = @base_common.compare(left.group, right.group)
  if group_order != 0 {
    group_order
  } else if left.order < right.order {
    -1
  } else if left.order > right.order {
    1
  } else {
    left.registration_order - right.registration_order
  }
}

///|
/// `registerEditorCommand` for one source-shaped cursor core command. Command
/// preconditions and keybinding context are intentionally independent: the
/// scoped commands have undefined preconditions while their 16 primary keys
/// retain the viewer's live text-input/model gate.
fn EditorContributionRegistry::register_core_editor_command(
  self : EditorContributionRegistry,
  command : CoreEditorCommand,
  keybinding_when : (CodeEditorWidget) -> Bool,
  keybindings : Array[(String, Bool, Bool)],
  shift_keybindings? : Array[(String, Bool, Bool)] = [],
) -> Unit {
  self.commands.set(command.id, RegisteredCore(command))
  self.push_keybinding_rules(
    keybindings,
    command.id,
    keybinding_when,
    shift=false,
  )
  self.push_keybinding_rules(
    shift_keybindings,
    command.id,
    keybinding_when,
    shift=true,
  )
}

///|
/// `CoreEditorCommand.runEditorCommand`: resolve the active view model, return
/// without one, and pass the logical empty-object fallback to the abstract
/// core member.
fn CoreEditorCommand::run_editor_command(
  self : CoreEditorCommand,
  viewer : CodeEditorWidget,
  args? : CursorCoreCommandArgs,
) -> Bool {
  guard viewer.is_code_presentation() else { return false }
  match self.precondition {
    Some(precondition) if !precondition(viewer) => return false
    _ => ()
  }
  guard viewer.get_view_model() is Some(view_model) else { return false }
  (self.run_core_editor_command)(
    viewer,
    view_model,
    args.unwrap_or(self.default_args),
  )
}

///|
/// Direct `runCoreEditorCommand` routing used by `ViewController`, which
/// already owns the active view model. The command is still resolved from the
/// process-wide registration table by its source ID.
fn EditorContributionRegistry::run_core_editor_command(
  self : EditorContributionRegistry,
  viewer : CodeEditorWidget,
  view_model : @view_model.ViewModel,
  id : String,
  args? : CursorCoreCommandArgs,
) -> Bool {
  guard viewer.is_code_presentation() else { return false }
  match self.commands.get(id) {
    Some(RegisteredCore(command)) => {
      match command.precondition {
        Some(precondition) if !precondition(viewer) => return false
        _ => ()
      }
      (command.run_core_editor_command)(
        viewer,
        view_model,
        args.unwrap_or(command.default_args),
      )
    }
    _ => false
  }
}

///|
/// Full editor-command routing for callers that do not already hold the view
/// model (for example the registered keyboard resolver).
fn EditorContributionRegistry::run_editor_command(
  self : EditorContributionRegistry,
  viewer : CodeEditorWidget,
  id : String,
  args? : CursorCoreCommandArgs,
) -> Bool {
  match self.commands.get(id) {
    Some(RegisteredEditor(command)) =>
      if (command.precondition)(viewer) {
        (command.run)(viewer)
        true
      } else {
        false
      }
    Some(RegisteredCore(command)) => command.run_editor_command(viewer, args?)
    None => false
  }
}

///|
/// Per-editor instantiation (`codeEditorContributions.ts` over
/// `codeEditorWidget.ts:344`): every registered contribution is constructed
/// for this viewer, in registration order (= the hand-wiring construction
/// order the registry replaced), keyed by id like the source's `_instances`
/// map. Instances live until `CodeEditorWidget::dispose`; `set_model` does not
/// re-create them, matching the source.
fn EditorContributionRegistry::instantiate_enabled(
  self : EditorContributionRegistry,
  viewer : CodeEditorWidget,
  descriptors : CodeEditorContributionDescriptors,
) -> Unit {
  for description in self.contributions {
    if descriptors.allows(description.kind) {
      viewer.contributions.instantiate(description, viewer)
    }
  }
}

///|
/// The keybinding-service resolution step, reduced: exact chord match, then
/// the command's precondition, then run. Returns whether a command handled
/// the key (callers `preventDefault` on `true`).
fn EditorContributionRegistry::dispatch_keybinding(
  self : EditorContributionRegistry,
  viewer : CodeEditorWidget,
  key : String,
  alt~ : Bool,
  ctrl_cmd~ : Bool,
  shift~ : Bool,
) -> Bool {
  guard viewer.is_code_presentation() else { return false }
  for rule in self.keybindings {
    if rule.key == key &&
      rule.alt == alt &&
      rule.ctrl_cmd == ctrl_cmd &&
      rule.shift == shift {
      if (rule.when)(viewer) && self.commands.contains(rule.command_id) {
        // A winning keybinding is handled even when its core movement reaches
        // a hard document boundary and reports no state change.
        self.run_editor_command(viewer, rule.command_id) |> ignore
        return true
      }
    }
  }
  false
}

///|
priv struct EditorRegistryHolder {
  mut registry : EditorContributionRegistry?
}

///|
/// Backing cell for the singleton: built on first use rather than in a
/// global initializer — the registered ctor/run closures reach `CodeEditorWidget`
/// methods whose dispatch consults the registry back, which MoonBit's
/// toplevel-definition cycle check would reject as an initializer cycle.
let editor_registry_holder : EditorRegistryHolder = { registry: None, }

///|
/// The singleton (`EditorContributionRegistry.INSTANCE`), populated once.
/// Registration preserves the existing agent-feedback/folding order. Markdown
/// comments follow folding so a model/content event commits the folding source
/// before comment zones reconcile against it; hover keeps its Monaco-shaped
/// contribution position. Cursor navigation commands register last: this is
/// the approved local substitute for Monaco's keybinding weights/context
/// expressions, so a focused hover's matching EditorContrib rule resolves
/// before the EditorCore cursor rule.
fn editor_registry() -> EditorContributionRegistry {
  match editor_registry_holder.registry {
    Some(registry) => registry
    None => {
      let registry : EditorContributionRegistry = {
        contributions: [],
        commands: Map([]),
        keybindings: [],
      }
      register_agent_feedback_contribution(registry)
      register_folding_contribution(registry)
      register_markdown_comment_contribution(registry)
      register_hover_contribution(registry)
      register_quick_diff_contribution(registry)
      register_context_menu_contribution(registry)
      register_definition_contribution(registry)
      register_references_contribution(registry)
      register_cursor_navigation_commands(registry)
      editor_registry_holder.registry = Some(registry)
      registry
    }
  }
}
