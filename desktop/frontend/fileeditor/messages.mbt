// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
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
    (English, AddToContext) => "Add to context"
    (SimplifiedChinese, AddToContext) => "添加到上下文"
    (Japanese, AddToContext) => "コンテキストに追加"
    (English, PartlyInContext) => "Partly in context"
    (SimplifiedChinese, PartlyInContext) => "部分已在上下文中"
    (Japanese, PartlyInContext) =>
      "一部がコンテキストに含まれています"
    (English, InContext) => "In context"
    (SimplifiedChinese, InContext) => "已在上下文中"
    (Japanese, InContext) => "コンテキストに含まれています"
    (English, RemoveHunkContext) => "Remove this hunk from context"
    (SimplifiedChinese, RemoveHunkContext) => "从上下文移除此差异块"
    (Japanese, RemoveHunkContext) =>
      "この差分ブロックをコンテキストから削除"
    (English, AddRemainingChanges) => "Add remaining changes"
    (SimplifiedChinese, AddRemainingChanges) => "添加其余更改"
    (Japanese, AddRemainingChanges) => "残りの変更を追加"
    (English, RemoveIncludedChanges) => "Remove included changes"
    (SimplifiedChinese, RemoveIncludedChanges) => "移除已包含的更改"
    (Japanese, RemoveIncludedChanges) => "含まれている変更を削除"
    (English, NoCommitContent) =>
      "No file content exists on either side of this commit."
    (SimplifiedChinese, NoCommitContent) =>
      "此提交的两侧均无文件内容。"
    (Japanese, NoCommitContent) =>
      "このコミットの両側にファイルの内容がありません。"
    (English, WaitingPlacement) => "Waiting for workspace placement…"
    (SimplifiedChinese, WaitingPlacement) => "正在等待工作区就绪…"
    (Japanese, WaitingPlacement) =>
      "ワークスペースの準備を待機中…"
    (English, MissingCheckout) => "Worktree checkout is missing."
    (SimplifiedChinese, MissingCheckout) => "工作树检出目录缺失。"
    (Japanese, MissingCheckout) =>
      "ワークツリーのチェックアウトがありません。"
    (English, NoConversation) => "No conversation selected."
    (SimplifiedChinese, NoConversation) => "未选择对话。"
    (Japanese, NoConversation) =>
      "チャットが選択されていません。"
    (English, ExplorerViews) => "Explorer views"
    (SimplifiedChinese, ExplorerViews) => "资源管理器视图"
    (Japanese, ExplorerViews) => "エクスプローラービュー"
    (English, WorkspaceFiles) => "Workspace files"
    (SimplifiedChinese, WorkspaceFiles) => "工作区文件"
    (Japanese, WorkspaceFiles) => "ワークスペースのファイル"
    (English, FilesLabel) => "Files"
    (SimplifiedChinese, FilesLabel) => "文件"
    (Japanese, FilesLabel) => "ファイル"
    (English, ChangedFilesHint) => "Changed files (click again to refresh)"
    (SimplifiedChinese, ChangedFilesHint) =>
      "更改的文件（再次点击刷新）"
    (Japanese, ChangedFilesHint) =>
      "変更したファイル（再クリックで更新）"
    (English, ChangesLabel) => "Changes"
    (SimplifiedChinese, ChangesLabel) => "更改"
    (Japanese, ChangesLabel) => "変更"
    (English, SearchWorkspace) => "Search across the workspace"
    (SimplifiedChinese, SearchWorkspace) => "搜索整个工作区"
    (Japanese, SearchWorkspace) => "ワークスペース全体を検索"
    (English, SearchLabel) => "Search"
    (SimplifiedChinese, SearchLabel) => "搜索"
    (Japanese, SearchLabel) => "検索"
    (English, ResizeGraph) => "Resize Changes and Git Graph"
    (SimplifiedChinese, ResizeGraph) => "调整更改列表和 Git 图的大小"
    (Japanese, ResizeGraph) =>
      "変更一覧と Git グラフのサイズを変更"
    (English, GraphLabel) => "Graph"
    (SimplifiedChinese, GraphLabel) => "提交图"
    (Japanese, GraphLabel) => "コミットグラフ"
    (English, RefreshGraph) => "Refresh Git Graph"
    (SimplifiedChinese, RefreshGraph) => "刷新 Git 图"
    (Japanese, RefreshGraph) => "Git グラフを更新"
    (English, RepositoryLabel) => "Repository"
    (SimplifiedChinese, RepositoryLabel) => "仓库"
    (Japanese, RepositoryLabel) => "リポジトリ"
    (English, NoCommits) => "No commits"
    (SimplifiedChinese, NoCommits) => "没有提交"
    (Japanese, NoCommits) => "コミットなし"
    (English, LoadingHistory) => "Loading Git history…"
    (SimplifiedChinese, LoadingHistory) => "正在加载 Git 历史…"
    (Japanese, LoadingHistory) => "Git 履歴を読み込み中…"
    (English, RetryLabel) => "Retry"
    (SimplifiedChinese, RetryLabel) => "重试"
    (Japanese, RetryLabel) => "再試行"
    (English, GitUnavailable) =>
      "Git is unavailable or this workspace is not a Git repository."
    (SimplifiedChinese, GitUnavailable) =>
      "Git 不可用，或此工作区不是 Git 仓库。"
    (Japanese, GitUnavailable) =>
      "Git が利用できないか、このワークスペースは Git リポジトリではありません。"
    (English, EmptyBranch) => "This branch has no commits."
    (SimplifiedChinese, EmptyBranch) => "此分支没有提交。"
    (Japanese, EmptyBranch) =>
      "このブランチにはコミットがありません。"
    (English, LoadingLabel) => "Loading…"
    (SimplifiedChinese, LoadingLabel) => "正在加载…"
    (Japanese, LoadingLabel) => "読み込み中…"
    (English, LoadMore) => "Load more"
    (SimplifiedChinese, LoadMore) => "加载更多"
    (Japanese, LoadMore) => "さらに読み込む"
    (English, CommitHistory) => "Git commit history"
    (SimplifiedChinese, CommitHistory) => "Git 提交历史"
    (Japanese, CommitHistory) => "Git コミット履歴"
    (English, LoadingChangedFiles) => "Loading changed files…"
    (SimplifiedChinese, LoadingChangedFiles) => "正在加载更改的文件…"
    (Japanese, LoadingChangedFiles) =>
      "変更したファイルを読み込み中…"
    (English, NoWorkspaceChanges) => "No changes in this workspace."
    (SimplifiedChinese, NoWorkspaceChanges) => "此工作区没有更改。"
    (Japanese, NoWorkspaceChanges) =>
      "このワークスペースには変更がありません。"
    (English, NoFilterMatches) => "No files match these filters."
    (SimplifiedChinese, NoFilterMatches) =>
      "没有符合筛选条件的文件。"
    (Japanese, NoFilterMatches) =>
      "フィルターに一致するファイルがありません。"
    (English, SubmoduleDiff) => "Git submodule cannot be shown as a text diff"
    (SimplifiedChinese, SubmoduleDiff) =>
      "Git 子模块无法显示为文本差异"
    (Japanese, SubmoduleDiff) =>
      "Git サブモジュールはテキスト差分として表示できません"
    (English, SymlinkDiff) => "Git symlink cannot be shown as a text diff"
    (SimplifiedChinese, SymlinkDiff) =>
      "Git 符号链接无法显示为文本差异"
    (Japanese, SymlinkDiff) =>
      "Git シンボリックリンクはテキスト差分として表示できません"
    (English, PathOutsideWorkspace) => "Original path is outside this workspace"
    (SimplifiedChinese, PathOutsideWorkspace) =>
      "原始路径位于此工作区之外"
    (Japanese, PathOutsideWorkspace) =>
      "元のパスはこのワークスペースの外にあります"
    (English, EmptyWorkspace) => "This workspace is empty."
    (SimplifiedChinese, EmptyWorkspace) => "此工作区为空。"
    (Japanese, EmptyWorkspace) => "このワークスペースは空です。"
    (English, LoadingChanges) => "Loading changes…"
    (SimplifiedChinese, LoadingChanges) => "正在加载更改…"
    (Japanese, LoadingChanges) => "変更を読み込み中…"
    (English, NoChangedFiles) => "No changed files."
    (SimplifiedChinese, NoChangedFiles) => "没有更改的文件。"
    (Japanese, NoChangedFiles) =>
      "変更したファイルはありません。"
    (English, NoReviewableFiles) => "No reviewable text files"
    (SimplifiedChinese, NoReviewableFiles) => "没有可审阅的文本文件"
    (Japanese, NoReviewableFiles) =>
      "レビュー可能なテキストファイルがありません"
    (English, ChangedFiles) => "Changed files"
    (SimplifiedChinese, ChangedFiles) => "更改的文件"
    (Japanese, ChangedFiles) => "変更したファイル"
    (English, ViewDiffPrefix) => "View diff: "
    (SimplifiedChinese, ViewDiffPrefix) => "查看差异："
    (Japanese, ViewDiffPrefix) => "差分を表示："
    (English, OpenDiffPrefix) => "Open diff — "
    (SimplifiedChinese, OpenDiffPrefix) => "打开差异 — "
    (Japanese, OpenDiffPrefix) => "差分を開く — "
    (English, MarkUnreviewed) => "Mark unreviewed"
    (SimplifiedChinese, MarkUnreviewed) => "标为未审阅"
    (Japanese, MarkUnreviewed) => "未レビューにする"
    (English, MarkReviewed) => "Mark reviewed"
    (SimplifiedChinese, MarkReviewed) => "标为已审阅"
    (Japanese, MarkReviewed) => "レビュー済みにする"
    (English, ReviewedPrefix) => "Reviewed: "
    (SimplifiedChinese, ReviewedPrefix) => "已审阅："
    (Japanese, ReviewedPrefix) => "レビュー済み："
    (English, HideFileTree) => "Hide file tree"
    (SimplifiedChinese, HideFileTree) => "隐藏文件树"
    (Japanese, HideFileTree) => "ファイルツリーを非表示"
    (English, ShowFileTree) => "Show file tree"
    (SimplifiedChinese, ShowFileTree) => "显示文件树"
    (Japanese, ShowFileTree) => "ファイルツリーを表示"
    (English, WorkspaceLabel) => "Workspace"
    (SimplifiedChinese, WorkspaceLabel) => "工作区"
    (Japanese, WorkspaceLabel) => "ワークスペース"
    (English, DiagramLabel) => "Diagram"
    (SimplifiedChinese, DiagramLabel) => "图表"
    (Japanese, DiagramLabel) => "図"
    (English, SourceLabel) => "Source"
    (SimplifiedChinese, SourceLabel) => "源码"
    (Japanese, SourceLabel) => "ソース"
    (English, MoonModuleView) => "Moon module view"
    (SimplifiedChinese, MoonModuleView) => "Moon 模块视图"
    (Japanese, MoonModuleView) => "Moon モジュールビュー"
    (English, DependencyGraph) => "Dependency graph"
    (SimplifiedChinese, DependencyGraph) => "依赖图"
    (Japanese, DependencyGraph) => "依存関係グラフ"
    (English, LineLabel) => "Line"
    (SimplifiedChinese, LineLabel) => "行"
    (Japanese, LineLabel) => "行"
    (English, TokenLabel) => "Token"
    (SimplifiedChinese, TokenLabel) => "词元"
    (Japanese, TokenLabel) => "トークン"
    (English, TreeLabel) => "Tree"
    (SimplifiedChinese, TreeLabel) => "语法树"
    (Japanese, TreeLabel) => "構文木"
    (English, ShowFile) => "Show file"
    (SimplifiedChinese, ShowFile) => "显示文件"
    (Japanese, ShowFile) => "ファイルを表示"
    (English, FileView) => "File view"
    (SimplifiedChinese, FileView) => "文件视图"
    (Japanese, FileView) => "ファイルビュー"
    (English, FileLabel) => "File"
    (SimplifiedChinese, FileLabel) => "文件"
    (Japanese, FileLabel) => "ファイル"
    (English, ReviewMode) => "Review mode"
    (SimplifiedChinese, ReviewMode) => "审阅模式"
    (Japanese, ReviewMode) => "レビューモード"
    (English, ComparisonAlgorithm) => "Comparison algorithm"
    (SimplifiedChinese, ComparisonAlgorithm) => "比较算法"
    (Japanese, ComparisonAlgorithm) => "比較アルゴリズム"
    (English, AvailableDiff) => "Available in diff view"
    (SimplifiedChinese, AvailableDiff) => "在差异视图中可用"
    (Japanese, AvailableDiff) => "差分ビューで利用可能"
    (English, AvailableTokenTree) => "Available in Token and Tree diff"
    (SimplifiedChinese, AvailableTokenTree) =>
      "在词元和语法树差异中可用"
    (Japanese, AvailableTokenTree) =>
      "トークン差分と構文木差分で利用可能"
    (English, IncludeComments) => "Include comments in the comparison"
    (SimplifiedChinese, IncludeComments) => "比较时包含注释"
    (Japanese, IncludeComments) => "比較にコメントを含める"
    (English, IgnoreCommentChanges) => "Ignore comment-only changes"
    (SimplifiedChinese, IgnoreCommentChanges) =>
      "忽略仅涉及注释的更改"
    (Japanese, IgnoreCommentChanges) => "コメントのみの変更を無視"
    (English, IgnoreComments) => "Ignore comments"
    (SimplifiedChinese, IgnoreComments) => "忽略注释"
    (Japanese, IgnoreComments) => "コメントを無視"
    (English, CommentsIgnored) => "Comments: ignored"
    (SimplifiedChinese, CommentsIgnored) => "注释：已忽略"
    (Japanese, CommentsIgnored) => "コメント：無視"
    (English, CommentsIncluded) => "Comments: included"
    (SimplifiedChinese, CommentsIncluded) => "注释：已包含"
    (Japanese, CommentsIncluded) => "コメント：含む"
    (English, IncludeTests) => "Include tests in the comparison"
    (SimplifiedChinese, IncludeTests) => "比较时包含测试"
    (Japanese, IncludeTests) => "比較にテストを含める"
    (English, IgnoreTestBlocks) => "Ignore MoonBit test blocks"
    (SimplifiedChinese, IgnoreTestBlocks) => "忽略 MoonBit 测试块"
    (Japanese, IgnoreTestBlocks) => "MoonBit テストブロックを無視"
    (English, IgnoreTests) => "Ignore tests"
    (SimplifiedChinese, IgnoreTests) => "忽略测试"
    (Japanese, IgnoreTests) => "テストを無視"
    (English, TestsIgnored) => "Tests: ignored"
    (SimplifiedChinese, TestsIgnored) => "测试：已忽略"
    (Japanese, TestsIgnored) => "テスト：無視"
    (English, TestsIncluded) => "Tests: included"
    (SimplifiedChinese, TestsIncluded) => "测试：已包含"
    (Japanese, TestsIncluded) => "テスト：含む"
    (English, PreviousChangeShortcut) => "Previous change (Shift+F7)"
    (SimplifiedChinese, PreviousChangeShortcut) =>
      "上一处更改（Shift+F7）"
    (Japanese, PreviousChangeShortcut) => "前の変更（Shift+F7）"
    (English, PreviousChange) => "Previous change"
    (SimplifiedChinese, PreviousChange) => "上一处更改"
    (Japanese, PreviousChange) => "前の変更"
    (English, NextChangeShortcut) => "Next change (F7)"
    (SimplifiedChinese, NextChangeShortcut) => "下一处更改（F7）"
    (Japanese, NextChangeShortcut) => "次の変更（F7）"
    (English, NextChange) => "Next change"
    (SimplifiedChinese, NextChange) => "下一处更改"
    (Japanese, NextChange) => "次の変更"
    (English, DiffNavigation) => "Diff change navigation"
    (SimplifiedChinese, DiffNavigation) => "差异更改导航"
    (Japanese, DiffNavigation) => "差分の変更箇所を移動"
    (English, FileReviewed) => "File is marked reviewed"
    (SimplifiedChinese, FileReviewed) => "文件已标为已审阅"
    (Japanese, FileReviewed) => "ファイルはレビュー済みです"
    (English, MarkHunkUnviewed) => "Mark this hunk unviewed"
    (SimplifiedChinese, MarkHunkUnviewed) => "将此差异块标为未查看"
    (Japanese, MarkHunkUnviewed) =>
      "この差分ブロックを未確認にする"
    (English, MarkHunkViewed) => "Mark this hunk viewed"
    (SimplifiedChinese, MarkHunkViewed) => "将此差异块标为已查看"
    (Japanese, MarkHunkViewed) =>
      "この差分ブロックを確認済みにする"
    (English, HunkViewed) => "Hunk viewed"
    (SimplifiedChinese, HunkViewed) => "差异块已查看"
    (Japanese, HunkViewed) => "差分ブロックは確認済み"
    (English, UnmarkHunkViewed) => "Unmark hunk viewed"
    (SimplifiedChinese, UnmarkHunkViewed) => "取消差异块已查看标记"
    (Japanese, UnmarkHunkViewed) =>
      "差分ブロックの確認済みマークを解除"
    (English, MarkHunkViewedLabel) => "Mark hunk viewed"
    (SimplifiedChinese, MarkHunkViewedLabel) => "标记差异块已查看"
    (Japanese, MarkHunkViewedLabel) =>
      "差分ブロックを確認済みにする"
    (English, MarkViewed) => "Mark viewed"
    (SimplifiedChinese, MarkViewed) => "标为已查看"
    (Japanese, MarkViewed) => "確認済みにする"
    (English, DiffLayout) => "Diff layout"
    (SimplifiedChinese, DiffLayout) => "差异布局"
    (Japanese, DiffLayout) => "差分レイアウト"
    (English, SideBySideHint) => "Use side-by-side diff layout"
    (SimplifiedChinese, SideBySideHint) => "使用并排差异布局"
    (Japanese, SideBySideHint) => "左右比較レイアウトを使用"
    (English, SplitDiffLayout) => "Split diff layout"
    (SimplifiedChinese, SplitDiffLayout) => "并排差异布局"
    (Japanese, SplitDiffLayout) => "左右比較レイアウト"
    (English, SplitLabel) => "Split"
    (SimplifiedChinese, SplitLabel) => "并排"
    (Japanese, SplitLabel) => "左右比較"
    (English, UnifiedDiffHint) => "Use unified diff layout"
    (SimplifiedChinese, UnifiedDiffHint) => "使用统一差异布局"
    (Japanese, UnifiedDiffHint) => "統合差分レイアウトを使用"
    (English, UnifiedDiffLayout) => "Unified diff layout"
    (SimplifiedChinese, UnifiedDiffLayout) => "统一差异布局"
    (Japanese, UnifiedDiffLayout) => "統合差分レイアウト"
    (English, UnifiedLabel) => "Unified"
    (SimplifiedChinese, UnifiedLabel) => "统一"
    (Japanese, UnifiedLabel) => "統合"
    (English, EmptyFolder) => "This folder is empty."
    (SimplifiedChinese, EmptyFolder) => "此文件夹为空。"
    (Japanese, EmptyFolder) => "このフォルダーは空です。"
    (English, CannotLoadFolder) => "Could not load this folder."
    (SimplifiedChinese, CannotLoadFolder) => "无法加载此文件夹。"
    (Japanese, CannotLoadFolder) =>
      "このフォルダーを読み込めません。"
    (English, RefreshingLabel) => "Refreshing…"
    (SimplifiedChinese, RefreshingLabel) => "正在刷新…"
    (Japanese, RefreshingLabel) => "更新中…"
    (English, ReturnReviewQueue) =>
      "Return this changed file to the review queue"
    (SimplifiedChinese, ReturnReviewQueue) =>
      "将此更改文件放回审阅队列"
    (Japanese, ReturnReviewQueue) =>
      "この変更ファイルをレビュー待ちに戻す"
    (English, MarkChangedReviewed) => "Mark this changed file as reviewed"
    (SimplifiedChinese, MarkChangedReviewed) =>
      "将此更改文件标为已审阅"
    (Japanese, MarkChangedReviewed) =>
      "この変更ファイルをレビュー済みにする"
    (English, MarkFileUnreviewed) => "Mark file unreviewed"
    (SimplifiedChinese, MarkFileUnreviewed) => "将文件标为未审阅"
    (Japanese, MarkFileUnreviewed) => "ファイルを未レビューにする"
    (English, MarkFileReviewed) => "Mark file reviewed"
    (SimplifiedChinese, MarkFileReviewed) => "将文件标为已审阅"
    (Japanese, MarkFileReviewed) => "ファイルをレビュー済みにする"
    (English, ViewFile) => "View file"
    (SimplifiedChinese, ViewFile) => "查看文件"
    (Japanese, ViewFile) => "ファイルを表示"
    (English, ReturnSourcePreview) =>
      "Return to the source preview and quick-diff gutter"
    (SimplifiedChinese, ReturnSourcePreview) =>
      "返回源码预览和快速差异边栏"
    (Japanese, ReturnSourcePreview) =>
      "ソースプレビューとクイック差分バーに戻る"
    (English, ViewFullDiff) => "View full diff"
    (SimplifiedChinese, ViewFullDiff) => "查看完整差异"
    (Japanese, ViewFullDiff) => "差分全体を表示"
    (English, FullDiffHint) => "Open the full diff against the review baseline"
    (SimplifiedChinese, FullDiffHint) =>
      "打开相对于审阅基准的完整差异"
    (Japanese, FullDiffHint) => "レビュー基準との差分全体を開く"
    (English, DeletedBaseline) => "Deleted · baseline"
    (SimplifiedChinese, DeletedBaseline) => "已删除 · 基准"
    (Japanese, DeletedBaseline) => "削除済み · 基準"
    (English, DeletedBaselineHint) =>
      "Deleted in the working tree; showing the review baseline"
    (SimplifiedChinese, DeletedBaselineHint) =>
      "工作树中已删除，正在显示审阅基准"
    (Japanese, DeletedBaselineHint) =>
      "ワークツリーでは削除済みのため、レビュー基準を表示しています"
    (English, WorkingUnavailable) => "Working unavailable · baseline"
    (SimplifiedChinese, WorkingUnavailable) => "工作副本不可用 · 基准"
    (Japanese, WorkingUnavailable) =>
      "作業コピーを取得できません · 基準"
    (English, WorkingUnavailableHint) =>
      "The working-tree file could not be read; showing the review baseline"
    (SimplifiedChinese, WorkingUnavailableHint) =>
      "无法读取工作树文件，正在显示审阅基准"
    (Japanese, WorkingUnavailableHint) =>
      "ワークツリーのファイルを読み取れないため、レビュー基準を表示しています"
    (English, DiffUnavailable) => "Diff unavailable"
    (SimplifiedChinese, DiffUnavailable) => "差异不可用"
    (Japanese, DiffUnavailable) => "差分を取得できません"
    (English, NotTextPreview) =>
      "The working-tree file cannot be previewed as text"
    (SimplifiedChinese, NotTextPreview) =>
      "工作树文件无法作为文本预览"
    (Japanese, NotTextPreview) =>
      "ワークツリーのファイルをテキストとしてプレビューできません"
    (English, DeletedNoBaseline) => "Deleted · no baseline"
    (SimplifiedChinese, DeletedNoBaseline) => "已删除 · 无基准"
    (Japanese, DeletedNoBaseline) => "削除済み · 基準なし"
    (English, NoBaseline) => "No review baseline is available to preview"
    (SimplifiedChinese, NoBaseline) => "没有可预览的审阅基准"
    (Japanese, NoBaseline) =>
      "プレビューできるレビュー基準がありません"
    (English, RenderedNoGutter) => "Rendered · no gutter"
    (SimplifiedChinese, RenderedNoGutter) => "已渲染 · 无差异边栏"
    (Japanese, RenderedNoGutter) =>
      "レンダリング表示 · 差分バーなし"
    (English, MarkdownGutterHint) =>
      "Rendered Markdown does not expose source diff decorations"
    (SimplifiedChinese, MarkdownGutterHint) =>
      "渲染后的 Markdown 不显示源码差异标记"
    (Japanese, MarkdownGutterHint) =>
      "レンダリングした Markdown ではソースの差分マークを表示しません"
    (English, NewMarkdownHint) =>
      "New Markdown has no review baseline; its rendered preview does not expose diff decorations"
    (SimplifiedChinese, NewMarkdownHint) =>
      "新 Markdown 文件没有审阅基准，渲染预览不显示差异标记"
    (Japanese, NewMarkdownHint) =>
      "新しい Markdown ファイルにはレビュー基準がなく、レンダリングプレビューに差分マークは表示されません"
    (English, DiffBaseline) => "Diff vs baseline"
    (SimplifiedChinese, DiffBaseline) => "相对于基准的差异"
    (Japanese, DiffBaseline) => "基準との差分"
    (English, QuickDiffBaseline) => "Quick diff against the review baseline"
    (SimplifiedChinese, QuickDiffBaseline) =>
      "相对于审阅基准的快速差异"
    (Japanese, QuickDiffBaseline) =>
      "レビュー基準とのクイック差分"
    (English, NewNoBaseline) => "New · no baseline"
    (SimplifiedChinese, NewNoBaseline) => "新文件 · 无基准"
    (Japanese, NewNoBaseline) => "新規ファイル · 基準なし"
    (English, NewBaselineHint) =>
      "New file compared with an empty review baseline"
    (SimplifiedChinese, NewBaselineHint) =>
      "将新文件与空审阅基准比较"
    (Japanese, NewBaselineHint) =>
      "新規ファイルを空のレビュー基準と比較"
    (English, BinaryBaseline) => "The review baseline is binary"
    (SimplifiedChinese, BinaryBaseline) => "审阅基准为二进制文件"
    (Japanese, BinaryBaseline) =>
      "レビュー基準はバイナリファイルです"
    (English, LargeBaseline) => "The review baseline is too large"
    (SimplifiedChinese, LargeBaseline) => "审阅基准过大"
    (Japanese, LargeBaseline) => "レビュー基準が大きすぎます"
    (English, BaselineFailedPrefix) => "Could not load review baseline: "
    (SimplifiedChinese, BaselineFailedPrefix) => "无法加载审阅基准："
    (Japanese, BaselineFailedPrefix) =>
      "レビュー基準を読み込めません："
    (English, FullDiff) => "Full diff"
    (SimplifiedChinese, FullDiff) => "完整差异"
    (Japanese, FullDiff) => "差分全体"
    (English, FilteringCommit) => "Filtering commit "
    (SimplifiedChinese, FilteringCommit) => "筛选提交 "
    (Japanese, FilteringCommit) => "コミットを絞り込み："
    (English, FilteringWorkingTree) => "Filtering working tree"
    (SimplifiedChinese, FilteringWorkingTree) => "筛选工作树"
    (Japanese, FilteringWorkingTree) => "ワークツリーを絞り込み"
    (English, FilterFilesPath) => "Filter files by path"
    (SimplifiedChinese, FilterFilesPath) => "按路径筛选文件"
    (Japanese, FilterFilesPath) => "パスでファイルを絞り込む"
    (English, FilterChangedPath) => "Filter changed files by path"
    (SimplifiedChinese, FilterChangedPath) => "按路径筛选更改的文件"
    (Japanese, FilterChangedPath) =>
      "パスで変更ファイルを絞り込む"
    (English, ClearFilters) => "Clear file filters"
    (SimplifiedChinese, ClearFilters) => "清除文件筛选条件"
    (Japanese, ClearFilters) => "ファイルのフィルターをクリア"
    (English, ClearLabel) => "Clear"
    (SimplifiedChinese, ClearLabel) => "清除"
    (Japanese, ClearLabel) => "クリア"
    (English, FileTypes) => "File types"
    (SimplifiedChinese, FileTypes) => "文件类型"
    (Japanese, FileTypes) => "ファイルの種類"
    (English, NoFileTypes) => "File types: none"
    (SimplifiedChinese, NoFileTypes) => "文件类型：无"
    (Japanese, NoFileTypes) => "ファイルの種類：なし"
    (English, FilterExtensionPrefix) => "Filter by file extension, "
    (SimplifiedChinese, FilterExtensionPrefix) => "按文件扩展名筛选，"
    (Japanese, FilterExtensionPrefix) => "拡張子で絞り込み、"
    (English, AllFileTypes) => "all file types"
    (SimplifiedChinese, AllFileTypes) => "所有文件类型"
    (Japanese, AllFileTypes) => "すべてのファイルの種類"
    (English, NoChangedTypes) => "No changed file types"
    (SimplifiedChinese, NoChangedTypes) => "没有更改的文件类型"
    (Japanese, NoChangedTypes) =>
      "変更されたファイルの種類はありません"
    (English, WholeFile) => "Whole file"
    (SimplifiedChinese, WholeFile) => "整个文件"
    (Japanese, WholeFile) => "ファイル全体"
    (English, LexicalFallback) => "Lexical fallback"
    (SimplifiedChinese, LexicalFallback) => "词法回退"
    (Japanese, LexicalFallback) => "字句比較にフォールバック"
    (English, SectioningFallback) => "Sectioning fallback"
    (SimplifiedChinese, SectioningFallback) => "分段回退"
    (Japanese, SectioningFallback) =>
      "セクション比較にフォールバック"
    (English, SectionLexicalFallback) => "Section lexical fallback"
    (SimplifiedChinese, SectionLexicalFallback) => "分段词法回退"
    (Japanese, SectionLexicalFallback) =>
      "セクションごとの字句比較にフォールバック"
    (English, SectionDiffFallback) => "Section diff fallback"
    (SimplifiedChinese, SectionDiffFallback) => "分段差异回退"
    (Japanese, SectionDiffFallback) =>
      "セクションごとの差分にフォールバック"
    (English, NoStructuralText) =>
      "No structural changes found. Switch to Token or Line to inspect text."
    (SimplifiedChinese, NoStructuralText) =>
      "未发现结构更改。切换到词元或行差异以检查文本。"
    (Japanese, NoStructuralText) =>
      "構造上の変更はありません。テキストを確認するにはトークン差分または行差分に切り替えてください。"
    (English, NoTokenChanges) => "No token changes found."
    (SimplifiedChinese, NoTokenChanges) => "未发现词元更改。"
    (Japanese, NoTokenChanges) => "トークンの変更はありません。"
    (English, NoStructuralToken) =>
      "No structural changes found. Switch to Token to view text changes."
    (SimplifiedChinese, NoStructuralToken) =>
      "未发现结构更改。切换到词元差异以查看文本更改。"
    (Japanese, NoStructuralToken) =>
      "構造上の変更はありません。テキストの変更を見るにはトークン差分に切り替えてください。"
    (English, NoDeclarationChanges) =>
      "No declaration-owned token changes found. Switch to Line to inspect the complete file."
    (SimplifiedChinese, NoDeclarationChanges) =>
      "未发现声明内的词元更改。切换到行差异以检查完整文件。"
    (Japanese, NoDeclarationChanges) =>
      "宣言内のトークンに変更はありません。ファイル全体を確認するには行差分に切り替えてください。"
    (English, ReorderedDeclarations) =>
      "Top-level declarations are reordered; each declaration keeps its own DiffEditor."
    (SimplifiedChinese, ReorderedDeclarations) =>
      "顶层声明顺序已调整，每个声明仍使用独立的差异视图。"
    (Japanese, ReorderedDeclarations) =>
      "最上位宣言の順序が変更されています。各宣言は個別の差分ビューで表示されます。"
    (English, NoSectionChanges) =>
      "No semantic section changes found. Switch to Line to inspect the complete file."
    (SimplifiedChinese, NoSectionChanges) =>
      "未发现语义分段更改。切换到行差异以检查完整文件。"
    (Japanese, NoSectionChanges) =>
      "セマンティックなセクション変更はありません。ファイル全体を確認するには行差分に切り替えてください。"
    (English, InvalidSemanticResult) =>
      "The semantic result was invalid. Switch to Line to inspect the complete file."
    (SimplifiedChinese, InvalidSemanticResult) =>
      "语义结果无效。切换到行差异以检查完整文件。"
    (Japanese, InvalidSemanticResult) =>
      "セマンティック解析の結果が無効です。ファイル全体を確認するには行差分に切り替えてください。"
  }
}
