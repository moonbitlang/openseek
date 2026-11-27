// Items this package exports for a consumer outside the root workspace.
// `moon ide analyze` counts uses from the modules listed in the root
// `moon.work` only; `desktop/app` is the module `openseek_desktop/app`, which
// builds in its own `desktop/app/moon.work`, so its uses of these items are
// invisible to the analyzer.

///|
/// The extension the window host registers. `desktop/app/internal/extension/extension.mbt`
/// derives every event descriptor from `@commands.extension_contract`
/// (`extension.mbt:13`, `extension/ssh.mbt:2`) and binds commands through it
/// (`extension/window_endpoint.mbt:43`), in the out-of-workspace
/// `openseek_desktop/app` module.
pub let extension_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id=ExtensionId,
  js_namespace="openseek",
)

///|
/// A window-only endpoint: `desktop/app/internal/extension/extension.mbt:477`
/// binds `@commands.host_connect` through `WindowEndpoint`, in the
/// out-of-workspace `openseek_desktop/app` module.
pub let host_connect : Command[@protocol.EmptyPayload, @protocol.EmptyReply] = Command(
  "host.connect",
)

///|
/// A window-only endpoint: `desktop/app/internal/extension/extension.mbt:449`
/// binds `@commands.ssh_request` through `WindowEndpoint`, in the
/// out-of-workspace `openseek_desktop/app` module.
pub let ssh_request : Command[@protocol.SshRequest, @protocol.SshReply] = Command(
  "ssh.request",
)

///|
/// The Proton-facing descriptor of a command. `Command` is opaque outside this
/// package, so other modules can only reach the descriptor by method:
/// `desktop/app/internal/extension/window_endpoint.mbt:18` calls
/// `command.descriptor()` to bind a typed handler, in the out-of-workspace
/// `openseek_desktop/app` module.
pub fn[Payload, Reply] Command::descriptor(
  self : Command[Payload, Reply],
) -> @proton_contract.Command[Payload, Reply] {
  self.descriptor
}
