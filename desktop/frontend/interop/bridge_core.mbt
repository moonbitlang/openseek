// The engine-host calling core: one `bridge_request` for every frontend
// package that talks to a host, routed by channel. `Local` is the desktop
// window's injected `__MoonBit__.openseek` op; `Remote(id)` is currently a
// relay device reached over its WebSocket (docs/remote-protocol.md). The method
// names and payloads are identical either way — callers and reply decoders
// cannot tell the transports apart.

///|
priv suberror BridgeError {
  // The host returned a command-level failure. The detail is safe to show and
  // the caller knows the requested action did not succeed.
  BridgeRefused(String)
  // The call left this client and something went wrong after that: a reply
  // arrived that could not be read.
  BridgeError(String)
  // The call never left: no bridge, no such method, no open socket. Raised
  // strictly before anything is written to the transport, which is what lets
  // callers treat it as "nothing landed" rather than "unknown".
  BridgeUnsent(String)
}

///|
impl Show for BridgeError with fn output(self, logger) {
  match self {
    BridgeRefused(message) | BridgeError(message) | BridgeUnsent(message) =>
      logger.write_string(message)
  }
}

///|
/// `globalThis.__MoonBit__.openseek`, once the proton bridge is injected.
pub fn openseek_api() -> @js.Value? {
  guard moonbit_bridge_root() is Some(root) else { return None }
  js_prop(root, "openseek")
}

///|
/// Call one typed Desktop command on a channel and wait for its concrete
/// reply. The command value fixes both generic types, so a caller cannot send
/// one command's payload under another command name or decode the wrong reply.
pub async fn[Payload : ToJson, Reply : @json.FromJson] bridge_request(
  channel : ChannelId,
  command : @commands.Command[Payload, Reply],
  payload : Payload,
) -> Reply {
  let op = command.name()
  let payload = @js.Value::from_json(payload.to_json())
  let reply = match channel {
    Local => {
      guard openseek_api() is Some(api) && js_prop(api, op) is Some(_) else {
        raise BridgeUnsent("SeekMoon bridge unavailable")
      }
      js_method_promise(api, op, payload).wait()
    }
    Remote(_) => ws_request(channel, op, payload)
  }
  let json = if reply.is_undefined() || reply.is_null() {
    Json::empty_object()
  } else {
    reply.to_json() catch {
      _ => raise BridgeError("Malformed reply from \{op}")
    }
  }
  @json.from_json(json) catch {
    _ => raise BridgeError("Malformed reply from \{op}")
  }
}

///|
/// Call one `codex.*` command and unwrap its command-level result. Native
/// handlers return original error text inside the reply so Proton cannot
/// replace it with a generic rejected-promise message.
pub async fn[Payload : ToJson, Reply : @json.FromJson] codex_request(
  channel : ChannelId,
  command : @commands.Command[Payload, @protocol.CodexCommandReply[Reply]],
  payload : Payload,
) -> Reply {
  match bridge_request(channel, command, payload) {
    CodexCommandSuccess(reply) => reply
    CodexCommandError(message) => raise BridgeRefused(message)
  }
}

///|
/// Keep local Proton method entry ordered even though its bridge dispatches
/// requests in separate native tasks. The per-channel lane below already
/// serializes callers; this promise tail also keeps ordering at the JS/native
/// handoff if that implementation detail changes.
extern "js" fn js_ordered_method_promise(
  target : @js.Value,
  name : String,
  payload : @js.Value,
) -> @js.Promise =
  #| (() => {
  #|   let tail = Promise.resolve();
  #|   return (target, name, payload) => {
  #|     const request = tail
  #|       .catch(() => undefined)
  #|       .then(() => target[name](payload));
  #|     tail = request.catch(() => undefined);
  #|     return request;
  #|   };
  #| })()

///|
/// The ordered-request lanes, keyed by the scope the ordering is about. This
/// transport-independent boundary is what makes the contract hold for remote
/// hosts: the wire protocol states that "responses may arrive out of order
/// relative to other requests — the `id` is the correlation", and the server
/// runs each request in its own task accordingly, so ordering can only be
/// established on the issuing side.
///
/// Most callers share one lane per host. A caller may name a narrower one
/// when its ordering is per-something-else and it would otherwise both wait
/// on and block work it has nothing to do with.
let ordered_request_lanes : Map[String, Lane] = Map([])

