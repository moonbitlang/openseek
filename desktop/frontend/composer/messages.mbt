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
    (Japanese, CommandsLabel) => "コマンド"
    (English, SkillsLabel) => "Skills"
    (SimplifiedChinese, SkillsLabel) => "技能"
    (Japanese, SkillsLabel) => "スキル"
    (English, SymbolsLabel) => "Symbols"
    (SimplifiedChinese, SymbolsLabel) => "符号"
    (Japanese, SymbolsLabel) => "シンボル"
    (English, FilesLabel) => "Files"
    (SimplifiedChinese, FilesLabel) => "文件"
    (Japanese, FilesLabel) => "ファイル"
    (English, SearchingLabel) => "Searching…"
    (SimplifiedChinese, SearchingLabel) => "正在搜索…"
    (Japanese, SearchingLabel) => "検索中…"
    (English, NoFiles) => "No files"
    (SimplifiedChinese, NoFiles) => "没有文件"
    (Japanese, NoFiles) => "ファイルなし"
    (English, NoSymbols) => "No symbols"
    (SimplifiedChinese, NoSymbols) => "没有符号"
    (Japanese, NoSymbols) => "シンボルなし"
    (English, EditingGoal) =>
      "You're editing this conversation's standing goal."
    (SimplifiedChinese, EditingGoal) =>
      "正在编辑此对话的长期目标。"
    (Japanese, EditingGoal) =>
      "このチャットの継続的な目標を編集中です。"
    (English, CancelGoalEditing) =>
      "Stop editing the standing goal — the goal itself is left alone (Esc)"
    (SimplifiedChinese, CancelGoalEditing) =>
      "取消编辑长期目标，保留原目标（Esc）"
    (Japanese, CancelGoalEditing) =>
      "目標の編集をキャンセルして元の目標を保持（Esc）"
    (English, ClearingGoal) => "Clearing goal…"
    (SimplifiedChinese, ClearingGoal) => "正在清除目标…"
    (Japanese, ClearingGoal) => "目標を解除中…"
    (English, WaitingEngine) => "Waiting for the engine to record it"
    (SimplifiedChinese, WaitingEngine) => "正在等待引擎保存"
    (Japanese, WaitingEngine) => "エンジンによる保存を待機中"
    (English, EditGoal) => "Edit the standing goal"
    (SimplifiedChinese, EditGoal) => "编辑长期目标"
    (Japanese, EditGoal) => "継続的な目標を編集"
    (English, EditLabel) => "Edit"
    (SimplifiedChinese, EditLabel) => "编辑"
    (Japanese, EditLabel) => "編集"
    (English, ClearGoal) => "Clear the standing goal"
    (SimplifiedChinese, ClearGoal) => "清除长期目标"
    (Japanese, ClearGoal) => "継続的な目標を解除"
    (English, SetGoal) => "Set the standing goal (Enter)"
    (SimplifiedChinese, SetGoal) => "设置长期目标（Enter）"
    (Japanese, SetGoal) => "継続的な目標を設定（Enter）"
    (English, SendLabel) => "Send"
    (SimplifiedChinese, SendLabel) => "发送"
    (Japanese, SendLabel) => "送信"
    (English, StopLabel) => "Stop"
    (SimplifiedChinese, StopLabel) => "停止"
    (Japanese, StopLabel) => "停止"
    (English, SteerTask) => "Steer the running task"
    (SimplifiedChinese, SteerTask) => "引导正在运行的任务"
    (Japanese, SteerTask) => "実行中のタスクに指示"
    (English, QueueNextTurn) => "Queue for the next turn"
    (SimplifiedChinese, QueueNextTurn) => "排队等待下一轮"
    (Japanese, QueueNextTurn) => "次のターンに追加"
    (English, SaveQueued) => "Save queued message"
    (SimplifiedChinese, SaveQueued) => "保存排队消息"
    (Japanese, SaveQueued) => "待機中のメッセージを保存"
    (English, AttachHint) => "Attach up to 4 images, 5 MiB each"
    (SimplifiedChinese, AttachHint) =>
      "最多添加 4 张图片，每张不超过 5 MiB"
    (Japanese, AttachHint) =>
      "最大 4 枚、1 枚あたり 5 MiB 以下の画像を追加"
    (English, AttachImages) => "Attach images"
    (SimplifiedChinese, AttachImages) => "添加图片"
    (Japanese, AttachImages) => "画像を追加"
    (English, ReadingImages) => "Reading images…"
    (SimplifiedChinese, ReadingImages) => "正在读取图片…"
    (Japanese, ReadingImages) => "画像を読み込み中…"
    (English, SteerPlaceholder) => "Steer the running task."
    (SimplifiedChinese, SteerPlaceholder) => "引导正在运行的任务。"
    (Japanese, SteerPlaceholder) => "実行中のタスクに指示を追加。"
    (English, QueuePlaceholder) => "Queue a follow-up for the next turn."
    (SimplifiedChinese, QueuePlaceholder) =>
      "为下一轮任务添加后续消息。"
    (Japanese, QueuePlaceholder) =>
      "次のターンへの追加メッセージを入力。"
    (English, ThisMessage) => "This message"
    (SimplifiedChinese, ThisMessage) => "此条消息"
    (Japanese, ThisMessage) => "このメッセージ"
    (English, SteerNowLabel) => "Steer now"
    (SimplifiedChinese, SteerNowLabel) => "立即引导"
    (Japanese, SteerNowLabel) => "今すぐ指示"
    (English, QueueNextLabel) => "Queue next"
    (SimplifiedChinese, QueueNextLabel) => "排队等待"
    (Japanese, QueueNextLabel) => "キューに追加"
    (English, FollowupHint) => "Send this message now or after the current turn"
    (SimplifiedChinese, FollowupHint) =>
      "立即发送此消息或等待当前轮结束"
    (Japanese, FollowupHint) =>
      "今すぐ送信するか現在のターンが終わるまで待機"
    (English, FollowupAction) => "Follow-up action"
    (SimplifiedChinese, FollowupAction) => "后续消息操作"
    (Japanese, FollowupAction) => "追加メッセージの操作"
    (English, ModelLabel) => "Model"
    (SimplifiedChinese, ModelLabel) => "模型"
    (Japanese, ModelLabel) => "モデル"
    (English, ReasoningEffort) => "Reasoning effort"
    (SimplifiedChinese, ReasoningEffort) => "推理强度"
    (Japanese, ReasoningEffort) => "推論の強度"
    (English, LocalLabel) => "Local"
    (SimplifiedChinese, LocalLabel) => "本地"
    (Japanese, LocalLabel) => "ローカル"
    (English, WorktreeLabel) => "Worktree"
    (SimplifiedChinese, WorktreeLabel) => "工作树"
    (Japanese, WorktreeLabel) => "ワークツリー"
    (English, LocalHint) =>
      "Runs in the workspace itself — click to run in a fresh git worktree"
    (SimplifiedChinese, LocalHint) =>
      "在当前工作区运行，点击切换到新的 Git 工作树"
    (Japanese, LocalHint) =>
      "現在のワークスペースで実行。クリックで新しい Git ワークツリーに切り替え"
    (English, WorktreeHint) =>
      "First prompt creates a git worktree and runs there — click for local"
    (SimplifiedChinese, WorktreeHint) =>
      "首次发送时创建 Git 工作树并在其中运行，点击切换到本地"
    (Japanese, WorktreeHint) =>
      "最初の送信時に Git ワークツリーを作成して実行。クリックでローカルに切り替え"
    (English, RebuildLabel) => "Rebuild it"
    (SimplifiedChinese, RebuildLabel) => "重建"
    (Japanese, RebuildLabel) => "再作成"
    (English, SendingLabel) => "Sending…"
    (SimplifiedChinese, SendingLabel) => "正在发送…"
    (Japanese, SendingLabel) => "送信中…"
    (English, RefuseHint) =>
      "Refuse this request; the tool reports the refusal and keeps working inside the sandbox"
    (SimplifiedChinese, RefuseHint) =>
      "拒绝此请求，工具会报告拒绝结果并继续在沙盒中工作"
    (Japanese, RefuseHint) =>
      "要求を拒否します。ツールは拒否を報告し、サンドボックス内で作業を続行します"
    (English, DenyLabel) => "Deny"
    (SimplifiedChinese, DenyLabel) => "拒绝"
    (Japanese, DenyLabel) => "拒否"
    (English, AllowOnceHint) =>
      "Allow this one run; nothing beyond it is granted"
    (SimplifiedChinese, AllowOnceHint) =>
      "仅允许本次运行，不授予后续权限"
    (Japanese, AllowOnceHint) =>
      "今回の実行のみ許可し、以降の権限は付与しません"
    (English, AllowOnce) => "Allow once"
    (SimplifiedChinese, AllowOnce) => "允许一次"
    (Japanese, AllowOnce) => "今回のみ許可"
    (English, ConfigureEndpoint) => "Configure the API endpoint"
    (SimplifiedChinese, ConfigureEndpoint) => "配置 API 端点"
    (Japanese, ConfigureEndpoint) => "API エンドポイントを設定"
    (English, SetupLabel) => "Set up"
    (SimplifiedChinese, SetupLabel) => "设置"
    (Japanese, SetupLabel) => "設定"
    (English, SteerLabel) => "Steer"
    (SimplifiedChinese, SteerLabel) => "引导"
    (Japanese, SteerLabel) => "指示"
    (English, QueuedLabel) => "Queued"
    (SimplifiedChinese, QueuedLabel) => "已排队"
    (Japanese, QueuedLabel) => "待機中"
    (English, QueuedResume) => "Queued for resume"
    (SimplifiedChinese, QueuedResume) => "已排队等待恢复"
    (Japanese, QueuedResume) => "再開待ち"
    (English, EditingLabel) => "Editing"
    (SimplifiedChinese, EditingLabel) => "编辑中"
    (Japanese, EditingLabel) => "編集中"
    (English, DeleteLabel) => "Delete"
    (SimplifiedChinese, DeleteLabel) => "删除"
    (Japanese, DeleteLabel) => "削除"
    (English, CompactionQueued) =>
      "Compaction queued — starts when the current turn ends"
    (SimplifiedChinese, CompactionQueued) =>
      "压缩已排队，将在当前轮结束后开始"
    (Japanese, CompactionQueued) =>
      "圧縮は現在のターン終了後に開始されます"
    (English, CompactingContext) => "Compacting context…"
    (SimplifiedChinese, CompactingContext) => "正在压缩上下文…"
    (Japanese, CompactingContext) => "コンテキストを圧縮中…"
    (English, WaitingPlacement) => "Waiting for workspace placement…"
    (SimplifiedChinese, WaitingPlacement) => "正在等待工作区就绪…"
    (Japanese, WaitingPlacement) =>
      "ワークスペースの準備を待機中…"
    (English, RetryWorktreeList) =>
      "Request this workspace's worktree list again"
    (SimplifiedChinese, RetryWorktreeList) =>
      "重新获取此工作区的工作树列表"
    (Japanese, RetryWorktreeList) =>
      "このワークスペースのワークツリー一覧を再取得"
    (English, RetryLabel) => "Retry"
    (SimplifiedChinese, RetryLabel) => "重试"
    (Japanese, RetryLabel) => "再試行"
    (English, AskLabel) => "Ask"
    (SimplifiedChinese, AskLabel) => "询问"
    (Japanese, AskLabel) => "確認する"
    (English, ApproveForMe) => "Approve for me"
    (SimplifiedChinese, ApproveForMe) => "代我审批"
    (Japanese, ApproveForMe) => "代理で承認"
    (English, FullAccess) => "Full access"
    (SimplifiedChinese, FullAccess) => "完全访问"
    (Japanese, FullAccess) => "フルアクセス"
    (English, RequestApproval) => "Request approval"
    (SimplifiedChinese, RequestApproval) => "请求批准"
    (Japanese, RequestApproval) => "承認を要求"
    (English, AskDescription) =>
      "Always ask before editing outside the workspace or using the internet"
    (SimplifiedChinese, AskDescription) =>
      "编辑工作区外的文件或访问互联网前始终询问"
    (Japanese, AskDescription) =>
      "ワークスペース外のファイル編集やインターネットへのアクセス前に必ず確認"
    (English, ReviewDescription) =>
      "Ask only when the reviewer detects a risky operation"
    (SimplifiedChinese, ReviewDescription) =>
      "仅在审查器检测到风险操作时询问"
    (Japanese, ReviewDescription) =>
      "レビュアーがリスクのある操作を検出した場合のみ確認"
    (English, FullAccessDescription) =>
      "Unrestricted internet access and access to any file on this computer"
    (SimplifiedChinese, FullAccessDescription) =>
      "不受限制地访问互联网和此电脑上的任何文件"
    (Japanese, FullAccessDescription) =>
      "インターネットとこのコンピューターの全ファイルに制限なくアクセス"
    (English, PermissionHint) => "Choose how Codex handles approval requests"
    (SimplifiedChinese, PermissionHint) =>
      "选择 Codex 处理审批请求的方式"
    (Japanese, PermissionHint) =>
      "Codex の承認要求の処理方法を選択"
    (English, PermissionLocked) =>
      "Permission mode cannot change while Codex is running"
    (SimplifiedChinese, PermissionLocked) =>
      "Codex 运行期间无法更改权限模式"
    (Japanese, PermissionLocked) =>
      "Codex の実行中は権限モードを変更できません"
    (English, PermissionQuestion) => "How should Codex approve operations?"
    (SimplifiedChinese, PermissionQuestion) => "Codex 应如何批准操作？"
    (Japanese, PermissionQuestion) =>
      "Codex の操作をどのように承認しますか？"
    (English, KeepWorking) => "Keep working"
    (SimplifiedChinese, KeepWorking) => "继续工作"
    (Japanese, KeepWorking) => "作業を続行"
    (English, DiscardAndArchive) => "Discard local changes and archive"
    (SimplifiedChinese, DiscardAndArchive) => "丢弃本地更改并归档"
    (Japanese, DiscardAndArchive) =>
      "ローカルの変更を破棄してアーカイブ"
    (English, RemoveLabel) => "Remove"
    (SimplifiedChinese, RemoveLabel) => "移除"
    (Japanese, RemoveLabel) => "削除"
    (English, StartingLabel) => "Starting…"
    (SimplifiedChinese, StartingLabel) => "正在启动…"
    (Japanese, StartingLabel) => "起動中…"
    (English, ThinkingLabel) => "Thinking…"
    (SimplifiedChinese, ThinkingLabel) => "正在思考…"
    (Japanese, ThinkingLabel) => "思考中…"
    (English, WorkingLabel) => "Working…"
    (SimplifiedChinese, WorkingLabel) => "正在处理…"
    (Japanese, WorkingLabel) => "処理中…"
    (English, StoppingLabel) => "Stopping…"
    (SimplifiedChinese, StoppingLabel) => "正在停止…"
    (Japanese, StoppingLabel) => "停止中…"
    (English, RemoveImage) => "Remove image"
    (SimplifiedChinese, RemoveImage) => "移除图片"
    (Japanese, RemoveImage) => "画像を削除"
    (English, RemovePrefix) => "Remove "
    (SimplifiedChinese, RemovePrefix) => "移除 "
    (Japanese, RemovePrefix) => "削除："
    (English, NetworkDestination) => "Network destination"
    (SimplifiedChinese, NetworkDestination) => "网络目标"
    (Japanese, NetworkDestination) => "ネットワークの接続先"
    (English, CommandLabel) => "Command"
    (SimplifiedChinese, CommandLabel) => "命令"
    (Japanese, CommandLabel) => "コマンド"
    (English, WorkingDirectory) => "Working directory"
    (SimplifiedChinese, WorkingDirectory) => "工作目录"
    (Japanese, WorkingDirectory) => "作業ディレクトリ"
    (English, RequestedRule) => "Requested rule"
    (SimplifiedChinese, RequestedRule) => "请求的规则"
    (Japanese, RequestedRule) => "要求されたルール"
    (English, AllowedPath) => "Allowed path"
    (SimplifiedChinese, AllowedPath) => "允许的路径"
    (Japanese, AllowedPath) => "許可するパス"
    (English, AdditionalPermissions) => "Additional permissions"
    (SimplifiedChinese, AdditionalPermissions) => "额外权限"
    (Japanese, AdditionalPermissions) => "追加の権限"
    (English, AllowByRule) => "Allow by rule"
    (SimplifiedChinese, AllowByRule) => "按规则允许"
    (Japanese, AllowByRule) => "ルールに従って許可"
    (English, ApproveOnce) => "Approve once"
    (SimplifiedChinese, ApproveOnce) => "批准一次"
    (Japanese, ApproveOnce) => "今回のみ承認"
    (English, ApproveSession) => "Approve for session"
    (SimplifiedChinese, ApproveSession) => "在此会话中批准"
    (Japanese, ApproveSession) => "このセッションで承認"
    (English, DeclineLabel) => "Decline"
    (SimplifiedChinese, DeclineLabel) => "拒绝"
    (Japanese, DeclineLabel) => "拒否"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (English, UnsupportedChoices) =>
      "This app version cannot answer the advertised approval choices."
    (SimplifiedChinese, UnsupportedChoices) =>
      "此应用版本无法处理提供的审批选项。"
    (Japanese, UnsupportedChoices) =>
      "このアプリのバージョンでは、指定された承認オプションを処理できません。"
    (English, QuestionLabel) => "Question"
    (SimplifiedChinese, QuestionLabel) => "问题"
    (Japanese, QuestionLabel) => "質問"
    (English, ShowDetails) => "Show details"
    (SimplifiedChinese, ShowDetails) => "显示详情"
    (Japanese, ShowDetails) => "詳細を表示"
    (English, NetworkApproval) => "Network access approval"
    (SimplifiedChinese, NetworkApproval) => "网络访问审批"
    (Japanese, NetworkApproval) => "ネットワークアクセスの承認"
    (English, CommandApproval) => "Command approval"
    (SimplifiedChinese, CommandApproval) => "命令审批"
    (Japanese, CommandApproval) => "コマンドの承認"
    (English, FileApproval) => "File change approval"
    (SimplifiedChinese, FileApproval) => "文件更改审批"
    (Japanese, FileApproval) => "ファイル変更の承認"
    (English, PermissionRequest) => "Permission request"
    (SimplifiedChinese, PermissionRequest) => "权限请求"
    (Japanese, PermissionRequest) => "権限の要求"
    (English, CodexNeedsInput) => "Codex needs your input"
    (SimplifiedChinese, CodexNeedsInput) => "Codex 需要你的输入"
    (Japanese, CodexNeedsInput) => "Codex が入力を求めています"
    (English, ToolRequest) => "Tool request"
    (SimplifiedChinese, ToolRequest) => "工具请求"
    (Japanese, ToolRequest) => "ツールの要求"
    (English, GrantTurn) => "Grant for turn"
    (SimplifiedChinese, GrantTurn) => "本轮允许"
    (Japanese, GrantTurn) => "このターンで許可"
    (English, GrantSession) => "Grant for session"
    (SimplifiedChinese, GrantSession) => "本会话允许"
    (Japanese, GrantSession) => "このセッションで許可"
    (English, TypeAnswer) => "Type an answer"
    (SimplifiedChinese, TypeAnswer) => "输入答案"
    (Japanese, TypeAnswer) => "回答を入力"
    (English, SubmitAnswers) => "Submit answers"
    (SimplifiedChinese, SubmitAnswers) => "提交答案"
    (Japanese, SubmitAnswers) => "回答を送信"
    (English, SubmitJson) => "Submit JSON"
    (SimplifiedChinese, SubmitJson) => "提交 JSON"
    (Japanese, SubmitJson) => "JSON を送信"
    (English, UnsupportedRequest) => "Unsupported app-server request:\n"
    (SimplifiedChinese, UnsupportedRequest) =>
      "不支持的应用服务请求：\n"
    (Japanese, UnsupportedRequest) =>
      "未対応のアプリサーバー要求：\n"
    (English, NoChecks) => "no checks"
    (SimplifiedChinese, NoChecks) => "没有检查"
    (Japanese, NoChecks) => "チェックなし"
    (English, OneFile) => "1 file"
    (SimplifiedChinese, OneFile) => "1 个文件"
    (Japanese, OneFile) => "1 ファイル"
    (English, BranchLabel) => "Branch"
    (SimplifiedChinese, BranchLabel) => "分支"
    (Japanese, BranchLabel) => "ブランチ"
    (English, CreatePullRequest) => "Create pull request"
    (SimplifiedChinese, CreatePullRequest) => "创建拉取请求"
    (Japanese, CreatePullRequest) => "プルリクエストを作成"
    (English, NotCounted) => "Not counted"
    (SimplifiedChinese, NotCounted) => "未统计"
    (Japanese, NotCounted) => "未集計"
    (English, NoChanges) => "No changes"
    (SimplifiedChinese, NoChanges) => "没有更改"
    (Japanese, NoChanges) => "変更なし"
    (English, ChangesLabel) => "Changes"
    (SimplifiedChinese, ChangesLabel) => "更改"
    (Japanese, ChangesLabel) => "変更"
  }
}
