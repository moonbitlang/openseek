///|
priv enum DynamicMessage {
  DLoadingDiff(String)
  DLoadingBaseline(String)
  DBinaryBaseline(String)
  DLargeBaseline(String)
  DBaselineFailed(String, String)
  DReadFailed(String, String)
  DLoadingHistoryDiff(String)
  DHistoryDiffFailed(String, String)
  DHistoryFailed(String)
  DLoadMoreFailed(String)
  DCommitFailed(String)
  DOpenHistoryDiff(String)
  DChangesFailed(String)
  DShowFiles(String)
  DFilePosition(String, String)
  DHunkPosition(String, String)
  DChangePosition(String, String)
  DFolderFailed(String)
  DFilesIn(String)
  DShowingFiles(String, String)
  DTopLevel(String)
  DExpand(String)
  DCollapse(String)
  DIgnoredChanges(String)
}

///|
fn dynamic_text(locale : @i18n.Locale, message : DynamicMessage) -> String {
  match (locale, message) {
    (English, DLoadingDiff(p0)) => "Loading diff for \{p0}…"
    (SimplifiedChinese, DLoadingDiff(p0)) => "正在加载 \{p0} 的差异…"
    (English, DLoadingBaseline(p0)) =>
      "Loading the review baseline for \{p0}…"
    (SimplifiedChinese, DLoadingBaseline(p0)) =>
      "正在加载 \{p0} 的审阅基准…"
    (English, DBinaryBaseline(p0)) =>
      "The review baseline for \{p0} is binary and cannot be previewed."
    (SimplifiedChinese, DBinaryBaseline(p0)) =>
      "\{p0} 的审阅基准为二进制文件，无法预览。"
    (English, DLargeBaseline(p0)) =>
      "The review baseline for \{p0} is too large to preview."
    (SimplifiedChinese, DLargeBaseline(p0)) =>
      "\{p0} 的审阅基准过大，无法预览。"
    (English, DBaselineFailed(p0, p1)) =>
      "Could not load the review baseline for \{p0}: \{p1}."
    (SimplifiedChinese, DBaselineFailed(p0, p1)) =>
      "无法加载 \{p0} 的审阅基准：\{p1}。"
    (English, DReadFailed(p0, p1)) => "Could not read \{p0}: \{p1}."
    (SimplifiedChinese, DReadFailed(p0, p1)) => "无法读取 \{p0}：\{p1}。"
    (English, DLoadingHistoryDiff(p0)) => "Loading historical diff for \{p0}…"
    (SimplifiedChinese, DLoadingHistoryDiff(p0)) =>
      "正在加载 \{p0} 的历史差异…"
    (English, DHistoryDiffFailed(p0, p1)) =>
      "Could not load historical diff for \{p0}: \{p1}."
    (SimplifiedChinese, DHistoryDiffFailed(p0, p1)) =>
      "无法加载 \{p0} 的历史差异：\{p1}。"
    (English, DHistoryFailed(p0)) => "Could not load Git history: \{p0}."
    (SimplifiedChinese, DHistoryFailed(p0)) =>
      "无法加载 Git 历史：\{p0}。"
    (English, DLoadMoreFailed(p0)) => "Could not load more: \{p0}"
    (SimplifiedChinese, DLoadMoreFailed(p0)) => "无法加载更多：\{p0}"
    (English, DCommitFailed(p0)) => "Could not load this commit: \{p0}."
    (SimplifiedChinese, DCommitFailed(p0)) => "无法加载此提交：\{p0}。"
    (English, DOpenHistoryDiff(p0)) => "Open historical diff for \{p0}"
    (SimplifiedChinese, DOpenHistoryDiff(p0)) => "打开 \{p0} 的历史差异"
    (English, DChangesFailed(p0)) =>
      "Could not load changed files: \{p0}. Click Changes to retry."
    (SimplifiedChinese, DChangesFailed(p0)) =>
      "无法加载更改的文件：\{p0}。点击“更改”重试。"
    (English, DShowFiles(p0)) => "Show files in \{p0}"
    (SimplifiedChinese, DShowFiles(p0)) => "显示 \{p0} 中的文件"
    (English, DFilePosition(p0, p1)) => "File \{p0} of \{p1}"
    (SimplifiedChinese, DFilePosition(p0, p1)) => "第 \{p0}/\{p1} 个文件"
    (English, DHunkPosition(p0, p1)) => "Hunk \{p0} of \{p1}"
    (SimplifiedChinese, DHunkPosition(p0, p1)) => "第 \{p0}/\{p1} 个差异块"
    (English, DChangePosition(p0, p1)) => "Change \{p0} of \{p1}"
    (SimplifiedChinese, DChangePosition(p0, p1)) => "第 \{p0}/\{p1} 处更改"
    (English, DFolderFailed(p0)) => "Could not load this folder: \{p0}"
    (SimplifiedChinese, DFolderFailed(p0)) => "无法加载此文件夹：\{p0}"
    (English, DFilesIn(p0)) => "Files in \{p0}"
    (SimplifiedChinese, DFilesIn(p0)) => "\{p0} 中的文件"
    (English, DShowingFiles(p0, p1)) => "Showing \{p0} of \{p1} files"
    (SimplifiedChinese, DShowingFiles(p0, p1)) => "显示 \{p0}/\{p1} 个文件"
    (English, DTopLevel(p0)) => "Top-level #\{p0}"
    (SimplifiedChinese, DTopLevel(p0)) => "顶层声明 #\{p0}"
    (English, DExpand(p0)) => "Expand \{p0}"
    (SimplifiedChinese, DExpand(p0)) => "展开 \{p0}"
    (English, DCollapse(p0)) => "Collapse \{p0}"
    (SimplifiedChinese, DCollapse(p0)) => "折叠 \{p0}"
    (English, DIgnoredChanges(p0)) =>
      "No changes besides ignored \{p0} were found. Turn off the relevant Ignore filter to view them."
    (SimplifiedChinese, DIgnoredChanges(p0)) =>
      "除已忽略的\{p0}外，未发现其他更改。关闭相应的忽略筛选条件即可查看。"
  }
}