///|
fn ordered_request_lane(lane : String) -> Lane {
  ordered_request_lanes.get_or_init(lane, () => Lane::Lane())
}

///|
/// The lane a host's ordinary ordered requests share.
fn host_lane(channel : ChannelId) -> String {
  channel.uri_authority()
}

///|
/// A lane of its own for one session's engine commands — start, compact and
/// goal.
///
/// This mirrors the host, which claims a single per-session slot for exactly
/// those three. Sent concurrently they collide there: one is refused outright,
/// and even when both are accepted the order is whichever reply raced ahead —
/// so a prompt sent right after a goal can begin its turn before the goal is
/// injected, and a Clear sent over a Set can lose to the goal it was
/// cancelling. Issue order is the user's order, and the host cannot recover
/// it, so it has to be kept here.
///
/// Not the shared host lane: these can spawn an engine, and the file-panel
/// watcher and browser view ops would then queue behind a process start for
/// an ordering they never asked for.
pub fn session_command_lane(channel : ChannelId, session : String) -> String {
  "\{channel.uri_authority()}\u{0}session\u{0}\{session}"
}

///|
/// Hold a lane across a caller's whole sequence, for work whose ordering is
/// more than one request wide — the goal chain's create-then-bind-then-send,
/// where a lane around the final request alone still lets two preflights race
/// and deliver their goals in the order their *replies* arrived.
///
/// The lane is not reentrant, so work run here must issue its requests with
/// plain `bridge_request`: the lane is already held on their behalf.
pub async fn[T] in_ordered_lane(lane : String, work : async () -> T) -> T {
  ordered_request_lane(lane).run(work)
}

///|
/// Call one host method in the page's issue order, for callers whose requests
/// are desired state or ordered observations rather than independent queries:
/// the file-panel watcher (`watch(A)` then `unwatch`), file-stat snapshots,
/// and browser view ops (create-then-place, bounds-before-visibility).
/// Deliberately do not put a caller-side timeout around this lane: neither the
/// Proton promise nor an older remote RPC is cancelable, so releasing the lane
/// early would allow its successor to overtake an operation still applying.
pub async fn[Payload : ToJson, Reply : @json.FromJson] bridge_request_in_order(
  channel : ChannelId,
  command : @commands.Command[Payload, Reply],
  payload : Payload,
  lane? : String,
) -> Reply {
  ordered_request_lane(lane.unwrap_or(host_lane(channel))).run(() => {
    let op = command.name()
    let payload = @js.Value::from_json(payload.to_json())
    let reply = match channel {
      Local => {
        guard openseek_api() is Some(api) && js_prop(api, op) is Some(_) else {
          raise BridgeUnsent("SeekMoon bridge unavailable")
        }
        js_ordered_method_promise(api, op, payload).wait()
      }
      Remote(_) => ws_request(channel, op, payload)
    }
    let json = if reply.is_undefined() || reply.is_null() {
      Json::empty_object()
    } else {
      reply.to_json() catch {
        _ => raise BridgeError("Malformed reply from \{op}")
      }
    }
    @json.from_json(json) catch {
      _ => raise BridgeError("Malformed reply from \{op}")
    }
  })
}

///|
test "a lane key separates what must not share a lane" {
  // Start, compact and goal are ordered per session because the host serves
  // one at a time there — all three claim its single slot. Sharing the host
  // lane would order them against file and view ops too, which a command able
  // to spawn an engine would then hold up for an ordering nobody asked for.
  let here = ChannelId::Local
  assert_true(
    session_command_lane(here, "s-1") == session_command_lane(here, "s-1"),
  )
  assert_false(
    session_command_lane(here, "s-1") == session_command_lane(here, "s-2"),
  )
  assert_false(session_command_lane(here, "s-1") == host_lane(here))
  assert_false(
    session_command_lane(here, "s-1") ==
    session_command_lane(Remote("d"), "s-1"),
  )
  // A session id cannot be spelled to collide with another lane.
  assert_false(
    session_command_lane(here, "s-1") ==
    session_command_lane(here, "s-1\u{0}goal\u{0}s-1"),
  )
}

