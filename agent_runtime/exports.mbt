// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// Maximum number of runtime events kept in one `AgentRuntime` event bus.
///
/// The event bus is intentionally lossy. `emit_event` uses nonblocking
/// `try_put`; when the bus is full, the incoming event is ignored and the
/// already-retained events stay queued. This is for progress/status feedback
/// such as watcher output, where losing some updates is preferable to blocking
/// the tool that posts them.
///
/// Steering input does not use this capacity; it is queued separately in an
/// unbounded queue.
pub let default_agent_event_capacity : Int32 = 32

///|
/// Drain all currently queued runtime events, oldest retained first.
///
/// The returned array contains the events still present in the lossy bus at the
/// moment of the drain. Events emitted while the bus was already full may have
/// been ignored before this call. The bus is empty after draining. Consumers
/// decide how to interpret and render the opaque event values.
pub fn AgentRuntime::drain_events(self : AgentRuntime) -> Array[AgentEvent] {
  drain_queue(self.events)
}

///|
/// Post one typed runtime event to the lossy event bus.
///
/// The call has no raising effect and ignores queue errors. Under normal use the
/// queue is open and `try_put` succeeds. If the bus already holds
/// `default_agent_event_capacity` events, the incoming event is ignored and the
/// existing queued events are retained.
///
/// Use this for background progress that can tolerate loss under pressure. Do
/// not use it for user steering text or other data that must be delivered
/// exactly once.
pub fn AgentRuntime::emit_event(
  self : AgentRuntime,
  event : AgentEvent,
) -> Unit {
  ignore(self.events.try_put(event) catch { _ => false })
}
