// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  UnresolvedGithubConversations
  AddToContext
  PartlyInContext
  InContext
  RemoveHunkContext
  AddRemainingChanges
  RemoveIncludedChanges
  NoCommitContent
  WaitingPlacement
  MissingCheckout
  NoConversation
  ExplorerViews
  WorkspaceFiles
  FilesLabel
  ChangedFilesHint
  ChangesLabel
  SearchWorkspace
  SearchLabel
  ResizeGraph
  GraphLabel
  RefreshGraph
  RepositoryLabel
  NoCommits
  LoadingHistory
  RetryLabel
  GitUnavailable
  EmptyBranch
  LoadingLabel
  LoadMore
  CommitHistory
  LoadingChangedFiles
  NoWorkspaceChanges
  NoFilterMatches
  SubmoduleDiff
  SymlinkDiff
  PathOutsideWorkspace
  EmptyWorkspace
  LoadingChanges
  NoChangedFiles
  NoReviewableFiles
  ChangedFiles
  ViewDiffPrefix
  OpenDiffPrefix
  MarkUnreviewed
  MarkReviewed
  ReviewedPrefix
  HideFileTree
  ShowFileTree
  WorkspaceLabel
  DiagramLabel
  SourceLabel
  MoonModuleView
  DependencyGraph
  LineLabel
  TokenLabel
  TreeLabel
  ShowFile
  FileView
  FileLabel
  ReviewMode
  ComparisonAlgorithm
  AvailableDiff
  AvailableTokenTree
  IncludeComments
  IgnoreCommentChanges
  IgnoreComments
  CommentsIgnored
  CommentsIncluded
  IncludeTests
  IgnoreTestBlocks
  IgnoreTests
  TestsIgnored
  TestsIncluded
  PreviousChangeShortcut
  PreviousChange
  NextChangeShortcut
  NextChange
  DiffNavigation
  FileReviewed
  MarkHunkUnviewed
  MarkHunkViewed
  HunkViewed
  UnmarkHunkViewed
  MarkHunkViewedLabel
  MarkViewed
  DiffLayout
  SideBySideHint
  SplitDiffLayout
  SplitLabel
  UnifiedDiffHint
  UnifiedDiffLayout
  UnifiedLabel
  EmptyFolder
  CannotLoadFolder
  RefreshingLabel
  ReturnReviewQueue
  MarkChangedReviewed
  MarkFileUnreviewed
  MarkFileReviewed
  ViewFile
  ReturnSourcePreview
  ViewFullDiff
  FullDiffHint
  DeletedBaseline
  DeletedBaselineHint
  WorkingUnavailable
  WorkingUnavailableHint
  DiffUnavailable
  NotTextPreview
  DeletedNoBaseline
  NoBaseline
  RenderedNoGutter
  MarkdownGutterHint
  NewMarkdownHint
  DiffBaseline
  QuickDiffBaseline
  NewNoBaseline
  NewBaselineHint
  BinaryBaseline
  LargeBaseline
  BaselineFailedPrefix
  FullDiff
  FilteringCommit
  FilteringWorkingTree
  FilterFilesPath
  FilterChangedPath
  ClearFilters
  ClearLabel
  FileTypes
  NoFileTypes
  FilterExtensionPrefix
  AllFileTypes
  NoChangedTypes
  WholeFile
  LexicalFallback
  SectioningFallback
  SectionLexicalFallback
  SectionDiffFallback
  NoStructuralText
  NoTokenChanges
  NoStructuralToken
  NoDeclarationChanges
  ReorderedDeclarations
  NoSectionChanges
  InvalidSemanticResult
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, UnresolvedGithubConversations) =>
      "Unresolved GitHub conversations"
    (SimplifiedChinese, UnresolvedGithubConversations) =>
      "未解决的 GitHub 讨论"
    (TraditionalChinese, UnresolvedGithubConversations) =>
      "未解決的 GitHub 討論"
    (Japanese, UnresolvedGithubConversations) =>
      "未解決の GitHub ディスカッション"
    (Spanish, UnresolvedGithubConversations) =>
      "Discusiones de GitHub sin resolver"
    (English, AddToContext) => "Add to context"
    (Spanish, AddToContext) => "Añadir al contexto"
    (SimplifiedChinese, AddToContext) => "添加到上下文"
    (TraditionalChinese, AddToContext) => "新增到上下文"
    (Japanese, AddToContext) => "コンテキストに追加"
    (English, PartlyInContext) => "Partly in context"
    (Spanish, PartlyInContext) => "Parcialmente en el contexto"
    (SimplifiedChinese, PartlyInContext) => "部分已在上下文中"
    (TraditionalChinese, PartlyInContext) => "部分已在上下文中"
    (Japanese, PartlyInContext) =>
      "一部がコンテキストに含まれています"
    (English, InContext) => "In context"
    (Spanish, InContext) => "En el contexto"
    (SimplifiedChinese, InContext) => "已在上下文中"
    (TraditionalChinese, InContext) => "已在上下文中"
    (Japanese, InContext) => "コンテキストに含まれています"
    (English, RemoveHunkContext) => "Remove this hunk from context"
    (Spanish, RemoveHunkContext) => "Quitar este bloque del contexto"
    (SimplifiedChinese, RemoveHunkContext) => "从上下文移除此差异块"
    (TraditionalChinese, RemoveHunkContext) => "從上下文移除此差異塊"
    (Japanese, RemoveHunkContext) =>
      "この差分ブロックをコンテキストから削除"
    (English, AddRemainingChanges) => "Add remaining changes"
    (Spanish, AddRemainingChanges) => "Añadir cambios restantes"
    (SimplifiedChinese, AddRemainingChanges) => "添加其余更改"
    (TraditionalChinese, AddRemainingChanges) => "新增其餘更改"
    (Japanese, AddRemainingChanges) => "残りの変更を追加"
    (English, RemoveIncludedChanges) => "Remove included changes"
    (Spanish, RemoveIncludedChanges) => "Quitar cambios incluidos"
    (SimplifiedChinese, RemoveIncludedChanges) => "移除已包含的更改"
    (TraditionalChinese, RemoveIncludedChanges) => "移除已包含的更改"
    (Japanese, RemoveIncludedChanges) => "含まれている変更を削除"
    (English, NoCommitContent) =>
      "No file content exists on either side of this commit."
    (Spanish, NoCommitContent) =>
      "No existe contenido del archivo en ninguno de los lados de este commit."
    (SimplifiedChinese, NoCommitContent) =>
      "此提交的两侧均无文件内容。"
    (TraditionalChinese, NoCommitContent) =>
      "此提交的兩側均無檔案內容。"
    (Japanese, NoCommitContent) =>
      "このコミットの両側にファイルの内容がありません。"
    (English, WaitingPlacement) => "Waiting for workspace placement…"
    (Spanish, WaitingPlacement) =>
      "Esperando la ubicación del espacio de trabajo…"
    (SimplifiedChinese, WaitingPlacement) => "正在等待工作区就绪…"
    (TraditionalChinese, WaitingPlacement) => "正在等待工作區就緒…"
    (Japanese, WaitingPlacement) =>
      "ワークスペースの準備を待機中…"
    (English, MissingCheckout) => "Worktree checkout is missing."
    (Spanish, MissingCheckout) => "Falta la copia de trabajo del worktree."
    (SimplifiedChinese, MissingCheckout) => "工作树检出目录缺失。"
    (TraditionalChinese, MissingCheckout) => "工作樹檢出目錄缺失。"
    (Japanese, MissingCheckout) =>
      "ワークツリーのチェックアウトがありません。"
    (English, NoConversation) => "No conversation selected."
    (Spanish, NoConversation) => "No hay ninguna conversación seleccionada."
    (SimplifiedChinese, NoConversation) => "未选择对话。"
    (TraditionalChinese, NoConversation) => "未選擇對話。"
    (Japanese, NoConversation) =>
      "チャットが選択されていません。"
    (English, ExplorerViews) => "Explorer views"
    (Spanish, ExplorerViews) => "Vistas del explorador"
    (SimplifiedChinese, ExplorerViews) => "资源管理器视图"
    (TraditionalChinese, ExplorerViews) => "資源管理器檢視"
    (Japanese, ExplorerViews) => "エクスプローラービュー"
    (English, WorkspaceFiles) => "Workspace files"
    (Spanish, WorkspaceFiles) => "Archivos del espacio de trabajo"
    (SimplifiedChinese, WorkspaceFiles) => "工作区文件"
    (TraditionalChinese, WorkspaceFiles) => "工作區檔案"
    (Japanese, WorkspaceFiles) => "ワークスペースのファイル"
    (English, FilesLabel) => "Files"
    (Spanish, FilesLabel) => "Archivos"
    (SimplifiedChinese, FilesLabel) => "文件"
    (TraditionalChinese, FilesLabel) => "檔案"
    (Japanese, FilesLabel) => "ファイル"
    (English, ChangedFilesHint) => "Changed files (click again to refresh)"
    (Spanish, ChangedFilesHint) =>
      "Archivos modificados (haz clic de nuevo para actualizar)"
    (SimplifiedChinese, ChangedFilesHint) =>
      "更改的文件（再次点击刷新）"
    (TraditionalChinese, ChangedFilesHint) =>
      "更改的檔案（再次點選重新整理）"
    (Japanese, ChangedFilesHint) =>
      "変更したファイル（再クリックで更新）"
    (English, ChangesLabel) => "Changes"
    (Spanish, ChangesLabel) => "Cambios"
    (SimplifiedChinese, ChangesLabel) => "更改"
    (TraditionalChinese, ChangesLabel) => "更改"
    (Japanese, ChangesLabel) => "変更"
    (English, SearchWorkspace) => "Search across the workspace"
    (Spanish, SearchWorkspace) => "Buscar en el espacio de trabajo"
    (SimplifiedChinese, SearchWorkspace) => "搜索整个工作区"
    (TraditionalChinese, SearchWorkspace) => "搜尋整個工作區"
    (Japanese, SearchWorkspace) => "ワークスペース全体を検索"
    (English, SearchLabel) => "Search"
    (Spanish, SearchLabel) => "Buscar"
    (SimplifiedChinese, SearchLabel) => "搜索"
    (TraditionalChinese, SearchLabel) => "搜尋"
    (Japanese, SearchLabel) => "検索"
    (English, ResizeGraph) => "Resize Changes and Git Graph"
    (Spanish, ResizeGraph) => "Ajustar tamaño de Cambios y Grafo de Git"
    (SimplifiedChinese, ResizeGraph) => "调整更改列表和 Git 图的大小"
    (TraditionalChinese, ResizeGraph) =>
      "調整更改列表和 Git 圖的大小"
    (Japanese, ResizeGraph) =>
      "変更一覧と Git グラフのサイズを変更"
    (English, GraphLabel) => "Graph"
    (Spanish, GraphLabel) => "Grafo"
    (SimplifiedChinese, GraphLabel) => "提交图"
    (TraditionalChinese, GraphLabel) => "提交圖"
    (Japanese, GraphLabel) => "コミットグラフ"
    (English, RefreshGraph) => "Refresh Git Graph"
    (Spanish, RefreshGraph) => "Actualizar grafo de Git"
    (SimplifiedChinese, RefreshGraph) => "刷新 Git 图"
    (TraditionalChinese, RefreshGraph) => "重新整理 Git 圖"
    (Japanese, RefreshGraph) => "Git グラフを更新"
    (English, RepositoryLabel) => "Repository"
    (Spanish, RepositoryLabel) => "Repositorio"
    (SimplifiedChinese, RepositoryLabel) => "仓库"
    (TraditionalChinese, RepositoryLabel) => "倉庫"
    (Japanese, RepositoryLabel) => "リポジトリ"
    (English, NoCommits) => "No commits"
    (Spanish, NoCommits) => "No hay commits"
    (SimplifiedChinese, NoCommits) => "没有提交"
    (TraditionalChinese, NoCommits) => "沒有提交"
    (Japanese, NoCommits) => "コミットなし"
    (English, LoadingHistory) => "Loading Git history…"
    (Spanish, LoadingHistory) => "Cargando historial de Git…"
    (SimplifiedChinese, LoadingHistory) => "正在加载 Git 历史…"
    (TraditionalChinese, LoadingHistory) => "正在載入 Git 歷史…"
    (Japanese, LoadingHistory) => "Git 履歴を読み込み中…"
    (English, RetryLabel) => "Retry"
    (Spanish, RetryLabel) => "Reintentar"
    (SimplifiedChinese, RetryLabel) => "重试"
    (TraditionalChinese, RetryLabel) => "重試"
    (Japanese, RetryLabel) => "再試行"
    (English, GitUnavailable) =>
      "Git is unavailable or this workspace is not a Git repository."
    (Spanish, GitUnavailable) =>
      "Git no está disponible o este espacio de trabajo no es un repositorio de Git."
    (SimplifiedChinese, GitUnavailable) =>
      "Git 不可用，或此工作区不是 Git 仓库。"
    (TraditionalChinese, GitUnavailable) =>
      "Git 不可用，或此工作區不是 Git 倉庫。"
    (Japanese, GitUnavailable) =>
      "Git が利用できないか、このワークスペースは Git リポジトリではありません。"
    (English, EmptyBranch) => "This branch has no commits."
    (Spanish, EmptyBranch) => "Esta rama no tiene commits."
    (SimplifiedChinese, EmptyBranch) => "此分支没有提交。"
    (TraditionalChinese, EmptyBranch) => "此分支沒有提交。"
    (Japanese, EmptyBranch) =>
      "このブランチにはコミットがありません。"
    (English, LoadingLabel) => "Loading…"
    (Spanish, LoadingLabel) => "Cargando…"
    (SimplifiedChinese, LoadingLabel) => "正在加载…"
    (TraditionalChinese, LoadingLabel) => "正在載入…"
    (Japanese, LoadingLabel) => "読み込み中…"
    (English, LoadMore) => "Load more"
    (Spanish, LoadMore) => "Cargar más"
    (SimplifiedChinese, LoadMore) => "加载更多"
    (TraditionalChinese, LoadMore) => "載入更多"
    (Japanese, LoadMore) => "さらに読み込む"
    (English, CommitHistory) => "Git commit history"
    (Spanish, CommitHistory) => "Historial de commits de Git"
    (SimplifiedChinese, CommitHistory) => "Git 提交历史"
    (TraditionalChinese, CommitHistory) => "Git 提交歷史"
    (Japanese, CommitHistory) => "Git コミット履歴"
    (English, LoadingChangedFiles) => "Loading changed files…"
    (Spanish, LoadingChangedFiles) => "Cargando archivos modificados…"
    (SimplifiedChinese, LoadingChangedFiles) => "正在加载更改的文件…"
    (TraditionalChinese, LoadingChangedFiles) =>
      "正在載入更改的檔案…"
    (Japanese, LoadingChangedFiles) =>
      "変更したファイルを読み込み中…"
    (English, NoWorkspaceChanges) => "No changes in this workspace."
    (Spanish, NoWorkspaceChanges) =>
      "No hay cambios en este espacio de trabajo."
    (SimplifiedChinese, NoWorkspaceChanges) => "此工作区没有更改。"
    (TraditionalChinese, NoWorkspaceChanges) => "此工作區沒有更改。"
    (Japanese, NoWorkspaceChanges) =>
      "このワークスペースには変更がありません。"
    (English, NoFilterMatches) => "No files match these filters."
    (Spanish, NoFilterMatches) => "Ningún archivo coincide con estos filtros."
    (SimplifiedChinese, NoFilterMatches) =>
      "没有符合筛选条件的文件。"
    (TraditionalChinese, NoFilterMatches) =>
      "沒有符合篩選條件的檔案。"
    (Japanese, NoFilterMatches) =>
      "フィルターに一致するファイルがありません。"
    (English, SubmoduleDiff) => "Git submodule cannot be shown as a text diff"
    (Spanish, SubmoduleDiff) =>
      "El submódulo de Git no se puede mostrar como diferencias de texto"
    (SimplifiedChinese, SubmoduleDiff) =>
      "Git 子模块无法显示为文本差异"
    (TraditionalChinese, SubmoduleDiff) =>
      "Git 子模組無法顯示為文字差異"
    (Japanese, SubmoduleDiff) =>
      "Git サブモジュールはテキスト差分として表示できません"
    (English, SymlinkDiff) => "Git symlink cannot be shown as a text diff"
    (Spanish, SymlinkDiff) =>
      "El enlace simbólico de Git no se puede mostrar como diferencias de texto"
    (SimplifiedChinese, SymlinkDiff) =>
      "Git 符号链接无法显示为文本差异"
    (TraditionalChinese, SymlinkDiff) =>
      "Git 符號連結無法顯示為文字差異"
    (Japanese, SymlinkDiff) =>
      "Git シンボリックリンクはテキスト差分として表示できません"
    (English, PathOutsideWorkspace) => "Original path is outside this workspace"
    (Spanish, PathOutsideWorkspace) =>
      "La ruta original está fuera de este espacio de trabajo"
    (SimplifiedChinese, PathOutsideWorkspace) =>
      "原始路径位于此工作区之外"
    (TraditionalChinese, PathOutsideWorkspace) =>
      "原始路徑位於此工作區之外"
    (Japanese, PathOutsideWorkspace) =>
      "元のパスはこのワークスペースの外にあります"
    (English, EmptyWorkspace) => "This workspace is empty."
    (Spanish, EmptyWorkspace) => "Este espacio de trabajo está vacío."
    (SimplifiedChinese, EmptyWorkspace) => "此工作区为空。"
    (TraditionalChinese, EmptyWorkspace) => "此工作區為空。"
    (Japanese, EmptyWorkspace) => "このワークスペースは空です。"
    (English, LoadingChanges) => "Loading changes…"
    (Spanish, LoadingChanges) => "Cargando cambios…"
    (SimplifiedChinese, LoadingChanges) => "正在加载更改…"
    (TraditionalChinese, LoadingChanges) => "正在載入更改…"
    (Japanese, LoadingChanges) => "変更を読み込み中…"
    (English, NoChangedFiles) => "No changed files."
    (Spanish, NoChangedFiles) => "No hay archivos modificados."
    (SimplifiedChinese, NoChangedFiles) => "没有更改的文件。"
    (TraditionalChinese, NoChangedFiles) => "沒有更改的檔案。"
    (Japanese, NoChangedFiles) =>
      "変更したファイルはありません。"
    (English, NoReviewableFiles) => "No reviewable text files"
    (Spanish, NoReviewableFiles) => "No hay archivos de texto para revisar"
    (SimplifiedChinese, NoReviewableFiles) => "没有可审阅的文本文件"
    (TraditionalChinese, NoReviewableFiles) => "沒有可審閱的文字檔案"
    (Japanese, NoReviewableFiles) =>
      "レビュー可能なテキストファイルがありません"
    (English, ChangedFiles) => "Changed files"
    (Spanish, ChangedFiles) => "Archivos modificados"
    (SimplifiedChinese, ChangedFiles) => "更改的文件"
    (TraditionalChinese, ChangedFiles) => "更改的檔案"
    (Japanese, ChangedFiles) => "変更したファイル"
    (English, ViewDiffPrefix) => "View diff: "
    (Spanish, ViewDiffPrefix) => "Ver diferencias: "
    (SimplifiedChinese, ViewDiffPrefix) => "查看差异："
    (TraditionalChinese, ViewDiffPrefix) => "檢視差異："
    (Japanese, ViewDiffPrefix) => "差分を表示："
    (English, OpenDiffPrefix) => "Open diff — "
    (Spanish, OpenDiffPrefix) => "Abrir diferencias — "
    (SimplifiedChinese, OpenDiffPrefix) => "打开差异 — "
    (TraditionalChinese, OpenDiffPrefix) => "開啟差異 — "
    (Japanese, OpenDiffPrefix) => "差分を開く — "
    (English, MarkUnreviewed) => "Mark unreviewed"
    (Spanish, MarkUnreviewed) => "Marcar como no revisado"
    (SimplifiedChinese, MarkUnreviewed) => "标为未审阅"
    (TraditionalChinese, MarkUnreviewed) => "標為未審閱"
    (Japanese, MarkUnreviewed) => "未レビューにする"
    (English, MarkReviewed) => "Mark reviewed"
    (Spanish, MarkReviewed) => "Marcar como revisado"
    (SimplifiedChinese, MarkReviewed) => "标为已审阅"
    (TraditionalChinese, MarkReviewed) => "標為已審閱"
    (Japanese, MarkReviewed) => "レビュー済みにする"
    (English, ReviewedPrefix) => "Reviewed: "
    (Spanish, ReviewedPrefix) => "Revisado: "
    (SimplifiedChinese, ReviewedPrefix) => "已审阅："
    (TraditionalChinese, ReviewedPrefix) => "已審閱："
    (Japanese, ReviewedPrefix) => "レビュー済み："
    (English, HideFileTree) => "Hide file tree"
    (Spanish, HideFileTree) => "Ocultar árbol de archivos"
    (SimplifiedChinese, HideFileTree) => "隐藏文件树"
    (TraditionalChinese, HideFileTree) => "隱藏檔案樹"
    (Japanese, HideFileTree) => "ファイルツリーを非表示"
    (English, ShowFileTree) => "Show file tree"
    (Spanish, ShowFileTree) => "Mostrar árbol de archivos"
    (SimplifiedChinese, ShowFileTree) => "显示文件树"
    (TraditionalChinese, ShowFileTree) => "顯示檔案樹"
    (Japanese, ShowFileTree) => "ファイルツリーを表示"
    (English, WorkspaceLabel) => "Workspace"
    (Spanish, WorkspaceLabel) => "Espacio de trabajo"
    (SimplifiedChinese, WorkspaceLabel) => "工作区"
    (TraditionalChinese, WorkspaceLabel) => "工作區"
    (Japanese, WorkspaceLabel) => "ワークスペース"
    (English, DiagramLabel) => "Diagram"
    (Spanish, DiagramLabel) => "Diagrama"
    (SimplifiedChinese, DiagramLabel) => "图表"
    (TraditionalChinese, DiagramLabel) => "圖表"
    (Japanese, DiagramLabel) => "図"
    (English, SourceLabel) => "Source"
    (Spanish, SourceLabel) => "Código fuente"
    (SimplifiedChinese, SourceLabel) => "源码"
    (TraditionalChinese, SourceLabel) => "原始碼"
    (Japanese, SourceLabel) => "ソース"
    (English, MoonModuleView) => "Moon module view"
    (Spanish, MoonModuleView) => "Vista de módulo MoonBit"
    (SimplifiedChinese, MoonModuleView) => "Moon 模块视图"
    (TraditionalChinese, MoonModuleView) => "Moon 模組檢視"
    (Japanese, MoonModuleView) => "Moon モジュールビュー"
    (English, DependencyGraph) => "Dependency graph"
    (Spanish, DependencyGraph) => "Grafo de dependencias"
    (SimplifiedChinese, DependencyGraph) => "依赖图"
    (TraditionalChinese, DependencyGraph) => "依賴圖"
    (Japanese, DependencyGraph) => "依存関係グラフ"
    (English, LineLabel) => "Line"
    (Spanish, LineLabel) => "Línea"
    (SimplifiedChinese, LineLabel) => "行"
    (TraditionalChinese, LineLabel) => "行"
    (Japanese, LineLabel) => "行"
    (English, TokenLabel) => "Token"
    (Spanish, TokenLabel) => "Token"
    (SimplifiedChinese, TokenLabel) => "词元"
    (TraditionalChinese, TokenLabel) => "詞元"
    (Japanese, TokenLabel) => "トークン"
    (English, TreeLabel) => "Tree"
    (Spanish, TreeLabel) => "Árbol"
    (SimplifiedChinese, TreeLabel) => "语法树"
    (TraditionalChinese, TreeLabel) => "語法樹"
    (Japanese, TreeLabel) => "構文木"
    (English, ShowFile) => "Show file"
    (Spanish, ShowFile) => "Mostrar archivo"
    (SimplifiedChinese, ShowFile) => "显示文件"
    (TraditionalChinese, ShowFile) => "顯示檔案"
    (Japanese, ShowFile) => "ファイルを表示"
    (English, FileView) => "File view"
    (Spanish, FileView) => "Vista de archivo"
    (SimplifiedChinese, FileView) => "文件视图"
    (TraditionalChinese, FileView) => "檔案檢視"
    (Japanese, FileView) => "ファイルビュー"
    (English, FileLabel) => "File"
    (Spanish, FileLabel) => "Archivo"
    (SimplifiedChinese, FileLabel) => "文件"
    (TraditionalChinese, FileLabel) => "檔案"
    (Japanese, FileLabel) => "ファイル"
    (English, ReviewMode) => "Review mode"
    (Spanish, ReviewMode) => "Modo de revisión"
    (SimplifiedChinese, ReviewMode) => "审阅模式"
    (TraditionalChinese, ReviewMode) => "審閱模式"
    (Japanese, ReviewMode) => "レビューモード"
    (English, ComparisonAlgorithm) => "Comparison algorithm"
    (Spanish, ComparisonAlgorithm) => "Algoritmo de comparación"
    (SimplifiedChinese, ComparisonAlgorithm) => "比较算法"
    (TraditionalChinese, ComparisonAlgorithm) => "比較演算法"
    (Japanese, ComparisonAlgorithm) => "比較アルゴリズム"
    (English, AvailableDiff) => "Available in diff view"
    (Spanish, AvailableDiff) => "Disponible en la vista de diferencias"
    (SimplifiedChinese, AvailableDiff) => "在差异视图中可用"
    (TraditionalChinese, AvailableDiff) => "在差異檢視中可用"
    (Japanese, AvailableDiff) => "差分ビューで利用可能"
    (English, AvailableTokenTree) => "Available in Token and Tree diff"
    (Spanish, AvailableTokenTree) =>
      "Disponible en diferencias por tokens y árbol"
    (SimplifiedChinese, AvailableTokenTree) =>
      "在词元和语法树差异中可用"
    (TraditionalChinese, AvailableTokenTree) =>
      "在詞元和語法樹差異中可用"
    (Japanese, AvailableTokenTree) =>
      "トークン差分と構文木差分で利用可能"
    (English, IncludeComments) => "Include comments in the comparison"
    (Spanish, IncludeComments) => "Incluir comentarios en la comparación"
    (SimplifiedChinese, IncludeComments) => "比较时包含注释"
    (TraditionalChinese, IncludeComments) => "比較時包含註釋"
    (Japanese, IncludeComments) => "比較にコメントを含める"
    (English, IgnoreCommentChanges) => "Ignore comment-only changes"
    (Spanish, IgnoreCommentChanges) => "Ignorar cambios solo en comentarios"
    (SimplifiedChinese, IgnoreCommentChanges) =>
      "忽略仅涉及注释的更改"
    (TraditionalChinese, IgnoreCommentChanges) =>
      "忽略僅涉及註釋的更改"
    (Japanese, IgnoreCommentChanges) => "コメントのみの変更を無視"
    (English, IgnoreComments) => "Ignore comments"
    (Spanish, IgnoreComments) => "Ignorar comentarios"
    (SimplifiedChinese, IgnoreComments) => "忽略注释"
    (TraditionalChinese, IgnoreComments) => "忽略註釋"
    (Japanese, IgnoreComments) => "コメントを無視"
    (English, CommentsIgnored) => "Comments: ignored"
    (Spanish, CommentsIgnored) => "Comentarios: ignorados"
    (SimplifiedChinese, CommentsIgnored) => "注释：已忽略"
    (TraditionalChinese, CommentsIgnored) => "註釋：已忽略"
    (Japanese, CommentsIgnored) => "コメント：無視"
    (English, CommentsIncluded) => "Comments: included"
    (Spanish, CommentsIncluded) => "Comentarios: incluidos"
    (SimplifiedChinese, CommentsIncluded) => "注释：已包含"
    (TraditionalChinese, CommentsIncluded) => "註釋：已包含"
    (Japanese, CommentsIncluded) => "コメント：含む"
    (English, IncludeTests) => "Include tests in the comparison"
    (Spanish, IncludeTests) => "Incluir pruebas en la comparación"
    (SimplifiedChinese, IncludeTests) => "比较时包含测试"
    (TraditionalChinese, IncludeTests) => "比較時包含測試"
    (Japanese, IncludeTests) => "比較にテストを含める"
    (English, IgnoreTestBlocks) => "Ignore MoonBit test blocks"
    (Spanish, IgnoreTestBlocks) => "Ignorar bloques de prueba de MoonBit"
    (SimplifiedChinese, IgnoreTestBlocks) => "忽略 MoonBit 测试块"
    (TraditionalChinese, IgnoreTestBlocks) => "忽略 MoonBit 測試塊"
    (Japanese, IgnoreTestBlocks) => "MoonBit テストブロックを無視"
    (English, IgnoreTests) => "Ignore tests"
    (Spanish, IgnoreTests) => "Ignorar pruebas"
    (SimplifiedChinese, IgnoreTests) => "忽略测试"
    (TraditionalChinese, IgnoreTests) => "忽略測試"
    (Japanese, IgnoreTests) => "テストを無視"
    (English, TestsIgnored) => "Tests: ignored"
    (Spanish, TestsIgnored) => "Pruebas: ignoradas"
    (SimplifiedChinese, TestsIgnored) => "测试：已忽略"
    (TraditionalChinese, TestsIgnored) => "測試：已忽略"
    (Japanese, TestsIgnored) => "テスト：無視"
    (English, TestsIncluded) => "Tests: included"
    (Spanish, TestsIncluded) => "Pruebas: incluidas"
    (SimplifiedChinese, TestsIncluded) => "测试：已包含"
    (TraditionalChinese, TestsIncluded) => "測試：已包含"
    (Japanese, TestsIncluded) => "テスト：含む"
    (English, PreviousChangeShortcut) => "Previous change (Shift+F7)"
    (Spanish, PreviousChangeShortcut) => "Cambio anterior (Shift+F7)"
    (SimplifiedChinese, PreviousChangeShortcut) =>
      "上一处更改（Shift+F7）"
    (TraditionalChinese, PreviousChangeShortcut) =>
      "上一處更改（Shift+F7）"
    (Japanese, PreviousChangeShortcut) => "前の変更（Shift+F7）"
    (English, PreviousChange) => "Previous change"
    (Spanish, PreviousChange) => "Cambio anterior"
    (SimplifiedChinese, PreviousChange) => "上一处更改"
    (TraditionalChinese, PreviousChange) => "上一處更改"
    (Japanese, PreviousChange) => "前の変更"
    (English, NextChangeShortcut) => "Next change (F7)"
    (Spanish, NextChangeShortcut) => "Siguiente cambio (F7)"
    (SimplifiedChinese, NextChangeShortcut) => "下一处更改（F7）"
    (TraditionalChinese, NextChangeShortcut) => "下一處更改（F7）"
    (Japanese, NextChangeShortcut) => "次の変更（F7）"
    (English, NextChange) => "Next change"
    (Spanish, NextChange) => "Siguiente cambio"
    (SimplifiedChinese, NextChange) => "下一处更改"
    (TraditionalChinese, NextChange) => "下一處更改"
    (Japanese, NextChange) => "次の変更"
    (English, DiffNavigation) => "Diff change navigation"
    (Spanish, DiffNavigation) => "Navegación por diferencias"
    (SimplifiedChinese, DiffNavigation) => "差异更改导航"
    (TraditionalChinese, DiffNavigation) => "差異更改導航"
    (Japanese, DiffNavigation) => "差分の変更箇所を移動"
    (English, FileReviewed) => "File is marked reviewed"
    (Spanish, FileReviewed) => "El archivo está marcado como revisado"
    (SimplifiedChinese, FileReviewed) => "文件已标为已审阅"
    (TraditionalChinese, FileReviewed) => "檔案已標為已審閱"
    (Japanese, FileReviewed) => "ファイルはレビュー済みです"
    (English, MarkHunkUnviewed) => "Mark this hunk unviewed"
    (Spanish, MarkHunkUnviewed) => "Marcar este bloque como no visto"
    (SimplifiedChinese, MarkHunkUnviewed) => "将此差异块标为未查看"
    (TraditionalChinese, MarkHunkUnviewed) => "將此差異塊標為未檢視"
    (Japanese, MarkHunkUnviewed) =>
      "この差分ブロックを未確認にする"
    (English, MarkHunkViewed) => "Mark this hunk viewed"
    (Spanish, MarkHunkViewed) => "Marcar este bloque como visto"
    (SimplifiedChinese, MarkHunkViewed) => "将此差异块标为已查看"
    (TraditionalChinese, MarkHunkViewed) => "將此差異塊標為已檢視"
    (Japanese, MarkHunkViewed) =>
      "この差分ブロックを確認済みにする"
    (English, HunkViewed) => "Hunk viewed"
    (Spanish, HunkViewed) => "Bloque visto"
    (SimplifiedChinese, HunkViewed) => "差异块已查看"
    (TraditionalChinese, HunkViewed) => "差異塊已檢視"
    (Japanese, HunkViewed) => "差分ブロックは確認済み"
    (English, UnmarkHunkViewed) => "Unmark hunk viewed"
    (Spanish, UnmarkHunkViewed) => "Desmarcar bloque como visto"
    (SimplifiedChinese, UnmarkHunkViewed) => "取消差异块已查看标记"
    (TraditionalChinese, UnmarkHunkViewed) => "取消差異塊已檢視標記"
    (Japanese, UnmarkHunkViewed) =>
      "差分ブロックの確認済みマークを解除"
    (English, MarkHunkViewedLabel) => "Mark hunk viewed"
    (Spanish, MarkHunkViewedLabel) => "Marcar bloque como visto"
    (SimplifiedChinese, MarkHunkViewedLabel) => "标记差异块已查看"
    (TraditionalChinese, MarkHunkViewedLabel) => "標記差異塊已檢視"
    (Japanese, MarkHunkViewedLabel) =>
      "差分ブロックを確認済みにする"
    (English, MarkViewed) => "Mark viewed"
    (Spanish, MarkViewed) => "Marcar como visto"
    (SimplifiedChinese, MarkViewed) => "标为已查看"
    (TraditionalChinese, MarkViewed) => "標為已檢視"
    (Japanese, MarkViewed) => "確認済みにする"
    (English, DiffLayout) => "Diff layout"
    (Spanish, DiffLayout) => "Disposición de diferencias"
    (SimplifiedChinese, DiffLayout) => "差异布局"
    (TraditionalChinese, DiffLayout) => "差異佈局"
    (Japanese, DiffLayout) => "差分レイアウト"
    (English, SideBySideHint) => "Use side-by-side diff layout"
    (Spanish, SideBySideHint) => "Usar disposición de diferencias en paralelo"
    (SimplifiedChinese, SideBySideHint) => "使用并排差异布局"
    (TraditionalChinese, SideBySideHint) => "使用並排差異佈局"
    (Japanese, SideBySideHint) => "左右比較レイアウトを使用"
    (English, SplitDiffLayout) => "Split diff layout"
    (Spanish, SplitDiffLayout) => "Disposición de diferencias en paralelo"
    (SimplifiedChinese, SplitDiffLayout) => "并排差异布局"
    (TraditionalChinese, SplitDiffLayout) => "並排差異佈局"
    (Japanese, SplitDiffLayout) => "左右比較レイアウト"
    (English, SplitLabel) => "Split"
    (Spanish, SplitLabel) => "En paralelo"
    (SimplifiedChinese, SplitLabel) => "并排"
    (TraditionalChinese, SplitLabel) => "並排"
    (Japanese, SplitLabel) => "左右比較"
    (English, UnifiedDiffHint) => "Use unified diff layout"
    (Spanish, UnifiedDiffHint) => "Usar disposición de diferencias unificada"
    (SimplifiedChinese, UnifiedDiffHint) => "使用统一差异布局"
    (TraditionalChinese, UnifiedDiffHint) => "使用統一差異佈局"
    (Japanese, UnifiedDiffHint) => "統合差分レイアウトを使用"
    (English, UnifiedDiffLayout) => "Unified diff layout"
    (Spanish, UnifiedDiffLayout) => "Disposición de diferencias unificada"
    (SimplifiedChinese, UnifiedDiffLayout) => "统一差异布局"
    (TraditionalChinese, UnifiedDiffLayout) => "統一差異佈局"
    (Japanese, UnifiedDiffLayout) => "統合差分レイアウト"
    (English, UnifiedLabel) => "Unified"
    (Spanish, UnifiedLabel) => "Unificada"
    (SimplifiedChinese, UnifiedLabel) => "统一"
    (TraditionalChinese, UnifiedLabel) => "統一"
    (Japanese, UnifiedLabel) => "統合"
    (English, EmptyFolder) => "This folder is empty."
    (Spanish, EmptyFolder) => "Esta carpeta está vacía."
    (SimplifiedChinese, EmptyFolder) => "此文件夹为空。"
    (TraditionalChinese, EmptyFolder) => "此資料夾為空。"
    (Japanese, EmptyFolder) => "このフォルダーは空です。"
    (English, CannotLoadFolder) => "Could not load this folder."
    (Spanish, CannotLoadFolder) => "No se pudo cargar esta carpeta."
    (SimplifiedChinese, CannotLoadFolder) => "无法加载此文件夹。"
    (TraditionalChinese, CannotLoadFolder) => "無法載入此資料夾。"
    (Japanese, CannotLoadFolder) =>
      "このフォルダーを読み込めません。"
    (English, RefreshingLabel) => "Refreshing…"
    (Spanish, RefreshingLabel) => "Actualizando…"
    (SimplifiedChinese, RefreshingLabel) => "正在刷新…"
    (TraditionalChinese, RefreshingLabel) => "正在重新整理…"
    (Japanese, RefreshingLabel) => "更新中…"
    (English, ReturnReviewQueue) =>
      "Return this changed file to the review queue"
    (Spanish, ReturnReviewQueue) =>
      "Devolver este archivo modificado a la cola de revisión"
    (SimplifiedChinese, ReturnReviewQueue) =>
      "将此更改文件放回审阅队列"
    (TraditionalChinese, ReturnReviewQueue) =>
      "將此更改檔案放回審閱佇列"
    (Japanese, ReturnReviewQueue) =>
      "この変更ファイルをレビュー待ちに戻す"
    (English, MarkChangedReviewed) => "Mark this changed file as reviewed"
    (Spanish, MarkChangedReviewed) =>
      "Marcar este archivo modificado como revisado"
    (SimplifiedChinese, MarkChangedReviewed) =>
      "将此更改文件标为已审阅"
    (TraditionalChinese, MarkChangedReviewed) =>
      "將此更改檔案標為已審閱"
    (Japanese, MarkChangedReviewed) =>
      "この変更ファイルをレビュー済みにする"
    (English, MarkFileUnreviewed) => "Mark file unreviewed"
    (Spanish, MarkFileUnreviewed) => "Marcar archivo como no revisado"
    (SimplifiedChinese, MarkFileUnreviewed) => "将文件标为未审阅"
    (TraditionalChinese, MarkFileUnreviewed) => "將檔案標為未審閱"
    (Japanese, MarkFileUnreviewed) => "ファイルを未レビューにする"
    (English, MarkFileReviewed) => "Mark file reviewed"
    (Spanish, MarkFileReviewed) => "Marcar archivo como revisado"
    (SimplifiedChinese, MarkFileReviewed) => "将文件标为已审阅"
    (TraditionalChinese, MarkFileReviewed) => "將檔案標為已審閱"
    (Japanese, MarkFileReviewed) => "ファイルをレビュー済みにする"
    (English, ViewFile) => "View file"
    (Spanish, ViewFile) => "Ver archivo"
    (SimplifiedChinese, ViewFile) => "查看文件"
    (TraditionalChinese, ViewFile) => "檢視檔案"
    (Japanese, ViewFile) => "ファイルを表示"
    (English, ReturnSourcePreview) =>
      "Return to the source preview and quick-diff gutter"
    (Spanish, ReturnSourcePreview) =>
      "Volver a la vista previa del código y al margen de diferencias rápidas"
    (SimplifiedChinese, ReturnSourcePreview) =>
      "返回源码预览和快速差异边栏"
    (TraditionalChinese, ReturnSourcePreview) =>
      "返回原始碼預覽和快速差異邊欄"
    (Japanese, ReturnSourcePreview) =>
      "ソースプレビューとクイック差分バーに戻る"
    (English, ViewFullDiff) => "View full diff"
    (Spanish, ViewFullDiff) => "Ver diferencias completas"
    (SimplifiedChinese, ViewFullDiff) => "查看完整差异"
    (TraditionalChinese, ViewFullDiff) => "檢視完整差異"
    (Japanese, ViewFullDiff) => "差分全体を表示"
    (English, FullDiffHint) => "Open the full diff against the review baseline"
    (Spanish, FullDiffHint) =>
      "Abrir las diferencias completas respecto a la base de revisión"
    (SimplifiedChinese, FullDiffHint) =>
      "打开相对于审阅基准的完整差异"
    (TraditionalChinese, FullDiffHint) =>
      "開啟相對於審閱基準的完整差異"
    (Japanese, FullDiffHint) => "レビュー基準との差分全体を開く"
    (English, DeletedBaseline) => "Deleted · baseline"
    (Spanish, DeletedBaseline) => "Eliminado · base"
    (SimplifiedChinese, DeletedBaseline) => "已删除 · 基准"
    (TraditionalChinese, DeletedBaseline) => "已刪除 · 基準"
    (Japanese, DeletedBaseline) => "削除済み · 基準"
    (English, DeletedBaselineHint) =>
      "Deleted in the working tree; showing the review baseline"
    (Spanish, DeletedBaselineHint) =>
      "Eliminado del árbol de trabajo; se muestra la base de revisión"
    (SimplifiedChinese, DeletedBaselineHint) =>
      "工作树中已删除，正在显示审阅基准"
    (TraditionalChinese, DeletedBaselineHint) =>
      "工作樹中已刪除，正在顯示審閱基準"
    (Japanese, DeletedBaselineHint) =>
      "ワークツリーでは削除済みのため、レビュー基準を表示しています"
    (English, WorkingUnavailable) => "Working unavailable · baseline"
    (Spanish, WorkingUnavailable) => "Archivo de trabajo no disponible · base"
    (SimplifiedChinese, WorkingUnavailable) => "工作副本不可用 · 基准"
    (TraditionalChinese, WorkingUnavailable) =>
      "工作副本不可用 · 基準"
    (Japanese, WorkingUnavailable) =>
      "作業コピーを取得できません · 基準"
    (English, WorkingUnavailableHint) =>
      "The working-tree file could not be read; showing the review baseline"
    (Spanish, WorkingUnavailableHint) =>
      "No se pudo leer el archivo del árbol de trabajo; se muestra la base de revisión"
    (SimplifiedChinese, WorkingUnavailableHint) =>
      "无法读取工作树文件，正在显示审阅基准"
    (TraditionalChinese, WorkingUnavailableHint) =>
      "無法讀取工作樹檔案，正在顯示審閱基準"
    (Japanese, WorkingUnavailableHint) =>
      "ワークツリーのファイルを読み取れないため、レビュー基準を表示しています"
    (English, DiffUnavailable) => "Diff unavailable"
    (Spanish, DiffUnavailable) => "Diferencias no disponibles"
    (SimplifiedChinese, DiffUnavailable) => "差异不可用"
    (TraditionalChinese, DiffUnavailable) => "差異不可用"
    (Japanese, DiffUnavailable) => "差分を取得できません"
    (English, NotTextPreview) =>
      "The working-tree file cannot be previewed as text"
    (Spanish, NotTextPreview) =>
      "El archivo del árbol de trabajo no se puede previsualizar como texto"
    (SimplifiedChinese, NotTextPreview) =>
      "工作树文件无法作为文本预览"
    (TraditionalChinese, NotTextPreview) =>
      "工作樹檔案無法作為文字預覽"
    (Japanese, NotTextPreview) =>
      "ワークツリーのファイルをテキストとしてプレビューできません"
    (English, DeletedNoBaseline) => "Deleted · no baseline"
    (Spanish, DeletedNoBaseline) => "Eliminado · sin base"
    (SimplifiedChinese, DeletedNoBaseline) => "已删除 · 无基准"
    (TraditionalChinese, DeletedNoBaseline) => "已刪除 · 無基準"
    (Japanese, DeletedNoBaseline) => "削除済み · 基準なし"
    (English, NoBaseline) => "No review baseline is available to preview"
    (Spanish, NoBaseline) =>
      "No hay una base de revisión disponible para previsualizar"
    (SimplifiedChinese, NoBaseline) => "没有可预览的审阅基准"
    (TraditionalChinese, NoBaseline) => "沒有可預覽的審閱基準"
    (Japanese, NoBaseline) =>
      "プレビューできるレビュー基準がありません"
    (English, RenderedNoGutter) => "Rendered · no gutter"
    (Spanish, RenderedNoGutter) => "Renderizado · sin margen"
    (SimplifiedChinese, RenderedNoGutter) => "已渲染 · 无差异边栏"
    (TraditionalChinese, RenderedNoGutter) => "已渲染 · 無差異邊欄"
    (Japanese, RenderedNoGutter) =>
      "レンダリング表示 · 差分バーなし"
    (English, MarkdownGutterHint) =>
      "Rendered Markdown does not expose source diff decorations"
    (Spanish, MarkdownGutterHint) =>
      "El Markdown renderizado no muestra indicadores de diferencias del código fuente"
    (SimplifiedChinese, MarkdownGutterHint) =>
      "渲染后的 Markdown 不显示源码差异标记"
    (TraditionalChinese, MarkdownGutterHint) =>
      "渲染後的 Markdown 不顯示原始碼差異標記"
    (Japanese, MarkdownGutterHint) =>
      "レンダリングした Markdown ではソースの差分マークを表示しません"
    (English, NewMarkdownHint) =>
      "New Markdown has no review baseline; its rendered preview does not expose diff decorations"
    (Spanish, NewMarkdownHint) =>
      "El nuevo Markdown no tiene una base de revisión; su vista renderizada no muestra indicadores de diferencias"
    (SimplifiedChinese, NewMarkdownHint) =>
      "新 Markdown 文件没有审阅基准，渲染预览不显示差异标记"
    (TraditionalChinese, NewMarkdownHint) =>
      "新 Markdown 檔案沒有審閱基準，渲染預覽不顯示差異標記"
    (Japanese, NewMarkdownHint) =>
      "新しい Markdown ファイルにはレビュー基準がなく、レンダリングプレビューに差分マークは表示されません"
    (English, DiffBaseline) => "Diff vs baseline"
    (Spanish, DiffBaseline) => "Diferencias respecto a la base"
    (SimplifiedChinese, DiffBaseline) => "相对于基准的差异"
    (TraditionalChinese, DiffBaseline) => "相對於基準的差異"
    (Japanese, DiffBaseline) => "基準との差分"
    (English, QuickDiffBaseline) => "Quick diff against the review baseline"
    (Spanish, QuickDiffBaseline) =>
      "Diferencias rápidas respecto a la base de revisión"
    (SimplifiedChinese, QuickDiffBaseline) =>
      "相对于审阅基准的快速差异"
    (TraditionalChinese, QuickDiffBaseline) =>
      "相對於審閱基準的快速差異"
    (Japanese, QuickDiffBaseline) =>
      "レビュー基準とのクイック差分"
    (English, NewNoBaseline) => "New · no baseline"
    (Spanish, NewNoBaseline) => "Nuevo · sin base"
    (SimplifiedChinese, NewNoBaseline) => "新文件 · 无基准"
    (TraditionalChinese, NewNoBaseline) => "新檔案 · 無基準"
    (Japanese, NewNoBaseline) => "新規ファイル · 基準なし"
    (English, NewBaselineHint) =>
      "New file compared with an empty review baseline"
    (Spanish, NewBaselineHint) =>
      "Archivo nuevo comparado con una base de revisión vacía"
    (SimplifiedChinese, NewBaselineHint) =>
      "将新文件与空审阅基准比较"
    (TraditionalChinese, NewBaselineHint) =>
      "將新檔案與空審閱基準比較"
    (Japanese, NewBaselineHint) =>
      "新規ファイルを空のレビュー基準と比較"
    (English, BinaryBaseline) => "The review baseline is binary"
    (Spanish, BinaryBaseline) => "La base de revisión es binaria"
    (SimplifiedChinese, BinaryBaseline) => "审阅基准为二进制文件"
    (TraditionalChinese, BinaryBaseline) => "審閱基準為二進位制檔案"
    (Japanese, BinaryBaseline) =>
      "レビュー基準はバイナリファイルです"
    (English, LargeBaseline) => "The review baseline is too large"
    (Spanish, LargeBaseline) => "La base de revisión es demasiado grande"
    (SimplifiedChinese, LargeBaseline) => "审阅基准过大"
    (TraditionalChinese, LargeBaseline) => "審閱基準過大"
    (Japanese, LargeBaseline) => "レビュー基準が大きすぎます"
    (English, BaselineFailedPrefix) => "Could not load review baseline: "
    (Spanish, BaselineFailedPrefix) =>
      "No se pudo cargar la base de revisión: "
    (SimplifiedChinese, BaselineFailedPrefix) => "无法加载审阅基准："
    (TraditionalChinese, BaselineFailedPrefix) => "無法載入審閱基準："
    (Japanese, BaselineFailedPrefix) =>
      "レビュー基準を読み込めません："
    (English, FullDiff) => "Full diff"
    (Spanish, FullDiff) => "Diferencias completas"
    (SimplifiedChinese, FullDiff) => "完整差异"
    (TraditionalChinese, FullDiff) => "完整差異"
    (Japanese, FullDiff) => "差分全体"
    (English, FilteringCommit) => "Filtering commit "
    (Spanish, FilteringCommit) => "Filtrando commit "
    (SimplifiedChinese, FilteringCommit) => "筛选提交 "
    (TraditionalChinese, FilteringCommit) => "篩選提交 "
    (Japanese, FilteringCommit) => "コミットを絞り込み："
    (English, FilteringWorkingTree) => "Filtering working tree"
    (Spanish, FilteringWorkingTree) => "Filtrando árbol de trabajo"
    (SimplifiedChinese, FilteringWorkingTree) => "筛选工作树"
    (TraditionalChinese, FilteringWorkingTree) => "篩選工作樹"
    (Japanese, FilteringWorkingTree) => "ワークツリーを絞り込み"
    (English, FilterFilesPath) => "Filter files by path"
    (Spanish, FilterFilesPath) => "Filtrar archivos por ruta"
    (SimplifiedChinese, FilterFilesPath) => "按路径筛选文件"
    (TraditionalChinese, FilterFilesPath) => "按路徑篩選檔案"
    (Japanese, FilterFilesPath) => "パスでファイルを絞り込む"
    (English, FilterChangedPath) => "Filter changed files by path"
    (Spanish, FilterChangedPath) => "Filtrar archivos modificados por ruta"
    (SimplifiedChinese, FilterChangedPath) => "按路径筛选更改的文件"
    (TraditionalChinese, FilterChangedPath) => "按路徑篩選更改的檔案"
    (Japanese, FilterChangedPath) =>
      "パスで変更ファイルを絞り込む"
    (English, ClearFilters) => "Clear file filters"
    (Spanish, ClearFilters) => "Borrar filtros de archivos"
    (SimplifiedChinese, ClearFilters) => "清除文件筛选条件"
    (TraditionalChinese, ClearFilters) => "清除檔案篩選條件"
    (Japanese, ClearFilters) => "ファイルのフィルターをクリア"
    (English, ClearLabel) => "Clear"
    (Spanish, ClearLabel) => "Borrar"
    (SimplifiedChinese, ClearLabel) => "清除"
    (TraditionalChinese, ClearLabel) => "清除"
    (Japanese, ClearLabel) => "クリア"
    (English, FileTypes) => "File types"
    (Spanish, FileTypes) => "Tipos de archivo"
    (SimplifiedChinese, FileTypes) => "文件类型"
    (TraditionalChinese, FileTypes) => "檔案型別"
    (Japanese, FileTypes) => "ファイルの種類"
    (English, NoFileTypes) => "File types: none"
    (Spanish, NoFileTypes) => "Tipos de archivo: ninguno"
    (SimplifiedChinese, NoFileTypes) => "文件类型：无"
    (TraditionalChinese, NoFileTypes) => "檔案型別：無"
    (Japanese, NoFileTypes) => "ファイルの種類：なし"
    (English, FilterExtensionPrefix) => "Filter by file extension, "
    (Spanish, FilterExtensionPrefix) => "Filtrar por extensión de archivo, "
    (SimplifiedChinese, FilterExtensionPrefix) => "按文件扩展名筛选，"
    (TraditionalChinese, FilterExtensionPrefix) => "按副檔名篩選，"
    (Japanese, FilterExtensionPrefix) => "拡張子で絞り込み、"
    (English, AllFileTypes) => "all file types"
    (Spanish, AllFileTypes) => "todos los tipos de archivo"
    (SimplifiedChinese, AllFileTypes) => "所有文件类型"
    (TraditionalChinese, AllFileTypes) => "所有檔案型別"
    (Japanese, AllFileTypes) => "すべてのファイルの種類"
    (English, NoChangedTypes) => "No changed file types"
    (Spanish, NoChangedTypes) => "No hay tipos de archivos modificados"
    (SimplifiedChinese, NoChangedTypes) => "没有更改的文件类型"
    (TraditionalChinese, NoChangedTypes) => "沒有更改的檔案型別"
    (Japanese, NoChangedTypes) =>
      "変更されたファイルの種類はありません"
    (English, WholeFile) => "Whole file"
    (Spanish, WholeFile) => "Archivo completo"
    (SimplifiedChinese, WholeFile) => "整个文件"
    (TraditionalChinese, WholeFile) => "整個檔案"
    (Japanese, WholeFile) => "ファイル全体"
    (English, LexicalFallback) => "Lexical fallback"
    (Spanish, LexicalFallback) => "Alternativa léxica"
    (SimplifiedChinese, LexicalFallback) => "词法回退"
    (TraditionalChinese, LexicalFallback) => "詞法回退"
    (Japanese, LexicalFallback) => "字句比較にフォールバック"
    (English, SectioningFallback) => "Sectioning fallback"
    (Spanish, SectioningFallback) => "Alternativa por secciones"
    (SimplifiedChinese, SectioningFallback) => "分段回退"
    (TraditionalChinese, SectioningFallback) => "分段回退"
    (Japanese, SectioningFallback) =>
      "セクション比較にフォールバック"
    (English, SectionLexicalFallback) => "Section lexical fallback"
    (Spanish, SectionLexicalFallback) => "Alternativa léxica por secciones"
    (SimplifiedChinese, SectionLexicalFallback) => "分段词法回退"
    (TraditionalChinese, SectionLexicalFallback) => "分段詞法回退"
    (Japanese, SectionLexicalFallback) =>
      "セクションごとの字句比較にフォールバック"
    (English, SectionDiffFallback) => "Section diff fallback"
    (Spanish, SectionDiffFallback) => "Alternativa de diferencias por secciones"
    (SimplifiedChinese, SectionDiffFallback) => "分段差异回退"
    (TraditionalChinese, SectionDiffFallback) => "分段差異回退"
    (Japanese, SectionDiffFallback) =>
      "セクションごとの差分にフォールバック"
    (English, NoStructuralText) =>
      "No structural changes found. Switch to Token or Line to inspect text."
    (Spanish, NoStructuralText) =>
      "No se encontraron cambios estructurales. Cambia a Token o Línea para examinar el texto."
    (SimplifiedChinese, NoStructuralText) =>
      "未发现结构更改。切换到词元或行差异以检查文本。"
    (TraditionalChinese, NoStructuralText) =>
      "未發現結構更改。切換到詞元或行差異以檢查文字。"
    (Japanese, NoStructuralText) =>
      "構造上の変更はありません。テキストを確認するにはトークン差分または行差分に切り替えてください。"
    (English, NoTokenChanges) => "No token changes found."
    (Spanish, NoTokenChanges) => "No se encontraron cambios en tokens."
    (SimplifiedChinese, NoTokenChanges) => "未发现词元更改。"
    (TraditionalChinese, NoTokenChanges) => "未發現詞元更改。"
    (Japanese, NoTokenChanges) => "トークンの変更はありません。"
    (English, NoStructuralToken) =>
      "No structural changes found. Switch to Token to view text changes."
    (Spanish, NoStructuralToken) =>
      "No se encontraron cambios estructurales. Cambia a Token para ver los cambios de texto."
    (SimplifiedChinese, NoStructuralToken) =>
      "未发现结构更改。切换到词元差异以查看文本更改。"
    (TraditionalChinese, NoStructuralToken) =>
      "未發現結構更改。切換到詞元差異以檢視文字更改。"
    (Japanese, NoStructuralToken) =>
      "構造上の変更はありません。テキストの変更を見るにはトークン差分に切り替えてください。"
    (English, NoDeclarationChanges) =>
      "No declaration-owned token changes found. Switch to Line to inspect the complete file."
    (Spanish, NoDeclarationChanges) =>
      "No se encontraron cambios en tokens de declaraciones. Cambia a Línea para examinar el archivo completo."
    (SimplifiedChinese, NoDeclarationChanges) =>
      "未发现声明内的词元更改。切换到行差异以检查完整文件。"
    (TraditionalChinese, NoDeclarationChanges) =>
      "未發現宣告內的詞元更改。切換到行差異以檢查完整檔案。"
    (Japanese, NoDeclarationChanges) =>
      "宣言内のトークンに変更はありません。ファイル全体を確認するには行差分に切り替えてください。"
    (English, ReorderedDeclarations) =>
      "Top-level declarations are reordered; each declaration keeps its own DiffEditor."
    (Spanish, ReorderedDeclarations) =>
      "Se ha cambiado el orden de las declaraciones de nivel superior; cada declaración conserva su propio DiffEditor."
    (SimplifiedChinese, ReorderedDeclarations) =>
      "顶层声明顺序已调整，每个声明仍使用独立的差异视图。"
    (TraditionalChinese, ReorderedDeclarations) =>
      "頂層宣告順序已調整，每個宣告仍使用獨立的差異檢視。"
    (Japanese, ReorderedDeclarations) =>
      "最上位宣言の順序が変更されています。各宣言は個別の差分ビューで表示されます。"
    (English, NoSectionChanges) =>
      "No semantic section changes found. Switch to Line to inspect the complete file."
    (Spanish, NoSectionChanges) =>
      "No se encontraron cambios en secciones semánticas. Cambia a Línea para examinar el archivo completo."
    (SimplifiedChinese, NoSectionChanges) =>
      "未发现语义分段更改。切换到行差异以检查完整文件。"
    (TraditionalChinese, NoSectionChanges) =>
      "未發現語義分段更改。切換到行差異以檢查完整檔案。"
    (Japanese, NoSectionChanges) =>
      "セマンティックなセクション変更はありません。ファイル全体を確認するには行差分に切り替えてください。"
    (English, InvalidSemanticResult) =>
      "The semantic result was invalid. Switch to Line to inspect the complete file."
    (Spanish, InvalidSemanticResult) =>
      "El resultado semántico no es válido. Cambia a Línea para examinar el archivo completo."
    (SimplifiedChinese, InvalidSemanticResult) =>
      "语义结果无效。切换到行差异以检查完整文件。"
    (TraditionalChinese, InvalidSemanticResult) =>
      "語義結果無效。切換到行差異以檢查完整檔案。"
    (Japanese, InvalidSemanticResult) =>
      "セマンティック解析の結果が無効です。ファイル全体を確認するには行差分に切り替えてください。"
  }
}