///|
test "an ordered request failure releases its channel lane" {
  // No bridge is injected under test, so both calls fail at the same point.
  // The second one only reaches it if the first released the lane on its way
  // out; before, a lane still held would have parked it forever.
  let failures = []
  for _ in 0..<2 {
    @js.async_run(() => {
      ignore(
        bridge_request_in_order(
          Local,
          @commands.fs_unwatch,
          @protocol.EmptyPayload::NoPayload,
        ),
      ) catch {
        _ => {
          failures.push(true)
          return
        }
      }
      failures.push(false)
    })
  }
  assert_eq(failures, [true, true])
}

///|
test "a Codex command error keeps its detail and is a definite refusal" {
  let error : Error = BridgeRefused(
    "Codex app-server request turn/start failed: invalid model",
  )
  assert_eq(
    bridge_error_text(error),
    "Codex app-server request turn/start failed: invalid model",
  )
  assert_true(bridge_failure(error) is Refused)
}

///|
/// A user-facing message for a failed bridge call, preferring the JS
/// error's `message` over its stringified form.
pub fn bridge_error_text(error : Error) -> String {
  match error {
    BridgeRefused(message) | BridgeError(message) | BridgeUnsent(message) =>
      message
    @js.Error_(value) =>
      if js_prop(value, "message") is Some(message) &&
        (@js.Cast::into(message) : String?) is Some(text) &&
        !text.is_empty() {
        text
      } else {
        value.to_string()
      }
    _ => "\{error}"
  }
}

///|
/// What a failed bridge call says about the command it carried. The question
/// a caller actually has is not "did this error" but "could the host have
/// acted on it", and that has three answers, not two — collapsing `Unsent`
/// into `Unknown` makes callers hedge over an outcome that is not in doubt,
/// and hedging is what leaves an optimistic local state with nothing left to
/// resolve it.
pub(all) enum BridgeFailure {
  // The host answered, and the answer was no. Nothing landed.
  Refused
  // The call never reached a transport: no injected bridge, no such method,
  // no open socket. Nothing landed, and nothing is on its way.
  Unsent
  // It went out and the answer did not come back. The host may have acted;
  // only the durable record can say.
  Unknown
}

///|
/// Classify a failed bridge call. Browser JSON-RPC errors carry a marker set
/// by the response decoder; socket close / down errors do not. In the
/// embedded proton bridge, a present method's rejected promise is the direct
/// host answer.
///
/// The `openseek_api()` test is about *this* page having an embedded host,
/// which on its own says nothing about a request that went out over a socket
/// — a proton page drives remote channels too. It is sound only because
/// `ws_request` names its own failures before they get here, so a bare
/// `@js.Error_` reaching this point came from the local path.
pub fn bridge_failure(error : Error) -> BridgeFailure {
  match error {
    BridgeRefused(_) => Refused
    BridgeUnsent(_) => Unsent
    // A reply that arrived and could not be decoded, or a socket that died
    // under a request already sent: it went out, and the answer is what is
    // lost.
    BridgeError(_) => Unknown
    @js.Error_(value) =>
      if openseek_api() is Some(_) || browser_rpc_error_is_definite(value) {
        Refused
      } else {
        Unknown
      }
    _ => Unknown
  }
}

///|
/// Whether a failed bridge call is a definitive host refusal — the two-state
/// view of `bridge_failure`, kept for the start and steer paths, whose
/// unconfirmed handling already does the conservative thing with `Unsent`.
pub fn bridge_error_is_definite(error : Error) -> Bool {
  bridge_failure(error) is Refused
}

///|
fn browser_rpc_error_is_definite(value : @js.Value) -> Bool {
  js_prop(value, "__openseek_rpc_rejection") is Some(marker) &&
  (@js.Cast::into(marker) : Bool?) is Some(true)
}
