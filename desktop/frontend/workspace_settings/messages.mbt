// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  NewChatsLabel
  LocalLabel
  WorktreeLabel
  NewChatsDescription
  SubmodulesLabel
  InitializeLabel
  LeaveUninitialized
  WorktreeSubmodules
  SubmodulesDescription
  CheckoutTimeout
  FiveSeconds
  TenSeconds
  ThirtySeconds
  SixtySeconds
  SubmoduleTimeout
  TimeoutDescription
  WorkspaceLabel
  ConversationsLabel
  WorktreesLabel
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, NewChatsLabel) => "New chats"
    (SimplifiedChinese, NewChatsLabel) => "新建对话"
    (Japanese, NewChatsLabel) => "新しいチャット"
    (English, LocalLabel) => "Local"
    (SimplifiedChinese, LocalLabel) => "本地"
    (Japanese, LocalLabel) => "ローカル"
    (English, WorktreeLabel) => "Worktree"
    (SimplifiedChinese, WorktreeLabel) => "工作树"
    (Japanese, WorktreeLabel) => "ワークツリー"
    (English, NewChatsDescription) =>
      "Where a new chat starts: the workspace itself, or a fresh git worktree bound to that chat. The composer's chip still changes a single chat."
    (SimplifiedChinese, NewChatsDescription) =>
      "新对话的运行位置：当前工作区，或专属于此对话的新 Git 工作树。仍可通过输入框旁的按钮更改单个对话的设置。"
    (Japanese, NewChatsDescription) =>
      "新しいチャットを現在のワークスペース、または専用の新しい Git ワークツリーで実行します。入力欄の隣のボタンでチャットごとに変更できます。"
    (English, SubmodulesLabel) => "Submodules"
    (SimplifiedChinese, SubmodulesLabel) => "子模块"
    (Japanese, SubmodulesLabel) => "サブモジュール"
    (English, InitializeLabel) => "Initialize"
    (SimplifiedChinese, InitializeLabel) => "初始化"
    (Japanese, InitializeLabel) => "初期化する"
    (English, LeaveUninitialized) => "Leave uninitialized"
    (SimplifiedChinese, LeaveUninitialized) => "不初始化"
    (Japanese, LeaveUninitialized) => "初期化しない"
    (English, WorktreeSubmodules) => "Submodules in worktrees"
    (SimplifiedChinese, WorktreeSubmodules) => "工作树中的子模块"
    (Japanese, WorktreeSubmodules) =>
      "ワークツリーのサブモジュール"
    (English, SubmodulesDescription) =>
      "For new or repaired worktrees in this workspace, mirror the top-level submodules already initialized in its main checkout."
    (SimplifiedChinese, SubmodulesDescription) =>
      "为此工作区新建或修复工作树时，同步主检出目录中已初始化的顶层子模块。"
    (Japanese, SubmodulesDescription) =>
      "このワークスペースでワークツリーを作成・修復する際、メインのチェックアウトで初期化済みの最上位サブモジュールを同期します。"
    (English, CheckoutTimeout) => "Checkout timeout"
    (SimplifiedChinese, CheckoutTimeout) => "检出超时"
    (Japanese, CheckoutTimeout) => "チェックアウトのタイムアウト"
    (English, FiveSeconds) => "5 seconds"
    (SimplifiedChinese, FiveSeconds) => "5 秒"
    (Japanese, FiveSeconds) => "5 秒"
    (English, TenSeconds) => "10 seconds"
    (SimplifiedChinese, TenSeconds) => "10 秒"
    (Japanese, TenSeconds) => "10 秒"
    (English, ThirtySeconds) => "30 seconds"
    (SimplifiedChinese, ThirtySeconds) => "30 秒"
    (Japanese, ThirtySeconds) => "30 秒"
    (English, SixtySeconds) => "60 seconds"
    (SimplifiedChinese, SixtySeconds) => "60 秒"
    (Japanese, SixtySeconds) => "60 秒"
    (English, SubmoduleTimeout) => "Submodule checkout timeout"
    (SimplifiedChinese, SubmoduleTimeout) => "子模块检出超时"
    (Japanese, SubmoduleTimeout) =>
      "サブモジュールのチェックアウトのタイムアウト"
    (English, TimeoutDescription) =>
      "Stop initializing submodules if Git has not finished within this time."
    (SimplifiedChinese, TimeoutDescription) =>
      "如果 Git 未在此时间内完成，则停止初始化子模块。"
    (Japanese, TimeoutDescription) =>
      "この時間内に Git が完了しない場合、サブモジュールの初期化を停止します。"
    (English, WorkspaceLabel) => "Workspace"
    (SimplifiedChinese, WorkspaceLabel) => "工作区"
    (Japanese, WorkspaceLabel) => "ワークスペース"
    (English, ConversationsLabel) => "Conversations"
    (SimplifiedChinese, ConversationsLabel) => "对话"
    (Japanese, ConversationsLabel) => "チャット"
    (English, WorktreesLabel) => "Worktrees"
    (SimplifiedChinese, WorktreesLabel) => "工作树"
    (Japanese, WorktreesLabel) => "ワークツリー"
  }
}
