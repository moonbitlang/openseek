// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  HandWritten
  Removing
  Uninstall
  NotInstalled
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
    (Spanish, HandWritten) => "escrita a mano"
    (SimplifiedChinese, HandWritten) => "手动编写"
    (TraditionalChinese, HandWritten) => "手動編寫"
    (Japanese, HandWritten) => "手動作成"
    (English, Removing) => "Removing…"
    (Spanish, Removing) => "Eliminando…"
    (SimplifiedChinese, Removing) => "正在移除…"
    (TraditionalChinese, Removing) => "正在移除…"
    (Japanese, Removing) => "削除中…"
    (English, Uninstall) => "Uninstall"
    (Spanish, Uninstall) => "Desinstalar"
    (SimplifiedChinese, Uninstall) => "卸载"
    (TraditionalChinese, Uninstall) => "解除安裝"
    (Japanese, Uninstall) => "アンインストール"
    (English, NotInstalled) => "Not installed"
    (Spanish, NotInstalled) => "No instalada"
    (SimplifiedChinese, NotInstalled) => "未安装"
    (TraditionalChinese, NotInstalled) => "未安裝"
    (Japanese, NotInstalled) => "未インストール"
    (English, InstalledCheck) => "✓ Installed"
    (Spanish, InstalledCheck) => "✓ Instalada"
    (SimplifiedChinese, InstalledCheck) => "✓ 已安装"
    (TraditionalChinese, InstalledCheck) => "✓ 已安裝"
    (Japanese, InstalledCheck) => "✓ インストール済み"
    (English, Installing) => "Installing…"
    (Spanish, Installing) => "Instalando…"
    (SimplifiedChinese, Installing) => "正在安装…"
    (TraditionalChinese, Installing) => "正在安裝…"
    (Japanese, Installing) => "インストール中…"
    (English, Install) => "Install"
    (Spanish, Install) => "Instalar"
    (SimplifiedChinese, Install) => "安装"
    (TraditionalChinese, Install) => "安裝"
    (Japanese, Install) => "インストール"
    (English, LoadingDocument) => "Loading SKILLS.md…"
    (Spanish, LoadingDocument) => "Cargando SKILLS.md…"
    (SimplifiedChinese, LoadingDocument) => "正在加载 SKILL.md…"
    (TraditionalChinese, LoadingDocument) => "正在載入 SKILL.md…"
    (Japanese, LoadingDocument) => "SKILL.md を読み込み中…"
    (English, Metadata) => "Metadata"
    (Spanish, Metadata) => "Metadatos"
    (SimplifiedChinese, Metadata) => "元数据"
    (TraditionalChinese, Metadata) => "後設資料"
    (Japanese, Metadata) => "メタデータ"
    (English, Back) => "← Back to skills"
    (Spanish, Back) => "← Volver a habilidades"
    (SimplifiedChinese, Back) => "← 返回技能"
    (TraditionalChinese, Back) => "← 返回技能"
    (Japanese, Back) => "← スキルに戻る"
    (English, Details) => "Skill details"
    (Spanish, Details) => "Detalles de la habilidad"
    (SimplifiedChinese, Details) => "技能详情"
    (TraditionalChinese, Details) => "技能詳情"
    (Japanese, Details) => "スキルの詳細"
    (English, CopyDocument) => "Copy SKILL.md"
    (Spanish, CopyDocument) => "Copiar SKILL.md"
    (SimplifiedChinese, CopyDocument) => "复制 SKILL.md"
    (TraditionalChinese, CopyDocument) => "複製 SKILL.md"
    (Japanese, CopyDocument) => "SKILL.md をコピー"
    (English, Copy) => "Copy"
    (Spanish, Copy) => "Copiar"
    (SimplifiedChinese, Copy) => "复制"
    (TraditionalChinese, Copy) => "複製"
    (Japanese, Copy) => "コピー"
    (English, Loading) => "Loading…"
    (Spanish, Loading) => "Cargando…"
    (SimplifiedChinese, Loading) => "正在加载…"
    (TraditionalChinese, Loading) => "正在載入…"
    (Japanese, Loading) => "読み込み中…"
    (English, InstallSkill) => "Install skill"
    (Spanish, InstallSkill) => "Instalar habilidad"
    (SimplifiedChinese, InstallSkill) => "安装技能"
    (TraditionalChinese, InstallSkill) => "安裝技能"
    (Japanese, InstallSkill) => "スキルをインストール"
    (English, HandWrittenSkill) => "hand-written skill"
    (Spanish, HandWrittenSkill) => "habilidad escrita a mano"
    (SimplifiedChinese, HandWrittenSkill) => "手动编写的技能"
    (TraditionalChinese, HandWrittenSkill) => "手動編寫的技能"
    (Japanese, HandWrittenSkill) => "手動作成のスキル"
    (English, Library) => "Library"
    (Spanish, Library) => "Biblioteca"
    (SimplifiedChinese, Library) => "技能库"
    (TraditionalChinese, Library) => "技能庫"
    (Japanese, Library) => "スキルライブラリ"
    (English, Skills) => "Skills"
    (Spanish, Skills) => "Habilidades"
    (SimplifiedChinese, Skills) => "技能"
    (TraditionalChinese, Skills) => "技能"
    (Japanese, Skills) => "スキル"
    (English, Description) =>
      "Playbooks the agent reads when a task matches. Skills apply to new chats."
    (Spanish, Description) =>
      "Guías que el agente lee cuando una tarea coincide. Las habilidades se aplican a las nuevas conversaciones."
    (SimplifiedChinese, Description) =>
      "智能体在任务匹配时读取的操作指南。技能对新建对话生效。"
    (TraditionalChinese, Description) =>
      "代理程式在任務匹配時讀取的操作指南。技能對新建對話生效。"
    (Japanese, Description) =>
      "タスクに応じてエージェントが参照する手順です。スキルは新しいチャットに適用されます。"
    (English, Search) => "Search skills…"
    (Spanish, Search) => "Buscar habilidades…"
    (SimplifiedChinese, Search) => "搜索技能…"
    (TraditionalChinese, Search) => "搜尋技能…"
    (Japanese, Search) => "スキルを検索…"
    (English, EmptyInstalled) => "No skills installed yet."
    (Spanish, EmptyInstalled) => "Aún no hay habilidades instaladas."
    (SimplifiedChinese, EmptyInstalled) => "尚未安装技能。"
    (TraditionalChinese, EmptyInstalled) => "尚未安裝技能。"
    (Japanese, EmptyInstalled) =>
      "インストール済みのスキルはありません。"
    (English, NoInstalledMatch) => "No installed skill matches the search."
    (Spanish, NoInstalledMatch) =>
      "Ninguna habilidad instalada coincide con la búsqueda."
    (SimplifiedChinese, NoInstalledMatch) =>
      "未找到匹配的已安装技能。"
    (TraditionalChinese, NoInstalledMatch) =>
      "未找到匹配的已安裝技能。"
    (Japanese, NoInstalledMatch) =>
      "一致するインストール済みスキルがありません。"
    (English, InstalledLabel) => "Installed"
    (Spanish, InstalledLabel) => "Instaladas"
    (SimplifiedChinese, InstalledLabel) => "已安装"
    (TraditionalChinese, InstalledLabel) => "已安裝"
    (Japanese, InstalledLabel) => "インストール済み"
    (English, LoadingCatalog) => "Loading the skill catalog…"
    (Spanish, LoadingCatalog) => "Cargando catálogo de habilidades…"
    (SimplifiedChinese, LoadingCatalog) => "正在加载技能目录…"
    (TraditionalChinese, LoadingCatalog) => "正在載入技能目錄…"
    (Japanese, LoadingCatalog) => "スキルカタログを読み込み中…"
    (English, EmptyRegistry) => "The registry lists no installable skills yet."
    (Spanish, EmptyRegistry) =>
      "El registro aún no contiene habilidades instalables."
    (SimplifiedChinese, EmptyRegistry) =>
      "注册表中尚无可安装的技能。"
    (TraditionalChinese, EmptyRegistry) =>
      "登錄檔中尚無可安裝的技能。"
    (Japanese, EmptyRegistry) =>
      "レジストリにはまだインストール可能なスキルがありません。"
    (English, NoRegistryMatch) => "No registry skill matches the search."
    (Spanish, NoRegistryMatch) =>
      "Ninguna habilidad del registro coincide con la búsqueda."
    (SimplifiedChinese, NoRegistryMatch) =>
      "注册表中未找到匹配的技能。"
    (TraditionalChinese, NoRegistryMatch) =>
      "登錄檔中未找到匹配的技能。"
    (Japanese, NoRegistryMatch) =>
      "レジストリに一致するスキルがありません。"
    (English, Registry) => "Mooncakes registry"
    (Spanish, Registry) => "Registro de Mooncakes"
    (SimplifiedChinese, Registry) => "Mooncakes 注册表"
    (TraditionalChinese, Registry) => "Mooncakes 登錄檔"
    (Japanese, Registry) => "Mooncakes レジストリ"
    (English, Refreshing) => "Refreshing…"
    (Spanish, Refreshing) => "Actualizando…"
    (SimplifiedChinese, Refreshing) => "正在刷新…"
    (TraditionalChinese, Refreshing) => "正在重新整理…"
    (Japanese, Refreshing) => "更新中…"
    (English, Refresh) => "Refresh"
    (Spanish, Refresh) => "Actualizar"
    (SimplifiedChinese, Refresh) => "刷新"
    (TraditionalChinese, Refresh) => "重新整理"
    (Japanese, Refresh) => "更新"
  }
}
