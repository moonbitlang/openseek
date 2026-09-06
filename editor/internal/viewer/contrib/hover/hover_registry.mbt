///|
/// Ordered registry of hover-participant factories. The MoonBit analog of
/// Monaco's `HoverParticipantRegistry` singleton in `hoverTypes.ts`: a free
/// global that the hover contribution populates, not state the viewer services
/// own. Each factory builds a participant from the editor-scoped services, like
/// Monaco's `instantiationService.createInstance(ctor, editor)`.
priv struct HoverParticipantRegistry {
  entries : Array[(HoverParticipantServices) -> HoverParticipantHandle]
}

///|
/// Creates an empty hover participant registry.
fn HoverParticipantRegistry::HoverParticipantRegistry() -> HoverParticipantRegistry {
  { entries: [], }
}

///|
/// Adds a hover participant factory to the registry.
fn HoverParticipantRegistry::register(
  self : HoverParticipantRegistry,
  factory : (HoverParticipantServices) -> HoverParticipantHandle,
) -> Unit {
  self.entries.push(factory)
}

///|
/// Builds one participant instance per registered factory for the given
/// services — Monaco's per-editor `_initializeHoverParticipants`.
fn HoverParticipantRegistry::build_all(
  self : HoverParticipantRegistry,
  services : HoverParticipantServices,
) -> Array[HoverParticipantHandle] {
  let participants = self.entries.map(factory => factory(services))
  // MoonBit's Array::sort_by is unstable, while JavaScript's source sort is
  // stable. Carry the registration index as an explicit tie-break so equal
  // ordinals retain registration order on every backend.
  sort_stably(participants, (left, right) => left.ordinal - right.ordinal)
}

///|
/// Process-wide hover participant registry, populated with the built-in
/// participants. The analog of Monaco's module-level `HoverParticipantRegistry`
/// plus the `HoverParticipantRegistry.register(...)` calls in
/// `hoverContribution.ts`.
let hover_participant_registry : HoverParticipantRegistry = make_default_hover_participant_registry()

///|
fn make_default_hover_participant_registry() -> HoverParticipantRegistry {
  let registry = HoverParticipantRegistry()
  register_default_hover_participants(registry)
  registry
}

///|
/// Registers the built-in marker and markdown hover participants
/// into `registry`, mirroring `hoverContribution.ts`. Registration lives here,
/// in the hover feature, never in the viewer services constructor.
fn register_default_hover_participants(
  registry : HoverParticipantRegistry,
) -> Unit {
  registry.register(services => {
    MarkerHoverParticipant(services.marker_decorations).hover_participant_handle()
  })
  registry.register(services => {
    MarkdownHoverParticipant(services.languages).hover_participant_handle()
  })
}
