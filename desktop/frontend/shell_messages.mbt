// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum ShellMessage {
  NewChatLabel
  ArchiveHint
  RestoreHint
  DeleteArchivedHint
  LoadingDevice
  NoDevices
  NoOnlineDevice
  UpdateLabel
  RestartingLabel
  ArchivedReadOnly
  RestoreBeforeContinue
  RestoreLabel
  ShowDetailed
  ShowMinimal
  DetailedMode
  ExportConversation
  HideTerminal
  ShowTerminal
  ShowPanel
  OpenProject
  ProjectOnboarding
  AddProject
  OpeningChat
  ConnectingDevice
  CheckingSignIn
  TryAgain
  SignInLabel
  BrowserAccess
  SignInGitHub
  CheckingDevice
  CannotLoadDevice
  WaitingConnection
  BringOnline
  DeviceUnavailable
  DeviceNotInAccount
  RefreshLabel
  DeviceLinkRequired
  DeviceLinkDescription
  SigningOut
  SignOutLabel
  LoadingConversation
  CannotLoadConversation
  RetryLabel
  ScheduleReadOnly
  ViewTask
  DisconnectedLabel
  InterruptForUpdate
  KeepWorking
  UpdateRestart
  SetupDeepSeek
  SetupGlm
  SetupOpenRouter
  SetupEndpoint
  NotNow
  DismissLabel
  RenameConversation
  CancelLabel
  SavingLabel
  SaveLabel
  DeleteChatQuestion
  DeletePermanently
  NoEndpoint
  NoGlmKey
  NoOpenRouterKey
  NoDeepSeekKey
  CompactContext
  SetGoal
  GoalPlaceholder
  EditQueuePlaceholder
  QueuePlaceholder
  SteerPlaceholder
  AskPlaceholder
}

