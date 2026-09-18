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
    (Japanese, CloseTerminal) => "ターミナルを閉じる"
    (English, TerminalLabel) => "Terminal"
    (SimplifiedChinese, TerminalLabel) => "终端"
    (Japanese, TerminalLabel) => "ターミナル"
    (English, NewTerminal) => "New terminal in this workspace"
    (SimplifiedChinese, NewTerminal) => "在此工作区新建终端"
    (Japanese, NewTerminal) =>
      "このワークスペースで新しいターミナルを開く"
    (English, WaitingPlacement) => "Waiting for workspace placement…"
    (SimplifiedChinese, WaitingPlacement) => "正在等待工作区就绪…"
    (Japanese, WaitingPlacement) =>
      "ワークスペースの準備を待機中…"
    (English, MissingWorktree) => "Worktree checkout is missing"
    (SimplifiedChinese, MissingWorktree) => "工作树检出目录缺失"
    (Japanese, MissingWorktree) =>
      "ワークツリーのチェックアウトがありません"
    (English, HideTerminal) => "Hide terminal (Ctrl+`)"
    (SimplifiedChinese, HideTerminal) => "隐藏终端（Ctrl+`）"
    (Japanese, HideTerminal) => "ターミナルを非表示（Ctrl+`）"
  }
}
