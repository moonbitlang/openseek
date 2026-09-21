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
    (Spanish, CloseTerminal) => "Cerrar terminal"
    (SimplifiedChinese, CloseTerminal) => "关闭终端"
    (TraditionalChinese, CloseTerminal) => "關閉終端"
    (Japanese, CloseTerminal) => "ターミナルを閉じる"
    (English, TerminalLabel) => "Terminal"
    (Spanish, TerminalLabel) => "Terminal"
    (SimplifiedChinese, TerminalLabel) => "终端"
    (TraditionalChinese, TerminalLabel) => "終端"
    (Japanese, TerminalLabel) => "ターミナル"
    (English, NewTerminal) => "New terminal in this workspace"
    (Spanish, NewTerminal) => "Nueva terminal en este espacio de trabajo"
    (SimplifiedChinese, NewTerminal) => "在此工作区新建终端"
    (TraditionalChinese, NewTerminal) => "在此工作區新建終端"
    (Japanese, NewTerminal) =>
      "このワークスペースで新しいターミナルを開く"
    (English, WaitingPlacement) => "Waiting for workspace placement…"
    (Spanish, WaitingPlacement) =>
      "Esperando la ubicación del espacio de trabajo…"
    (SimplifiedChinese, WaitingPlacement) => "正在等待工作区就绪…"
    (TraditionalChinese, WaitingPlacement) => "正在等待工作區就緒…"
    (Japanese, WaitingPlacement) =>
      "ワークスペースの準備を待機中…"
    (English, MissingWorktree) => "Worktree checkout is missing"
    (Spanish, MissingWorktree) => "Falta la copia de trabajo del worktree"
    (SimplifiedChinese, MissingWorktree) => "工作树检出目录缺失"
    (TraditionalChinese, MissingWorktree) => "工作樹檢出目錄缺失"
    (Japanese, MissingWorktree) =>
      "ワークツリーのチェックアウトがありません"
    (English, HideTerminal) => "Hide terminal (Ctrl+`)"
    (Spanish, HideTerminal) => "Ocultar terminal (Ctrl+`)"
    (SimplifiedChinese, HideTerminal) => "隐藏终端（Ctrl+`）"
    (TraditionalChinese, HideTerminal) => "隱藏終端（Ctrl+`）"
    (Japanese, HideTerminal) => "ターミナルを非表示（Ctrl+`）"
  }
}
