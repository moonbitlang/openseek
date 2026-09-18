// Feature-owned UI messages; both built-in languages are exhaustive.

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
    (English, Projects) => "Projects"
    (SimplifiedChinese, Projects) => "项目"
    (English, NoChats) => "No chats yet"
    (SimplifiedChinese, NoChats) => "暂无对话"
    (English, NewChat) => "New chat"
    (SimplifiedChinese, NewChat) => "新建对话"
    (English, CreatingChat) => "Creating chat…"
    (SimplifiedChinese, CreatingChat) => "正在创建对话…"
    (English, AddProject) => "Add a project"
    (SimplifiedChinese, AddProject) => "添加项目"
    (English, ArchivedChats(count)) =>
      if count == 0 {
        "Archived chats"
      } else {
        "Archived chats (\{count})"
      }
    (SimplifiedChinese, ArchivedChats(count)) =>
      if count == 0 {
        "已归档对话"
      } else {
        "已归档对话（\{count}）"
      }
    (English, ShowMore) => "Show more"
    (SimplifiedChinese, ShowMore) => "显示更多"
    (English, ShowMoreIn(label)) => "Show more in \{label}"
    (SimplifiedChinese, ShowMoreIn(label)) =>
      "显示“\{label}”中的更多内容"
    (English, ShowMoreChats) => "Show more chats in this project"
    (SimplifiedChinese, ShowMoreChats) => "显示此项目中的更多对话"
    (English, MoreActions) => "More actions"
    (SimplifiedChinese, MoreActions) => "更多操作"
    (English, NewProjectConversation) => "New conversation in this project"
    (SimplifiedChinese, NewProjectConversation) => "在此项目中新建对话"
    (English, WorkspaceSettings) => "Workspace settings"
    (SimplifiedChinese, WorkspaceSettings) => "工作区设置"
    (English, WorkspaceDefaults) => "Defaults for new chats in this workspace"
    (SimplifiedChinese, WorkspaceDefaults) =>
      "此工作区中新建对话的默认设置"
    (English, DetachProject) => "Detach project"
    (SimplifiedChinese, DetachProject) => "移除项目"
    (English, DetachDescription) =>
      "Detach this project — its files and sessions stay"
    (SimplifiedChinese, DetachDescription) =>
      "从列表中移除此项目，保留文件和对话"
    (English, HideSidebar) => "Hide sidebar"
    (SimplifiedChinese, HideSidebar) => "隐藏侧边栏"
    (English, ShowSidebar) => "Show sidebar"
    (SimplifiedChinese, ShowSidebar) => "显示侧边栏"
    (English, WorkspaceActions) => "Workspace actions"
    (SimplifiedChinese, WorkspaceActions) => "工作区操作"
    (English, ConversationActions) => "Conversation actions"
    (SimplifiedChinese, ConversationActions) => "对话操作"
    (English, Skills) => "Skills"
    (SimplifiedChinese, Skills) => "技能"
    (English, Scheduled) => "Scheduled"
    (SimplifiedChinese, Scheduled) => "定时任务"
    (English, Settings) => "Settings"
    (SimplifiedChinese, Settings) => "设置"
    (English, RefreshDevices) => "Refresh the device list"
    (SimplifiedChinese, RefreshDevices) => "刷新设备列表"
    (English, Refresh) => "Refresh"
    (SimplifiedChinese, Refresh) => "刷新"
    (English, SignOut) => "Sign out"
    (SimplifiedChinese, SignOut) => "退出登录"
  }
}
