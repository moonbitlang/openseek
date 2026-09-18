// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
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
    (English, NoCommitContent) =>
      "No file content exists on either side of this commit."
    (SimplifiedChinese, NoCommitContent) =>
      "此提交的两侧均无文件内容。"
    (English, WaitingPlacement) => "Waiting for workspace placement…"
    (SimplifiedChinese, WaitingPlacement) => "正在等待工作区就绪…"
    (English, MissingCheckout) => "Worktree checkout is missing."
    (SimplifiedChinese, MissingCheckout) => "工作树检出目录缺失。"
    (English, NoConversation) => "No conversation selected."
    (SimplifiedChinese, NoConversation) => "未选择对话。"
    (English, ExplorerViews) => "Explorer views"
    (SimplifiedChinese, ExplorerViews) => "资源管理器视图"
    (English, WorkspaceFiles) => "Workspace files"
    (SimplifiedChinese, WorkspaceFiles) => "工作区文件"
    (English, FilesLabel) => "Files"
    (SimplifiedChinese, FilesLabel) => "文件"
    (English, ChangedFilesHint) => "Changed files (click again to refresh)"
    (SimplifiedChinese, ChangedFilesHint) =>
      "更改的文件（再次点击刷新）"
    (English, ChangesLabel) => "Changes"
    (SimplifiedChinese, ChangesLabel) => "更改"
    (English, SearchWorkspace) => "Search across the workspace"
    (SimplifiedChinese, SearchWorkspace) => "搜索整个工作区"
    (English, SearchLabel) => "Search"
    (SimplifiedChinese, SearchLabel) => "搜索"
    (English, ResizeGraph) => "Resize Changes and Git Graph"
    (SimplifiedChinese, ResizeGraph) => "调整更改列表和 Git 图的大小"
    (English, GraphLabel) => "Graph"
    (SimplifiedChinese, GraphLabel) => "提交图"
    (English, RefreshGraph) => "Refresh Git Graph"
    (SimplifiedChinese, RefreshGraph) => "刷新 Git 图"
    (English, RepositoryLabel) => "Repository"
    (SimplifiedChinese, RepositoryLabel) => "仓库"
    (English, NoCommits) => "No commits"
    (SimplifiedChinese, NoCommits) => "没有提交"
    (English, LoadingHistory) => "Loading Git history…"
    (SimplifiedChinese, LoadingHistory) => "正在加载 Git 历史…"
    (English, RetryLabel) => "Retry"
    (SimplifiedChinese, RetryLabel) => "重试"
    (English, GitUnavailable) =>
      "Git is unavailable or this workspace is not a Git repository."
    (SimplifiedChinese, GitUnavailable) =>
      "Git 不可用，或此工作区不是 Git 仓库。"
    (English, EmptyBranch) => "This branch has no commits."
    (SimplifiedChinese, EmptyBranch) => "此分支没有提交。"
    (English, LoadingLabel) => "Loading…"
    (SimplifiedChinese, LoadingLabel) => "正在加载…"
    (English, LoadMore) => "Load more"
    (SimplifiedChinese, LoadMore) => "加载更多"
    (English, CommitHistory) => "Git commit history"
    (SimplifiedChinese, CommitHistory) => "Git 提交历史"
    (English, LoadingChangedFiles) => "Loading changed files…"
    (SimplifiedChinese, LoadingChangedFiles) => "正在加载更改的文件…"
    (English, NoWorkspaceChanges) => "No changes in this workspace."
    (SimplifiedChinese, NoWorkspaceChanges) => "此工作区没有更改。"
    (English, NoFilterMatches) => "No files match these filters."
    (SimplifiedChinese, NoFilterMatches) =>
      "没有符合筛选条件的文件。"
    (English, SubmoduleDiff) => "Git submodule cannot be shown as a text diff"
    (SimplifiedChinese, SubmoduleDiff) =>
      "Git 子模块无法显示为文本差异"
    (English, SymlinkDiff) => "Git symlink cannot be shown as a text diff"
    (SimplifiedChinese, SymlinkDiff) =>
      "Git 符号链接无法显示为文本差异"
    (English, PathOutsideWorkspace) => "Original path is outside this workspace"
    (SimplifiedChinese, PathOutsideWorkspace) =>
      "原始路径位于此工作区之外"
    (English, EmptyWorkspace) => "This workspace is empty."
    (SimplifiedChinese, EmptyWorkspace) => "此工作区为空。"
    (English, LoadingChanges) => "Loading changes…"
    (SimplifiedChinese, LoadingChanges) => "正在加载更改…"
    (English, NoChangedFiles) => "No changed files."
    (SimplifiedChinese, NoChangedFiles) => "没有更改的文件。"
    (English, NoReviewableFiles) => "No reviewable text files"
    (SimplifiedChinese, NoReviewableFiles) => "没有可审阅的文本文件"
    (English, ChangedFiles) => "Changed files"
    (SimplifiedChinese, ChangedFiles) => "更改的文件"
    (English, ViewDiffPrefix) => "View diff: "
    (SimplifiedChinese, ViewDiffPrefix) => "查看差异："
    (English, OpenDiffPrefix) => "Open diff — "
    (SimplifiedChinese, OpenDiffPrefix) => "打开差异 — "
    (English, MarkUnreviewed) => "Mark unreviewed"
    (SimplifiedChinese, MarkUnreviewed) => "标为未审阅"
    (English, MarkReviewed) => "Mark reviewed"
    (SimplifiedChinese, MarkReviewed) => "标为已审阅"
    (English, ReviewedPrefix) => "Reviewed: "
    (SimplifiedChinese, ReviewedPrefix) => "已审阅："
    (English, HideFileTree) => "Hide file tree"
    (SimplifiedChinese, HideFileTree) => "隐藏文件树"
    (English, ShowFileTree) => "Show file tree"
    (SimplifiedChinese, ShowFileTree) => "显示文件树"
    (English, WorkspaceLabel) => "Workspace"
    (SimplifiedChinese, WorkspaceLabel) => "工作区"
    (English, DiagramLabel) => "Diagram"
    (SimplifiedChinese, DiagramLabel) => "图表"
    (English, SourceLabel) => "Source"
    (SimplifiedChinese, SourceLabel) => "源码"
    (English, MoonModuleView) => "Moon module view"
    (SimplifiedChinese, MoonModuleView) => "Moon 模块视图"
    (English, DependencyGraph) => "Dependency graph"
    (SimplifiedChinese, DependencyGraph) => "依赖图"
    (English, LineLabel) => "Line"
    (SimplifiedChinese, LineLabel) => "行"
    (English, TokenLabel) => "Token"
    (SimplifiedChinese, TokenLabel) => "词元"
    (English, TreeLabel) => "Tree"
    (SimplifiedChinese, TreeLabel) => "语法树"
    (English, ShowFile) => "Show file"
    (SimplifiedChinese, ShowFile) => "显示文件"
    (English, FileView) => "File view"
    (SimplifiedChinese, FileView) => "文件视图"
    (English, FileLabel) => "File"
    (SimplifiedChinese, FileLabel) => "文件"
    (English, ReviewMode) => "Review mode"
    (SimplifiedChinese, ReviewMode) => "审阅模式"
    (English, ComparisonAlgorithm) => "Comparison algorithm"
    (SimplifiedChinese, ComparisonAlgorithm) => "比较算法"
    (English, AvailableDiff) => "Available in diff view"
    (SimplifiedChinese, AvailableDiff) => "在差异视图中可用"
    (English, AvailableTokenTree) => "Available in Token and Tree diff"
    (SimplifiedChinese, AvailableTokenTree) =>
      "在词元和语法树差异中可用"
    (English, IncludeComments) => "Include comments in the comparison"
    (SimplifiedChinese, IncludeComments) => "比较时包含注释"
    (English, IgnoreCommentChanges) => "Ignore comment-only changes"
    (SimplifiedChinese, IgnoreCommentChanges) =>
      "忽略仅涉及注释的更改"
    (English, IgnoreComments) => "Ignore comments"
    (SimplifiedChinese, IgnoreComments) => "忽略注释"
    (English, CommentsIgnored) => "Comments: ignored"
    (SimplifiedChinese, CommentsIgnored) => "注释：已忽略"
    (English, CommentsIncluded) => "Comments: included"
    (SimplifiedChinese, CommentsIncluded) => "注释：已包含"
    (English, IncludeTests) => "Include tests in the comparison"
    (SimplifiedChinese, IncludeTests) => "比较时包含测试"
    (English, IgnoreTestBlocks) => "Ignore MoonBit test blocks"
    (SimplifiedChinese, IgnoreTestBlocks) => "忽略 MoonBit 测试块"
    (English, IgnoreTests) => "Ignore tests"
    (SimplifiedChinese, IgnoreTests) => "忽略测试"
    (English, TestsIgnored) => "Tests: ignored"
    (SimplifiedChinese, TestsIgnored) => "测试：已忽略"
    (English, TestsIncluded) => "Tests: included"
    (SimplifiedChinese, TestsIncluded) => "测试：已包含"
    (English, PreviousChangeShortcut) => "Previous change (Shift+F7)"
    (SimplifiedChinese, PreviousChangeShortcut) =>
      "上一处更改（Shift+F7）"
    (English, PreviousChange) => "Previous change"
    (SimplifiedChinese, PreviousChange) => "上一处更改"
    (English, NextChangeShortcut) => "Next change (F7)"
    (SimplifiedChinese, NextChangeShortcut) => "下一处更改（F7）"
    (English, NextChange) => "Next change"
    (SimplifiedChinese, NextChange) => "下一处更改"
    (English, DiffNavigation) => "Diff change navigation"
    (SimplifiedChinese, DiffNavigation) => "差异更改导航"
    (English, FileReviewed) => "File is marked reviewed"
    (SimplifiedChinese, FileReviewed) => "文件已标为已审阅"
    (English, MarkHunkUnviewed) => "Mark this hunk unviewed"
    (SimplifiedChinese, MarkHunkUnviewed) => "将此差异块标为未查看"
    (English, MarkHunkViewed) => "Mark this hunk viewed"
    (SimplifiedChinese, MarkHunkViewed) => "将此差异块标为已查看"
    (English, HunkViewed) => "Hunk viewed"
    (SimplifiedChinese, HunkViewed) => "差异块已查看"
    (English, UnmarkHunkViewed) => "Unmark hunk viewed"
    (SimplifiedChinese, UnmarkHunkViewed) => "取消差异块已查看标记"
    (English, MarkHunkViewedLabel) => "Mark hunk viewed"
    (SimplifiedChinese, MarkHunkViewedLabel) => "标记差异块已查看"
    (English, MarkViewed) => "Mark viewed"
    (SimplifiedChinese, MarkViewed) => "标为已查看"
    (English, DiffLayout) => "Diff layout"
    (SimplifiedChinese, DiffLayout) => "差异布局"
    (English, SideBySideHint) => "Use side-by-side diff layout"
    (SimplifiedChinese, SideBySideHint) => "使用并排差异布局"
    (English, SplitDiffLayout) => "Split diff layout"
    (SimplifiedChinese, SplitDiffLayout) => "并排差异布局"
    (English, SplitLabel) => "Split"
    (SimplifiedChinese, SplitLabel) => "并排"
    (English, UnifiedDiffHint) => "Use unified diff layout"
    (SimplifiedChinese, UnifiedDiffHint) => "使用统一差异布局"
    (English, UnifiedDiffLayout) => "Unified diff layout"
    (SimplifiedChinese, UnifiedDiffLayout) => "统一差异布局"
    (English, UnifiedLabel) => "Unified"
    (SimplifiedChinese, UnifiedLabel) => "统一"
    (English, EmptyFolder) => "This folder is empty."
    (SimplifiedChinese, EmptyFolder) => "此文件夹为空。"
    (English, CannotLoadFolder) => "Could not load this folder."
    (SimplifiedChinese, CannotLoadFolder) => "无法加载此文件夹。"
    (English, RefreshingLabel) => "Refreshing…"
    (SimplifiedChinese, RefreshingLabel) => "正在刷新…"
    (English, ReturnReviewQueue) =>
      "Return this changed file to the review queue"
    (SimplifiedChinese, ReturnReviewQueue) =>
      "将此更改文件放回审阅队列"
    (English, MarkChangedReviewed) => "Mark this changed file as reviewed"
    (SimplifiedChinese, MarkChangedReviewed) =>
      "将此更改文件标为已审阅"
    (English, MarkFileUnreviewed) => "Mark file unreviewed"
    (SimplifiedChinese, MarkFileUnreviewed) => "将文件标为未审阅"
    (English, MarkFileReviewed) => "Mark file reviewed"
    (SimplifiedChinese, MarkFileReviewed) => "将文件标为已审阅"
    (English, ViewFile) => "View file"
    (SimplifiedChinese, ViewFile) => "查看文件"
    (English, ReturnSourcePreview) =>
      "Return to the source preview and quick-diff gutter"
    (SimplifiedChinese, ReturnSourcePreview) =>
      "返回源码预览和快速差异边栏"
    (English, ViewFullDiff) => "View full diff"
    (SimplifiedChinese, ViewFullDiff) => "查看完整差异"
    (English, FullDiffHint) => "Open the full diff against the review baseline"
    (SimplifiedChinese, FullDiffHint) =>
      "打开相对于审阅基准的完整差异"
    (English, DeletedBaseline) => "Deleted · baseline"
    (SimplifiedChinese, DeletedBaseline) => "已删除 · 基准"
    (English, DeletedBaselineHint) =>
      "Deleted in the working tree; showing the review baseline"
    (SimplifiedChinese, DeletedBaselineHint) =>
      "工作树中已删除，正在显示审阅基准"
    (English, WorkingUnavailable) => "Working unavailable · baseline"
    (SimplifiedChinese, WorkingUnavailable) => "工作副本不可用 · 基准"
    (English, WorkingUnavailableHint) =>
      "The working-tree file could not be read; showing the review baseline"
    (SimplifiedChinese, WorkingUnavailableHint) =>
      "无法读取工作树文件，正在显示审阅基准"
    (English, DiffUnavailable) => "Diff unavailable"
    (SimplifiedChinese, DiffUnavailable) => "差异不可用"
    (English, NotTextPreview) =>
      "The working-tree file cannot be previewed as text"
    (SimplifiedChinese, NotTextPreview) =>
      "工作树文件无法作为文本预览"
    (English, DeletedNoBaseline) => "Deleted · no baseline"
    (SimplifiedChinese, DeletedNoBaseline) => "已删除 · 无基准"
    (English, NoBaseline) => "No review baseline is available to preview"
    (SimplifiedChinese, NoBaseline) => "没有可预览的审阅基准"
    (English, RenderedNoGutter) => "Rendered · no gutter"
    (SimplifiedChinese, RenderedNoGutter) => "已渲染 · 无差异边栏"
    (English, MarkdownGutterHint) =>
      "Rendered Markdown does not expose source diff decorations"
    (SimplifiedChinese, MarkdownGutterHint) =>
      "渲染后的 Markdown 不显示源码差异标记"
    (English, NewMarkdownHint) =>
      "New Markdown has no review baseline; its rendered preview does not expose diff decorations"
    (SimplifiedChinese, NewMarkdownHint) =>
      "新 Markdown 文件没有审阅基准，渲染预览不显示差异标记"
    (English, DiffBaseline) => "Diff vs baseline"
    (SimplifiedChinese, DiffBaseline) => "相对于基准的差异"
    (English, QuickDiffBaseline) => "Quick diff against the review baseline"
    (SimplifiedChinese, QuickDiffBaseline) =>
      "相对于审阅基准的快速差异"
    (English, NewNoBaseline) => "New · no baseline"
    (SimplifiedChinese, NewNoBaseline) => "新文件 · 无基准"
    (English, NewBaselineHint) =>
      "New file compared with an empty review baseline"
    (SimplifiedChinese, NewBaselineHint) =>
      "将新文件与空审阅基准比较"
    (English, BinaryBaseline) => "The review baseline is binary"
    (SimplifiedChinese, BinaryBaseline) => "审阅基准为二进制文件"
    (English, LargeBaseline) => "The review baseline is too large"
    (SimplifiedChinese, LargeBaseline) => "审阅基准过大"
    (English, BaselineFailedPrefix) => "Could not load review baseline: "
    (SimplifiedChinese, BaselineFailedPrefix) => "无法加载审阅基准："
    (English, FullDiff) => "Full diff"
    (SimplifiedChinese, FullDiff) => "完整差异"
    (English, FilteringCommit) => "Filtering commit "
    (SimplifiedChinese, FilteringCommit) => "筛选提交 "
    (English, FilteringWorkingTree) => "Filtering working tree"
    (SimplifiedChinese, FilteringWorkingTree) => "筛选工作树"
    (English, FilterFilesPath) => "Filter files by path"
    (SimplifiedChinese, FilterFilesPath) => "按路径筛选文件"
    (English, FilterChangedPath) => "Filter changed files by path"
    (SimplifiedChinese, FilterChangedPath) => "按路径筛选更改的文件"
    (English, ClearFilters) => "Clear file filters"
    (SimplifiedChinese, ClearFilters) => "清除文件筛选条件"
    (English, ClearLabel) => "Clear"
    (SimplifiedChinese, ClearLabel) => "清除"
    (English, FileTypes) => "File types"
    (SimplifiedChinese, FileTypes) => "文件类型"
    (English, NoFileTypes) => "File types: none"
    (SimplifiedChinese, NoFileTypes) => "文件类型：无"
    (English, FilterExtensionPrefix) => "Filter by file extension, "
    (SimplifiedChinese, FilterExtensionPrefix) => "按文件扩展名筛选，"
    (English, AllFileTypes) => "all file types"
    (SimplifiedChinese, AllFileTypes) => "所有文件类型"
    (English, NoChangedTypes) => "No changed file types"
    (SimplifiedChinese, NoChangedTypes) => "没有更改的文件类型"
    (English, WholeFile) => "Whole file"
    (SimplifiedChinese, WholeFile) => "整个文件"
    (English, LexicalFallback) => "Lexical fallback"
    (SimplifiedChinese, LexicalFallback) => "词法回退"
    (English, SectioningFallback) => "Sectioning fallback"
    (SimplifiedChinese, SectioningFallback) => "分段回退"
    (English, SectionLexicalFallback) => "Section lexical fallback"
    (SimplifiedChinese, SectionLexicalFallback) => "分段词法回退"
    (English, SectionDiffFallback) => "Section diff fallback"
    (SimplifiedChinese, SectionDiffFallback) => "分段差异回退"
    (English, NoStructuralText) =>
      "No structural changes found. Switch to Token or Line to inspect text."
    (SimplifiedChinese, NoStructuralText) =>
      "未发现结构更改。切换到词元或行差异以检查文本。"
    (English, NoTokenChanges) => "No token changes found."
    (SimplifiedChinese, NoTokenChanges) => "未发现词元更改。"
    (English, NoStructuralToken) =>
      "No structural changes found. Switch to Token to view text changes."
    (SimplifiedChinese, NoStructuralToken) =>
      "未发现结构更改。切换到词元差异以查看文本更改。"
    (English, NoDeclarationChanges) =>
      "No declaration-owned token changes found. Switch to Line to inspect the complete file."
    (SimplifiedChinese, NoDeclarationChanges) =>
      "未发现声明内的词元更改。切换到行差异以检查完整文件。"
    (English, ReorderedDeclarations) =>
      "Top-level declarations are reordered; each declaration keeps its own DiffEditor."
    (SimplifiedChinese, ReorderedDeclarations) =>
      "顶层声明顺序已调整，每个声明仍使用独立的差异视图。"
    (English, NoSectionChanges) =>
      "No semantic section changes found. Switch to Line to inspect the complete file."
    (SimplifiedChinese, NoSectionChanges) =>
      "未发现语义分段更改。切换到行差异以检查完整文件。"
    (English, InvalidSemanticResult) =>
      "The semantic result was invalid. Switch to Line to inspect the complete file."
    (SimplifiedChinese, InvalidSemanticResult) =>
      "语义结果无效。切换到行差异以检查完整文件。"
  }
}
