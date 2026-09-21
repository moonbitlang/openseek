///|
priv enum UiMessage {
  SuccessfulChecks(Int)
  PendingChecks(Int)
  FailedChecks(Int)
  CancelledChecks(Int)
  SkippedChecks(Int)
  NeutralChecks(Int)
  OtherChecks(Int)
  BeforeCheckout(Int)
  BeforeUpdate(Int)
  RetryAvatars
  DraftLabel
  CurrentCheckout
  NoCreatedPulls
  NoOpenPulls
  NoOpenIssues
  LoadMore
  ViewAll
  LoadingLabel
  RetryLabel
  UpdatingCheckout(Int)
  CheckingOut(Int)
  UpdateCheckout(Int)
  CheckoutLocally(Int)
  PullRequestsLabel
  CreatedByMeLabel
  AllOpenLabel
  IssuesLabel
  RefreshGithub
  OpenRepositoryHint
  ConnectGithubHint
  SelectPullRequestHint
  LoadingPullRequest
  ConnectPullRequestHint
  OpenPullRequest
  DeletedUser
  OpenOnGithub
  RefreshPullRequest
  RefreshingLabel
  RefreshLabel
  CloseDetails
  OpenLabel
  MergedLabel
  ClosedLabel
  ConversationLabel
  CommentedAt(String)
  AuthorLabel
  NoDescription
  DetailsLabel
  ReviewersLabel
  NoReviews
  ApprovedLabel
  ChangesRequested
  ReviewRequested
  CommentedLabel
  DismissedLabel
  PendingLabel
  AssigneesLabel
  NoAssignees
  LabelsLabel
  NoLabels
  MilestoneLabel
  NoMilestone
  ChangesLabel
  ChangedFiles(Int)
  ChecksLabel
  NoChecks
  CheckStatus
  ShowLabel
  HideLabel
  CheckResults
  NoChecksReported
  SuccessfulLabel
  FailedLabel
  CancelledLabel
  SkippedLabel
  NeutralLabel
  QueuedLabel
  InProgressLabel
  ExpectedLabel
  WaitingLabel
  RequestedLabel
  TimedOutLabel
  ActionRequiredLabel
  StartupFailureLabel
  StaleLabel
  StatusCheck
  CheckDetails(String)
  ViewDetails
  MergeSucceeded
  PullRequestClosed
  NoConflicts
  HasConflicts
  ConflictsUnavailable
  MergeConflictStatus
  DismissCheckout
  HideDetails
  ShowDetails
  UncommittedBeforeUpdate(Int)
  UncommittedBeforeCheckout(Int)
  UncommittedChanges
  StashChanges
  DiscardChanges
  UpdateAnyway
  CheckoutAnyway
  CancelLabel
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, SuccessfulChecks(count)) =>
      if count == 1 {
        "1 successful check"
      } else {
        "\{count} successful checks"
      }
    (SimplifiedChinese, SuccessfulChecks(count)) => "\{count} 项检查成功"
    (TraditionalChinese, SuccessfulChecks(count)) => "\{count} 項檢查成功"
    (Japanese, SuccessfulChecks(count)) => "成功のチェック \{count} 件"
    (Spanish, SuccessfulChecks(count)) =>
      if count == 1 {
        "1 comprobación correcta"
      } else {
        "\{count} comprobaciones correctas"
      }
    (English, PendingChecks(count)) =>
      if count == 1 {
        "1 pending check"
      } else {
        "\{count} pending checks"
      }
    (SimplifiedChinese, PendingChecks(count)) => "\{count} 项检查等待中"
    (TraditionalChinese, PendingChecks(count)) => "\{count} 項檢查等待中"
    (Japanese, PendingChecks(count)) => "保留中のチェック \{count} 件"
    (Spanish, PendingChecks(count)) =>
      if count == 1 {
        "1 comprobación pendiente"
      } else {
        "\{count} comprobaciones pendientes"
      }
    (English, FailedChecks(count)) =>
      if count == 1 {
        "1 failed check"
      } else {
        "\{count} failed checks"
      }
    (SimplifiedChinese, FailedChecks(count)) => "\{count} 项检查失败"
    (TraditionalChinese, FailedChecks(count)) => "\{count} 項檢查失敗"
    (Japanese, FailedChecks(count)) => "失敗のチェック \{count} 件"
    (Spanish, FailedChecks(count)) =>
      if count == 1 {
        "1 comprobación fallida"
      } else {
        "\{count} comprobaciones fallidas"
      }
    (English, CancelledChecks(count)) =>
      if count == 1 {
        "1 cancelled check"
      } else {
        "\{count} cancelled checks"
      }
    (SimplifiedChinese, CancelledChecks(count)) => "\{count} 项检查已取消"
    (TraditionalChinese, CancelledChecks(count)) =>
      "\{count} 項檢查已取消"
    (Japanese, CancelledChecks(count)) =>
      "キャンセル済みのチェック \{count} 件"
    (Spanish, CancelledChecks(count)) =>
      if count == 1 {
        "1 comprobación cancelada"
      } else {
        "\{count} comprobaciones canceladas"
      }
    (English, SkippedChecks(count)) =>
      if count == 1 {
        "1 skipped check"
      } else {
        "\{count} skipped checks"
      }
    (SimplifiedChinese, SkippedChecks(count)) => "\{count} 项检查已跳过"
    (TraditionalChinese, SkippedChecks(count)) => "\{count} 項檢查已略過"
    (Japanese, SkippedChecks(count)) =>
      "スキップ済みのチェック \{count} 件"
    (Spanish, SkippedChecks(count)) =>
      if count == 1 {
        "1 comprobación omitida"
      } else {
        "\{count} comprobaciones omitidas"
      }
    (English, NeutralChecks(count)) =>
      if count == 1 {
        "1 neutral check"
      } else {
        "\{count} neutral checks"
      }
    (SimplifiedChinese, NeutralChecks(count)) => "\{count} 项检查中性"
    (TraditionalChinese, NeutralChecks(count)) => "\{count} 項檢查中性"
    (Japanese, NeutralChecks(count)) => "中立のチェック \{count} 件"
    (Spanish, NeutralChecks(count)) =>
      if count == 1 {
        "1 comprobación neutral"
      } else {
        "\{count} comprobaciones neutrales"
      }
    (English, OtherChecks(count)) =>
      if count == 1 {
        "1 other check"
      } else {
        "\{count} other checks"
      }
    (SimplifiedChinese, OtherChecks(count)) =>
      "\{count} 项检查处于其他状态"
    (TraditionalChinese, OtherChecks(count)) =>
      "\{count} 項檢查處於其他狀態"
    (Japanese, OtherChecks(count)) => "その他のチェック \{count} 件"
    (Spanish, OtherChecks(count)) =>
      if count == 1 {
        "1 comprobación con otro estado"
      } else {
        "\{count} comprobaciones con otro estado"
      }
    (English, BeforeCheckout(number)) =>
      "Choose how to handle your changes before checking out PR #\{number}. Stashed changes remain saved for later. Discard permanently removes tracked changes. Untracked files are kept."
    (SimplifiedChinese, BeforeCheckout(number)) =>
      "请在检出 PR #\{number} 前选择如何处理更改。暂存的更改可稍后恢复。丢弃会永久删除已跟踪文件的更改。未跟踪文件会保留。"
    (TraditionalChinese, BeforeCheckout(number)) =>
      "請在簽出 PR #\{number} 前選擇如何處理變更。暫存的變更可稍後還原。捨棄會永久刪除已追蹤檔案的變更。未追蹤檔案會保留。"
    (Japanese, BeforeCheckout(number)) =>
      "PR #\{number} のチェックアウト前に、変更の扱いを選択してください。スタッシュした変更は後で復元できます。破棄すると追跡対象の変更が完全に削除されます。未追跡のファイルは保持されます。"
    (Spanish, BeforeCheckout(number)) =>
      "Elige cómo gestionar tus cambios antes de obtener la PR #\{number}. Los cambios guardados en stash se conservan para después. Descartar elimina permanentemente los cambios en archivos con seguimiento. Los archivos sin seguimiento se conservan."
    (English, BeforeUpdate(number)) =>
      "Choose how to handle your changes before updating the checkout for PR #\{number}. Stashed changes remain saved for later. Discard permanently removes tracked changes. Untracked files are kept."
    (SimplifiedChinese, BeforeUpdate(number)) =>
      "请在更新 PR #\{number} 的本地检出前选择如何处理更改。暂存的更改可稍后恢复。丢弃会永久删除已跟踪文件的更改。未跟踪文件会保留。"
    (TraditionalChinese, BeforeUpdate(number)) =>
      "請在更新 PR #\{number} 的本機簽出前選擇如何處理變更。暫存的變更可稍後還原。捨棄會永久刪除已追蹤檔案的變更。未追蹤檔案會保留。"
    (Japanese, BeforeUpdate(number)) =>
      "PR #\{number} のチェックアウトを更新する前に、変更の扱いを選択してください。スタッシュした変更は後で復元できます。破棄すると追跡対象の変更が完全に削除されます。未追跡のファイルは保持されます。"
    (Spanish, BeforeUpdate(number)) =>
      "Elige cómo gestionar tus cambios antes de actualizar la copia local de la PR #\{number}. Los cambios guardados en stash se conservan para después. Descartar elimina permanentemente los cambios en archivos con seguimiento. Los archivos sin seguimiento se conservan."
    (English, RetryAvatars) => "Retry avatars"
    (SimplifiedChinese, RetryAvatars) => "重新加载头像"
    (TraditionalChinese, RetryAvatars) => "重新載入頭像"
    (Japanese, RetryAvatars) => "アバターを再読み込み"
    (Spanish, RetryAvatars) => "Reintentar avatares"
    (English, DraftLabel) => "Draft"
    (SimplifiedChinese, DraftLabel) => "草稿"
    (TraditionalChinese, DraftLabel) => "草稿"
    (Japanese, DraftLabel) => "下書き"
    (Spanish, DraftLabel) => "Borrador"
    (English, CurrentCheckout) => "Currently checked out"
    (SimplifiedChinese, CurrentCheckout) => "当前已检出"
    (TraditionalChinese, CurrentCheckout) => "目前已簽出"
    (Japanese, CurrentCheckout) => "チェックアウト中"
    (Spanish, CurrentCheckout) => "Actualmente en uso"
    (English, NoCreatedPulls) => "No open pull requests created by you."
    (SimplifiedChinese, NoCreatedPulls) =>
      "你创建的拉取请求中没有待处理项。"
    (TraditionalChinese, NoCreatedPulls) =>
      "你建立的提取要求中沒有待處理項目。"
    (Japanese, NoCreatedPulls) =>
      "作成した未完了のプルリクエストはありません。"
    (Spanish, NoCreatedPulls) =>
      "No hay solicitudes de incorporación abiertas creadas por ti."
    (English, NoOpenPulls) => "No open pull requests."
    (SimplifiedChinese, NoOpenPulls) => "没有待处理的拉取请求。"
    (TraditionalChinese, NoOpenPulls) => "沒有待處理的提取要求。"
    (Japanese, NoOpenPulls) =>
      "未完了のプルリクエストはありません。"
    (Spanish, NoOpenPulls) => "No hay solicitudes de incorporación abiertas."
    (English, NoOpenIssues) => "No open issues."
    (SimplifiedChinese, NoOpenIssues) => "没有待处理的议题。"
    (TraditionalChinese, NoOpenIssues) => "沒有待處理的議題。"
    (Japanese, NoOpenIssues) => "未解決の Issue はありません。"
    (Spanish, NoOpenIssues) => "No hay incidencias abiertas."
    (English, LoadMore) => "Load more…"
    (SimplifiedChinese, LoadMore) => "加载更多…"
    (TraditionalChinese, LoadMore) => "載入更多…"
    (Japanese, LoadMore) => "さらに読み込む…"
    (Spanish, LoadMore) => "Cargar más…"
    (English, ViewAll) => "View all on GitHub"
    (SimplifiedChinese, ViewAll) => "在 GitHub 上查看全部"
    (TraditionalChinese, ViewAll) => "在 GitHub 上檢視全部"
    (Japanese, ViewAll) => "GitHub ですべて表示"
    (Spanish, ViewAll) => "Ver todo en GitHub"
    (English, LoadingLabel) => "Loading…"
    (SimplifiedChinese, LoadingLabel) => "加载中…"
    (TraditionalChinese, LoadingLabel) => "載入中…"
    (Japanese, LoadingLabel) => "読み込み中…"
    (Spanish, LoadingLabel) => "Cargando…"
    (English, RetryLabel) => "Retry"
    (SimplifiedChinese, RetryLabel) => "重试"
    (TraditionalChinese, RetryLabel) => "重試"
    (Japanese, RetryLabel) => "再試行"
    (Spanish, RetryLabel) => "Reintentar"
    (English, UpdatingCheckout(number)) =>
      "Updating checkout for PR #\{number}…"
    (SimplifiedChinese, UpdatingCheckout(number)) =>
      "正在更新 PR #\{number} 的本地检出…"
    (TraditionalChinese, UpdatingCheckout(number)) =>
      "正在更新 PR #\{number} 的本機簽出…"
    (Japanese, UpdatingCheckout(number)) =>
      "PR #\{number} のチェックアウトを更新中…"
    (Spanish, UpdatingCheckout(number)) =>
      "Actualizando la copia local de la PR #\{number}…"
    (English, CheckingOut(number)) => "Checking out PR #\{number}…"
    (SimplifiedChinese, CheckingOut(number)) => "正在检出 PR #\{number}…"
    (TraditionalChinese, CheckingOut(number)) => "正在簽出 PR #\{number}…"
    (Japanese, CheckingOut(number)) =>
      "PR #\{number} をチェックアウト中…"
    (Spanish, CheckingOut(number)) => "Obteniendo la PR #\{number}…"
    (English, UpdateCheckout(number)) => "Update checkout for PR #\{number}"
    (SimplifiedChinese, UpdateCheckout(number)) =>
      "更新 PR #\{number} 的本地检出"
    (TraditionalChinese, UpdateCheckout(number)) =>
      "更新 PR #\{number} 的本機簽出"
    (Japanese, UpdateCheckout(number)) =>
      "PR #\{number} のチェックアウトを更新"
    (Spanish, UpdateCheckout(number)) =>
      "Actualizar la copia local de la PR #\{number}"
    (English, CheckoutLocally(number)) => "Check out PR #\{number} locally"
    (SimplifiedChinese, CheckoutLocally(number)) =>
      "在本地检出 PR #\{number}"
    (TraditionalChinese, CheckoutLocally(number)) =>
      "在本機簽出 PR #\{number}"
    (Japanese, CheckoutLocally(number)) =>
      "PR #\{number} をローカルにチェックアウト"
    (Spanish, CheckoutLocally(number)) => "Obtener la PR #\{number} localmente"
    (English, PullRequestsLabel) => "Pull Requests"
    (SimplifiedChinese, PullRequestsLabel) => "拉取请求"
    (TraditionalChinese, PullRequestsLabel) => "提取要求"
    (Japanese, PullRequestsLabel) => "プルリクエスト"
    (Spanish, PullRequestsLabel) => "Solicitudes de incorporación"
    (English, CreatedByMeLabel) => "Created By Me"
    (SimplifiedChinese, CreatedByMeLabel) => "我创建的"
    (TraditionalChinese, CreatedByMeLabel) => "我建立的"
    (Japanese, CreatedByMeLabel) => "自分が作成"
    (Spanish, CreatedByMeLabel) => "Creadas por mí"
    (English, AllOpenLabel) => "All Open"
    (SimplifiedChinese, AllOpenLabel) => "全部待处理"
    (TraditionalChinese, AllOpenLabel) => "全部待處理"
    (Japanese, AllOpenLabel) => "すべての未完了"
    (Spanish, AllOpenLabel) => "Todas las abiertas"
    (English, IssuesLabel) => "Issues"
    (SimplifiedChinese, IssuesLabel) => "议题"
    (TraditionalChinese, IssuesLabel) => "議題"
    (Japanese, IssuesLabel) => "Issue"
    (Spanish, IssuesLabel) => "Incidencias"
    (English, RefreshGithub) => "Refresh GitHub"
    (SimplifiedChinese, RefreshGithub) => "刷新 GitHub"
    (TraditionalChinese, RefreshGithub) => "重新整理 GitHub"
    (Japanese, RefreshGithub) => "GitHub を更新"
    (Spanish, RefreshGithub) => "Actualizar GitHub"
    (English, OpenRepositoryHint) =>
      "Open a task with a GitHub repository to see pull requests and issues."
    (SimplifiedChinese, OpenRepositoryHint) =>
      "打开关联 GitHub 仓库的任务以查看拉取请求和议题。"
    (TraditionalChinese, OpenRepositoryHint) =>
      "開啟關聯 GitHub 儲存庫的任務以檢視提取要求和議題。"
    (Japanese, OpenRepositoryHint) =>
      "GitHub リポジトリのタスクを開くと、プルリクエストと Issue が表示されます。"
    (Spanish, OpenRepositoryHint) =>
      "Abre una tarea con un repositorio de GitHub para ver solicitudes de incorporación e incidencias."
    (English, ConnectGithubHint) =>
      "Connect to the workspace host to load GitHub."
    (SimplifiedChinese, ConnectGithubHint) =>
      "连接工作区主机以加载 GitHub。"
    (TraditionalChinese, ConnectGithubHint) =>
      "連線至工作區主機以載入 GitHub。"
    (Japanese, ConnectGithubHint) =>
      "GitHub を読み込むにはワークスペースのホストに接続してください。"
    (Spanish, ConnectGithubHint) =>
      "Conéctate al host del espacio de trabajo para cargar GitHub."
    (English, SelectPullRequestHint) =>
      "Select a pull request to view its description and discussion."
    (SimplifiedChinese, SelectPullRequestHint) =>
      "选择拉取请求以查看描述和讨论。"
    (TraditionalChinese, SelectPullRequestHint) =>
      "選取提取要求以檢視描述和討論。"
    (Japanese, SelectPullRequestHint) =>
      "プルリクエストを選択すると、説明とディスカッションが表示されます。"
    (Spanish, SelectPullRequestHint) =>
      "Selecciona una solicitud de incorporación para ver su descripción y discusión."
    (English, LoadingPullRequest) => "Loading pull request…"
    (SimplifiedChinese, LoadingPullRequest) => "正在加载拉取请求…"
    (TraditionalChinese, LoadingPullRequest) => "正在載入提取要求…"
    (Japanese, LoadingPullRequest) =>
      "プルリクエストを読み込み中…"
    (Spanish, LoadingPullRequest) => "Cargando solicitud de incorporación…"
    (English, ConnectPullRequestHint) =>
      "Connect to the workspace host to refresh this pull request."
    (SimplifiedChinese, ConnectPullRequestHint) =>
      "连接工作区主机以刷新此拉取请求。"
    (TraditionalChinese, ConnectPullRequestHint) =>
      "連線至工作區主機以重新整理此提取要求。"
    (Japanese, ConnectPullRequestHint) =>
      "このプルリクエストを更新するにはワークスペースのホストに接続してください。"
    (Spanish, ConnectPullRequestHint) =>
      "Conéctate al host del espacio de trabajo para actualizar esta solicitud de incorporación."
    (English, OpenPullRequest) => "Open pull request on GitHub"
    (SimplifiedChinese, OpenPullRequest) => "在 GitHub 上打开拉取请求"
    (TraditionalChinese, OpenPullRequest) => "在 GitHub 上開啟提取要求"
    (Japanese, OpenPullRequest) => "GitHub でプルリクエストを開く"
    (Spanish, OpenPullRequest) => "Abrir solicitud de incorporación en GitHub"
    (English, DeletedUser) => "Deleted user"
    (SimplifiedChinese, DeletedUser) => "已删除用户"
    (TraditionalChinese, DeletedUser) => "已刪除使用者"
    (Japanese, DeletedUser) => "削除されたユーザー"
    (Spanish, DeletedUser) => "Usuario eliminado"
    (English, OpenOnGithub) => "Open on GitHub"
    (SimplifiedChinese, OpenOnGithub) => "在 GitHub 上打开"
    (TraditionalChinese, OpenOnGithub) => "在 GitHub 上開啟"
    (Japanese, OpenOnGithub) => "GitHub で開く"
    (Spanish, OpenOnGithub) => "Abrir en GitHub"
    (English, RefreshPullRequest) => "Refresh pull request"
    (SimplifiedChinese, RefreshPullRequest) => "刷新拉取请求"
    (TraditionalChinese, RefreshPullRequest) => "重新整理提取要求"
    (Japanese, RefreshPullRequest) => "プルリクエストを更新"
    (Spanish, RefreshPullRequest) => "Actualizar solicitud de incorporación"
    (English, RefreshingLabel) => "Refreshing…"
    (SimplifiedChinese, RefreshingLabel) => "刷新中…"
    (TraditionalChinese, RefreshingLabel) => "重新整理中…"
    (Japanese, RefreshingLabel) => "更新中…"
    (Spanish, RefreshingLabel) => "Actualizando…"
    (English, RefreshLabel) => "Refresh"
    (SimplifiedChinese, RefreshLabel) => "刷新"
    (TraditionalChinese, RefreshLabel) => "重新整理"
    (Japanese, RefreshLabel) => "更新"
    (Spanish, RefreshLabel) => "Actualizar"
    (English, CloseDetails) => "Close pull request details"
    (SimplifiedChinese, CloseDetails) => "关闭拉取请求详情"
    (TraditionalChinese, CloseDetails) => "關閉提取要求詳細資料"
    (Japanese, CloseDetails) => "プルリクエストの詳細を閉じる"
    (Spanish, CloseDetails) =>
      "Cerrar detalles de la solicitud de incorporación"
    (English, OpenLabel) => "Open"
    (SimplifiedChinese, OpenLabel) => "待处理"
    (TraditionalChinese, OpenLabel) => "待處理"
    (Japanese, OpenLabel) => "未完了"
    (Spanish, OpenLabel) => "Abierta"
    (English, MergedLabel) => "Merged"
    (SimplifiedChinese, MergedLabel) => "已合并"
    (TraditionalChinese, MergedLabel) => "已合併"
    (Japanese, MergedLabel) => "マージ済み"
    (Spanish, MergedLabel) => "Fusionada"
    (English, ClosedLabel) => "Closed"
    (SimplifiedChinese, ClosedLabel) => "已关闭"
    (TraditionalChinese, ClosedLabel) => "已關閉"
    (Japanese, ClosedLabel) => "クローズ済み"
    (Spanish, ClosedLabel) => "Cerrada"
    (English, ConversationLabel) => "Pull request conversation"
    (SimplifiedChinese, ConversationLabel) => "拉取请求讨论"
    (TraditionalChinese, ConversationLabel) => "提取要求討論"
    (Japanese, ConversationLabel) =>
      "プルリクエストのディスカッション"
    (Spanish, ConversationLabel) =>
      "Discusión de la solicitud de incorporación"
    (English, CommentedAt(date)) => "commented \{date}"
    (SimplifiedChinese, CommentedAt(date)) => "评论于\{date}"
    (TraditionalChinese, CommentedAt(date)) => "留言於\{date}"
    (Japanese, CommentedAt(date)) => "\{date}にコメント"
    (Spanish, CommentedAt(date)) => "comentó \{date}"
    (English, AuthorLabel) => "Author"
    (SimplifiedChinese, AuthorLabel) => "作者"
    (TraditionalChinese, AuthorLabel) => "作者"
    (Japanese, AuthorLabel) => "作成者"
    (Spanish, AuthorLabel) => "Autor"
    (English, NoDescription) => "No description provided."
    (SimplifiedChinese, NoDescription) => "未提供描述。"
    (TraditionalChinese, NoDescription) => "未提供描述。"
    (Japanese, NoDescription) => "説明はありません。"
    (Spanish, NoDescription) => "No se proporcionó ninguna descripción."
    (English, DetailsLabel) => "Pull request details"
    (SimplifiedChinese, DetailsLabel) => "拉取请求详情"
    (TraditionalChinese, DetailsLabel) => "提取要求詳細資料"
    (Japanese, DetailsLabel) => "プルリクエストの詳細"
    (Spanish, DetailsLabel) => "Detalles de la solicitud de incorporación"
    (English, ReviewersLabel) => "Reviewers"
    (SimplifiedChinese, ReviewersLabel) => "审阅者"
    (TraditionalChinese, ReviewersLabel) => "審閱者"
    (Japanese, ReviewersLabel) => "レビュアー"
    (Spanish, ReviewersLabel) => "Revisores"
    (English, NoReviews) => "No reviews yet"
    (SimplifiedChinese, NoReviews) => "暂无审阅"
    (TraditionalChinese, NoReviews) => "尚無審閱"
    (Japanese, NoReviews) => "レビューはまだありません"
    (Spanish, NoReviews) => "Aún no hay revisiones"
    (English, ApprovedLabel) => "Approved"
    (SimplifiedChinese, ApprovedLabel) => "已批准"
    (TraditionalChinese, ApprovedLabel) => "已核准"
    (Japanese, ApprovedLabel) => "承認済み"
    (Spanish, ApprovedLabel) => "Aprobado"
    (English, ChangesRequested) => "Changes requested"
    (SimplifiedChinese, ChangesRequested) => "要求更改"
    (TraditionalChinese, ChangesRequested) => "要求變更"
    (Japanese, ChangesRequested) => "変更をリクエスト済み"
    (Spanish, ChangesRequested) => "Cambios solicitados"
    (English, ReviewRequested) => "Review requested"
    (SimplifiedChinese, ReviewRequested) => "已请求审阅"
    (TraditionalChinese, ReviewRequested) => "已要求審閱"
    (Japanese, ReviewRequested) => "レビューを依頼済み"
    (Spanish, ReviewRequested) => "Revisión solicitada"
    (English, CommentedLabel) => "Commented"
    (SimplifiedChinese, CommentedLabel) => "已评论"
    (TraditionalChinese, CommentedLabel) => "已留言"
    (Japanese, CommentedLabel) => "コメント済み"
    (Spanish, CommentedLabel) => "Comentado"
    (English, DismissedLabel) => "Dismissed"
    (SimplifiedChinese, DismissedLabel) => "已撤销"
    (TraditionalChinese, DismissedLabel) => "已撤銷"
    (Japanese, DismissedLabel) => "却下済み"
    (Spanish, DismissedLabel) => "Descartado"
    (English, PendingLabel) => "Pending"
    (SimplifiedChinese, PendingLabel) => "等待中"
    (TraditionalChinese, PendingLabel) => "等待中"
    (Japanese, PendingLabel) => "待機中"
    (Spanish, PendingLabel) => "Pendiente"
    (English, AssigneesLabel) => "Assignees"
    (SimplifiedChinese, AssigneesLabel) => "负责人"
    (TraditionalChinese, AssigneesLabel) => "負責人"
    (Japanese, AssigneesLabel) => "担当者"
    (Spanish, AssigneesLabel) => "Responsables"
    (English, NoAssignees) => "No one assigned"
    (SimplifiedChinese, NoAssignees) => "未分配负责人"
    (TraditionalChinese, NoAssignees) => "未指派負責人"
    (Japanese, NoAssignees) => "担当者なし"
    (Spanish, NoAssignees) => "Sin asignar"
    (English, LabelsLabel) => "Labels"
    (SimplifiedChinese, LabelsLabel) => "标签"
    (TraditionalChinese, LabelsLabel) => "標籤"
    (Japanese, LabelsLabel) => "ラベル"
    (Spanish, LabelsLabel) => "Etiquetas"
    (English, NoLabels) => "None yet"
    (SimplifiedChinese, NoLabels) => "暂无"
    (TraditionalChinese, NoLabels) => "尚無"
    (Japanese, NoLabels) => "なし"
    (Spanish, NoLabels) => "Ninguna"
    (English, MilestoneLabel) => "Milestone"
    (SimplifiedChinese, MilestoneLabel) => "里程碑"
    (TraditionalChinese, MilestoneLabel) => "里程碑"
    (Japanese, MilestoneLabel) => "マイルストーン"
    (Spanish, MilestoneLabel) => "Hito"
    (English, NoMilestone) => "No milestone"
    (SimplifiedChinese, NoMilestone) => "无里程碑"
    (TraditionalChinese, NoMilestone) => "無里程碑"
    (Japanese, NoMilestone) => "マイルストーンなし"
    (Spanish, NoMilestone) => "Sin hito"
    (English, ChangesLabel) => "Changes"
    (SimplifiedChinese, ChangesLabel) => "更改"
    (TraditionalChinese, ChangesLabel) => "變更"
    (Japanese, ChangesLabel) => "変更"
    (Spanish, ChangesLabel) => "Cambios"
    (English, ChangedFiles(count)) =>
      if count == 1 {
        "1 changed file"
      } else {
        "\{count} changed files"
      }
    (SimplifiedChinese, ChangedFiles(count)) => "\{count} 个文件已更改"
    (TraditionalChinese, ChangedFiles(count)) => "\{count} 個檔案已變更"
    (Japanese, ChangedFiles(count)) => "\{count} 個のファイルを変更"
    (Spanish, ChangedFiles(count)) =>
      if count == 1 {
        "1 archivo modificado"
      } else {
        "\{count} archivos modificados"
      }
    (English, ChecksLabel) => "Checks"
    (SimplifiedChinese, ChecksLabel) => "检查"
    (TraditionalChinese, ChecksLabel) => "檢查"
    (Japanese, ChecksLabel) => "チェック"
    (Spanish, ChecksLabel) => "Comprobaciones"
    (English, NoChecks) => "No checks"
    (SimplifiedChinese, NoChecks) => "无检查"
    (TraditionalChinese, NoChecks) => "無檢查"
    (Japanese, NoChecks) => "チェックなし"
    (Spanish, NoChecks) => "Sin comprobaciones"
    (English, CheckStatus) => "Check status"
    (SimplifiedChinese, CheckStatus) => "检查状态"
    (TraditionalChinese, CheckStatus) => "檢查狀態"
    (Japanese, CheckStatus) => "チェックの状態"
    (Spanish, CheckStatus) => "Estado de las comprobaciones"
    (English, ShowLabel) => "Show"
    (SimplifiedChinese, ShowLabel) => "显示"
    (TraditionalChinese, ShowLabel) => "顯示"
    (Japanese, ShowLabel) => "表示"
    (Spanish, ShowLabel) => "Mostrar"
    (English, HideLabel) => "Hide"
    (SimplifiedChinese, HideLabel) => "隐藏"
    (TraditionalChinese, HideLabel) => "隱藏"
    (Japanese, HideLabel) => "非表示"
    (Spanish, HideLabel) => "Ocultar"
    (English, CheckResults) => "Check results"
    (SimplifiedChinese, CheckResults) => "检查结果"
    (TraditionalChinese, CheckResults) => "檢查結果"
    (Japanese, CheckResults) => "チェック結果"
    (Spanish, CheckResults) => "Resultados de las comprobaciones"
    (English, NoChecksReported) => "No checks reported"
    (SimplifiedChinese, NoChecksReported) => "暂无检查结果"
    (TraditionalChinese, NoChecksReported) => "尚無檢查結果"
    (Japanese, NoChecksReported) => "チェック結果はまだありません"
    (Spanish, NoChecksReported) => "No hay resultados de comprobaciones"
    (English, SuccessfulLabel) => "Successful"
    (SimplifiedChinese, SuccessfulLabel) => "成功"
    (TraditionalChinese, SuccessfulLabel) => "成功"
    (Japanese, SuccessfulLabel) => "成功"
    (Spanish, SuccessfulLabel) => "Correcta"
    (English, FailedLabel) => "Failed"
    (SimplifiedChinese, FailedLabel) => "失败"
    (TraditionalChinese, FailedLabel) => "失敗"
    (Japanese, FailedLabel) => "失敗"
    (Spanish, FailedLabel) => "Fallida"
    (English, CancelledLabel) => "Cancelled"
    (SimplifiedChinese, CancelledLabel) => "已取消"
    (TraditionalChinese, CancelledLabel) => "已取消"
    (Japanese, CancelledLabel) => "キャンセル済み"
    (Spanish, CancelledLabel) => "Cancelada"
    (English, SkippedLabel) => "Skipped"
    (SimplifiedChinese, SkippedLabel) => "已跳过"
    (TraditionalChinese, SkippedLabel) => "已略過"
    (Japanese, SkippedLabel) => "スキップ済み"
    (Spanish, SkippedLabel) => "Omitida"
    (English, NeutralLabel) => "Neutral"
    (SimplifiedChinese, NeutralLabel) => "中性"
    (TraditionalChinese, NeutralLabel) => "中性"
    (Japanese, NeutralLabel) => "中立"
    (Spanish, NeutralLabel) => "Neutral"
    (English, QueuedLabel) => "Queued"
    (SimplifiedChinese, QueuedLabel) => "排队中"
    (TraditionalChinese, QueuedLabel) => "排隊中"
    (Japanese, QueuedLabel) => "キュー待ち"
    (Spanish, QueuedLabel) => "En cola"
    (English, InProgressLabel) => "In progress"
    (SimplifiedChinese, InProgressLabel) => "进行中"
    (TraditionalChinese, InProgressLabel) => "進行中"
    (Japanese, InProgressLabel) => "実行中"
    (Spanish, InProgressLabel) => "En curso"
    (English, ExpectedLabel) => "Expected"
    (SimplifiedChinese, ExpectedLabel) => "等待上报"
    (TraditionalChinese, ExpectedLabel) => "等待回報"
    (Japanese, ExpectedLabel) => "結果待ち"
    (Spanish, ExpectedLabel) => "Esperada"
    (English, WaitingLabel) => "Waiting"
    (SimplifiedChinese, WaitingLabel) => "等待中"
    (TraditionalChinese, WaitingLabel) => "等待中"
    (Japanese, WaitingLabel) => "待機中"
    (Spanish, WaitingLabel) => "En espera"
    (English, RequestedLabel) => "Requested"
    (SimplifiedChinese, RequestedLabel) => "已请求"
    (TraditionalChinese, RequestedLabel) => "已要求"
    (Japanese, RequestedLabel) => "リクエスト済み"
    (Spanish, RequestedLabel) => "Solicitada"
    (English, TimedOutLabel) => "Timed out"
    (SimplifiedChinese, TimedOutLabel) => "已超时"
    (TraditionalChinese, TimedOutLabel) => "已逾時"
    (Japanese, TimedOutLabel) => "タイムアウト"
    (Spanish, TimedOutLabel) => "Tiempo agotado"
    (English, ActionRequiredLabel) => "Action required"
    (SimplifiedChinese, ActionRequiredLabel) => "需要操作"
    (TraditionalChinese, ActionRequiredLabel) => "需要操作"
    (Japanese, ActionRequiredLabel) => "操作が必要"
    (Spanish, ActionRequiredLabel) => "Requiere intervención"
    (English, StartupFailureLabel) => "Startup failure"
    (SimplifiedChinese, StartupFailureLabel) => "启动失败"
    (TraditionalChinese, StartupFailureLabel) => "啟動失敗"
    (Japanese, StartupFailureLabel) => "起動失敗"
    (Spanish, StartupFailureLabel) => "Error de inicio"
    (English, StaleLabel) => "Stale"
    (SimplifiedChinese, StaleLabel) => "已过期"
    (TraditionalChinese, StaleLabel) => "已過期"
    (Japanese, StaleLabel) => "期限切れ"
    (Spanish, StaleLabel) => "Obsoleta"
    (English, StatusCheck) => "Status check"
    (SimplifiedChinese, StatusCheck) => "状态检查"
    (TraditionalChinese, StatusCheck) => "狀態檢查"
    (Japanese, StatusCheck) => "ステータスチェック"
    (Spanish, StatusCheck) => "Comprobación de estado"
    (English, CheckDetails(name)) => "Details for \{name}"
    (SimplifiedChinese, CheckDetails(name)) => "\{name} 的详情"
    (TraditionalChinese, CheckDetails(name)) => "\{name} 的詳細資料"
    (Japanese, CheckDetails(name)) => "\{name} の詳細"
    (Spanish, CheckDetails(name)) => "Detalles de \{name}"
    (English, ViewDetails) => "Details"
    (SimplifiedChinese, ViewDetails) => "详情"
    (TraditionalChinese, ViewDetails) => "詳細資料"
    (Japanese, ViewDetails) => "詳細"
    (Spanish, ViewDetails) => "Detalles"
    (English, MergeSucceeded) => "Pull request successfully merged."
    (SimplifiedChinese, MergeSucceeded) => "拉取请求已成功合并。"
    (TraditionalChinese, MergeSucceeded) => "提取要求已成功合併。"
    (Japanese, MergeSucceeded) =>
      "プルリクエストは正常にマージされました。"
    (Spanish, MergeSucceeded) =>
      "La solicitud de incorporación se ha fusionado correctamente."
    (English, PullRequestClosed) => "This pull request is closed."
    (SimplifiedChinese, PullRequestClosed) => "此拉取请求已关闭。"
    (TraditionalChinese, PullRequestClosed) => "此提取要求已關閉。"
    (Japanese, PullRequestClosed) =>
      "このプルリクエストはクローズされています。"
    (Spanish, PullRequestClosed) =>
      "Esta solicitud de incorporación está cerrada."
    (English, NoConflicts) =>
      "This branch has no conflicts with the base branch."
    (SimplifiedChinese, NoConflicts) =>
      "此分支与目标分支没有冲突。"
    (TraditionalChinese, NoConflicts) =>
      "此分支與目標分支沒有衝突。"
    (Japanese, NoConflicts) =>
      "このブランチとベースブランチの間に競合はありません。"
    (Spanish, NoConflicts) => "Esta rama no tiene conflictos con la rama base."
    (English, HasConflicts) => "This branch has conflicts with the base branch."
    (SimplifiedChinese, HasConflicts) =>
      "此分支与目标分支存在冲突。"
    (TraditionalChinese, HasConflicts) =>
      "此分支與目標分支存在衝突。"
    (Japanese, HasConflicts) =>
      "このブランチとベースブランチの間に競合があります。"
    (Spanish, HasConflicts) => "Esta rama tiene conflictos con la rama base."
    (English, ConflictsUnavailable) =>
      "Merge conflict status is not available yet."
    (SimplifiedChinese, ConflictsUnavailable) =>
      "暂时无法获取合并冲突状态。"
    (TraditionalChinese, ConflictsUnavailable) =>
      "暫時無法取得合併衝突狀態。"
    (Japanese, ConflictsUnavailable) =>
      "マージの競合状態はまだ確認できません。"
    (Spanish, ConflictsUnavailable) =>
      "El estado de los conflictos de fusión aún no está disponible."
    (English, MergeConflictStatus) => "Merge conflict status"
    (SimplifiedChinese, MergeConflictStatus) => "合并冲突状态"
    (TraditionalChinese, MergeConflictStatus) => "合併衝突狀態"
    (Japanese, MergeConflictStatus) => "マージの競合状態"
    (Spanish, MergeConflictStatus) => "Estado de los conflictos de fusión"
    (English, DismissCheckout) => "Dismiss checkout notification"
    (SimplifiedChinese, DismissCheckout) => "关闭检出通知"
    (TraditionalChinese, DismissCheckout) => "關閉簽出通知"
    (Japanese, DismissCheckout) => "チェックアウト通知を閉じる"
    (Spanish, DismissCheckout) => "Cerrar notificación de la copia local"
    (English, HideDetails) => "Hide details"
    (SimplifiedChinese, HideDetails) => "隐藏详情"
    (TraditionalChinese, HideDetails) => "隱藏詳細資料"
    (Japanese, HideDetails) => "詳細を非表示"
    (Spanish, HideDetails) => "Ocultar detalles"
    (English, ShowDetails) => "Show details"
    (SimplifiedChinese, ShowDetails) => "显示详情"
    (TraditionalChinese, ShowDetails) => "顯示詳細資料"
    (Japanese, ShowDetails) => "詳細を表示"
    (Spanish, ShowDetails) => "Mostrar detalles"
    (English, UncommittedBeforeUpdate(number)) =>
      "Uncommitted changes before updating checkout for PR #\{number}"
    (SimplifiedChinese, UncommittedBeforeUpdate(number)) =>
      "更新 PR #\{number} 的本地检出前有未提交的更改"
    (TraditionalChinese, UncommittedBeforeUpdate(number)) =>
      "更新 PR #\{number} 的本機簽出前有未提交的變更"
    (Japanese, UncommittedBeforeUpdate(number)) =>
      "PR #\{number} のチェックアウト更新前に未コミットの変更があります"
    (Spanish, UncommittedBeforeUpdate(number)) =>
      "Hay cambios sin confirmar antes de actualizar la copia local de la PR #\{number}"
    (English, UncommittedBeforeCheckout(number)) =>
      "Uncommitted changes before checking out PR #\{number}"
    (SimplifiedChinese, UncommittedBeforeCheckout(number)) =>
      "检出 PR #\{number} 前有未提交的更改"
    (TraditionalChinese, UncommittedBeforeCheckout(number)) =>
      "簽出 PR #\{number} 前有未提交的變更"
    (Japanese, UncommittedBeforeCheckout(number)) =>
      "PR #\{number} のチェックアウト前に未コミットの変更があります"
    (Spanish, UncommittedBeforeCheckout(number)) =>
      "Hay cambios sin confirmar antes de obtener la PR #\{number}"
    (English, UncommittedChanges) => "You have uncommitted changes"
    (SimplifiedChinese, UncommittedChanges) => "你有未提交的更改"
    (TraditionalChinese, UncommittedChanges) => "你有未提交的變更"
    (Japanese, UncommittedChanges) => "未コミットの変更があります"
    (Spanish, UncommittedChanges) => "Tienes cambios sin confirmar"
    (English, StashChanges) => "Stash changes"
    (SimplifiedChinese, StashChanges) => "暂存更改"
    (TraditionalChinese, StashChanges) => "暫存變更"
    (Japanese, StashChanges) => "変更をスタッシュ"
    (Spanish, StashChanges) => "Guardar cambios en stash"
    (English, DiscardChanges) => "Discard changes"
    (SimplifiedChinese, DiscardChanges) => "丢弃更改"
    (TraditionalChinese, DiscardChanges) => "捨棄變更"
    (Japanese, DiscardChanges) => "変更を破棄"
    (Spanish, DiscardChanges) => "Descartar cambios"
    (English, UpdateAnyway) => "Update checkout anyway"
    (SimplifiedChinese, UpdateAnyway) => "仍然更新本地检出"
    (TraditionalChinese, UpdateAnyway) => "仍然更新本機簽出"
    (Japanese, UpdateAnyway) => "そのままチェックアウトを更新"
    (Spanish, UpdateAnyway) => "Actualizar la copia local de todos modos"
    (English, CheckoutAnyway) => "Try checkout anyway"
    (SimplifiedChinese, CheckoutAnyway) => "仍然尝试检出"
    (TraditionalChinese, CheckoutAnyway) => "仍然嘗試簽出"
    (Japanese, CheckoutAnyway) => "そのままチェックアウトを試す"
    (Spanish, CheckoutAnyway) => "Intentar obtener de todos modos"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (TraditionalChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (Spanish, CancelLabel) => "Cancelar"
  }
}

