// The Desktop command catalog. Each value binds one stable wire name to one
// payload type and one reply type. Native endpoint registration supplies the
// handler; no dynamic request or response union sits between them.

///|
pub const ExtensionId = "openseek-desktop"

///|
pub let extension_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id=ExtensionId,
  js_namespace="openseek",
)

///|
/// A target-neutral command identity. The type parameters prevent a caller
/// from pairing a command name with an unrelated payload or reply.
struct Command[Payload, Reply] {
  descriptor : @proton_contract.Command[Payload, Reply]
}

///|
fn[Payload, Reply] Command::Command(name : String) -> Command[Payload, Reply] {
  { descriptor: extension_contract.command(name) }
}

///|
pub fn[Payload, Reply] Command::descriptor(
  self : Command[Payload, Reply],
) -> @proton_contract.Command[Payload, Reply] {
  self.descriptor
}

///|
pub fn[Payload, Reply] Command::name(self : Command[Payload, Reply]) -> String {
  self.descriptor.name()
}

///|
pub let agent_start : Command[@protocol.StartPayload, @protocol.StartReply] = Command(
  "agent.start",
)

///|
pub let agent_cancel : Command[@protocol.CancelPayload, @protocol.CancelReply] = Command(
  "agent.cancel",
)

///|
pub let agent_steer : Command[@protocol.SteerPayload, @protocol.SteerReply] = Command(
  "agent.steer",
)

///|
pub let agent_compact : Command[
  @protocol.CompactPayload,
  @protocol.CompactReply,
] = Command("agent.compact")

///|
pub let agent_runs : Command[@protocol.RunsPayload, @protocol.RunsReply] = Command(
  "agent.runs",
)

///|
pub let session_list : Command[@protocol.EmptyPayload, @protocol.SessionsReply] = Command(
  "session.list",
)

///|
pub let session_load : Command[
  @protocol.LoadSessionPayload,
  @protocol.LoadSessionReply,
] = Command("session.load")

///|
pub let session_list_archived : Command[
  @protocol.EmptyPayload,
  @protocol.SessionsReply,
] = Command("session.list_archived")

///|
pub let session_archive : Command[
  @protocol.SessionPayload,
  @protocol.SessionsReply,
] = Command("session.archive")

///|
pub let session_unarchive : Command[
  @protocol.SessionPayload,
  @protocol.SessionsReply,
] = Command("session.unarchive")

///|
pub let settings_get : Command[
  @protocol.EmptyPayload,
  @protocol.SettingsStatusPayload,
] = Command("settings.get")

///|
pub let settings_set : Command[
  @protocol.SettingsSetPayload,
  @protocol.SettingsStatusPayload,
] = Command("settings.set")

///|
pub let app_info : Command[@protocol.EmptyPayload, @protocol.AppInfoReply] = Command(
  "app.info",
)

///|
pub let workspace_list : Command[
  @protocol.EmptyPayload,
  @protocol.WorkspacesReply,
] = Command("workspace.list")

///|
pub let workspace_add : Command[
  @protocol.WorkspacePayload,
  @protocol.WorkspacesReply,
] = Command("workspace.add")

///|
pub let workspace_remove : Command[
  @protocol.WorkspacePayload,
  @protocol.WorkspacesReply,
] = Command("workspace.remove")

///|
pub let worktree_list : Command[
  @protocol.WorktreeListPayload,
  @protocol.WorktreesReply,
] = Command("worktree.list")

///|
pub let worktree_create : Command[
  @protocol.WorktreeCreatePayload,
  @protocol.WorktreeCreateReply,
] = Command("worktree.create")

///|
pub let worktree_remove : Command[
  @protocol.WorktreeRemovePayload,
  @protocol.WorktreesReply,
] = Command("worktree.remove")

///|
pub let auth_status : Command[
  @protocol.EmptyPayload,
  @protocol.AuthStatusPayload,
] = Command("auth.status")

///|
pub let auth_connect : Command[
  @protocol.EmptyPayload,
  @protocol.AuthStatusPayload,
] = Command("auth.connect")

///|
pub let auth_disconnect : Command[
  @protocol.EmptyPayload,
  @protocol.AuthStatusPayload,
] = Command("auth.disconnect")

///|
pub let auth_cancel : Command[
  @protocol.EmptyPayload,
  @protocol.AuthStatusPayload,
] = Command("auth.cancel")

///|
pub let fs_read_file : Command[
  @protocol.ReadFilePayload,
  @protocol.ReadFileReply,
] = Command("fs.read_file")

