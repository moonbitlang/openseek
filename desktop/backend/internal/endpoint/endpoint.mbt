// Type erasure happens here, after a concrete Command[Payload, Reply] has
// been paired with a handler of exactly Payload -> Reply. The retained
// closure is what the JSON-RPC transport invokes by name; the shared catalog
// and the desktop window's loopback-only extras are both lists of these.

///|
/// The transport supplied the wrong JSON shape for a known endpoint.
pub(all) suberror InvalidEndpointPayload {
  InvalidEndpointPayload(String)
}

///|
impl Show for InvalidEndpointPayload with fn output(self, logger) {
  match self {
    InvalidEndpointPayload(message) => logger.write_string(message)
  }
}

///|
/// A native command after its payload and reply types have been safely
/// paired. The generic types remain captured inside `invoke`; users of the
/// registry only need the stable name.
priv enum Invoker {
  Async(async (Json) -> Json)
  Sync((Json) -> Json raise)
}

///|
struct Endpoint {
  name : String
  invoke : Invoker
}

///|
/// Construct an endpoint from an asynchronous operation.
pub fn[Payload : @json.FromJson, Reply : ToJson] Endpoint::Endpoint(
  command : @commands.Command[Payload, Reply],
  handler : async (Payload) -> Reply,
) -> Endpoint {
  {
    name: command.name(),
    invoke: Async(async fn(params) {
      let payload : Payload = @json.from_json(params) catch {
        _ => raise InvalidEndpointPayload("malformed request payload")
      }
      handler(payload).to_json()
    }),
  }
}

///|
/// Construct an endpoint whose native operation does not suspend.
pub fn[Payload : @json.FromJson, Reply : ToJson] Endpoint::sync(
  command : @commands.Command[Payload, Reply],
  handler : (Payload) -> Reply raise,
) -> Endpoint {
  {
    name: command.name(),
    invoke: Sync(params => {
      let payload : Payload = @json.from_json(params) catch {
        _ => raise InvalidEndpointPayload("malformed request payload")
      }
      handler(payload).to_json()
    }),
  }
}

///|
/// Construct a Codex endpoint whose raised handler errors travel as ordinary
/// typed replies, so the original app-server error text reaches the client
/// instead of a generic JSON-RPC error.
pub fn[Payload : @json.FromJson, Reply : ToJson] Endpoint::codex(
  command : @commands.Command[Payload, @protocol.CodexCommandReply[Reply]],
  handler : async (Payload) -> Reply,
) -> Endpoint {
  Endpoint(command, async fn(payload) {
    let reply = handler(payload) catch {
      error if @async.is_being_cancelled() => raise error
      error => return CodexCommandError("\{error}")
    }
    CodexCommandSuccess(reply)
  })
}

///|
/// Construct a Codex endpoint whose handler completes synchronously. Keeping
/// this separate avoids pretending a synchronous command can suspend merely
/// to share the Codex error-reply contract.
pub fn[Payload : @json.FromJson, Reply : ToJson] Endpoint::codex_sync(
  command : @commands.Command[Payload, @protocol.CodexCommandReply[Reply]],
  handler : (Payload) -> Reply raise,
) -> Endpoint {
  Endpoint::sync(command, fn(payload) {
    let reply = handler(payload) catch {
      error => return CodexCommandError("\{error}")
    }
    CodexCommandSuccess(reply)
  })
}

///|
pub fn Endpoint::name(self : Endpoint) -> String {
  self.name
}

///|
pub async fn Endpoint::invoke(self : Endpoint, params : Json) -> Json {
  match self.invoke {
    Async(invoke) => invoke(params)
    Sync(invoke) => invoke(params)
  }
}
