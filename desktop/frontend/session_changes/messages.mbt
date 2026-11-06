// Feature-owned UI messages; all built-in languages are exhaustive.

///|
priv enum UiMessage {
  Current
  PullRequestCount(Int32)
  BranchCount(Int32)
  MergedCount(Int32)
  CheckFailed
  RemoveFailed
  PartialCount
  Remove
  RemoveMerged
  StateOpen
  StateDraft
  StateMerged
  StateClosed
}

///|
fn text(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, Current) => "Current"
    (Spanish, Current) => "Actual"
    (SimplifiedChinese, Current) => "当前"
    (TraditionalChinese, Current) => "目前"
    (Japanese, Current) => "現在"
    (English, PullRequestCount(1)) => "1 PR"
    (English, PullRequestCount(count)) => "\{count} PRs"
    (Spanish, PullRequestCount(1)) => "1 PR"
    (Spanish, PullRequestCount(count)) => "\{count} PR"
    (SimplifiedChinese, PullRequestCount(count)) => "\{count} 个 PR"
    (TraditionalChinese, PullRequestCount(count)) => "\{count} 個 PR"
    (Japanese, PullRequestCount(count)) => "PR \{count} 件"
    (English, BranchCount(1)) => "1 branch"
    (English, BranchCount(count)) => "\{count} branches"
    (Spanish, BranchCount(1)) => "1 rama"
    (Spanish, BranchCount(count)) => "\{count} ramas"
    (SimplifiedChinese, BranchCount(count)) => "\{count} 个分支"
    (TraditionalChinese, BranchCount(count)) => "\{count} 個分支"
    (Japanese, BranchCount(count)) => "ブランチ \{count} 件"
    (English, MergedCount(count)) => "\{count} merged"
    (Spanish, MergedCount(1)) => "1 fusionada"
    (Spanish, MergedCount(count)) => "\{count} fusionadas"
    (SimplifiedChinese, MergedCount(count)) => "\{count} 个已合并"
    (TraditionalChinese, MergedCount(count)) => "\{count} 個已合併"
    (Japanese, MergedCount(count)) => "マージ済み \{count} 件"
    (English, CheckFailed) => "The attached changes could not be read"
    (Spanish, CheckFailed) => "No se pudieron leer los cambios adjuntos"
    (SimplifiedChinese, CheckFailed) => "未能读取附加的更改"
    (TraditionalChinese, CheckFailed) => "未能讀取附加的變更"
    (Japanese, CheckFailed) =>
      "添付された変更を読み取れませんでした"
    (English, RemoveFailed) => "Could not remove it"
    (Spanish, RemoveFailed) => "No se pudo quitar"
    (SimplifiedChinese, RemoveFailed) => "未能移除"
    (TraditionalChinese, RemoveFailed) => "未能移除"
    (Japanese, RemoveFailed) => "削除できませんでした"
    (English, PartialCount) => "Some untracked files were not counted"
    (Spanish, PartialCount) => "No se contaron algunos archivos sin seguimiento"
    (SimplifiedChinese, PartialCount) => "部分未跟踪文件未计入"
    (TraditionalChinese, PartialCount) => "部分未追蹤檔案未計入"
    (Japanese, PartialCount) =>
      "一部の未追跡ファイルは集計されていません"
    (English, Remove) => "Remove from this conversation"
    (Spanish, Remove) => "Quitar de esta conversación"
    (SimplifiedChinese, Remove) => "从此对话中移除"
    (TraditionalChinese, Remove) => "從此對話中移除"
    (Japanese, Remove) => "この会話から削除"
    (English, RemoveMerged) =>
      "Remove merged pull requests from this conversation"
    (Spanish, RemoveMerged) =>
      "Quitar de esta conversación las solicitudes fusionadas"
    (SimplifiedChinese, RemoveMerged) => "从此对话中移除已合并的 PR"
    (TraditionalChinese, RemoveMerged) => "從此對話中移除已合併的 PR"
    (Japanese, RemoveMerged) =>
      "マージ済みの PR をこの会話から削除"
    (English, StateOpen) => "Open"
    (Spanish, StateOpen) => "Abierta"
    (SimplifiedChinese, StateOpen) => "已打开"
    (TraditionalChinese, StateOpen) => "已開啟"
    (Japanese, StateOpen) => "オープン"
    (English, StateDraft) => "Draft"
    (Spanish, StateDraft) => "Borrador"
    (SimplifiedChinese, StateDraft) => "草稿"
    (TraditionalChinese, StateDraft) => "草稿"
    (Japanese, StateDraft) => "下書き"
    (English, StateMerged) => "Merged"
    (Spanish, StateMerged) => "Fusionada"
    (SimplifiedChinese, StateMerged) => "已合并"
    (TraditionalChinese, StateMerged) => "已合併"
    (Japanese, StateMerged) => "マージ済み"
    (English, StateClosed) => "Closed"
    (Spanish, StateClosed) => "Cerrada"
    (SimplifiedChinese, StateClosed) => "已关闭"
    (TraditionalChinese, StateClosed) => "已關閉"
    (Japanese, StateClosed) => "クローズ"
  }
}
