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
    (English, SkillsLabel) => "Skills"
    (SimplifiedChinese, SkillsLabel) => "技能"
    (English, SymbolsLabel) => "Symbols"
    (SimplifiedChinese, SymbolsLabel) => "符号"
    (English, FilesLabel) => "Files"
    (SimplifiedChinese, FilesLabel) => "文件"
    (English, SearchingLabel) => "Searching…"
    (SimplifiedChinese, SearchingLabel) => "正在搜索…"
    (English, NoFiles) => "No files"
    (SimplifiedChinese, NoFiles) => "没有文件"
    (English, NoSymbols) => "No symbols"
    (SimplifiedChinese, NoSymbols) => "没有符号"
    (English, EditingGoal) =>
      "You're editing this conversation's standing goal."
    (SimplifiedChinese, EditingGoal) =>
      "正在编辑此对话的长期目标。"
    (English, CancelGoalEditing) =>
      "Stop editing the standing goal — the goal itself is left alone (Esc)"
    (SimplifiedChinese, CancelGoalEditing) =>
      "取消编辑长期目标，保留原目标（Esc）"
    (English, ClearingGoal) => "Clearing goal…"
    (SimplifiedChinese, ClearingGoal) => "正在清除目标…"
    (English, WaitingEngine) => "Waiting for the engine to record it"
    (SimplifiedChinese, WaitingEngine) => "正在等待引擎保存"
    (English, EditGoal) => "Edit the standing goal"
    (SimplifiedChinese, EditGoal) => "编辑长期目标"
    (English, EditLabel) => "Edit"
    (SimplifiedChinese, EditLabel) => "编辑"
    (English, ClearGoal) => "Clear the standing goal"
    (SimplifiedChinese, ClearGoal) => "清除长期目标"
    (English, SetGoal) => "Set the standing goal (Enter)"
    (SimplifiedChinese, SetGoal) => "设置长期目标（Enter）"
    (English, SendLabel) => "Send"
    (SimplifiedChinese, SendLabel) => "发送"
    (English, StopLabel) => "Stop"
    (SimplifiedChinese, StopLabel) => "停止"
    (English, SteerTask) => "Steer the running task"
    (SimplifiedChinese, SteerTask) => "引导正在运行的任务"
    (English, QueueNextTurn) => "Queue for the next turn"
    (SimplifiedChinese, QueueNextTurn) => "排队等待下一轮"
    (English, SaveQueued) => "Save queued message"
    (SimplifiedChinese, SaveQueued) => "保存排队消息"
    (English, AttachHint) => "Attach up to 4 images, 5 MiB each"
    (SimplifiedChinese, AttachHint) =>
      "最多添加 4 张图片，每张不超过 5 MiB"
    (English, AttachImages) => "Attach images"
    (SimplifiedChinese, AttachImages) => "添加图片"
    (English, ReadingImages) => "Reading images…"
    (SimplifiedChinese, ReadingImages) => "正在读取图片…"
    (English, SteerPlaceholder) => "Steer the running task."
    (SimplifiedChinese, SteerPlaceholder) => "引导正在运行的任务。"
    (English, QueuePlaceholder) => "Queue a follow-up for the next turn."
    (SimplifiedChinese, QueuePlaceholder) =>
      "为下一轮任务添加后续消息。"
    (English, ThisMessage) => "This message"
    (SimplifiedChinese, ThisMessage) => "此条消息"
    (English, SteerNowLabel) => "Steer now"
    (SimplifiedChinese, SteerNowLabel) => "立即引导"
    (English, QueueNextLabel) => "Queue next"
    (SimplifiedChinese, QueueNextLabel) => "排队等待"
    (English, FollowupHint) => "Send this message now or after the current turn"
    (SimplifiedChinese, FollowupHint) =>
      "立即发送此消息或等待当前轮结束"
    (English, FollowupAction) => "Follow-up action"
    (SimplifiedChinese, FollowupAction) => "后续消息操作"
    (English, ModelLabel) => "Model"
    (SimplifiedChinese, ModelLabel) => "模型"
    (English, ReasoningEffort) => "Reasoning effort"
    (SimplifiedChinese, ReasoningEffort) => "推理强度"
    (English, LocalLabel) => "Local"
    (SimplifiedChinese, LocalLabel) => "本地"
    (English, WorktreeLabel) => "Worktree"
    (SimplifiedChinese, WorktreeLabel) => "工作树"
    (English, LocalHint) =>
      "Runs in the workspace itself — click to run in a fresh git worktree"
    (SimplifiedChinese, LocalHint) =>
      "在当前工作区运行，点击切换到新的 Git 工作树"
    (English, WorktreeHint) =>
      "First prompt creates a git worktree and runs there — click for local"
    (SimplifiedChinese, WorktreeHint) =>
      "首次发送时创建 Git 工作树并在其中运行，点击切换到本地"
    (English, RebuildLabel) => "Rebuild it"
    (SimplifiedChinese, RebuildLabel) => "重建"
    (English, SendingLabel) => "Sending…"
    (SimplifiedChinese, SendingLabel) => "正在发送…"
    (English, RefuseHint) =>
      "Refuse this request; the tool reports the refusal and keeps working inside the sandbox"
    (SimplifiedChinese, RefuseHint) =>
      "拒绝此请求，工具会报告拒绝结果并继续在沙盒中工作"
    (English, DenyLabel) => "Deny"
    (SimplifiedChinese, DenyLabel) => "拒绝"
    (English, AllowOnceHint) =>
      "Allow this one run; nothing beyond it is granted"
    (SimplifiedChinese, AllowOnceHint) =>
      "仅允许本次运行，不授予后续权限"
    (English, AllowOnce) => "Allow once"
    (SimplifiedChinese, AllowOnce) => "允许一次"
    (English, ConfigureEndpoint) => "Configure the API endpoint"
    (SimplifiedChinese, ConfigureEndpoint) => "配置 API 端点"
    (English, SetupLabel) => "Set up"
    (SimplifiedChinese, SetupLabel) => "设置"
    (English, SteerLabel) => "Steer"
    (SimplifiedChinese, SteerLabel) => "引导"
    (English, QueuedLabel) => "Queued"
    (SimplifiedChinese, QueuedLabel) => "已排队"
    (English, QueuedResume) => "Queued for resume"
    (SimplifiedChinese, QueuedResume) => "已排队等待恢复"
    (English, EditingLabel) => "Editing"
    (SimplifiedChinese, EditingLabel) => "编辑中"
    (English, DeleteLabel) => "Delete"
    (SimplifiedChinese, DeleteLabel) => "删除"
    (English, CompactionQueued) =>
      "Compaction queued — starts when the current turn ends"
    (SimplifiedChinese, CompactionQueued) =>
      "压缩已排队，将在当前轮结束后开始"
    (English, CompactingContext) => "Compacting context…"
    (SimplifiedChinese, CompactingContext) => "正在压缩上下文…"
    (English, WaitingPlacement) => "Waiting for workspace placement…"
    (SimplifiedChinese, WaitingPlacement) => "正在等待工作区就绪…"
    (English, RetryWorktreeList) =>
      "Request this workspace's worktree list again"
    (SimplifiedChinese, RetryWorktreeList) =>
      "重新获取此工作区的工作树列表"
    (English, RetryLabel) => "Retry"
    (SimplifiedChinese, RetryLabel) => "重试"
    (English, AskLabel) => "Ask"
    (SimplifiedChinese, AskLabel) => "询问"
    (English, ApproveForMe) => "Approve for me"
    (SimplifiedChinese, ApproveForMe) => "代我审批"
    (English, FullAccess) => "Full access"
    (SimplifiedChinese, FullAccess) => "完全访问"
    (English, RequestApproval) => "Request approval"
    (SimplifiedChinese, RequestApproval) => "请求批准"
    (English, AskDescription) =>
      "Always ask before editing outside the workspace or using the internet"
    (SimplifiedChinese, AskDescription) =>
      "编辑工作区外的文件或访问互联网前始终询问"
    (English, ReviewDescription) =>
      "Ask only when the reviewer detects a risky operation"
    (SimplifiedChinese, ReviewDescription) =>
      "仅在审查器检测到风险操作时询问"
    (English, FullAccessDescription) =>
      "Unrestricted internet access and access to any file on this computer"
    (SimplifiedChinese, FullAccessDescription) =>
      "不受限制地访问互联网和此电脑上的任何文件"
    (English, PermissionHint) => "Choose how Codex handles approval requests"
    (SimplifiedChinese, PermissionHint) =>
      "选择 Codex 处理审批请求的方式"
    (English, PermissionLocked) =>
      "Permission mode cannot change while Codex is running"
    (SimplifiedChinese, PermissionLocked) =>
      "Codex 运行期间无法更改权限模式"
    (English, PermissionQuestion) => "How should Codex approve operations?"
    (SimplifiedChinese, PermissionQuestion) => "Codex 应如何批准操作？"
    (English, KeepWorking) => "Keep working"
    (SimplifiedChinese, KeepWorking) => "继续工作"
    (English, DiscardAndArchive) => "Discard local changes and archive"
    (SimplifiedChinese, DiscardAndArchive) => "丢弃本地更改并归档"
    (English, RemoveLabel) => "Remove"
    (SimplifiedChinese, RemoveLabel) => "移除"
    (English, StartingLabel) => "Starting…"
    (SimplifiedChinese, StartingLabel) => "正在启动…"
    (English, ThinkingLabel) => "Thinking…"
    (SimplifiedChinese, ThinkingLabel) => "正在思考…"
    (English, WorkingLabel) => "Working…"
    (SimplifiedChinese, WorkingLabel) => "正在处理…"
    (English, StoppingLabel) => "Stopping…"
    (SimplifiedChinese, StoppingLabel) => "正在停止…"
    (English, RemoveImage) => "Remove image"
    (SimplifiedChinese, RemoveImage) => "移除图片"
    (English, RemovePrefix) => "Remove "
    (SimplifiedChinese, RemovePrefix) => "移除 "
    (English, NetworkDestination) => "Network destination"
    (SimplifiedChinese, NetworkDestination) => "网络目标"
    (English, CommandLabel) => "Command"
    (SimplifiedChinese, CommandLabel) => "命令"
    (English, WorkingDirectory) => "Working directory"
    (SimplifiedChinese, WorkingDirectory) => "工作目录"
    (English, RequestedRule) => "Requested rule"
    (SimplifiedChinese, RequestedRule) => "请求的规则"
    (English, AllowedPath) => "Allowed path"
    (SimplifiedChinese, AllowedPath) => "允许的路径"
    (English, AdditionalPermissions) => "Additional permissions"
    (SimplifiedChinese, AdditionalPermissions) => "额外权限"
    (English, AllowByRule) => "Allow by rule"
    (SimplifiedChinese, AllowByRule) => "按规则允许"
    (English, ApproveOnce) => "Approve once"
    (SimplifiedChinese, ApproveOnce) => "批准一次"
    (English, ApproveSession) => "Approve for session"
    (SimplifiedChinese, ApproveSession) => "在此会话中批准"
    (English, DeclineLabel) => "Decline"
    (SimplifiedChinese, DeclineLabel) => "拒绝"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (English, UnsupportedChoices) =>
      "This app version cannot answer the advertised approval choices."
    (SimplifiedChinese, UnsupportedChoices) =>
      "此应用版本无法处理提供的审批选项。"
    (English, QuestionLabel) => "Question"
    (SimplifiedChinese, QuestionLabel) => "问题"
    (English, ShowDetails) => "Show details"
    (SimplifiedChinese, ShowDetails) => "显示详情"
    (English, NetworkApproval) => "Network access approval"
    (SimplifiedChinese, NetworkApproval) => "网络访问审批"
    (English, CommandApproval) => "Command approval"
    (SimplifiedChinese, CommandApproval) => "命令审批"
    (English, FileApproval) => "File change approval"
    (SimplifiedChinese, FileApproval) => "文件更改审批"
    (English, PermissionRequest) => "Permission request"
    (SimplifiedChinese, PermissionRequest) => "权限请求"
    (English, CodexNeedsInput) => "Codex needs your input"
    (SimplifiedChinese, CodexNeedsInput) => "Codex 需要你的输入"
    (English, ToolRequest) => "Tool request"
    (SimplifiedChinese, ToolRequest) => "工具请求"
    (English, GrantTurn) => "Grant for turn"
    (SimplifiedChinese, GrantTurn) => "本轮允许"
    (English, GrantSession) => "Grant for session"
    (SimplifiedChinese, GrantSession) => "本会话允许"
    (English, TypeAnswer) => "Type an answer"
    (SimplifiedChinese, TypeAnswer) => "输入答案"
    (English, SubmitAnswers) => "Submit answers"
    (SimplifiedChinese, SubmitAnswers) => "提交答案"
    (English, SubmitJson) => "Submit JSON"
    (SimplifiedChinese, SubmitJson) => "提交 JSON"
    (English, UnsupportedRequest) => "Unsupported app-server request:\n"
    (SimplifiedChinese, UnsupportedRequest) =>
      "不支持的应用服务请求：\n"
    (English, NoChecks) => "no checks"
    (SimplifiedChinese, NoChecks) => "没有检查"
    (English, OneFile) => "1 file"
    (SimplifiedChinese, OneFile) => "1 个文件"
    (English, BranchLabel) => "Branch"
    (SimplifiedChinese, BranchLabel) => "分支"
    (English, CreatePullRequest) => "Create pull request"
    (SimplifiedChinese, CreatePullRequest) => "创建拉取请求"
    (English, NotCounted) => "Not counted"
    (SimplifiedChinese, NotCounted) => "未统计"
    (English, NoChanges) => "No changes"
    (SimplifiedChinese, NoChanges) => "没有更改"
    (English, ChangesLabel) => "Changes"
    (SimplifiedChinese, ChangesLabel) => "更改"
  }
}
