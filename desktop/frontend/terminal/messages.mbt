// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  CloseTerminal
  TerminalLabel
  NewTerminal
  WaitingPlacement
  MissingWorktree
  HideTerminal
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, CloseTerminal) => "Close terminal"
    (SimplifiedChinese, CloseTerminal) => "关闭终端"
    (English, TerminalLabel) => "Terminal"
    (SimplifiedChinese, TerminalLabel) => "终端"
    (English, NewTerminal) => "New terminal in this workspace"
    (SimplifiedChinese, NewTerminal) => "在此工作区新建终端"
    (English, WaitingPlacement) => "Waiting for workspace placement…"
    (SimplifiedChinese, WaitingPlacement) => "正在等待工作区就绪…"
    (English, MissingWorktree) => "Worktree checkout is missing"
    (SimplifiedChinese, MissingWorktree) => "工作树检出目录缺失"
    (English, HideTerminal) => "Hide terminal (Ctrl+`)"
    (SimplifiedChinese, HideTerminal) => "隐藏终端（Ctrl+`）"
  }
}
