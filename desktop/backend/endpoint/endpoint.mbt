// Type erasure happens here, after a concrete Command[Payload, Reply] has
// been paired with a handler of exactly Payload -> Reply. The retained
// invoker lets every transport consume the same endpoint list. A payload that does not decode
// raises the decoder's own error, which the JSON-RPC transport maps to its
// invalid-params code.

///|
/// A host command after its payload and reply types have been safely
/// paired. The generic types remain captured inside `invoke`;
/// users of the registry only need the stable name.
priv enum Invoker {
  Async(async (Json) -> Json)
  Sync((Json) -> Json raise)
}

///|
/// A command invoked by name after transport authentication.
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
    invoke: Async(params => {
      let payload : Payload = @json.from_json(params)
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
      let payload : Payload = @json.from_json(params)
      handler(payload).to_json()
    }),
  }
}

///|
/// Construct a Codex endpoint whose raised handler errors travel as ordinary
/// typed replies. Proton may redact a raised error, so the catch must happen
/// before the shared endpoint hands the result to either channel.
pub fn[Payload : @json.FromJson, Reply : ToJson] Endpoint::codex(
  command : @commands.Command[Payload, @protocol.CodexCommandReply[Reply]],
  handler : async (Payload) -> Reply,
) -> Endpoint {
  Endpoint(command, payload => {
    let reply = handler(payload) catch {
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
  Endpoint::sync(command, payload => {
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