///|
fn shell_text(locale : @i18n.Locale, message : ShellMessage) -> String {
  match (locale, message) {
    (English, NewChatLabel) => "New chat"
    (SimplifiedChinese, NewChatLabel) => "新建对话"
    (English, ArchiveHint) =>
      "Archive — tuck this chat away; its files stay where they are"
    (SimplifiedChinese, ArchiveHint) =>
      "归档此对话，文件保留在原处"
    (English, RestoreHint) => "Restore this conversation to the sidebar"
    (SimplifiedChinese, RestoreHint) => "将此对话恢复到侧边栏"
    (English, DeleteArchivedHint) =>
      "Permanently delete this archived conversation"
    (SimplifiedChinese, DeleteArchivedHint) => "永久删除此归档对话"
    (English, LoadingDevice) => "Loading device…"
    (SimplifiedChinese, LoadingDevice) => "正在加载设备…"
    (English, NoDevices) =>
      "No devices yet — open SeekMoon and sign in under Settings → Remote access."
    (SimplifiedChinese, NoDevices) =>
      "尚无设备，请打开 SeekMoon 并在“设置 → 远程访问”中登录。"
    (English, NoOnlineDevice) => "No online device — reconnecting…"
    (SimplifiedChinese, NoOnlineDevice) =>
      "没有在线设备，正在重新连接…"
    (English, UpdateLabel) => "Update"
    (SimplifiedChinese, UpdateLabel) => "更新"
    (English, RestartingLabel) => "Restarting…"
    (SimplifiedChinese, RestartingLabel) => "正在重启…"
    (English, ArchivedReadOnly) => "Archived conversation · Read only"
    (SimplifiedChinese, ArchivedReadOnly) => "已归档对话 · 只读"
    (English, RestoreBeforeContinue) =>
      "Restore this conversation before continuing it"
    (SimplifiedChinese, RestoreBeforeContinue) =>
      "恢复此对话后即可继续"
    (English, RestoreLabel) => "Restore"
    (SimplifiedChinese, RestoreLabel) => "恢复"
    (English, ShowDetailed) => "Show detailed conversation"
    (SimplifiedChinese, ShowDetailed) => "显示完整对话"
    (English, ShowMinimal) => "Show minimal conversation"
    (SimplifiedChinese, ShowMinimal) => "显示精简对话"
    (English, DetailedMode) => "Detailed mode"
    (SimplifiedChinese, DetailedMode) => "详细模式"
    (English, ExportConversation) => "Export conversation"
    (SimplifiedChinese, ExportConversation) => "导出对话"
    (English, HideTerminal) => "Hide terminal (Ctrl+`)"
    (SimplifiedChinese, HideTerminal) => "隐藏终端（Ctrl+`）"
    (English, ShowTerminal) => "Show terminal (Ctrl+`)"
    (SimplifiedChinese, ShowTerminal) => "显示终端（Ctrl+`）"
    (English, ShowPanel) => "Show panel"
    (SimplifiedChinese, ShowPanel) => "显示面板"
    (English, OpenProject) => "Open a project"
    (SimplifiedChinese, OpenProject) => "打开项目"
    (English, ProjectOnboarding) =>
      "SeekMoon works inside a project directory. Add one and its first chat opens here."
    (SimplifiedChinese, ProjectOnboarding) =>
      "SeekMoon 在项目目录中工作。添加项目后，首个对话将在此处打开。"
    (English, AddProject) => "Add a project"
    (SimplifiedChinese, AddProject) => "添加项目"
    (English, OpeningChat) => "Opening a chat…"
    (SimplifiedChinese, OpeningChat) => "正在打开对话…"
    (English, ConnectingDevice) => "Connecting to this device…"
    (SimplifiedChinese, ConnectingDevice) => "正在连接此设备…"
    (English, CheckingSignIn) => "Checking sign-in…"
    (SimplifiedChinese, CheckingSignIn) => "正在检查登录状态…"
    (English, TryAgain) => "Try again"
    (SimplifiedChinese, TryAgain) => "重试"
    (English, SignInLabel) => "Sign in"
    (SimplifiedChinese, SignInLabel) => "登录"
    (English, BrowserAccess) => "Access this SeekMoon device from your browser."
    (SimplifiedChinese, BrowserAccess) =>
      "通过浏览器访问此 SeekMoon 设备。"
    (English, SignInGitHub) => "Sign in with GitHub"
    (SimplifiedChinese, SignInGitHub) => "使用 GitHub 登录"
    (English, CheckingDevice) => "Checking device…"
    (SimplifiedChinese, CheckingDevice) => "正在检查设备…"
    (English, CannotLoadDevice) => "Can't load device"
    (SimplifiedChinese, CannotLoadDevice) => "无法加载设备"
    (English, WaitingConnection) => "Waiting for this device's connection."
    (SimplifiedChinese, WaitingConnection) => "正在等待此设备连接。"
    (English, BringOnline) => "Bring this device online, then refresh."
    (SimplifiedChinese, BringOnline) =>
      "请将此设备联网，然后刷新。"
    (English, DeviceUnavailable) => "Device unavailable"
    (SimplifiedChinese, DeviceUnavailable) => "设备不可用"
    (English, DeviceNotInAccount) =>
      "This device is not available to the signed-in account."
    (SimplifiedChinese, DeviceNotInAccount) =>
      "当前登录的账户无法访问此设备。"
    (English, RefreshLabel) => "Refresh"
    (SimplifiedChinese, RefreshLabel) => "刷新"
    (English, DeviceLinkRequired) => "Device link required"
    (SimplifiedChinese, DeviceLinkRequired) => "需要设备链接"
    (English, DeviceLinkDescription) =>
      "Open this page from Remote access in SeekMoon so the URL identifies one device."
    (SimplifiedChinese, DeviceLinkDescription) =>
      "请从 SeekMoon 的“远程访问”中打开此页面，以便通过链接识别设备。"
    (English, SigningOut) => "Signing out…"
    (SimplifiedChinese, SigningOut) => "正在退出登录…"
    (English, SignOutLabel) => "Sign out"
    (SimplifiedChinese, SignOutLabel) => "退出登录"
    (English, LoadingConversation) => "Loading conversation…"
    (SimplifiedChinese, LoadingConversation) => "正在加载对话…"
    (English, CannotLoadConversation) => "Could not load conversation"
    (SimplifiedChinese, CannotLoadConversation) => "无法加载对话"
    (English, RetryLabel) => "Retry"
    (SimplifiedChinese, RetryLabel) => "重试"
    (English, ScheduleReadOnly) => "Scheduled task · Read only while running"
    (SimplifiedChinese, ScheduleReadOnly) =>
      "定时任务 · 运行期间只读"
    (English, ViewTask) => "View task"
    (SimplifiedChinese, ViewTask) => "查看任务"
    (English, DisconnectedLabel) => "Disconnected"
    (SimplifiedChinese, DisconnectedLabel) => "已断开连接"
    (English, InterruptForUpdate) =>
      "A conversation is still running. Updating restarts the app and interrupts it; the transcript so far is saved."
    (SimplifiedChinese, InterruptForUpdate) =>
      "仍有对话正在运行。更新会重启应用并中断运行，已有的对话记录将会保留。"
    (English, KeepWorking) => "Keep working"
    (SimplifiedChinese, KeepWorking) => "继续工作"
    (English, UpdateRestart) => "Update and restart"
    (SimplifiedChinese, UpdateRestart) => "更新并重启"
    (English, SetupDeepSeek) => "Set up your DeepSeek API key"
    (SimplifiedChinese, SetupDeepSeek) => "设置 DeepSeek API 密钥"
    (English, SetupGlm) => "Set up your GLM API key"
    (SimplifiedChinese, SetupGlm) => "设置 GLM API 密钥"
    (English, SetupOpenRouter) => "Set up OpenRouter"
    (SimplifiedChinese, SetupOpenRouter) => "设置 OpenRouter"
    (English, SetupEndpoint) => "Set your endpoint URL"
    (SimplifiedChinese, SetupEndpoint) => "设置端点 URL"
    (English, NotNow) => "Not now"
    (SimplifiedChinese, NotNow) => "暂不设置"
    (English, DismissLabel) => "Dismiss"
    (SimplifiedChinese, DismissLabel) => "关闭"
    (English, RenameConversation) => "Rename conversation"
    (SimplifiedChinese, RenameConversation) => "重命名对话"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (English, SavingLabel) => "Saving…"
    (SimplifiedChinese, SavingLabel) => "正在保存…"
    (English, SaveLabel) => "Save"
    (SimplifiedChinese, SaveLabel) => "保存"
    (English, DeleteChatQuestion) => "Permanently delete this chat?"
    (SimplifiedChinese, DeleteChatQuestion) => "永久删除此对话？"
    (English, DeletePermanently) => "Delete permanently"
    (SimplifiedChinese, DeletePermanently) => "永久删除"
    (English, NoEndpoint) => "No endpoint URL configured — Send is disabled."
    (SimplifiedChinese, NoEndpoint) =>
      "尚未设置端点 URL，无法发送。"
    (English, NoGlmKey) => "No GLM API key configured — Send is disabled."
    (SimplifiedChinese, NoGlmKey) =>
      "尚未设置 GLM API 密钥，无法发送。"
    (English, NoOpenRouterKey) =>
      "No OpenRouter API key configured — Send is disabled."
    (SimplifiedChinese, NoOpenRouterKey) =>
      "尚未设置 OpenRouter API 密钥，无法发送。"
    (English, NoDeepSeekKey) =>
      "No DeepSeek API key configured — Send is disabled."
    (SimplifiedChinese, NoDeepSeekKey) =>
      "尚未设置 DeepSeek API 密钥，无法发送。"
    (English, CompactContext) =>
      "Summarize and shrink this conversation's context"
    (SimplifiedChinese, CompactContext) =>
      "总结并压缩此对话的上下文"
    (English, SetGoal) => "Set or clear this conversation's standing goal"
    (SimplifiedChinese, SetGoal) => "设置或清除此对话的长期目标"
    (English, GoalPlaceholder) =>
      "Describe the standing goal for this conversation — Enter sets it, Esc cancels."
    (SimplifiedChinese, GoalPlaceholder) =>
      "描述此对话的长期目标，按 Enter 设置，按 Esc 取消。"
    (English, EditQueuePlaceholder) =>
      "Edit the queued message — Enter saves it."
    (SimplifiedChinese, EditQueuePlaceholder) =>
      "编辑已排队的消息，按 Enter 保存。"
    (English, QueuePlaceholder) => "Queue a follow-up for the next turn."
    (SimplifiedChinese, QueuePlaceholder) =>
      "为下一轮任务添加后续消息。"
    (English, SteerPlaceholder) =>
      "Steer the running task — your message joins it at the next step."
    (SimplifiedChinese, SteerPlaceholder) =>
      "引导正在运行的任务，消息将在下一步加入。"
    (English, AskPlaceholder) =>
      "Ask SeekMoon to inspect, edit, or explain this workspace."
    (SimplifiedChinese, AskPlaceholder) =>
      "让 SeekMoon 检查、编辑或解释此工作区。"
  }
}
