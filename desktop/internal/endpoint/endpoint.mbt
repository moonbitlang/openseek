// Type erasure happens here, after a concrete Command[Payload, Reply] has
// been paired with a handler of exactly Payload -> Reply. The retained
// closures let Proton and remote JSON-RPC consume the same endpoint list.

///|
/// The remote transport supplied the wrong JSON shape for a known endpoint.
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
/// A native command after its payload and reply types have been safely paired.
/// The generic types remain captured inside `bind` and `invoke_remote`; users
/// of the registry only need the stable name and route.
priv enum RemoteInvoker {
  Async(async (Json) -> Json)
  Sync((Json) -> Json raise)
  WindowOnly
}

///|
struct Endpoint {
  name : String
  route : @proton_contract.ContractRoute
  bind : (@proton.CommandRegistrar) -> Unit raise
  invoke_remote : RemoteInvoker
}

///|
/// Construct an endpoint shared by Proton and remote JSON-RPC.
pub fn[Payload : @json.FromJson, Reply : ToJson] Endpoint::remote(
  command : @commands.Command[Payload, Reply],
  handler : async (Payload) -> Reply,
) -> Endpoint {
  {
    name: command.name(),
    route: command.descriptor().contract_route(),
    bind: registrar => {
      registrar.bind(command.descriptor(), async fn(_, payload) {
        handler(payload)
      })
    },
    invoke_remote: Async(async fn(params) {
      let payload : Payload = @json.from_json(params) catch {
        _ => raise InvalidEndpointPayload("malformed request payload")
      }
      handler(payload).to_json()
    }),
  }
}

///|
/// Construct a shared endpoint whose native operation does not suspend.
pub fn[Payload : @json.FromJson, Reply : ToJson] Endpoint::remote_sync(
  command : @commands.Command[Payload, Reply],
  handler : (Payload) -> Reply raise,
) -> Endpoint {
  {
    name: command.name(),
    route: command.descriptor().contract_route(),
    bind: registrar => {
      registrar.bind(command.descriptor(), (_, payload) => handler(payload))
    },
    invoke_remote: Sync(params => {
      let payload : Payload = @json.from_json(params) catch {
        _ => raise InvalidEndpointPayload("malformed request payload")
      }
      handler(payload).to_json()
    }),
  }
}

///|
/// Construct a window-only endpoint whose handler needs Proton's page context.
/// It is registered in the local catalog but never placed in the remote list.
pub fn[Payload : @json.FromJson, Reply : ToJson] Endpoint::window(
  command : @commands.Command[Payload, Reply],
  handler : async (@proton.CommandContext, Payload) -> Reply,
) -> Endpoint {
  {
    name: command.name(),
    route: command.descriptor().contract_route(),
    bind: registrar => registrar.bind(command.descriptor(), handler),
    invoke_remote: WindowOnly,
  }
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
pub async fn Endpoint::invoke_remote(self : Endpoint, params : Json) -> Json {
  match self.invoke_remote {
    Async(invoke) => invoke(params)
    Sync(invoke) => invoke(params)
    WindowOnly =>
      raise InvalidEndpointPayload(
        "endpoint is only available to the desktop window",
      )
  }
}
