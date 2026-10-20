// Feature-owned UI messages; all built-in languages are exhaustive.

///|
priv enum UiMessage {
  Overview
  ShowOverview
  HideOverview
  EnvironmentTitle
  ChangesTitle
  ConnectorsTitle
  ThisComputer
  WorktreeTag
  Refresh
  BackgroundTasksTitle
  OpenJobs
  HideJobs
  OpenWorkflows
  HideWorkflows
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
    (English, ChangesTitle) => "Changes"
    (Spanish, ChangesTitle) => "Cambios"
    (SimplifiedChinese, ChangesTitle) => "更改"
    (TraditionalChinese, ChangesTitle) => "變更"
    (Japanese, ChangesTitle) => "変更"
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
    (English, BackgroundTasksTitle) => "Background tasks"
    (Spanish, BackgroundTasksTitle) => "Tareas en segundo plano"
    (SimplifiedChinese, BackgroundTasksTitle) => "后台任务"
    (TraditionalChinese, BackgroundTasksTitle) => "後臺任務"
    (Japanese, BackgroundTasksTitle) => "バックグラウンドタスク"
    (English, OpenJobs) => "Open Jobs"
    (Spanish, OpenJobs) => "Abrir Trabajos"
    (SimplifiedChinese, OpenJobs) => "打开后台任务"
    (TraditionalChinese, OpenJobs) => "開啟後臺任務"
    (Japanese, OpenJobs) => "バックグラウンドジョブを開く"
    (English, HideJobs) => "Hide Jobs"
    (Spanish, HideJobs) => "Ocultar Trabajos"
    (SimplifiedChinese, HideJobs) => "隐藏后台任务"
    (TraditionalChinese, HideJobs) => "隱藏後臺任務"
    (Japanese, HideJobs) => "バックグラウンドジョブを隠す"
    (English, HideWorkflows) => "Hide Workflows"
    (Spanish, HideWorkflows) => "Ocultar Flujos de trabajo"
    (SimplifiedChinese, HideWorkflows) => "隐藏工作流"
    (TraditionalChinese, HideWorkflows) => "隱藏工作流"
    (Japanese, HideWorkflows) => "ワークフローを隠す"
    (English, OpenWorkflows) => "Open Workflows"
    (Spanish, OpenWorkflows) => "Abrir Flujos de trabajo"
    (SimplifiedChinese, OpenWorkflows) => "打开工作流"
    (TraditionalChinese, OpenWorkflows) => "開啟工作流"
    (Japanese, OpenWorkflows) => "ワークフローを開く"
  }
}

///|
/// How many tasks are running, for the folded card.
fn running_text(locale : @i18n.Locale, count : Int32) -> String {
  match locale {
    English => "\{count} running"
    Spanish => "\{count} en ejecución"
    SimplifiedChinese => "\{count} 个运行中"
    TraditionalChinese => "\{count} 個執行中"
    Japanese => "\{count} 件実行中"
  }
}

///|
/// How many tasks have ended; `more` when older ones are left unlisted.
fn finished_text(locale : @i18n.Locale, count : Int32, more : Bool) -> String {
  let count = if more { "\{count}+" } else { count.to_string() }
  match locale {
    English => "\{count} finished"
    Spanish => "\{count} finalizadas"
    SimplifiedChinese => "\{count} 个已完成"
    TraditionalChinese => "\{count} 個已完成"
    Japanese => "\{count} 件完了"
  }
}
