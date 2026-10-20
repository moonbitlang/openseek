// Feature-owned UI messages; all built-in languages are exhaustive.

///|
priv enum UiMessage {
  Overview
  ShowOverview
  HideOverview
  EnvironmentTitle
  ConnectorsTitle
  ThisComputer
  WorktreeTag
  Refresh
}

///|
fn text(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, Overview) => "Overview"
    (Spanish, Overview) => "Resumen"
    (SimplifiedChinese, Overview) => "概览"
    (TraditionalChinese, Overview) => "概覽"
    (Japanese, Overview) => "概要"
    (English, ShowOverview) => "Show overview"
    (Spanish, ShowOverview) => "Mostrar resumen"
    (SimplifiedChinese, ShowOverview) => "显示概览"
    (TraditionalChinese, ShowOverview) => "顯示概覽"
    (Japanese, ShowOverview) => "概要を表示"
    (English, HideOverview) => "Hide overview"
    (Spanish, HideOverview) => "Ocultar resumen"
    (SimplifiedChinese, HideOverview) => "隐藏概览"
    (TraditionalChinese, HideOverview) => "隱藏概覽"
    (Japanese, HideOverview) => "概要を隠す"
    (English, EnvironmentTitle) => "Environment"
    (Spanish, EnvironmentTitle) => "Entorno"
    (SimplifiedChinese, EnvironmentTitle) => "环境"
    (TraditionalChinese, EnvironmentTitle) => "環境"
    (Japanese, EnvironmentTitle) => "環境"
    (English, ConnectorsTitle) => "Connectors"
    (Spanish, ConnectorsTitle) => "Conectores"
    (SimplifiedChinese, ConnectorsTitle) => "连接器"
    (TraditionalChinese, ConnectorsTitle) => "連接器"
    (Japanese, ConnectorsTitle) => "コネクタ"
    (English, ThisComputer) => "This computer"
    (Spanish, ThisComputer) => "Este equipo"
    (SimplifiedChinese, ThisComputer) => "本机"
    (TraditionalChinese, ThisComputer) => "本機"
    (Japanese, ThisComputer) => "このコンピューター"
    (English, WorktreeTag) => "Worktree"
    (Spanish, WorktreeTag) => "Worktree"
    (SimplifiedChinese, WorktreeTag) => "工作树"
    (TraditionalChinese, WorktreeTag) => "工作樹"
    (Japanese, WorktreeTag) => "ワークツリー"
    (English, Refresh) => "Refresh"
    (Spanish, Refresh) => "Actualizar"
    (SimplifiedChinese, Refresh) => "刷新"
    (TraditionalChinese, Refresh) => "重新整理"
    (Japanese, Refresh) => "更新"
  }
}
