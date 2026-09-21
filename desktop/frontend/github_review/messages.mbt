///|
priv enum UiMessage {
  ShowComments
  CommentsLabel
  RefreshComments
  DeletedUser
  DeleteComment
  ConfirmDelete
  CancelLabel
  DeleteLabel
  WriteComment
  ReplyLabel
  ReplyPlaceholder
  CommentPlaceholder
  SendingLabel
  SendLabel
  OriginalLine(Int)
  LineLabel(Int)
  FileConversation
  OutdatedLabel
  ResolvedShow
  ResolvedHide
  UnresolveConversation
  ResolveConversation
  CheckFailed(String)
  RetryCheck
  LoadingComments
  UpdateHint
  UpdatingCheckout
  UpdateCheckout
  OutsideDiff(Int)
  EarlierDraft
  EarlierRevision
  LineOutsideDiff
  WrongDraftPullRequest
  StorageUnavailable
  RestoreDraftsFailed(String)
  SaveDraftsFailed(String)
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, ShowComments) => "Show GitHub pull request comments"
    (SimplifiedChinese, ShowComments) => "显示 GitHub 拉取请求评论"
    (TraditionalChinese, ShowComments) => "顯示 GitHub 提取要求留言"
    (Japanese, ShowComments) =>
      "GitHub プルリクエストのコメントを表示"
    (Spanish, ShowComments) =>
      "Mostrar comentarios de la solicitud de incorporación de GitHub"
    (English, CommentsLabel) => "GitHub comments"
    (SimplifiedChinese, CommentsLabel) => "GitHub 评论"
    (TraditionalChinese, CommentsLabel) => "GitHub 留言"
    (Japanese, CommentsLabel) => "GitHub コメント"
    (Spanish, CommentsLabel) => "Comentarios de GitHub"
    (English, RefreshComments) => "Refresh GitHub comments"
    (SimplifiedChinese, RefreshComments) => "刷新 GitHub 评论"
    (TraditionalChinese, RefreshComments) => "重新整理 GitHub 留言"
    (Japanese, RefreshComments) => "GitHub コメントを更新"
    (Spanish, RefreshComments) => "Actualizar comentarios de GitHub"
    (English, DeletedUser) => "Deleted user"
    (SimplifiedChinese, DeletedUser) => "已删除用户"
    (TraditionalChinese, DeletedUser) => "已刪除使用者"
    (Japanese, DeletedUser) => "削除されたユーザー"
    (Spanish, DeletedUser) => "Usuario eliminado"
    (English, DeleteComment) => "Delete comment"
    (SimplifiedChinese, DeleteComment) => "删除评论"
    (TraditionalChinese, DeleteComment) => "刪除留言"
    (Japanese, DeleteComment) => "コメントを削除"
    (Spanish, DeleteComment) => "Eliminar comentario"
    (English, ConfirmDelete) => "Delete this comment?"
    (SimplifiedChinese, ConfirmDelete) => "删除这条评论？"
    (TraditionalChinese, ConfirmDelete) => "刪除這則留言？"
    (Japanese, ConfirmDelete) => "このコメントを削除しますか？"
    (Spanish, ConfirmDelete) => "¿Eliminar este comentario?"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (TraditionalChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (Spanish, CancelLabel) => "Cancelar"
    (English, DeleteLabel) => "Delete"
    (SimplifiedChinese, DeleteLabel) => "删除"
    (TraditionalChinese, DeleteLabel) => "刪除"
    (Japanese, DeleteLabel) => "削除"
    (Spanish, DeleteLabel) => "Eliminar"
    (English, WriteComment) => "Write a comment"
    (SimplifiedChinese, WriteComment) => "撰写评论"
    (TraditionalChinese, WriteComment) => "撰寫留言"
    (Japanese, WriteComment) => "コメントを入力"
    (Spanish, WriteComment) => "Escribir un comentario"
    (English, ReplyLabel) => "Reply"
    (SimplifiedChinese, ReplyLabel) => "回复"
    (TraditionalChinese, ReplyLabel) => "回覆"
    (Japanese, ReplyLabel) => "返信"
    (Spanish, ReplyLabel) => "Responder"
    (English, ReplyPlaceholder) => "Reply…"
    (SimplifiedChinese, ReplyPlaceholder) => "回复…"
    (TraditionalChinese, ReplyPlaceholder) => "回覆…"
    (Japanese, ReplyPlaceholder) => "返信…"
    (Spanish, ReplyPlaceholder) => "Responder…"
    (English, CommentPlaceholder) => "Leave a comment…"
    (SimplifiedChinese, CommentPlaceholder) => "留下评论…"
    (TraditionalChinese, CommentPlaceholder) => "留下留言…"
    (Japanese, CommentPlaceholder) => "コメントを入力…"
    (Spanish, CommentPlaceholder) => "Dejar un comentario…"
    (English, SendingLabel) => "Sending…"
    (SimplifiedChinese, SendingLabel) => "发送中…"
    (TraditionalChinese, SendingLabel) => "傳送中…"
    (Japanese, SendingLabel) => "送信中…"
    (Spanish, SendingLabel) => "Enviando…"
    (English, SendLabel) => "Send"
    (SimplifiedChinese, SendLabel) => "发送"
    (TraditionalChinese, SendLabel) => "傳送"
    (Japanese, SendLabel) => "送信"
    (Spanish, SendLabel) => "Enviar"
    (English, OriginalLine(number)) => "Original line \{number}"
    (SimplifiedChinese, OriginalLine(number)) => "原始行 \{number}"
    (TraditionalChinese, OriginalLine(number)) => "原始行 \{number}"
    (Japanese, OriginalLine(number)) => "変更前の \{number} 行目"
    (Spanish, OriginalLine(number)) => "Línea original \{number}"
    (English, LineLabel(number)) => "Line \{number}"
    (SimplifiedChinese, LineLabel(number)) => "第 \{number} 行"
    (TraditionalChinese, LineLabel(number)) => "第 \{number} 行"
    (Japanese, LineLabel(number)) => "\{number} 行目"
    (Spanish, LineLabel(number)) => "Línea \{number}"
    (English, FileConversation) => "File conversation"
    (SimplifiedChinese, FileConversation) => "文件讨论"
    (TraditionalChinese, FileConversation) => "檔案討論"
    (Japanese, FileConversation) => "ファイルのディスカッション"
    (Spanish, FileConversation) => "Discusión del archivo"
    (English, OutdatedLabel) => "Outdated"
    (SimplifiedChinese, OutdatedLabel) => "已过时"
    (TraditionalChinese, OutdatedLabel) => "已過時"
    (Japanese, OutdatedLabel) => "古い内容"
    (Spanish, OutdatedLabel) => "Obsoleta"
    (English, ResolvedShow) => "Resolved · Show conversation"
    (SimplifiedChinese, ResolvedShow) => "已解决 · 显示讨论"
    (TraditionalChinese, ResolvedShow) => "已解決 · 顯示討論"
    (Japanese, ResolvedShow) =>
      "解決済み · ディスカッションを表示"
    (Spanish, ResolvedShow) => "Resuelta · Mostrar discusión"
    (English, ResolvedHide) => "Resolved · Hide conversation"
    (SimplifiedChinese, ResolvedHide) => "已解决 · 隐藏讨论"
    (TraditionalChinese, ResolvedHide) => "已解決 · 隱藏討論"
    (Japanese, ResolvedHide) =>
      "解決済み · ディスカッションを非表示"
    (Spanish, ResolvedHide) => "Resuelta · Ocultar discusión"
    (English, UnresolveConversation) => "Unresolve conversation"
    (SimplifiedChinese, UnresolveConversation) => "重新打开讨论"
    (TraditionalChinese, UnresolveConversation) => "重新開啟討論"
    (Japanese, UnresolveConversation) =>
      "ディスカッションを未解決に戻す"
    (Spanish, UnresolveConversation) => "Reabrir discusión"
    (English, ResolveConversation) => "Resolve conversation"
    (SimplifiedChinese, ResolveConversation) => "解决讨论"
    (TraditionalChinese, ResolveConversation) => "解決討論"
    (Japanese, ResolveConversation) => "ディスカッションを解決"
    (Spanish, ResolveConversation) => "Resolver discusión"
    (English, CheckFailed(error)) =>
      "Could not check the current GitHub pull request. \{error}"
    (SimplifiedChinese, CheckFailed(error)) =>
      "无法检查当前 GitHub 拉取请求。\{error}"
    (TraditionalChinese, CheckFailed(error)) =>
      "無法檢查目前的 GitHub 提取要求。\{error}"
    (Japanese, CheckFailed(error)) =>
      "現在の GitHub プルリクエストを確認できませんでした。\{error}"
    (Spanish, CheckFailed(error)) =>
      "No se pudo comprobar la solicitud de incorporación actual de GitHub. \{error}"
    (English, RetryCheck) => "Retry PR check"
    (SimplifiedChinese, RetryCheck) => "重新检查 PR"
    (TraditionalChinese, RetryCheck) => "重新檢查 PR"
    (Japanese, RetryCheck) => "PR の確認を再試行"
    (Spanish, RetryCheck) => "Reintentar comprobación de la PR"
    (English, LoadingComments) => "Loading GitHub comments…"
    (SimplifiedChinese, LoadingComments) => "正在加载 GitHub 评论…"
    (TraditionalChinese, LoadingComments) => "正在載入 GitHub 留言…"
    (Japanese, LoadingComments) => "GitHub コメントを読み込み中…"
    (Spanish, LoadingComments) => "Cargando comentarios de GitHub…"
    (English, UpdateHint) =>
      "Update this checkout to the latest PR revision to add inline comments. Local edits can also make the comparison differ."
    (SimplifiedChinese, UpdateHint) =>
      "将本地检出更新到最新 PR 版本后即可添加行内评论。本地编辑也可能导致比较内容不同。"
    (TraditionalChinese, UpdateHint) =>
      "將本機簽出更新到最新 PR 版本後即可新增行內留言。本機編輯也可能導致比較內容不同。"
    (Japanese, UpdateHint) =>
      "行内コメントを追加するには、チェックアウトを最新の PR リビジョンに更新してください。ローカルの編集によっても比較内容が異なる場合があります。"
    (Spanish, UpdateHint) =>
      "Actualiza esta copia local a la última revisión de la PR para añadir comentarios en línea. Los cambios locales también pueden alterar la comparación."
    (English, UpdatingCheckout) => "Updating checkout…"
    (SimplifiedChinese, UpdatingCheckout) => "正在更新本地检出…"
    (TraditionalChinese, UpdatingCheckout) => "正在更新本機簽出…"
    (Japanese, UpdatingCheckout) => "チェックアウトを更新中…"
    (Spanish, UpdatingCheckout) => "Actualizando copia local…"
    (English, UpdateCheckout) => "Update checkout"
    (SimplifiedChinese, UpdateCheckout) => "更新本地检出"
    (TraditionalChinese, UpdateCheckout) => "更新本機簽出"
    (Japanese, UpdateCheckout) => "チェックアウトを更新"
    (Spanish, UpdateCheckout) => "Actualizar copia local"
    (English, OutsideDiff(count)) =>
      "Conversations outside the current diff (\{count})"
    (SimplifiedChinese, OutsideDiff(count)) =>
      "当前差异之外的讨论（\{count}）"
    (TraditionalChinese, OutsideDiff(count)) =>
      "目前差異之外的討論（\{count}）"
    (Japanese, OutsideDiff(count)) =>
      "現在の差分に含まれないディスカッション（\{count}）"
    (Spanish, OutsideDiff(count)) =>
      "Discusiones fuera de la diferencia actual (\{count})"
    (English, EarlierDraft) => "Local draft · earlier or hidden line"
    (SimplifiedChinese, EarlierDraft) => "本地草稿 · 旧版本或隐藏行"
    (TraditionalChinese, EarlierDraft) =>
      "本機草稿 · 舊版本或隱藏行"
    (Japanese, EarlierDraft) =>
      "ローカルの下書き · 以前の行または非表示の行"
    (Spanish, EarlierDraft) => "Borrador local · línea anterior u oculta"
    (English, EarlierRevision) =>
      "This draft belongs to an earlier PR revision. Copy it to a current line before sending."
    (SimplifiedChinese, EarlierRevision) =>
      "此草稿属于较早的 PR 版本。请复制到当前行后再发送。"
    (TraditionalChinese, EarlierRevision) =>
      "此草稿屬於較早的 PR 版本。請複製到目前的行後再傳送。"
    (Japanese, EarlierRevision) =>
      "この下書きは以前の PR リビジョンのものです。送信前に現在の行にコピーしてください。"
    (Spanish, EarlierRevision) =>
      "Este borrador pertenece a una revisión anterior de la PR. Cópialo a una línea actual antes de enviarlo."
    (English, LineOutsideDiff) =>
      "This line is outside the GitHub PR diff. Choose a current diff line; your draft is kept locally."
    (SimplifiedChinese, LineOutsideDiff) =>
      "此行不在 GitHub PR 差异中。请选择当前差异中的行；草稿已保留在本地。"
    (TraditionalChinese, LineOutsideDiff) =>
      "此行不在 GitHub PR 差異中。請選擇目前差異中的行；草稿已保留在本機。"
    (Japanese, LineOutsideDiff) =>
      "この行は GitHub PR の差分に含まれていません。現在の差分の行を選択してください。下書きはローカルに保持されます。"
    (Spanish, LineOutsideDiff) =>
      "Esta línea está fuera de la diferencia de la PR de GitHub. Elige una línea de la diferencia actual; el borrador se conserva localmente."
    (English, WrongDraftPullRequest) =>
      "Local drafts belong to a different pull request."
    (SimplifiedChinese, WrongDraftPullRequest) =>
      "本地草稿属于另一个拉取请求。"
    (TraditionalChinese, WrongDraftPullRequest) =>
      "本機草稿屬於另一個提取要求。"
    (Japanese, WrongDraftPullRequest) =>
      "ローカルの下書きは別のプルリクエストのものです。"
    (Spanish, WrongDraftPullRequest) =>
      "Los borradores locales pertenecen a otra solicitud de incorporación."
    (English, StorageUnavailable) => "Local draft storage is unavailable."
    (SimplifiedChinese, StorageUnavailable) => "本地草稿存储不可用。"
    (TraditionalChinese, StorageUnavailable) =>
      "本機草稿儲存空間無法使用。"
    (Japanese, StorageUnavailable) =>
      "ローカルの下書きストレージを利用できません。"
    (Spanish, StorageUnavailable) =>
      "El almacenamiento local de borradores no está disponible."
    (English, RestoreDraftsFailed(error)) =>
      "Could not restore local comment drafts: \{error}"
    (SimplifiedChinese, RestoreDraftsFailed(error)) =>
      "无法恢复本地评论草稿：\{error}"
    (TraditionalChinese, RestoreDraftsFailed(error)) =>
      "無法還原本機留言草稿：\{error}"
    (Japanese, RestoreDraftsFailed(error)) =>
      "ローカルのコメント下書きを復元できませんでした：\{error}"
    (Spanish, RestoreDraftsFailed(error)) =>
      "No se pudieron restaurar los borradores de comentarios locales: \{error}"
    (English, SaveDraftsFailed(error)) =>
      "Your draft remains in this window, but could not be saved locally: \{error}"
    (SimplifiedChinese, SaveDraftsFailed(error)) =>
      "草稿仍保留在此窗口中，但无法保存到本地：\{error}"
    (TraditionalChinese, SaveDraftsFailed(error)) =>
      "草稿仍保留在此視窗中，但無法儲存至本機：\{error}"
    (Japanese, SaveDraftsFailed(error)) =>
      "下書きはこのウィンドウに残っていますが、ローカルに保存できませんでした：\{error}"
    (Spanish, SaveDraftsFailed(error)) =>
      "El borrador sigue en esta ventana, pero no se pudo guardar localmente: \{error}"
  }
}

///|
/// Preserve frontend failures as data so existing notices follow live language changes.
pub(all) enum Failure {
  Remote(String)
  EarlierRevision
  LineOutsideDiff
  WrongDraftPullRequest
  StorageUnavailable
  RestoreDraftsFailed(String)
  SaveDraftsFailed(String)
} derive(Eq, Debug)

///|
pub extend Failure with Eq::{equal, not_equal}

///|
pub extend Failure with Debug::{to_repr}

///|
fn failure_text(locale : @i18n.Locale, failure : Failure) -> String {
  match failure {
    Remote(error) => error
    EarlierRevision => ui(locale, EarlierRevision)
    LineOutsideDiff => ui(locale, LineOutsideDiff)
    WrongDraftPullRequest => ui(locale, WrongDraftPullRequest)
    StorageUnavailable => ui(locale, StorageUnavailable)
    RestoreDraftsFailed(error) => ui(locale, RestoreDraftsFailed(error))
    SaveDraftsFailed(error) => ui(locale, SaveDraftsFailed(error))
  }
}
