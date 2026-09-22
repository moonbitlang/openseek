// Type erasure happens here, after a concrete Command[Payload, Reply] has
// been paired with a handler of exactly Payload -> Reply. The retained
// closures let Proton and remote JSON-RPC consume the same endpoint list; a
// window endpoint has only the Proton half. A payload that does not decode
// raises the decoder's own error, which the JSON-RPC transport maps to its
// invalid-params code.

///|
/// A native command after its payload and reply types have been safely
/// paired. The generic types remain captured inside `bind` and `invoke`;
/// users of the registry only need the stable name and route.
priv enum Invoker {
  Async(async (Json) -> Json)
  Sync((Json) -> Json raise)
}

///|
/// A command every client may issue: bound for the desktop window and
/// invoked by name over remote JSON-RPC.
struct Endpoint {
  name : String
  route : @proton_contract.ContractRoute
  bind : (@proton.CommandRegistrar) -> Unit raise
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
    route: command.descriptor().contract_route(),
    bind: registrar => {
      registrar.bind(command.descriptor(), (_, payload) => handler(payload))
    },
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
    route: command.descriptor().contract_route(),
    bind: registrar => {
      registrar.bind(command.descriptor(), (_, payload) => handler(payload))
    },
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
pub fn Endpoint::route(self : Endpoint) -> @proton_contract.ContractRoute {
  self.route
}

///|
pub fn Endpoint::bind(
  self : Endpoint,
  registrar : @proton.CommandRegistrar,
) -> Unit raise {
  (self.bind)(registrar)
}

///|
pub async fn Endpoint::invoke(self : Endpoint, params : Json) -> Json {
  match self.invoke {
    Async(invoke) => invoke(params)
    Sync(invoke) => invoke(params)
  }
}

///|
/// A command only the desktop window can issue: its handler needs Proton's
/// page context, so it is bound for the window and has no remote half. The
/// type keeps it out of every remote catalog, which is built from
/// `Endpoint` alone.
struct WindowEndpoint {
  name : String
  route : @proton_contract.ContractRoute
  bind : (@proton.CommandRegistrar) -> Unit raise
}

///|
pub fn[Payload : @json.FromJson, Reply : ToJson] WindowEndpoint::WindowEndpoint(
  command : @commands.Command[Payload, Reply],
  handler : async (@proton.CommandContext, Payload) -> Reply,
) -> WindowEndpoint {
  {
    name: command.name(),
    route: command.descriptor().contract_route(),
    bind: registrar => registrar.bind(command.descriptor(), handler),
  }
}

///|
pub fn WindowEndpoint::name(self : WindowEndpoint) -> String {
  self.name
}

///|
pub fn WindowEndpoint::route(
  self : WindowEndpoint,
) -> @proton_contract.ContractRoute {
  self.route
}

///|
pub fn WindowEndpoint::bind(
  self : WindowEndpoint,
  registrar : @proton.CommandRegistrar,
) -> Unit raise {
  (self.bind)(registrar)
}
