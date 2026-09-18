// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  HandWritten
  Removing
  Uninstall
  InstalledCheck
  Installing
  Install
  LoadingDocument
  Metadata
  Back
  Details
  CopyDocument
  Copy
  Loading
  InstallSkill
  HandWrittenSkill
  Library
  Skills
  Description
  Search
  EmptyInstalled
  NoInstalledMatch
  InstalledLabel
  LoadingCatalog
  EmptyRegistry
  NoRegistryMatch
  Registry
  Refreshing
  Refresh
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, HandWritten) => "hand-written"
    (SimplifiedChinese, HandWritten) => "手动编写"
    (English, Removing) => "Removing…"
    (SimplifiedChinese, Removing) => "正在移除…"
    (English, Uninstall) => "Uninstall"
    (SimplifiedChinese, Uninstall) => "卸载"
    (English, InstalledCheck) => "✓ Installed"
    (SimplifiedChinese, InstalledCheck) => "✓ 已安装"
    (English, Installing) => "Installing…"
    (SimplifiedChinese, Installing) => "正在安装…"
    (English, Install) => "Install"
    (SimplifiedChinese, Install) => "安装"
    (English, LoadingDocument) => "Loading SKILLS.md…"
    (SimplifiedChinese, LoadingDocument) => "正在加载 SKILL.md…"
    (English, Metadata) => "Metadata"
    (SimplifiedChinese, Metadata) => "元数据"
    (English, Back) => "← Back to skills"
    (SimplifiedChinese, Back) => "← 返回技能"
    (English, Details) => "Skill details"
    (SimplifiedChinese, Details) => "技能详情"
    (English, CopyDocument) => "Copy SKILL.md"
    (SimplifiedChinese, CopyDocument) => "复制 SKILL.md"
    (English, Copy) => "Copy"
    (SimplifiedChinese, Copy) => "复制"
    (English, Loading) => "Loading…"
    (SimplifiedChinese, Loading) => "正在加载…"
    (English, InstallSkill) => "Install skill"
    (SimplifiedChinese, InstallSkill) => "安装技能"
    (English, HandWrittenSkill) => "hand-written skill"
    (SimplifiedChinese, HandWrittenSkill) => "手动编写的技能"
    (English, Library) => "Library"
    (SimplifiedChinese, Library) => "技能库"
    (English, Skills) => "Skills"
    (SimplifiedChinese, Skills) => "技能"
    (English, Description) =>
      "Playbooks the agent reads when a task matches. Skills apply to new chats."
    (SimplifiedChinese, Description) =>
      "智能体在任务匹配时读取的操作指南。技能对新建对话生效。"
    (English, Search) => "Search skills…"
    (SimplifiedChinese, Search) => "搜索技能…"
    (English, EmptyInstalled) => "No skills installed yet."
    (SimplifiedChinese, EmptyInstalled) => "尚未安装技能。"
    (English, NoInstalledMatch) => "No installed skill matches the search."
    (SimplifiedChinese, NoInstalledMatch) =>
      "未找到匹配的已安装技能。"
    (English, InstalledLabel) => "Installed"
    (SimplifiedChinese, InstalledLabel) => "已安装"
    (English, LoadingCatalog) => "Loading the skill catalog…"
    (SimplifiedChinese, LoadingCatalog) => "正在加载技能目录…"
    (English, EmptyRegistry) => "The registry lists no installable skills yet."
    (SimplifiedChinese, EmptyRegistry) =>
      "注册表中尚无可安装的技能。"
    (English, NoRegistryMatch) => "No registry skill matches the search."
    (SimplifiedChinese, NoRegistryMatch) =>
      "注册表中未找到匹配的技能。"
    (English, Registry) => "Mooncakes registry"
    (SimplifiedChinese, Registry) => "Mooncakes 注册表"
    (English, Refreshing) => "Refreshing…"
    (SimplifiedChinese, Refreshing) => "正在刷新…"
    (English, Refresh) => "Refresh"
    (SimplifiedChinese, Refresh) => "刷新"
  }
}
