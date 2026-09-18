// Feature-owned UI messages; all built-in languages are exhaustive.

///|
/// Shared chrome for sidebar sections and projects; never user-authored titles.
pub(all) enum Message {
  Chats
  Projects
  NoChats
  NewChat
  CreatingChat
  AddProject
  ArchivedChats(Int)
  ShowMore
  ShowMoreIn(String)
  ShowMoreChats
  MoreActions
  NewProjectConversation
  WorkspaceSettings
  WorkspaceDefaults
  DetachProject
  DetachDescription
  HideSidebar
  ShowSidebar
  WorkspaceActions
  ConversationActions
  Skills
  Scheduled
  Settings
  RefreshDevices
  Refresh
  SignOut
}

///|
/// Translate sidebar chrome without changing stable component identities.
pub fn text(locale : @i18n.Locale, message : Message) -> String {
  match (locale, message) {
    (English, Chats) => "Chats"
    (SimplifiedChinese, Chats) => "对话"
    (TraditionalChinese, Chats) => "對話"
    (Japanese, Chats) => "チャット"
    (English, Projects) => "Projects"
    (SimplifiedChinese, Projects) => "项目"
    (TraditionalChinese, Projects) => "專案"
    (Japanese, Projects) => "プロジェクト"
    (English, NoChats) => "No chats yet"
    (SimplifiedChinese, NoChats) => "暂无对话"
    (TraditionalChinese, NoChats) => "暫無對話"
    (Japanese, NoChats) => "チャットはありません"
    (English, NewChat) => "New chat"
    (SimplifiedChinese, NewChat) => "新建对话"
    (TraditionalChinese, NewChat) => "新建對話"
    (Japanese, NewChat) => "新しいチャット"
    (English, CreatingChat) => "Creating chat…"
    (SimplifiedChinese, CreatingChat) => "正在创建对话…"
    (TraditionalChinese, CreatingChat) => "正在建立對話…"
    (Japanese, CreatingChat) => "チャットを作成中…"
    (English, AddProject) => "Add a project"
    (SimplifiedChinese, AddProject) => "添加项目"
    (TraditionalChinese, AddProject) => "新增專案"
    (Japanese, AddProject) => "プロジェクトを追加"
    (English, ArchivedChats(count)) =>
      if count == 0 {
        "Archived chats"
      } else {
        "Archived chats (\{count})"
      }
    (Japanese, ArchivedChats(count)) =>
      if count == 0 {
        "アーカイブ済みチャット"
      } else {
        "アーカイブ済みチャット（\{count}）"
      }
    (SimplifiedChinese, ArchivedChats(count)) =>
      if count == 0 {
        "已归档对话"
      } else {
        "已归档对话（\{count}）"
      }
    (TraditionalChinese, ArchivedChats(count)) =>
      if count == 0 {
        "已歸檔對話"
      } else {
        "已歸檔對話（\{count}）"
      }
    (English, ShowMore) => "Show more"
    (SimplifiedChinese, ShowMore) => "显示更多"
    (TraditionalChinese, ShowMore) => "顯示更多"
    (Japanese, ShowMore) => "さらに表示"
    (English, ShowMoreIn(label)) => "Show more in \{label}"
    (SimplifiedChinese, ShowMoreIn(label)) =>
      "显示“\{label}”中的更多内容"
    (TraditionalChinese, ShowMoreIn(label)) =>
      "顯示“\{label}”中的更多內容"
    (Japanese, ShowMoreIn(label)) => "「\{label}」の項目をさらに表示"
    (English, ShowMoreChats) => "Show more chats in this project"
    (SimplifiedChinese, ShowMoreChats) => "显示此项目中的更多对话"
    (TraditionalChinese, ShowMoreChats) => "顯示此專案中的更多對話"
    (Japanese, ShowMoreChats) =>
      "このプロジェクトのチャットをさらに表示"
    (English, MoreActions) => "More actions"
    (SimplifiedChinese, MoreActions) => "更多操作"
    (TraditionalChinese, MoreActions) => "更多操作"
    (Japanese, MoreActions) => "その他の操作"
    (English, NewProjectConversation) => "New conversation in this project"
    (SimplifiedChinese, NewProjectConversation) => "在此项目中新建对话"
    (TraditionalChinese, NewProjectConversation) =>
      "在此專案中新建對話"
    (Japanese, NewProjectConversation) =>
      "このプロジェクトで新しいチャットを作成"
    (English, WorkspaceSettings) => "Workspace settings"
    (SimplifiedChinese, WorkspaceSettings) => "工作区设置"
    (TraditionalChinese, WorkspaceSettings) => "工作區設定"
    (Japanese, WorkspaceSettings) => "ワークスペースの設定"
    (English, WorkspaceDefaults) => "Defaults for new chats in this workspace"
    (SimplifiedChinese, WorkspaceDefaults) =>
      "此工作区中新建对话的默认设置"
    (TraditionalChinese, WorkspaceDefaults) =>
      "此工作區中新建對話的預設設定"
    (Japanese, WorkspaceDefaults) =>
      "このワークスペースの新しいチャットの既定設定"
    (English, DetachProject) => "Detach project"
    (SimplifiedChinese, DetachProject) => "移除项目"
    (TraditionalChinese, DetachProject) => "移除專案"
    (Japanese, DetachProject) => "プロジェクトを削除"
    (English, DetachDescription) =>
      "Detach this project — its files and sessions stay"
    (SimplifiedChinese, DetachDescription) =>
      "从列表中移除此项目，保留文件和对话"
    (TraditionalChinese, DetachDescription) =>
      "從列表中移除此專案，保留檔案和對話"
    (Japanese, DetachDescription) =>
      "ファイルとチャットを保持してプロジェクトを一覧から削除"
    (English, HideSidebar) => "Hide sidebar"
    (SimplifiedChinese, HideSidebar) => "隐藏侧边栏"
    (TraditionalChinese, HideSidebar) => "隱藏側邊欄"
    (Japanese, HideSidebar) => "サイドバーを非表示"
    (English, ShowSidebar) => "Show sidebar"
    (SimplifiedChinese, ShowSidebar) => "显示侧边栏"
    (TraditionalChinese, ShowSidebar) => "顯示側邊欄"
    (Japanese, ShowSidebar) => "サイドバーを表示"
    (English, WorkspaceActions) => "Workspace actions"
    (SimplifiedChinese, WorkspaceActions) => "工作区操作"
    (TraditionalChinese, WorkspaceActions) => "工作區操作"
    (Japanese, WorkspaceActions) => "ワークスペースの操作"
    (English, ConversationActions) => "Conversation actions"
    (SimplifiedChinese, ConversationActions) => "对话操作"
    (TraditionalChinese, ConversationActions) => "對話操作"
    (Japanese, ConversationActions) => "チャットの操作"
    (English, Skills) => "Skills"
    (SimplifiedChinese, Skills) => "技能"
    (TraditionalChinese, Skills) => "技能"
    (Japanese, Skills) => "スキル"
    (English, Scheduled) => "Scheduled"
    (SimplifiedChinese, Scheduled) => "定时任务"
    (TraditionalChinese, Scheduled) => "定時任務"
    (Japanese, Scheduled) => "スケジュールタスク"
    (English, Settings) => "Settings"
    (SimplifiedChinese, Settings) => "设置"
    (TraditionalChinese, Settings) => "設定"
    (Japanese, Settings) => "設定"
    (English, RefreshDevices) => "Refresh the device list"
    (SimplifiedChinese, RefreshDevices) => "刷新设备列表"
    (TraditionalChinese, RefreshDevices) => "重新整理裝置列表"
    (Japanese, RefreshDevices) => "デバイス一覧を更新"
    (English, Refresh) => "Refresh"
    (SimplifiedChinese, Refresh) => "刷新"
    (TraditionalChinese, Refresh) => "重新整理"
    (Japanese, Refresh) => "更新"
    (English, SignOut) => "Sign out"
    (SimplifiedChinese, SignOut) => "退出登录"
    (TraditionalChinese, SignOut) => "退出登入"
    (Japanese, SignOut) => "ログアウト"
  }
}