///|
pub let fs_read_directory : Command[
  @protocol.ReadDirPayload,
  @protocol.ReadDirReply,
] = Command("fs.read_directory")

///|
pub let fs_list_files : Command[
  @protocol.ListFilesPayload,
  @protocol.ListFilesReply,
] = Command("fs.list_files")

///|
pub let fs_stat_files : Command[
  @protocol.StatFilesPayload,
  @protocol.StatFilesReply,
] = Command("fs.stat_files")

///|
pub let fs_watch : Command[
  @protocol.WatchWorkspacePayload,
  @protocol.EmptyReply,
] = Command("fs.watch")

///|
pub let fs_unwatch : Command[@protocol.EmptyPayload, @protocol.EmptyReply] = Command(
  "fs.unwatch",
)

///|
pub let fs_browse : Command[
  @protocol.BrowseDirectoryPayload,
  @protocol.BrowseDirectoryReply,
] = Command("fs.browse")

///|
pub let terminal_open : Command[
  @protocol.TerminalOpenPayload,
  @protocol.TerminalOpenReply,
] = Command("terminal.open")

///|
pub let terminal_input : Command[
  @protocol.TerminalInputPayload,
  @protocol.EmptyReply,
] = Command("terminal.input")

///|
pub let terminal_resize : Command[
  @protocol.TerminalResizePayload,
  @protocol.EmptyReply,
] = Command("terminal.resize")

///|
pub let terminal_ack : Command[
  @protocol.TerminalAckPayload,
  @protocol.EmptyReply,
] = Command("terminal.ack")

///|
pub let terminal_close : Command[
  @protocol.TerminalClosePayload,
  @protocol.EmptyReply,
] = Command("terminal.close")

///|
pub let lsp_open : Command[
  @protocol.LspOpenPayload,
  @protocol.LspDiagnosticsReply,
] = Command("lsp.open")

///|
pub let lsp_hover : Command[@protocol.LspHoverPayload, @protocol.LspHoverReply] = Command(
  "lsp.hover",
)

///|
pub let lsp_workspace_symbols : Command[
  @protocol.WorkspaceSymbolsPayload,
  @protocol.WorkspaceSymbolsReply,
] = Command("lsp.workspace_symbols")

///|
pub let moonide_definition : Command[
  @protocol.MoonIdeNavigationPayload,
  @protocol.MoonIdeLocationsReply,
] = Command("moonide.definition")

///|
pub let moonide_references : Command[
  @protocol.MoonIdeNavigationPayload,
  @protocol.MoonIdeLocationsReply,
] = Command("moonide.references")

///|
pub let skills_catalog : Command[
  @protocol.EmptyPayload,
  @protocol.SkillsCatalogReply,
] = Command("skills.catalog")

///|
pub let skills_installed : Command[
  @protocol.EmptyPayload,
  @protocol.InstalledSkillsReply,
] = Command("skills.installed")

///|
pub let skills_install : Command[
  @protocol.InstallSkillPayload,
  @protocol.InstallSkillReply,
] = Command("skills.install")

///|
pub let skills_uninstall : Command[
  @protocol.UninstallSkillPayload,
  @protocol.UninstallSkillReply,
] = Command("skills.uninstall")

///|
pub let update_check : Command[
  @protocol.UpdateChannelPayload,
  @protocol.CheckUpdateReply,
] = Command("update.check")

///|
pub let update_download : Command[
  @protocol.UpdateChannelPayload,
  @protocol.DownloadUpdateAcceptedReply,
] = Command("update.download")

///|
pub let update_apply : Command[
  @protocol.EmptyPayload,
  @protocol.ApplyUpdateReply,
] = Command("update.apply")

///|
pub let app_list : Command[@protocol.EmptyPayload, @protocol.ListAppsReply] = Command(
  "app.list",
)

///|
pub let app_launch : Command[
  @protocol.LaunchAppPayload,
  @protocol.LaunchAppReply,
] = Command("app.launch")

///|
pub let git_branch : Command[
  @protocol.GitBranchPayload,
  @protocol.GitBranchReply,
] = Command("git.branch")

///|
pub let host_open_path : Command[
  @protocol.OpenPathPayload,
  @protocol.OpenPathReply,
] = Command("host.open_path")

///|
pub let host_connect : Command[@protocol.EmptyPayload, @protocol.EmptyReply] = Command(
  "host.connect",
)

///|
pub let shell_open_external : Command[
  @protocol.ExternalLinkPayload,
  @protocol.OpenExternalReply,
] = Command("shell.open_external")
