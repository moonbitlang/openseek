///|
/// A command only the desktop window can issue: it needs Proton's page context
/// or has a window-local contract, so it has no remote half. The
/// type keeps it out of every remote catalog, which is built from
/// `@endpoint.Endpoint` alone.
priv struct WindowEndpoint {
  name : String
  bind : (@proton.CommandRegistrar) -> Unit raise
}

///|
fn[Payload : @json.FromJson, Reply : ToJson] WindowEndpoint::WindowEndpoint(
  command : @commands.Command[Payload, Reply],
  handler : async (@proton.CommandContext, Payload) -> Reply,
) -> WindowEndpoint {
  {
    name: command.name(),
    bind: registrar => registrar.bind(command.descriptor(), handler),
  }
}

///|
fn WindowEndpoint::name(self : WindowEndpoint) -> String {
  self.name
}

///|
fn WindowEndpoint::bind(
  self : WindowEndpoint,
  registrar : @proton.CommandRegistrar,
) -> Unit raise {
  (self.bind)(registrar)
}

///|
/// Bind a shared endpoint for the window. The endpoint already owns its
/// payload decoding, so Proton carries the JSON through untouched under the
/// same route the typed descriptor names.
fn bind_shared(
  registrar : @proton.CommandRegistrar,
  endpoint : @endpoint.Endpoint,
) -> Unit raise {
  let command : @proton_contract.Command[Json, Json] = @commands.extension_contract.command(
    endpoint.name(),
  )
  registrar.bind(command, (_, payload) => endpoint.invoke(payload))
}
