// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  CommandsLabel
  SkillsLabel
  SymbolsLabel
  FilesLabel
  SearchingLabel
  NoFiles
  NoSymbols
  EditingGoal
  CancelGoalEditing
  ClearingGoal
  WaitingEngine
  EditGoal
  EditLabel
  ClearGoal
  SetGoal
  SendLabel
  StopLabel
  SteerTask
  QueueNextTurn
  SaveQueued
  AttachHint
  AttachImages
  ReadingImages
  SteerPlaceholder
  QueuePlaceholder
  ThisMessage
  SteerNowLabel
  QueueNextLabel
  FollowupHint
  FollowupAction
  ModelLabel
  ReasoningEffort
  LocalLabel
  WorktreeLabel
  LocalHint
  WorktreeHint
  RebuildLabel
  SendingLabel
  RefuseHint
  DenyLabel
  AllowOnceHint
  AllowOnce
  ConfigureEndpoint
  SetupLabel
  SteerLabel
  QueuedLabel
  QueuedResume
  EditingLabel
  DeleteLabel
  CompactionQueued
  CompactingContext
  WaitingPlacement
  RetryWorktreeList
  RetryLabel
  AskLabel
  ApproveForMe
  FullAccess
  RequestApproval
  AskDescription
  ReviewDescription
  FullAccessDescription
  PermissionHint
  PermissionLocked
  PermissionQuestion
  KeepWorking
  DiscardAndArchive
  RemoveLabel
  StartingLabel
  ThinkingLabel
  WorkingLabel
  StoppingLabel
  RemoveImage
  RemovePrefix
  NetworkDestination
  CommandLabel
  WorkingDirectory
  RequestedRule
  AllowedPath
  AdditionalPermissions
  AllowByRule
  ApproveOnce
  ApproveSession
  DeclineLabel
  CancelLabel
  UnsupportedChoices
  QuestionLabel
  ShowDetails
  NetworkApproval
  CommandApproval
  FileApproval
  PermissionRequest
  CodexNeedsInput
  ToolRequest
  GrantTurn
  GrantSession
  TypeAnswer
  SubmitAnswers
  SubmitJson
  UnsupportedRequest
  NoChecks
  OneFile
  BranchLabel
  CreatePullRequest
  NotCounted
  NoChanges
  ChangesLabel
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, CommandsLabel) => "Commands"
    (SimplifiedChinese, CommandsLabel) => "命令"
    (TraditionalChinese, CommandsLabel) => "命令"
    (Japanese, CommandsLabel) => "コマンド"
    (English, SkillsLabel) => "Skills"
    (SimplifiedChinese, SkillsLabel) => "技能"
    (TraditionalChinese, SkillsLabel) => "技能"
    (Japanese, SkillsLabel) => "スキル"
    (English, SymbolsLabel) => "Symbols"
    (SimplifiedChinese, SymbolsLabel) => "符号"
    (TraditionalChinese, SymbolsLabel) => "符號"
    (Japanese, SymbolsLabel) => "シンボル"
    (English, FilesLabel) => "Files"
    (SimplifiedChinese, FilesLabel) => "文件"
    (TraditionalChinese, FilesLabel) => "檔案"
    (Japanese, FilesLabel) => "ファイル"
    (English, SearchingLabel) => "Searching…"
    (SimplifiedChinese, SearchingLabel) => "正在搜索…"
    (TraditionalChinese, SearchingLabel) => "正在搜尋…"
    (Japanese, SearchingLabel) => "検索中…"
    (English, NoFiles) => "No files"
    (SimplifiedChinese, NoFiles) => "没有文件"
    (TraditionalChinese, NoFiles) => "沒有檔案"
    (Japanese, NoFiles) => "ファイルなし"
    (English, NoSymbols) => "No symbols"
    (SimplifiedChinese, NoSymbols) => "没有符号"
    (TraditionalChinese, NoSymbols) => "沒有符號"
    (Japanese, NoSymbols) => "シンボルなし"
    (English, EditingGoal) =>
      "You're editing this conversation's standing goal."
    (SimplifiedChinese, EditingGoal) =>
      "正在编辑此对话的长期目标。"
    (TraditionalChinese, EditingGoal) =>
      "正在編輯此對話的長期目標。"
    (Japanese, EditingGoal) =>
      "このチャットの継続的な目標を編集中です。"
    (English, CancelGoalEditing) =>
      "Stop editing the standing goal — the goal itself is left alone (Esc)"
    (SimplifiedChinese, CancelGoalEditing) =>
      "取消编辑长期目标，保留原目标（Esc）"
    (TraditionalChinese, CancelGoalEditing) =>
      "取消編輯長期目標，保留原目標（Esc）"
    (Japanese, CancelGoalEditing) =>
      "目標の編集をキャンセルして元の目標を保持（Esc）"
    (English, ClearingGoal) => "Clearing goal…"
    (SimplifiedChinese, ClearingGoal) => "正在清除目标…"
    (TraditionalChinese, ClearingGoal) => "正在清除目標…"
    (Japanese, ClearingGoal) => "目標を解除中…"
    (English, WaitingEngine) => "Waiting for the engine to record it"
    (SimplifiedChinese, WaitingEngine) => "正在等待引擎保存"
    (TraditionalChinese, WaitingEngine) => "正在等待引擎儲存"
    (Japanese, WaitingEngine) => "エンジンによる保存を待機中"
    (English, EditGoal) => "Edit the standing goal"
    (SimplifiedChinese, EditGoal) => "编辑长期目标"
    (TraditionalChinese, EditGoal) => "編輯長期目標"
    (Japanese, EditGoal) => "継続的な目標を編集"
    (English, EditLabel) => "Edit"
    (SimplifiedChinese, EditLabel) => "编辑"
    (TraditionalChinese, EditLabel) => "編輯"
    (Japanese, EditLabel) => "編集"
    (English, ClearGoal) => "Clear the standing goal"
    (SimplifiedChinese, ClearGoal) => "清除长期目标"
    (TraditionalChinese, ClearGoal) => "清除長期目標"
    (Japanese, ClearGoal) => "継続的な目標を解除"
    (English, SetGoal) => "Set the standing goal (Enter)"
    (SimplifiedChinese, SetGoal) => "设置长期目标（Enter）"
    (TraditionalChinese, SetGoal) => "設定長期目標（Enter）"
    (Japanese, SetGoal) => "継続的な目標を設定（Enter）"
    (English, SendLabel) => "Send"
    (SimplifiedChinese, SendLabel) => "发送"
    (TraditionalChinese, SendLabel) => "傳送"
    (Japanese, SendLabel) => "送信"
    (English, StopLabel) => "Stop"
    (SimplifiedChinese, StopLabel) => "停止"
    (TraditionalChinese, StopLabel) => "停止"
    (Japanese, StopLabel) => "停止"
    (English, SteerTask) => "Steer the running task"
    (SimplifiedChinese, SteerTask) => "引导正在运行的任务"
    (TraditionalChinese, SteerTask) => "引導正在執行的任務"
    (Japanese, SteerTask) => "実行中のタスクに指示"
    (English, QueueNextTurn) => "Queue for the next turn"
    (SimplifiedChinese, QueueNextTurn) => "排队等待下一轮"
    (TraditionalChinese, QueueNextTurn) => "排隊等待下一輪"
    (Japanese, QueueNextTurn) => "次のターンに追加"
    (English, SaveQueued) => "Save queued message"
    (SimplifiedChinese, SaveQueued) => "保存排队消息"
    (TraditionalChinese, SaveQueued) => "儲存排隊訊息"
    (Japanese, SaveQueued) => "待機中のメッセージを保存"
    (English, AttachHint) => "Attach up to 4 images, 5 MiB each"
    (SimplifiedChinese, AttachHint) =>
      "最多添加 4 张图片，每张不超过 5 MiB"
    (TraditionalChinese, AttachHint) =>
      "最多新增 4 張圖片，每張不超過 5 MiB"
    (Japanese, AttachHint) =>
      "最大 4 枚、1 枚あたり 5 MiB 以下の画像を追加"
    (English, AttachImages) => "Attach images"
    (SimplifiedChinese, AttachImages) => "添加图片"
    (TraditionalChinese, AttachImages) => "新增圖片"
    (Japanese, AttachImages) => "画像を追加"
    (English, ReadingImages) => "Reading images…"
    (SimplifiedChinese, ReadingImages) => "正在读取图片…"
    (TraditionalChinese, ReadingImages) => "正在讀取圖片…"
    (Japanese, ReadingImages) => "画像を読み込み中…"
    (English, SteerPlaceholder) => "Steer the running task."
    (SimplifiedChinese, SteerPlaceholder) => "引导正在运行的任务。"
    (TraditionalChinese, SteerPlaceholder) => "引導正在執行的任務。"
    (Japanese, SteerPlaceholder) => "実行中のタスクに指示を追加。"
    (English, QueuePlaceholder) => "Queue a follow-up for the next turn."
    (SimplifiedChinese, QueuePlaceholder) =>
      "为下一轮任务添加后续消息。"
    (TraditionalChinese, QueuePlaceholder) =>
      "為下一輪任務新增後續訊息。"
    (Japanese, QueuePlaceholder) =>
      "次のターンへの追加メッセージを入力。"
    (English, ThisMessage) => "This message"
    (SimplifiedChinese, ThisMessage) => "此条消息"
    (TraditionalChinese, ThisMessage) => "此條訊息"
    (Japanese, ThisMessage) => "このメッセージ"
    (English, SteerNowLabel) => "Steer now"
    (SimplifiedChinese, SteerNowLabel) => "立即引导"
    (TraditionalChinese, SteerNowLabel) => "立即引導"
    (Japanese, SteerNowLabel) => "今すぐ指示"
    (English, QueueNextLabel) => "Queue next"
    (SimplifiedChinese, QueueNextLabel) => "排队等待"
    (TraditionalChinese, QueueNextLabel) => "排隊等待"
    (Japanese, QueueNextLabel) => "キューに追加"
    (English, FollowupHint) => "Send this message now or after the current turn"
    (SimplifiedChinese, FollowupHint) =>
      "立即发送此消息或等待当前轮结束"
    (TraditionalChinese, FollowupHint) =>
      "立即傳送此訊息或等待當前輪結束"
    (Japanese, FollowupHint) =>
      "今すぐ送信するか現在のターンが終わるまで待機"
    (English, FollowupAction) => "Follow-up action"
    (SimplifiedChinese, FollowupAction) => "后续消息操作"
    (TraditionalChinese, FollowupAction) => "後續訊息操作"
    (Japanese, FollowupAction) => "追加メッセージの操作"
    (English, ModelLabel) => "Model"
    (SimplifiedChinese, ModelLabel) => "模型"
    (TraditionalChinese, ModelLabel) => "模型"
    (Japanese, ModelLabel) => "モデル"
    (English, ReasoningEffort) => "Reasoning effort"
    (SimplifiedChinese, ReasoningEffort) => "推理强度"
    (TraditionalChinese, ReasoningEffort) => "推理強度"
    (Japanese, ReasoningEffort) => "推論の強度"
    (English, LocalLabel) => "Local"
    (SimplifiedChinese, LocalLabel) => "本地"
    (TraditionalChinese, LocalLabel) => "本地"
    (Japanese, LocalLabel) => "ローカル"
    (English, WorktreeLabel) => "Worktree"
    (SimplifiedChinese, WorktreeLabel) => "工作树"
    (TraditionalChinese, WorktreeLabel) => "工作樹"
    (Japanese, WorktreeLabel) => "ワークツリー"
    (English, LocalHint) =>
      "Runs in the workspace itself — click to run in a fresh git worktree"
    (SimplifiedChinese, LocalHint) =>
      "在当前工作区运行，点击切换到新的 Git 工作树"
    (TraditionalChinese, LocalHint) =>
      "在當前工作區執行，點選切換到新的 Git 工作樹"
    (Japanese, LocalHint) =>
      "現在のワークスペースで実行。クリックで新しい Git ワークツリーに切り替え"
    (English, WorktreeHint) =>
      "First prompt creates a git worktree and runs there — click for local"
    (SimplifiedChinese, WorktreeHint) =>
      "首次发送时创建 Git 工作树并在其中运行，点击切换到本地"
    (TraditionalChinese, WorktreeHint) =>
      "首次傳送時建立 Git 工作樹並在其中執行，點選切換到本地"
    (Japanese, WorktreeHint) =>
      "最初の送信時に Git ワークツリーを作成して実行。クリックでローカルに切り替え"
    (English, RebuildLabel) => "Rebuild it"
    (SimplifiedChinese, RebuildLabel) => "重建"
    (TraditionalChinese, RebuildLabel) => "重建"
    (Japanese, RebuildLabel) => "再作成"
    (English, SendingLabel) => "Sending…"
    (SimplifiedChinese, SendingLabel) => "正在发送…"
    (TraditionalChinese, SendingLabel) => "正在傳送…"
    (Japanese, SendingLabel) => "送信中…"
    (English, RefuseHint) =>
      "Refuse this request; the tool reports the refusal and keeps working inside the sandbox"
    (SimplifiedChinese, RefuseHint) =>
      "拒绝此请求，工具会报告拒绝结果并继续在沙盒中工作"
    (TraditionalChinese, RefuseHint) =>
      "拒絕此請求，工具會報告拒絕結果並繼續在沙盒中工作"
    (Japanese, RefuseHint) =>
      "要求を拒否します。ツールは拒否を報告し、サンドボックス内で作業を続行します"
    (English, DenyLabel) => "Deny"
    (SimplifiedChinese, DenyLabel) => "拒绝"
    (TraditionalChinese, DenyLabel) => "拒絕"
    (Japanese, DenyLabel) => "拒否"
    (English, AllowOnceHint) =>
      "Allow this one run; nothing beyond it is granted"
    (SimplifiedChinese, AllowOnceHint) =>
      "仅允许本次运行，不授予后续权限"
    (TraditionalChinese, AllowOnceHint) =>
      "僅允許本次執行，不授予後續許可權"
    (Japanese, AllowOnceHint) =>
      "今回の実行のみ許可し、以降の権限は付与しません"
    (English, AllowOnce) => "Allow once"
    (SimplifiedChinese, AllowOnce) => "允许一次"
    (TraditionalChinese, AllowOnce) => "允許一次"
    (Japanese, AllowOnce) => "今回のみ許可"
    (English, ConfigureEndpoint) => "Configure the API endpoint"
    (SimplifiedChinese, ConfigureEndpoint) => "配置 API 端点"
    (TraditionalChinese, ConfigureEndpoint) => "配置 API 端點"
    (Japanese, ConfigureEndpoint) => "API エンドポイントを設定"
    (English, SetupLabel) => "Set up"
    (SimplifiedChinese, SetupLabel) => "设置"
    (TraditionalChinese, SetupLabel) => "設定"
    (Japanese, SetupLabel) => "設定"
    (English, SteerLabel) => "Steer"
    (SimplifiedChinese, SteerLabel) => "引导"
    (TraditionalChinese, SteerLabel) => "引導"
    (Japanese, SteerLabel) => "指示"
    (English, QueuedLabel) => "Queued"
    (SimplifiedChinese, QueuedLabel) => "已排队"
    (TraditionalChinese, QueuedLabel) => "已排隊"
    (Japanese, QueuedLabel) => "待機中"
    (English, QueuedResume) => "Queued for resume"
    (SimplifiedChinese, QueuedResume) => "已排队等待恢复"
    (TraditionalChinese, QueuedResume) => "已排隊等待恢復"
    (Japanese, QueuedResume) => "再開待ち"
    (English, EditingLabel) => "Editing"
    (SimplifiedChinese, EditingLabel) => "编辑中"
    (TraditionalChinese, EditingLabel) => "編輯中"
    (Japanese, EditingLabel) => "編集中"
    (English, DeleteLabel) => "Delete"
    (SimplifiedChinese, DeleteLabel) => "删除"
    (TraditionalChinese, DeleteLabel) => "刪除"
    (Japanese, DeleteLabel) => "削除"
    (English, CompactionQueued) =>
      "Compaction queued — starts when the current turn ends"
    (SimplifiedChinese, CompactionQueued) =>
      "压缩已排队，将在当前轮结束后开始"
    (TraditionalChinese, CompactionQueued) =>
      "壓縮已排隊，將在當前輪結束後開始"
    (Japanese, CompactionQueued) =>
      "圧縮は現在のターン終了後に開始されます"
    (English, CompactingContext) => "Compacting context…"
    (SimplifiedChinese, CompactingContext) => "正在压缩上下文…"
    (TraditionalChinese, CompactingContext) => "正在壓縮上下文…"
    (Japanese, CompactingContext) => "コンテキストを圧縮中…"
    (English, WaitingPlacement) => "Waiting for workspace placement…"
    (SimplifiedChinese, WaitingPlacement) => "正在等待工作区就绪…"
    (TraditionalChinese, WaitingPlacement) => "正在等待工作區就緒…"
    (Japanese, WaitingPlacement) =>
      "ワークスペースの準備を待機中…"
    (English, RetryWorktreeList) =>
      "Request this workspace's worktree list again"
    (SimplifiedChinese, RetryWorktreeList) =>
      "重新获取此工作区的工作树列表"
    (TraditionalChinese, RetryWorktreeList) =>
      "重新獲取此工作區的工作樹列表"
    (Japanese, RetryWorktreeList) =>
      "このワークスペースのワークツリー一覧を再取得"
    (English, RetryLabel) => "Retry"
    (SimplifiedChinese, RetryLabel) => "重试"
    (TraditionalChinese, RetryLabel) => "重試"
    (Japanese, RetryLabel) => "再試行"
    (English, AskLabel) => "Ask"
    (SimplifiedChinese, AskLabel) => "询问"
    (TraditionalChinese, AskLabel) => "詢問"
    (Japanese, AskLabel) => "確認する"
    (English, ApproveForMe) => "Approve for me"
    (SimplifiedChinese, ApproveForMe) => "代我审批"
    (TraditionalChinese, ApproveForMe) => "代我審批"
    (Japanese, ApproveForMe) => "代理で承認"
    (English, FullAccess) => "Full access"
    (SimplifiedChinese, FullAccess) => "完全访问"
    (TraditionalChinese, FullAccess) => "完全訪問"
    (Japanese, FullAccess) => "フルアクセス"
    (English, RequestApproval) => "Request approval"
    (SimplifiedChinese, RequestApproval) => "请求批准"
    (TraditionalChinese, RequestApproval) => "請求批准"
    (Japanese, RequestApproval) => "承認を要求"
    (English, AskDescription) =>
      "Always ask before editing outside the workspace or using the internet"
    (SimplifiedChinese, AskDescription) =>
      "编辑工作区外的文件或访问互联网前始终询问"
    (TraditionalChinese, AskDescription) =>
      "編輯工作區外的檔案或訪問網際網路前始終詢問"
    (Japanese, AskDescription) =>
      "ワークスペース外のファイル編集やインターネットへのアクセス前に必ず確認"
    (English, ReviewDescription) =>
      "Ask only when the reviewer detects a risky operation"
    (SimplifiedChinese, ReviewDescription) =>
      "仅在审查器检测到风险操作时询问"
    (TraditionalChinese, ReviewDescription) =>
      "僅在審查器檢測到風險操作時詢問"
    (Japanese, ReviewDescription) =>
      "レビュアーがリスクのある操作を検出した場合のみ確認"
    (English, FullAccessDescription) =>
      "Unrestricted internet access and access to any file on this computer"
    (SimplifiedChinese, FullAccessDescription) =>
      "不受限制地访问互联网和此电脑上的任何文件"
    (TraditionalChinese, FullAccessDescription) =>
      "不受限制地訪問網際網路和此電腦上的任何檔案"
    (Japanese, FullAccessDescription) =>
      "インターネットとこのコンピューターの全ファイルに制限なくアクセス"
    (English, PermissionHint) => "Choose how Codex handles approval requests"
    (SimplifiedChinese, PermissionHint) =>
      "选择 Codex 处理审批请求的方式"
    (TraditionalChinese, PermissionHint) =>
      "選擇 Codex 處理審批請求的方式"
    (Japanese, PermissionHint) =>
      "Codex の承認要求の処理方法を選択"
    (English, PermissionLocked) =>
      "Permission mode cannot change while Codex is running"
    (SimplifiedChinese, PermissionLocked) =>
      "Codex 运行期间无法更改权限模式"
    (TraditionalChinese, PermissionLocked) =>
      "Codex 執行期間無法更改許可權模式"
    (Japanese, PermissionLocked) =>
      "Codex の実行中は権限モードを変更できません"
    (English, PermissionQuestion) => "How should Codex approve operations?"
    (SimplifiedChinese, PermissionQuestion) => "Codex 应如何批准操作？"
    (TraditionalChinese, PermissionQuestion) => "Codex 應如何批准操作？"
    (Japanese, PermissionQuestion) =>
      "Codex の操作をどのように承認しますか？"
    (English, KeepWorking) => "Keep working"
    (SimplifiedChinese, KeepWorking) => "继续工作"
    (TraditionalChinese, KeepWorking) => "繼續工作"
    (Japanese, KeepWorking) => "作業を続行"
    (English, DiscardAndArchive) => "Discard local changes and archive"
    (SimplifiedChinese, DiscardAndArchive) => "丢弃本地更改并归档"
    (TraditionalChinese, DiscardAndArchive) => "丟棄本地更改並歸檔"
    (Japanese, DiscardAndArchive) =>
      "ローカルの変更を破棄してアーカイブ"
    (English, RemoveLabel) => "Remove"
    (SimplifiedChinese, RemoveLabel) => "移除"
    (TraditionalChinese, RemoveLabel) => "移除"
    (Japanese, RemoveLabel) => "削除"
    (English, StartingLabel) => "Starting…"
    (SimplifiedChinese, StartingLabel) => "正在启动…"
    (TraditionalChinese, StartingLabel) => "正在啟動…"
    (Japanese, StartingLabel) => "起動中…"
    (English, ThinkingLabel) => "Thinking…"
    (SimplifiedChinese, ThinkingLabel) => "正在思考…"
    (TraditionalChinese, ThinkingLabel) => "正在思考…"
    (Japanese, ThinkingLabel) => "思考中…"
    (English, WorkingLabel) => "Working…"
    (SimplifiedChinese, WorkingLabel) => "正在处理…"
    (TraditionalChinese, WorkingLabel) => "正在處理…"
    (Japanese, WorkingLabel) => "処理中…"
    (English, StoppingLabel) => "Stopping…"
    (SimplifiedChinese, StoppingLabel) => "正在停止…"
    (TraditionalChinese, StoppingLabel) => "正在停止…"
    (Japanese, StoppingLabel) => "停止中…"
    (English, RemoveImage) => "Remove image"
    (SimplifiedChinese, RemoveImage) => "移除图片"
    (TraditionalChinese, RemoveImage) => "移除圖片"
    (Japanese, RemoveImage) => "画像を削除"
    (English, RemovePrefix) => "Remove "
    (SimplifiedChinese, RemovePrefix) => "移除 "
    (TraditionalChinese, RemovePrefix) => "移除 "
    (Japanese, RemovePrefix) => "削除："
    (English, NetworkDestination) => "Network destination"
    (SimplifiedChinese, NetworkDestination) => "网络目标"
    (TraditionalChinese, NetworkDestination) => "網路目標"
    (Japanese, NetworkDestination) => "ネットワークの接続先"
    (English, CommandLabel) => "Command"
    (SimplifiedChinese, CommandLabel) => "命令"
    (TraditionalChinese, CommandLabel) => "命令"
    (Japanese, CommandLabel) => "コマンド"
    (English, WorkingDirectory) => "Working directory"
    (SimplifiedChinese, WorkingDirectory) => "工作目录"
    (TraditionalChinese, WorkingDirectory) => "工作目錄"
    (Japanese, WorkingDirectory) => "作業ディレクトリ"
    (English, RequestedRule) => "Requested rule"
    (SimplifiedChinese, RequestedRule) => "请求的规则"
    (TraditionalChinese, RequestedRule) => "請求的規則"
    (Japanese, RequestedRule) => "要求されたルール"
    (English, AllowedPath) => "Allowed path"
    (SimplifiedChinese, AllowedPath) => "允许的路径"
    (TraditionalChinese, AllowedPath) => "允許的路徑"
    (Japanese, AllowedPath) => "許可するパス"
    (English, AdditionalPermissions) => "Additional permissions"
    (SimplifiedChinese, AdditionalPermissions) => "额外权限"
    (TraditionalChinese, AdditionalPermissions) => "額外許可權"
    (Japanese, AdditionalPermissions) => "追加の権限"
    (English, AllowByRule) => "Allow by rule"
    (SimplifiedChinese, AllowByRule) => "按规则允许"
    (TraditionalChinese, AllowByRule) => "按規則允許"
    (Japanese, AllowByRule) => "ルールに従って許可"
    (English, ApproveOnce) => "Approve once"
    (SimplifiedChinese, ApproveOnce) => "批准一次"
    (TraditionalChinese, ApproveOnce) => "批准一次"
    (Japanese, ApproveOnce) => "今回のみ承認"
    (English, ApproveSession) => "Approve for session"
    (SimplifiedChinese, ApproveSession) => "在此会话中批准"
    (TraditionalChinese, ApproveSession) => "在此會話中批准"
    (Japanese, ApproveSession) => "このセッションで承認"
    (English, DeclineLabel) => "Decline"
    (SimplifiedChinese, DeclineLabel) => "拒绝"
    (TraditionalChinese, DeclineLabel) => "拒絕"
    (Japanese, DeclineLabel) => "拒否"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (TraditionalChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (English, UnsupportedChoices) =>
      "This app version cannot answer the advertised approval choices."
    (SimplifiedChinese, UnsupportedChoices) =>
      "此应用版本无法处理提供的审批选项。"
    (TraditionalChinese, UnsupportedChoices) =>
      "此應用版本無法處理提供的審批選項。"
    (Japanese, UnsupportedChoices) =>
      "このアプリのバージョンでは、指定された承認オプションを処理できません。"
    (English, QuestionLabel) => "Question"
    (SimplifiedChinese, QuestionLabel) => "问题"
    (TraditionalChinese, QuestionLabel) => "問題"
    (Japanese, QuestionLabel) => "質問"
    (English, ShowDetails) => "Show details"
    (SimplifiedChinese, ShowDetails) => "显示详情"
    (TraditionalChinese, ShowDetails) => "顯示詳情"
    (Japanese, ShowDetails) => "詳細を表示"
    (English, NetworkApproval) => "Network access approval"
    (SimplifiedChinese, NetworkApproval) => "网络访问审批"
    (TraditionalChinese, NetworkApproval) => "網路訪問審批"
    (Japanese, NetworkApproval) => "ネットワークアクセスの承認"
    (English, CommandApproval) => "Command approval"
    (SimplifiedChinese, CommandApproval) => "命令审批"
    (TraditionalChinese, CommandApproval) => "命令審批"
    (Japanese, CommandApproval) => "コマンドの承認"
    (English, FileApproval) => "File change approval"
    (SimplifiedChinese, FileApproval) => "文件更改审批"
    (TraditionalChinese, FileApproval) => "檔案更改審批"
    (Japanese, FileApproval) => "ファイル変更の承認"
    (English, PermissionRequest) => "Permission request"
    (SimplifiedChinese, PermissionRequest) => "权限请求"
    (TraditionalChinese, PermissionRequest) => "許可權請求"
    (Japanese, PermissionRequest) => "権限の要求"
    (English, CodexNeedsInput) => "Codex needs your input"
    (SimplifiedChinese, CodexNeedsInput) => "Codex 需要你的输入"
    (TraditionalChinese, CodexNeedsInput) => "Codex 需要你的輸入"
    (Japanese, CodexNeedsInput) => "Codex が入力を求めています"
    (English, ToolRequest) => "Tool request"
    (SimplifiedChinese, ToolRequest) => "工具请求"
    (TraditionalChinese, ToolRequest) => "工具請求"
    (Japanese, ToolRequest) => "ツールの要求"
    (English, GrantTurn) => "Grant for turn"
    (SimplifiedChinese, GrantTurn) => "本轮允许"
    (TraditionalChinese, GrantTurn) => "本輪允許"
    (Japanese, GrantTurn) => "このターンで許可"
    (English, GrantSession) => "Grant for session"
    (SimplifiedChinese, GrantSession) => "本会话允许"
    (TraditionalChinese, GrantSession) => "本會話允許"
    (Japanese, GrantSession) => "このセッションで許可"
    (English, TypeAnswer) => "Type an answer"
    (SimplifiedChinese, TypeAnswer) => "输入答案"
    (TraditionalChinese, TypeAnswer) => "輸入答案"
    (Japanese, TypeAnswer) => "回答を入力"
    (English, SubmitAnswers) => "Submit answers"
    (SimplifiedChinese, SubmitAnswers) => "提交答案"
    (TraditionalChinese, SubmitAnswers) => "提交答案"
    (Japanese, SubmitAnswers) => "回答を送信"
    (English, SubmitJson) => "Submit JSON"
    (SimplifiedChinese, SubmitJson) => "提交 JSON"
    (TraditionalChinese, SubmitJson) => "提交 JSON"
    (Japanese, SubmitJson) => "JSON を送信"
    (English, UnsupportedRequest) => "Unsupported app-server request:\n"
    (SimplifiedChinese, UnsupportedRequest) =>
      "不支持的应用服务请求：\n"
    (TraditionalChinese, UnsupportedRequest) =>
      "不支援的應用服務請求：\n"
    (Japanese, UnsupportedRequest) =>
      "未対応のアプリサーバー要求：\n"
    (English, NoChecks) => "no checks"
    (SimplifiedChinese, NoChecks) => "没有检查"
    (TraditionalChinese, NoChecks) => "沒有檢查"
    (Japanese, NoChecks) => "チェックなし"
    (English, OneFile) => "1 file"
    (SimplifiedChinese, OneFile) => "1 个文件"
    (TraditionalChinese, OneFile) => "1 個檔案"
    (Japanese, OneFile) => "1 ファイル"
    (English, BranchLabel) => "Branch"
    (SimplifiedChinese, BranchLabel) => "分支"
    (TraditionalChinese, BranchLabel) => "分支"
    (Japanese, BranchLabel) => "ブランチ"
    (English, CreatePullRequest) => "Create pull request"
    (SimplifiedChinese, CreatePullRequest) => "创建拉取请求"
    (TraditionalChinese, CreatePullRequest) => "建立拉取請求"
    (Japanese, CreatePullRequest) => "プルリクエストを作成"
    (English, NotCounted) => "Not counted"
    (SimplifiedChinese, NotCounted) => "未统计"
    (TraditionalChinese, NotCounted) => "未統計"
    (Japanese, NotCounted) => "未集計"
    (English, NoChanges) => "No changes"
    (SimplifiedChinese, NoChanges) => "没有更改"
    (TraditionalChinese, NoChanges) => "沒有更改"
    (Japanese, NoChanges) => "変更なし"
    (English, ChangesLabel) => "Changes"
    (SimplifiedChinese, ChangesLabel) => "更改"
    (TraditionalChinese, ChangesLabel) => "更改"
    (Japanese, ChangesLabel) => "変更"
  }
}
