// Feature-owned UI messages; all built-in languages are exhaustive.

///|
priv enum UiMessage {
  Current
  PullRequestCount(Int32)
  BranchCount(Int32)
  CheckFailed
  RemoveFailed
  PartialCount
  Remove
  StateOpen
  StateDraft
  StateMerged
  StateClosed
  MoreActions
  OpenOnGitHub
  CopyLink
  CreatePullRequest
  ShowMore(Int32)
  ShowLess
  ChecksFailing(Int32)
  ChecksFailedCount(Int32)
  ChecksPendingCount(Int32)
  ChecksPassedCount(Int32)
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
    (English, MoreActions) => "More actions"
    (Spanish, MoreActions) => "Más acciones"
    (SimplifiedChinese, MoreActions) => "更多操作"
    (TraditionalChinese, MoreActions) => "更多動作"
    (Japanese, MoreActions) => "その他の操作"
    (English, OpenOnGitHub) => "Open on GitHub"
    (Spanish, OpenOnGitHub) => "Abrir en GitHub"
    (SimplifiedChinese, OpenOnGitHub) => "在 GitHub 上打开"
    (TraditionalChinese, OpenOnGitHub) => "在 GitHub 上開啟"
    (Japanese, OpenOnGitHub) => "GitHub で開く"
    (English, CopyLink) => "Copy link"
    (Spanish, CopyLink) => "Copiar enlace"
    (SimplifiedChinese, CopyLink) => "复制链接"
    (TraditionalChinese, CopyLink) => "複製連結"
    (Japanese, CopyLink) => "リンクをコピー"
    (English, CreatePullRequest) => "Create PR"
    (Spanish, CreatePullRequest) => "Crear PR"
    (SimplifiedChinese, CreatePullRequest) => "创建 PR"
    (TraditionalChinese, CreatePullRequest) => "建立 PR"
    (Japanese, CreatePullRequest) => "PR を作成"
    (English, ShowMore(count)) => "Show \{count} more"
    (Spanish, ShowMore(count)) => "Mostrar \{count} más"
    (SimplifiedChinese, ShowMore(count)) => "显示其余 \{count} 项"
    (TraditionalChinese, ShowMore(count)) => "顯示其餘 \{count} 項"
    (Japanese, ShowMore(count)) => "残り \{count} 件を表示"
    (English, ShowLess) => "Show less"
    (Spanish, ShowLess) => "Mostrar menos"
    (SimplifiedChinese, ShowLess) => "收起"
    (TraditionalChinese, ShowLess) => "收合"
    (Japanese, ShowLess) => "折りたたむ"
    (English, ChecksFailing(count)) => "\{count} failing"
    (Spanish, ChecksFailing(1)) => "1 fallida"
    (Spanish, ChecksFailing(count)) => "\{count} fallidas"
    (SimplifiedChinese, ChecksFailing(count)) => "\{count} 项失败"
    (TraditionalChinese, ChecksFailing(count)) => "\{count} 項失敗"
    (Japanese, ChecksFailing(count)) => "\{count} 件失敗"
    (English, ChecksFailedCount(count)) => "\{count} failed"
    (Spanish, ChecksFailedCount(1)) => "1 fallida"
    (Spanish, ChecksFailedCount(count)) => "\{count} fallidas"
    (SimplifiedChinese, ChecksFailedCount(count)) => "失败 \{count}"
    (TraditionalChinese, ChecksFailedCount(count)) => "失敗 \{count}"
    (Japanese, ChecksFailedCount(count)) => "失敗 \{count}"
    (English, ChecksPendingCount(count)) => "\{count} running"
    (Spanish, ChecksPendingCount(count)) => "\{count} en curso"
    (SimplifiedChinese, ChecksPendingCount(count)) => "进行中 \{count}"
    (TraditionalChinese, ChecksPendingCount(count)) => "進行中 \{count}"
    (Japanese, ChecksPendingCount(count)) => "実行中 \{count}"
    (English, ChecksPassedCount(count)) => "\{count} passed"
    (Spanish, ChecksPassedCount(1)) => "1 superada"
    (Spanish, ChecksPassedCount(count)) => "\{count} superadas"
    (SimplifiedChinese, ChecksPassedCount(count)) => "已通过 \{count}"
    (TraditionalChinese, ChecksPassedCount(count)) => "已通過 \{count}"
    (Japanese, ChecksPassedCount(count)) => "成功 \{count}"
  }
}
