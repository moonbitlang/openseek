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
  { descriptor: extension_contract.command(name), }
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
pub let agent_goal : Command[@protocol.GoalPayload, @protocol.GoalReply] = Command(
  "agent.goal",
)

///|
pub let agent_approval : Command[
  @protocol.ApprovalPayload,
  @protocol.ApprovalReply,
] = Command("agent.approval")

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
pub let session_load_archived : Command[
  @protocol.LoadSessionPayload,
  @protocol.LoadSessionReply,
] = Command("session.load_archived")

///|
pub let session_export : Command[
  @protocol.SessionExportPayload,
  @protocol.SessionExportReply,
] = Command("session.export")

///|
pub let session_list_archived : Command[
  @protocol.EmptyPayload,
  @protocol.SessionsReply,
] = Command("session.list_archived")

///|
pub let session_archive : Command[
  @protocol.SessionPayload,
  @protocol.ArchiveReply,
] = Command("session.archive")

///|
pub let session_unarchive : Command[
  @protocol.SessionPayload,
  @protocol.SessionsReply,
] = Command("session.unarchive")

///|
pub let session_delete_archived : Command[
  @protocol.ArchivedSessionPayload,
  @protocol.SessionsReply,
] = Command("session.delete_archived")

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
pub let workspace_settings_get : Command[
  @protocol.WorkspaceSettingsGetPayload,
  @protocol.WorkspaceSettingsPayload,
] = Command("workspace.settings_get")

///|
pub let workspace_settings_set : Command[
  @protocol.WorkspaceSettingsSetPayload,
  @protocol.WorkspaceSettingsPayload,
] = Command("workspace.settings_set")

///|
pub let worktree_list : Command[
  @protocol.WorktreeListPayload,
  @protocol.WorktreesReply,
] = Command("worktree.list")

///|
pub let worktree_create : Command[
  @protocol.WorktreeCreatePayload,
  @protocol.WorktreeCreateResult,
] = Command("worktree.create")

///|
pub let worktree_remove : Command[
  @protocol.WorktreeRemovePayload,
  @protocol.WorktreesReply,
] = Command("worktree.remove")

///|
/// Codex commands expose SeekMoon-owned typed envelopes. Versioned nested
/// app-server records remain JSON fields inside those envelopes.
pub let codex_status : Command[
  @protocol.EmptyPayload,
  @protocol.CodexCommandReply[@protocol.CodexStatusReply],
] = Command("codex.status")

///|
/// Ensure and open the Codex home's `config.toml` with the platform opener.
pub let codex_config_open : Command[
  @protocol.EmptyPayload,
  @protocol.CodexCommandReply[@protocol.EmptyReply],
] = Command("codex.config.open")

///|
/// Authorize one browser-local Codex draft against its selected main project.
/// This process-local operation does not create an app-server thread.
pub let codex_draft_open : Command[
  @protocol.CodexDraftOpenPayload,
  @protocol.CodexCommandReply[@protocol.CodexDraftOpenReply],
] = Command("codex.draft.open")

///|
/// Revoke a browser-local draft's process-local filesystem authority.
pub let codex_draft_close : Command[
  @protocol.CodexDraftClosePayload,
  @protocol.CodexCommandReply[@protocol.EmptyReply],
] = Command("codex.draft.close")

///|
pub let codex_server_request_list : Command[
  @protocol.EmptyPayload,
  @protocol.CodexCommandReply[@protocol.CodexServerRequestsReply],
] = Command("codex.server_request.list")

///|
pub let codex_server_request_respond : Command[
  @protocol.CodexServerRequestRespondPayload,
  @protocol.CodexCommandReply[@protocol.EmptyReply],
] = Command("codex.server_request.respond")

///|
pub let codex_file_search : Command[
  @protocol.CodexFileSearchPayload,
  @protocol.CodexCommandReply[@protocol.CodexFileSearchReply],
] = Command("codex.file.search")

///|
/// List the Codex app-server skills available to one authorized thread cwd.
pub let codex_skills_list : Command[
  @protocol.CodexSkillsListPayload,
  @protocol.CodexCommandReply[@protocol.CodexDataReply],
] = Command("codex.skills.list")

///|
pub let codex_account_read : Command[
  @protocol.CodexAccountReadPayload,
  @protocol.CodexCommandReply[@protocol.CodexAccountReply],
] = Command("codex.account.read")

