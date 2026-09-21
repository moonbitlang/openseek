// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  GithubHint
  BrowseLabel
  BrowseHint
  SearchLabel
  SearchHint
  FilesLabel
  FilesHint
  ReviewLabel
  ReviewHint
  WorkflowsLabel
  WorkflowsHint
  JobsLabel
  JobsHint
  CloseLabel
  CloseAllTabs
  NewTab
  RestorePanel
  ExpandPanel
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, GithubHint) => "Browse pull requests and issues"
    (SimplifiedChinese, GithubHint) => "浏览拉取请求和议题"
    (TraditionalChinese, GithubHint) => "瀏覽提取要求和議題"
    (Japanese, GithubHint) => "プルリクエストと Issue を表示"
    (Spanish, GithubHint) =>
      "Explorar solicitudes de incorporación e incidencias"
    (English, BrowseLabel) => "Browse"
    (Spanish, BrowseLabel) => "Navegar"
    (SimplifiedChinese, BrowseLabel) => "浏览"
    (TraditionalChinese, BrowseLabel) => "瀏覽"
    (Japanese, BrowseLabel) => "ブラウザー"
    (English, BrowseHint) => "Open a page in a tab"
    (Spanish, BrowseHint) => "Abrir una página en una pestaña"
    (SimplifiedChinese, BrowseHint) => "在标签页中打开网页"
    (TraditionalChinese, BrowseHint) => "在標籤頁中開啟網頁"
    (Japanese, BrowseHint) => "タブでウェブページを開く"
    (English, SearchLabel) => "Search"
    (Spanish, SearchLabel) => "Buscar"
    (SimplifiedChinese, SearchLabel) => "搜索"
    (TraditionalChinese, SearchLabel) => "搜尋"
    (Japanese, SearchLabel) => "検索"
    (English, SearchHint) => "Search text across the workspace"
    (Spanish, SearchHint) => "Buscar texto en el espacio de trabajo"
    (SimplifiedChinese, SearchHint) => "在工作区中搜索文本"
    (TraditionalChinese, SearchHint) => "在工作區中搜尋文字"
    (Japanese, SearchHint) => "ワークスペース内のテキストを検索"
    (English, FilesLabel) => "Files"
    (Spanish, FilesLabel) => "Archivos"
    (SimplifiedChinese, FilesLabel) => "文件"
    (TraditionalChinese, FilesLabel) => "檔案"
    (Japanese, FilesLabel) => "ファイル"
    (English, FilesHint) => "Open a file from the workspace"
    (Spanish, FilesHint) => "Abrir un archivo del espacio de trabajo"
    (SimplifiedChinese, FilesHint) => "打开工作区中的文件"
    (TraditionalChinese, FilesHint) => "開啟工作區中的檔案"
    (Japanese, FilesHint) => "ワークスペースのファイルを開く"
    (English, ReviewLabel) => "Review"
    (Spanish, ReviewLabel) => "Revisar"
    (SimplifiedChinese, ReviewLabel) => "审阅"
    (TraditionalChinese, ReviewLabel) => "審閱"
    (Japanese, ReviewLabel) => "レビュー"
    (English, ReviewHint) => "Review changed files and diffs"
    (Spanish, ReviewHint) => "Revisar archivos modificados y diferencias"
    (SimplifiedChinese, ReviewHint) => "审阅文件更改和差异"
    (TraditionalChinese, ReviewHint) => "審閱檔案更改和差異"
    (Japanese, ReviewHint) => "ファイルの変更と差分をレビュー"
    (English, WorkflowsLabel) => "Workflows"
    (Spanish, WorkflowsLabel) => "Flujos de trabajo"
    (SimplifiedChinese, WorkflowsLabel) => "工作流"
    (TraditionalChinese, WorkflowsLabel) => "工作流"
    (Japanese, WorkflowsLabel) => "ワークフロー"
    (English, WorkflowsHint) => "Subagents this conversation delegated to"
    (Spanish, WorkflowsHint) =>
      "Subagentes en los que ha delegado esta conversación"
    (SimplifiedChinese, WorkflowsHint) => "此对话委派的子智能体"
    (TraditionalChinese, WorkflowsHint) => "此對話委派的子代理程式"
    (Japanese, WorkflowsHint) => "このチャットのサブエージェント"
    (English, JobsLabel) => "Jobs"
    (Spanish, JobsLabel) => "Trabajos"
    (SimplifiedChinese, JobsLabel) => "后台任务"
    (TraditionalChinese, JobsLabel) => "後臺任務"
    (Japanese, JobsLabel) => "バックグラウンドジョブ"
    (English, JobsHint) => "Follow background commands and their logs"
    (Spanish, JobsHint) => "Seguir comandos en segundo plano y sus registros"
    (SimplifiedChinese, JobsHint) => "查看后台命令及其日志"
    (TraditionalChinese, JobsHint) => "檢視後臺命令及其日誌"
    (Japanese, JobsHint) =>
      "バックグラウンドコマンドとログを表示"
    (English, CloseLabel) => "Close"
    (Spanish, CloseLabel) => "Cerrar"
    (SimplifiedChinese, CloseLabel) => "关闭"
    (TraditionalChinese, CloseLabel) => "關閉"
    (Japanese, CloseLabel) => "閉じる"
    (English, CloseAllTabs) => "Close all tabs"
    (Spanish, CloseAllTabs) => "Cerrar todas las pestañas"
    (SimplifiedChinese, CloseAllTabs) => "关闭所有标签页"
    (TraditionalChinese, CloseAllTabs) => "關閉所有標籤頁"
    (Japanese, CloseAllTabs) => "すべてのタブを閉じる"
    (English, NewTab) => "New tab"
    (Spanish, NewTab) => "Nueva pestaña"
    (SimplifiedChinese, NewTab) => "新建标签页"
    (TraditionalChinese, NewTab) => "新建標籤頁"
    (Japanese, NewTab) => "新しいタブ"
    (English, RestorePanel) => "Restore panel"
    (Spanish, RestorePanel) => "Restaurar panel"
    (SimplifiedChinese, RestorePanel) => "还原面板"
    (TraditionalChinese, RestorePanel) => "還原面板"
    (Japanese, RestorePanel) => "パネルを元に戻す"
    (English, ExpandPanel) => "Expand panel"
    (Spanish, ExpandPanel) => "Ampliar panel"
    (SimplifiedChinese, ExpandPanel) => "展开面板"
    (TraditionalChinese, ExpandPanel) => "展開面板"
    (Japanese, ExpandPanel) => "パネルを展開"
  }
}