///|
/// Keep the styled author and branch names in each language's sentence order.
fn merge_description(
  locale : @i18n.Locale,
  state : String,
  author : @html.Html,
  base : @html.Html,
  head : @html.Html,
) -> Array[@html.Html] {
  match locale {
    English =>
      [
        author,
        @html.text(
          match state {
            "MERGED" => " merged changes into "
            "CLOSED" => " proposed changes into "
            _ => " wants to merge changes into "
          },
        ),
        base,
        @html.text(" from "),
        head,
      ]
    SimplifiedChinese =>
      [
        author,
        @html.text(
          match state {
            "MERGED" => " 已将 "
            "CLOSED" => " 曾提议将 "
            _ => " 希望将 "
          },
        ),
        head,
        @html.text(" 的更改合并到 "),
        base,
      ]
    TraditionalChinese =>
      [
        author,
        @html.text(
          match state {
            "MERGED" => " 已將 "
            "CLOSED" => " 曾提議將 "
            _ => " 希望將 "
          },
        ),
        head,
        @html.text(" 的變更合併至 "),
        base,
      ]
    Japanese =>
      [
        author,
        @html.text(" が "),
        head,
        @html.text(" から "),
        base,
        @html.text(
          match state {
            "MERGED" => " へ変更をマージしました"
            "CLOSED" => " への変更のマージを提案しました"
            _ => " へ変更をマージしようとしています"
          },
        ),
      ]
    Spanish =>
      [
        author,
        @html.text(
          match state {
            "MERGED" => " fusionó cambios de "
            "CLOSED" => " propuso fusionar cambios de "
            _ => " quiere fusionar cambios de "
          },
        ),
        head,
        @html.text(" en "),
        base,
      ]
  }
}
