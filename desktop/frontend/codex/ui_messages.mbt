// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  ReasoningPrefix
  NewChat
  RestoreCodex
  ArchiveCodex
  UnknownLabel
  NoMatchingPr
  HideTerminal
  ShowTerminal
  TerminalPlacement
  ShowFiles
  FilesDirectory
  EnableFullCodex
  EnableFullQuestion
  FullAccessWarning
  CancelLabel
  EnableFullAccess
  CompactContext
  ReviewChanges
  SteerPlaceholder
  RebuildWorktree
  AskCodex
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, ReasoningPrefix) => "Reasoning effort: "
    (SimplifiedChinese, ReasoningPrefix) => "推理强度："
    (English, NewChat) => "New chat"
    (SimplifiedChinese, NewChat) => "新建对话"
    (English, RestoreCodex) => "Restore this Codex conversation to the sidebar"
    (SimplifiedChinese, RestoreCodex) => "将此 Codex 对话恢复到侧边栏"
    (English, ArchiveCodex) => "Archive Codex conversation"
    (SimplifiedChinese, ArchiveCodex) => "归档 Codex 对话"
    (English, UnknownLabel) => "Unknown"
    (SimplifiedChinese, UnknownLabel) => "未知"
    (English, NoMatchingPr) => "No matching pull request"
    (SimplifiedChinese, NoMatchingPr) => "没有匹配的拉取请求"
    (English, HideTerminal) => "Hide terminal"
    (SimplifiedChinese, HideTerminal) => "隐藏终端"
    (English, ShowTerminal) => "Show terminal"
    (SimplifiedChinese, ShowTerminal) => "显示终端"
    (English, TerminalPlacement) =>
      "Terminal requires an available Codex task placement"
    (SimplifiedChinese, TerminalPlacement) =>
      "终端需要可用的 Codex 任务运行目录"
    (English, ShowFiles) => "Show files"
    (SimplifiedChinese, ShowFiles) => "显示文件"
    (English, FilesDirectory) => "Files require a Codex working directory"
    (SimplifiedChinese, FilesDirectory) =>
      "文件视图需要 Codex 工作目录"
    (English, EnableFullCodex) => "Enable full Codex access"
    (SimplifiedChinese, EnableFullCodex) => "启用 Codex 完全访问权限"
    (English, EnableFullQuestion) => "Enable full access?"
    (SimplifiedChinese, EnableFullQuestion) => "启用完全访问权限？"
    (English, FullAccessWarning) =>
      "Codex will be able to access the internet and read or modify any file on this computer without asking. Approve for me is safer because it keeps the workspace sandbox in place."
    (SimplifiedChinese, FullAccessWarning) =>
      "Codex 将能够无需询问就访问互联网、读取或修改此电脑上的任何文件。“代我审批”会保留工作区沙盒，因此更加安全。"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (English, EnableFullAccess) => "Enable full access"
    (SimplifiedChinese, EnableFullAccess) => "启用完全访问权限"
    (English, CompactContext) =>
      "Summarize and shrink this conversation's context"
    (SimplifiedChinese, CompactContext) =>
      "总结并压缩此对话的上下文"
    (English, ReviewChanges) => "Review staged, unstaged, and untracked changes"
    (SimplifiedChinese, ReviewChanges) =>
      "审阅已暂存、未暂存和未跟踪的更改"
    (English, SteerPlaceholder) =>
      "Steer the running task — your message joins it at the next step."
    (SimplifiedChinese, SteerPlaceholder) =>
      "引导正在运行的任务，消息将在下一步加入。"
    (English, RebuildWorktree) =>
      "Rebuild this task's worktree before continuing."
    (SimplifiedChinese, RebuildWorktree) =>
      "重建此任务的工作树后才能继续。"
    (English, AskCodex) =>
      "Ask Codex to inspect, edit, or explain this workspace."
    (SimplifiedChinese, AskCodex) =>
      "让 Codex 检查、编辑或解释此工作区。"
  }
}
