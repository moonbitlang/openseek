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
  RestartToUpdateLabel
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
  RestartNow
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
    (TraditionalChinese, NewChatLabel) => "新建對話"
    (Japanese, NewChatLabel) => "新しいチャット"
    (English, ArchiveHint) =>
      "Archive — tuck this chat away; its files stay where they are"
    (SimplifiedChinese, ArchiveHint) =>
      "归档此对话，文件保留在原处"
    (TraditionalChinese, ArchiveHint) =>
      "歸檔此對話，檔案保留在原處"
    (Japanese, ArchiveHint) =>
      "このチャットをアーカイブし、ファイルはそのまま保持"
    (English, RestoreHint) => "Restore this conversation to the sidebar"
    (SimplifiedChinese, RestoreHint) => "将此对话恢复到侧边栏"
    (TraditionalChinese, RestoreHint) => "將此對話恢復到側邊欄"
    (Japanese, RestoreHint) => "このチャットをサイドバーに復元"
    (English, DeleteArchivedHint) =>
      "Permanently delete this archived conversation"
    (SimplifiedChinese, DeleteArchivedHint) => "永久删除此归档对话"
    (TraditionalChinese, DeleteArchivedHint) => "永久刪除此歸檔對話"
    (Japanese, DeleteArchivedHint) =>
      "このアーカイブ済みチャットを完全に削除"
    (English, LoadingDevice) => "Loading device…"
    (SimplifiedChinese, LoadingDevice) => "正在加载设备…"
    (TraditionalChinese, LoadingDevice) => "正在載入裝置…"
    (Japanese, LoadingDevice) => "デバイスを読み込み中…"
    (English, NoDevices) =>
      "No devices yet — open SeekMoon and sign in under Settings → Remote access."
    (SimplifiedChinese, NoDevices) =>
      "尚无设备，请打开 SeekMoon 并在“设置 → 远程访问”中登录。"
    (TraditionalChinese, NoDevices) =>
      "尚無裝置，請開啟 SeekMoon 並在“設定 → 遠端存取”中登入。"
    (Japanese, NoDevices) =>
      "デバイスがありません。SeekMoon を開き、「設定 → リモートアクセス」からログインしてください。"
    (English, NoOnlineDevice) => "No online device — reconnecting…"
    (SimplifiedChinese, NoOnlineDevice) =>
      "没有在线设备，正在重新连接…"
    (TraditionalChinese, NoOnlineDevice) =>
      "沒有線上裝置，正在重新連線…"
    (Japanese, NoOnlineDevice) =>
      "オンラインのデバイスがありません。再接続中…"
    (English, UpdateLabel) => "Update"
    (SimplifiedChinese, UpdateLabel) => "更新"
    (TraditionalChinese, UpdateLabel) => "更新"
    (Japanese, UpdateLabel) => "更新"
    (English, RestartingLabel) => "Restarting…"
    (SimplifiedChinese, RestartingLabel) => "正在重启…"
    (TraditionalChinese, RestartingLabel) => "正在重啟…"
    (Japanese, RestartingLabel) => "再起動中…"
    (English, RestartToUpdateLabel) => "Restart to update"
    (SimplifiedChinese, RestartToUpdateLabel) => "重启以更新"
    (TraditionalChinese, RestartToUpdateLabel) => "重啟以更新"
    (Japanese, RestartToUpdateLabel) => "再起動して更新"
    (English, ArchivedReadOnly) => "Archived conversation · Read only"
    (SimplifiedChinese, ArchivedReadOnly) => "已归档对话 · 只读"
    (TraditionalChinese, ArchivedReadOnly) => "已歸檔對話 · 唯讀"
    (Japanese, ArchivedReadOnly) =>
      "アーカイブ済みチャット · 読み取り専用"
    (English, RestoreBeforeContinue) =>
      "Restore this conversation before continuing it"
    (SimplifiedChinese, RestoreBeforeContinue) =>
      "恢复此对话后即可继续"
    (TraditionalChinese, RestoreBeforeContinue) =>
      "恢復此對話後即可繼續"
    (Japanese, RestoreBeforeContinue) =>
      "続行するにはこのチャットを復元してください"
    (English, RestoreLabel) => "Restore"
    (SimplifiedChinese, RestoreLabel) => "恢复"
    (TraditionalChinese, RestoreLabel) => "恢復"
    (Japanese, RestoreLabel) => "復元"
    (English, ShowDetailed) => "Show detailed conversation"
    (SimplifiedChinese, ShowDetailed) => "显示完整对话"
    (TraditionalChinese, ShowDetailed) => "顯示完整對話"
    (Japanese, ShowDetailed) => "チャット全体を表示"
    (English, ShowMinimal) => "Show minimal conversation"
    (SimplifiedChinese, ShowMinimal) => "显示精简对话"
    (TraditionalChinese, ShowMinimal) => "顯示精簡對話"
    (Japanese, ShowMinimal) => "簡易チャットを表示"
    (English, DetailedMode) => "Detailed mode"
    (SimplifiedChinese, DetailedMode) => "详细模式"
    (TraditionalChinese, DetailedMode) => "詳細模式"
    (Japanese, DetailedMode) => "詳細モード"
    (English, ExportConversation) => "Export conversation"
    (SimplifiedChinese, ExportConversation) => "导出对话"
    (TraditionalChinese, ExportConversation) => "匯出對話"
    (Japanese, ExportConversation) => "チャットをエクスポート"
    (English, HideTerminal) => "Hide terminal (Ctrl+`)"
    (SimplifiedChinese, HideTerminal) => "隐藏终端（Ctrl+`）"
    (TraditionalChinese, HideTerminal) => "隱藏終端（Ctrl+`）"
    (Japanese, HideTerminal) => "ターミナルを非表示（Ctrl+`）"
    (English, ShowTerminal) => "Show terminal (Ctrl+`)"
    (SimplifiedChinese, ShowTerminal) => "显示终端（Ctrl+`）"
    (TraditionalChinese, ShowTerminal) => "顯示終端（Ctrl+`）"
    (Japanese, ShowTerminal) => "ターミナルを表示（Ctrl+`）"
    (English, ShowPanel) => "Show panel"
    (SimplifiedChinese, ShowPanel) => "显示面板"
    (TraditionalChinese, ShowPanel) => "顯示面板"
    (Japanese, ShowPanel) => "パネルを表示"
    (English, OpenProject) => "Open a project"
    (SimplifiedChinese, OpenProject) => "打开项目"
    (TraditionalChinese, OpenProject) => "開啟專案"
    (Japanese, OpenProject) => "プロジェクトを開く"
    (English, ProjectOnboarding) =>
      "SeekMoon works inside a project directory. Add one and its first chat opens here."
    (SimplifiedChinese, ProjectOnboarding) =>
      "SeekMoon 在项目目录中工作。添加项目后，首个对话将在此处打开。"
    (TraditionalChinese, ProjectOnboarding) =>
      "SeekMoon 在專案目錄中工作。新增專案後，首個對話將在此處開啟。"
    (Japanese, ProjectOnboarding) =>
      "SeekMoon はプロジェクトのディレクトリで作業します。プロジェクトを追加すると、最初のチャットがここに開きます。"
    (English, AddProject) => "Add a project"
    (SimplifiedChinese, AddProject) => "添加项目"
    (TraditionalChinese, AddProject) => "新增專案"
    (Japanese, AddProject) => "プロジェクトを追加"
    (English, OpeningChat) => "Opening a chat…"
    (SimplifiedChinese, OpeningChat) => "正在打开对话…"
    (TraditionalChinese, OpeningChat) => "正在開啟對話…"
    (Japanese, OpeningChat) => "チャットを開いています…"
    (English, ConnectingDevice) => "Connecting to this device…"
    (SimplifiedChinese, ConnectingDevice) => "正在连接此设备…"
    (TraditionalChinese, ConnectingDevice) => "正在連線此裝置…"
    (Japanese, ConnectingDevice) => "このデバイスに接続中…"
    (English, CheckingSignIn) => "Checking sign-in…"
    (SimplifiedChinese, CheckingSignIn) => "正在检查登录状态…"
    (TraditionalChinese, CheckingSignIn) => "正在檢查登入狀態…"
    (Japanese, CheckingSignIn) => "ログイン状態を確認中…"
    (English, TryAgain) => "Try again"
    (SimplifiedChinese, TryAgain) => "重试"
    (TraditionalChinese, TryAgain) => "重試"
    (Japanese, TryAgain) => "再試行"
    (English, SignInLabel) => "Sign in"
    (SimplifiedChinese, SignInLabel) => "登录"
    (TraditionalChinese, SignInLabel) => "登入"
    (Japanese, SignInLabel) => "ログイン"
    (English, BrowserAccess) => "Access this SeekMoon device from your browser."
    (SimplifiedChinese, BrowserAccess) =>
      "通过浏览器访问此 SeekMoon 设备。"
    (TraditionalChinese, BrowserAccess) =>
      "透過瀏覽器訪問此 SeekMoon 裝置。"
    (Japanese, BrowserAccess) =>
      "ブラウザーからこの SeekMoon デバイスにアクセスします。"
    (English, SignInGitHub) => "Sign in with GitHub"
    (SimplifiedChinese, SignInGitHub) => "使用 GitHub 登录"
    (TraditionalChinese, SignInGitHub) => "使用 GitHub 登入"
    (Japanese, SignInGitHub) => "GitHub でログイン"
    (English, CheckingDevice) => "Checking device…"
    (SimplifiedChinese, CheckingDevice) => "正在检查设备…"
    (TraditionalChinese, CheckingDevice) => "正在檢查裝置…"
    (Japanese, CheckingDevice) => "デバイスを確認中…"
    (English, CannotLoadDevice) => "Can't load device"
    (SimplifiedChinese, CannotLoadDevice) => "无法加载设备"
    (TraditionalChinese, CannotLoadDevice) => "無法載入裝置"
    (Japanese, CannotLoadDevice) => "デバイスを読み込めません"
    (English, WaitingConnection) => "Waiting for this device's connection."
    (SimplifiedChinese, WaitingConnection) => "正在等待此设备连接。"
    (TraditionalChinese, WaitingConnection) => "正在等待此裝置連線。"
    (Japanese, WaitingConnection) =>
      "このデバイスの接続を待機中です。"
    (English, BringOnline) => "Bring this device online, then refresh."
    (SimplifiedChinese, BringOnline) =>
      "请将此设备联网，然后刷新。"
    (TraditionalChinese, BringOnline) =>
      "請將此裝置聯網，然後重新整理。"
    (Japanese, BringOnline) =>
      "このデバイスをオンラインにしてから更新してください。"
    (English, DeviceUnavailable) => "Device unavailable"
    (SimplifiedChinese, DeviceUnavailable) => "设备不可用"
    (TraditionalChinese, DeviceUnavailable) => "裝置不可用"
    (Japanese, DeviceUnavailable) => "デバイスを利用できません"
    (English, DeviceNotInAccount) =>
      "This device is not available to the signed-in account."
    (SimplifiedChinese, DeviceNotInAccount) =>
      "当前登录的账户无法访问此设备。"
    (TraditionalChinese, DeviceNotInAccount) =>
      "當前登入的帳戶無法訪問此裝置。"
    (Japanese, DeviceNotInAccount) =>
      "現在のアカウントではこのデバイスにアクセスできません。"
    (English, RefreshLabel) => "Refresh"
    (SimplifiedChinese, RefreshLabel) => "刷新"
    (TraditionalChinese, RefreshLabel) => "重新整理"
    (Japanese, RefreshLabel) => "更新"
    (English, DeviceLinkRequired) => "Device link required"
    (SimplifiedChinese, DeviceLinkRequired) => "需要设备链接"
    (TraditionalChinese, DeviceLinkRequired) => "需要裝置連結"
    (Japanese, DeviceLinkRequired) => "デバイスのリンクが必要です"
    (English, DeviceLinkDescription) =>
      "Open this page from Remote access in SeekMoon so the URL identifies one device."
    (SimplifiedChinese, DeviceLinkDescription) =>
      "请从 SeekMoon 的“远程访问”中打开此页面，以便通过链接识别设备。"
    (TraditionalChinese, DeviceLinkDescription) =>
      "請從 SeekMoon 的“遠端存取”中開啟此頁面，以便透過連結識別裝置。"
    (Japanese, DeviceLinkDescription) =>
      "SeekMoon の「リモートアクセス」からこのページを開いてください。リンクによってデバイスを識別します。"
    (English, SigningOut) => "Signing out…"
    (SimplifiedChinese, SigningOut) => "正在退出登录…"
    (TraditionalChinese, SigningOut) => "正在退出登入…"
    (Japanese, SigningOut) => "ログアウト中…"
    (English, SignOutLabel) => "Sign out"
    (SimplifiedChinese, SignOutLabel) => "退出登录"
    (TraditionalChinese, SignOutLabel) => "退出登入"
    (Japanese, SignOutLabel) => "ログアウト"
    (English, LoadingConversation) => "Loading conversation…"
    (SimplifiedChinese, LoadingConversation) => "正在加载对话…"
    (TraditionalChinese, LoadingConversation) => "正在載入對話…"
    (Japanese, LoadingConversation) => "チャットを読み込み中…"
    (English, CannotLoadConversation) => "Could not load conversation"
    (SimplifiedChinese, CannotLoadConversation) => "无法加载对话"
    (TraditionalChinese, CannotLoadConversation) => "無法載入對話"
    (Japanese, CannotLoadConversation) => "チャットを読み込めません"
    (English, RetryLabel) => "Retry"
    (SimplifiedChinese, RetryLabel) => "重试"
    (TraditionalChinese, RetryLabel) => "重試"
    (Japanese, RetryLabel) => "再試行"
    (English, ScheduleReadOnly) => "Scheduled task · Read only while running"
    (SimplifiedChinese, ScheduleReadOnly) =>
      "定时任务 · 运行期间只读"
    (TraditionalChinese, ScheduleReadOnly) =>
      "定時任務 · 執行期間唯讀"
    (Japanese, ScheduleReadOnly) =>
      "スケジュールタスク · 実行中は読み取り専用"
    (English, ViewTask) => "View task"
    (SimplifiedChinese, ViewTask) => "查看任务"
    (TraditionalChinese, ViewTask) => "檢視任務"
    (Japanese, ViewTask) => "タスクを表示"
    (English, DisconnectedLabel) => "Disconnected"
    (SimplifiedChinese, DisconnectedLabel) => "已断开连接"
    (TraditionalChinese, DisconnectedLabel) => "已斷開連線"
    (Japanese, DisconnectedLabel) => "切断済み"
    (English, InterruptForUpdate) =>
      "A conversation is still running. Restarting the app interrupts it; the transcript so far is saved."
    (SimplifiedChinese, InterruptForUpdate) =>
      "仍有对话正在运行。重启应用会中断运行，已有的对话记录将会保留。"
    (TraditionalChinese, InterruptForUpdate) =>
      "仍有對話正在執行。重啟應用會中斷執行，已有的對話記錄將會保留。"
    (Japanese, InterruptForUpdate) =>
      "実行中のチャットがあります。アプリを再起動すると実行が中断されますが、既存のチャット履歴は保持されます。"
    (English, KeepWorking) => "Keep working"
    (SimplifiedChinese, KeepWorking) => "继续工作"
    (TraditionalChinese, KeepWorking) => "繼續工作"
    (Japanese, KeepWorking) => "作業を続行"
    (English, RestartNow) => "Restart now"
    (SimplifiedChinese, RestartNow) => "立即重启"
    (TraditionalChinese, RestartNow) => "立即重啟"
    (Japanese, RestartNow) => "今すぐ再起動"
    (English, SetupDeepSeek) => "Set up your DeepSeek API key"
    (SimplifiedChinese, SetupDeepSeek) => "设置 DeepSeek API 密钥"
    (TraditionalChinese, SetupDeepSeek) => "設定 DeepSeek API 金鑰"
    (Japanese, SetupDeepSeek) => "DeepSeek API キーを設定"
    (English, SetupGlm) => "Set up your GLM API key"
    (SimplifiedChinese, SetupGlm) => "设置 GLM API 密钥"
    (TraditionalChinese, SetupGlm) => "設定 GLM API 金鑰"
    (Japanese, SetupGlm) => "GLM API キーを設定"
    (English, SetupOpenRouter) => "Set up OpenRouter"
    (SimplifiedChinese, SetupOpenRouter) => "设置 OpenRouter"
    (TraditionalChinese, SetupOpenRouter) => "設定 OpenRouter"
    (Japanese, SetupOpenRouter) => "OpenRouter を設定"
    (English, SetupEndpoint) => "Set your endpoint URL"
    (SimplifiedChinese, SetupEndpoint) => "设置端点 URL"
    (TraditionalChinese, SetupEndpoint) => "設定端點 URL"
    (Japanese, SetupEndpoint) => "エンドポイント URL を設定"
    (English, NotNow) => "Not now"
    (SimplifiedChinese, NotNow) => "暂不设置"
    (TraditionalChinese, NotNow) => "暫不設定"
    (Japanese, NotNow) => "後で設定"
    (English, DismissLabel) => "Dismiss"
    (SimplifiedChinese, DismissLabel) => "关闭"
    (TraditionalChinese, DismissLabel) => "關閉"
    (Japanese, DismissLabel) => "閉じる"
    (English, RenameConversation) => "Rename conversation"
    (SimplifiedChinese, RenameConversation) => "重命名对话"
    (TraditionalChinese, RenameConversation) => "重新命名對話"
    (Japanese, RenameConversation) => "チャット名を変更"
    (English, CancelLabel) => "Cancel"
    (SimplifiedChinese, CancelLabel) => "取消"
    (TraditionalChinese, CancelLabel) => "取消"
    (Japanese, CancelLabel) => "キャンセル"
    (English, SavingLabel) => "Saving…"
    (SimplifiedChinese, SavingLabel) => "正在保存…"
    (TraditionalChinese, SavingLabel) => "正在儲存…"
    (Japanese, SavingLabel) => "保存中…"
    (English, SaveLabel) => "Save"
    (SimplifiedChinese, SaveLabel) => "保存"
    (TraditionalChinese, SaveLabel) => "儲存"
    (Japanese, SaveLabel) => "保存"
    (English, DeleteChatQuestion) => "Permanently delete this chat?"
    (SimplifiedChinese, DeleteChatQuestion) => "永久删除此对话？"
    (TraditionalChinese, DeleteChatQuestion) => "永久刪除此對話？"
    (Japanese, DeleteChatQuestion) =>
      "このチャットを完全に削除しますか？"
    (English, DeletePermanently) => "Delete permanently"
    (SimplifiedChinese, DeletePermanently) => "永久删除"
    (TraditionalChinese, DeletePermanently) => "永久刪除"
    (Japanese, DeletePermanently) => "完全に削除"
    (English, NoEndpoint) => "No endpoint URL configured — Send is disabled."
    (SimplifiedChinese, NoEndpoint) =>
      "尚未设置端点 URL，无法发送。"
    (TraditionalChinese, NoEndpoint) =>
      "尚未設定端點 URL，無法傳送。"
    (Japanese, NoEndpoint) =>
      "エンドポイント URL が未設定のため送信できません。"
    (English, NoGlmKey) => "No GLM API key configured — Send is disabled."
    (SimplifiedChinese, NoGlmKey) =>
      "尚未设置 GLM API 密钥，无法发送。"
    (TraditionalChinese, NoGlmKey) =>
      "尚未設定 GLM API 金鑰，無法傳送。"
    (Japanese, NoGlmKey) =>
      "GLM API キーが未設定のため送信できません。"
    (English, NoOpenRouterKey) =>
      "No OpenRouter API key configured — Send is disabled."
    (SimplifiedChinese, NoOpenRouterKey) =>
      "尚未设置 OpenRouter API 密钥，无法发送。"
    (TraditionalChinese, NoOpenRouterKey) =>
      "尚未設定 OpenRouter API 金鑰，無法傳送。"
    (Japanese, NoOpenRouterKey) =>
      "OpenRouter API キーが未設定のため送信できません。"
    (English, NoDeepSeekKey) =>
      "No DeepSeek API key configured — Send is disabled."
    (SimplifiedChinese, NoDeepSeekKey) =>
      "尚未设置 DeepSeek API 密钥，无法发送。"
    (TraditionalChinese, NoDeepSeekKey) =>
      "尚未設定 DeepSeek API 金鑰，無法傳送。"
    (Japanese, NoDeepSeekKey) =>
      "DeepSeek API キーが未設定のため送信できません。"
    (English, CompactContext) =>
      "Summarize and shrink this conversation's context"
    (SimplifiedChinese, CompactContext) =>
      "总结并压缩此对话的上下文"
    (TraditionalChinese, CompactContext) =>
      "總結並壓縮此對話的上下文"
    (Japanese, CompactContext) =>
      "このチャットのコンテキストを要約・圧縮"
    (English, SetGoal) => "Set or clear this conversation's standing goal"
    (SimplifiedChinese, SetGoal) => "设置或清除此对话的长期目标"
    (TraditionalChinese, SetGoal) => "設定或清除此對話的長期目標"
    (Japanese, SetGoal) =>
      "このチャットの継続的な目標を設定・解除"
    (English, GoalPlaceholder) =>
      "Describe the standing goal for this conversation — Enter sets it, Esc cancels."
    (SimplifiedChinese, GoalPlaceholder) =>
      "描述此对话的长期目标，按 Enter 设置，按 Esc 取消。"
    (TraditionalChinese, GoalPlaceholder) =>
      "描述此對話的長期目標，按 Enter 設定，按 Esc 取消。"
    (Japanese, GoalPlaceholder) =>
      "このチャットの継続的な目標を入力。Enter で設定、Esc でキャンセル。"
    (English, EditQueuePlaceholder) =>
      "Edit the queued message — Enter saves it."
    (SimplifiedChinese, EditQueuePlaceholder) =>
      "编辑已排队的消息，按 Enter 保存。"
    (TraditionalChinese, EditQueuePlaceholder) =>
      "編輯已排隊的訊息，按 Enter 儲存。"
    (Japanese, EditQueuePlaceholder) =>
      "待機中のメッセージを編集。Enter で保存。"
    (English, QueuePlaceholder) => "Queue a follow-up for the next turn."
    (SimplifiedChinese, QueuePlaceholder) =>
      "为下一轮任务添加后续消息。"
    (TraditionalChinese, QueuePlaceholder) =>
      "為下一輪任務新增後續訊息。"
    (Japanese, QueuePlaceholder) =>
      "次のターンへの追加メッセージを入力。"
    (English, SteerPlaceholder) =>
      "Steer the running task — your message joins it at the next step."
    (SimplifiedChinese, SteerPlaceholder) =>
      "引导正在运行的任务，消息将在下一步加入。"
    (TraditionalChinese, SteerPlaceholder) =>
      "引導正在執行的任務，訊息將在下一步加入。"
    (Japanese, SteerPlaceholder) =>
      "実行中のタスクに指示します。メッセージは次のステップで追加されます。"
    (English, AskPlaceholder) =>
      "Ask SeekMoon to inspect, edit, or explain this workspace."
    (SimplifiedChinese, AskPlaceholder) =>
      "让 SeekMoon 检查、编辑或解释此工作区。"
    (TraditionalChinese, AskPlaceholder) =>
      "讓 SeekMoon 檢查、編輯或解釋此工作區。"
    (Japanese, AskPlaceholder) =>
      "このワークスペースの調査・編集・説明を SeekMoon に依頼。"
  }
}