///|
pub let codex_account_login_start : Command[
  @protocol.CodexAccountLoginStartPayload,
  @protocol.CodexCommandReply[@protocol.CodexLoginStartReply],
] = Command("codex.account.login.start")

///|
pub let codex_account_login_cancel : Command[
  @protocol.CodexAccountLoginCancelPayload,
  @protocol.CodexCommandReply[@protocol.EmptyReply],
] = Command("codex.account.login.cancel")

///|
pub let codex_account_logout : Command[
  @protocol.EmptyPayload,
  @protocol.CodexCommandReply[@protocol.EmptyReply],
] = Command("codex.account.logout")

///|
pub let codex_model_list : Command[
  @protocol.CodexModelListPayload,
  @protocol.CodexCommandReply[@protocol.CodexDataReply],
] = Command("codex.model.list")

///|
pub let codex_thread_start : Command[
  @protocol.CodexThreadStartPayload,
  @protocol.CodexCommandReply[@protocol.CodexThreadReply],
] = Command("codex.thread.start")

///|
pub let codex_thread_resume : Command[
  @protocol.CodexThreadResumePayload,
  @protocol.CodexCommandReply[@protocol.CodexThreadReply],
] = Command("codex.thread.resume")

///|
pub let codex_thread_read : Command[
  @protocol.CodexThreadReadPayload,
  @protocol.CodexCommandReply[@protocol.CodexThreadReply],
] = Command("codex.thread.read")

///|
/// Read either legacy inline turns or every page of a paginated Codex history
/// without resuming the task or acquiring its writer.
pub let codex_thread_history_read : Command[
  @protocol.CodexThreadPayload,
  @protocol.CodexCommandReply[@protocol.CodexThreadReply],
] = Command("codex.thread.history.read")

///|
pub let codex_thread_list : Command[
  @protocol.CodexThreadListPayload,
  @protocol.CodexCommandReply[@protocol.CodexDataReply],
] = Command("codex.thread.list")

///|
pub let codex_thread_archive : Command[
  @protocol.CodexThreadArchivePayload,
  @protocol.CodexCommandReply[@protocol.CodexArchiveReply],
] = Command("codex.thread.archive")

///|
pub let codex_thread_unarchive : Command[
  @protocol.CodexThreadPayload,
  @protocol.CodexCommandReply[@protocol.EmptyReply],
] = Command("codex.thread.unarchive")

///|
pub let codex_thread_compact : Command[
  @protocol.CodexThreadPayload,
  @protocol.CodexCommandReply[@protocol.EmptyReply],
] = Command("codex.thread.compact")

///|
pub let codex_review_start : Command[
  @protocol.CodexReviewStartPayload,
  @protocol.CodexCommandReply[@protocol.EmptyReply],
] = Command("codex.review.start")

///|
pub let codex_turn_start : Command[
  @protocol.CodexTurnStartPayload,
  @protocol.CodexCommandReply[@protocol.CodexTurnReply],
] = Command("codex.turn.start")

///|
pub let codex_turn_steer : Command[
  @protocol.CodexTurnSteerPayload,
  @protocol.CodexCommandReply[@protocol.CodexTurnReply],
] = Command("codex.turn.steer")

///|
pub let codex_turn_interrupt : Command[
  @protocol.CodexTurnInterruptPayload,
  @protocol.CodexCommandReply[@protocol.EmptyReply],
] = Command("codex.turn.interrupt")

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
pub let fs_search_files : Command[
  @protocol.SearchFilesPayload,
  @protocol.SearchFilesReply,
] = Command("fs.search_files")

///|
pub let fs_cancel_search_files : Command[
  @protocol.CancelSearchFilesPayload,
  @protocol.EmptyReply,
] = Command("fs.cancel_search_files")

///|
pub let fs_search_text : Command[
  @protocol.SearchTextPayload,
  @protocol.SearchTextReply,
] = Command("fs.search_text")

///|
pub let fs_cancel_search_text : Command[
  @protocol.CancelSearchTextPayload,
  @protocol.EmptyReply,
] = Command("fs.cancel_search_text")

///|
pub let fs_search_semantic : Command[
  @protocol.SearchSemanticPayload,
  @protocol.SearchSemanticReply,
] = Command("fs.search_semantic")

///|
pub let fs_cancel_search_semantic : Command[
  @protocol.CancelSearchSemanticPayload,
  @protocol.EmptyReply,
] = Command("fs.cancel_search_semantic")

///|
pub let pattern_repair : Command[
  @protocol.PatternRepairPayload,
  @protocol.PatternRepairReply,
] = Command("pattern.repair")

///|
pub let fs_clear_file_search_cache : Command[
  @protocol.ClearFileSearchCachePayload,
  @protocol.EmptyReply,
] = Command("fs.clear_file_search_cache")

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
pub let fs_create_directory : Command[
  @protocol.CreateDirectoryPayload,
  @protocol.BrowseDirectoryReply,
] = Command("fs.create_directory")

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
pub let skills_content : Command[
  @protocol.InstallSkillPayload,
  @protocol.ReadFileReply,
] = Command("skills.content")

///|
pub let skills_installed_content : Command[
  @protocol.UninstallSkillPayload,
  @protocol.ReadFileReply,
] = Command("skills.installed_content")

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
  @protocol.EmptyPayload,
  @protocol.CheckUpdateReply,
] = Command("update.check")

///|
pub let update_download : Command[
  @protocol.EmptyPayload,
  @protocol.DownloadUpdateAcceptedReply,
] = Command("update.download")

///|
pub let update_apply : Command[
  @protocol.EmptyPayload,
  @protocol.ApplyUpdateReply,
] = Command("update.apply")

///|
pub let git_branch : Command[
  @protocol.GitBranchPayload,
  @protocol.GitBranchReply,
] = Command("git.branch")

///|
pub let git_pull_request : Command[
  @protocol.GitPullRequestPayload,
  @protocol.GitPullRequestReply,
] = Command("git.pull_request")

///|
pub let git_changes : Command[
  @protocol.GitChangesPayload,
  @protocol.GitChangesReply,
] = Command("git.changes")

///|
pub let git_history : Command[
  @protocol.GitHistoryPayload,
  @protocol.GitHistoryReply,
] = Command("git.history")

///|
pub let git_commit_changes : Command[
  @protocol.GitCommitChangesPayload,
  @protocol.GitCommitChangesReply,
] = Command("git.commit_changes")

///|
pub let git_original_file : Command[
  @protocol.GitOriginalFilePayload,
  @protocol.GitOriginalFileReply,
] = Command("git.original_file")

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
// The dock's browser-tab commands. Like `host.connect` and
// `shell.open_external`, they are bound window-only: the native web
// contents views live in the desktop window, so a relay browser has
// nothing to command.

///|
pub let browser_open : Command[
  @protocol.BrowserOpenPayload,
  @protocol.EmptyReply,
] = Command("browser.open")

///|
pub let browser_navigate : Command[
  @protocol.BrowserOpenPayload,
  @protocol.EmptyReply,
] = Command("browser.navigate")

///|
pub let browser_back : Command[@protocol.BrowserIdPayload, @protocol.EmptyReply] = Command(
  "browser.back",
)

///|
pub let browser_forward : Command[
  @protocol.BrowserIdPayload,
  @protocol.EmptyReply,
] = Command("browser.forward")

///|
pub let browser_reload : Command[
  @protocol.BrowserIdPayload,
  @protocol.EmptyReply,
] = Command("browser.reload")

///|
pub let browser_set_theme : Command[
  @protocol.BrowserThemePayload,
  @protocol.EmptyReply,
] = Command("browser.set_theme")

///|
pub let app_open_devtools : Command[
  @protocol.EmptyPayload,
  @protocol.EmptyReply,
] = Command("app.open_devtools")

///|
/// Match this native desktop window's caption controls to the effective app
/// palette. Window-only: a relay browser has no local application window.
pub let app_set_titlebar_theme : Command[
  @protocol.AppTitlebarThemePayload,
  @protocol.EmptyReply,
] = Command("app.set_titlebar_theme")

///|
/// Toggle this native desktop window between its maximized and restored
/// bounds. Window-only: a relay browser has no local application window.
pub let app_toggle_maximized : Command[
  @protocol.EmptyPayload,
  @protocol.EmptyReply,
] = Command("app.toggle_maximized")

///|
pub let browser_set_bounds : Command[
  @protocol.BrowserBoundsPayload,
  @protocol.EmptyReply,
] = Command("browser.set_bounds")

///|
pub let browser_set_visible : Command[
  @protocol.BrowserVisiblePayload,
  @protocol.EmptyReply,
] = Command("browser.set_visible")

///|
pub let browser_close : Command[
  @protocol.BrowserIdPayload,
  @protocol.EmptyReply,
] = Command("browser.close")
