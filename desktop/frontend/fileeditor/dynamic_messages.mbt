///|
priv enum DynamicMessage {
  DReviewedFiles(Int, Int)
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
    (English, DReviewedFiles(reviewed, total)) =>
      "\{reviewed} / \{total} reviewed"
    (SimplifiedChinese, DReviewedFiles(reviewed, total)) =>
      "已审阅 \{reviewed} / \{total}"
    (TraditionalChinese, DReviewedFiles(reviewed, total)) =>
      "已審閱 \{reviewed} / \{total}"
    (Japanese, DReviewedFiles(reviewed, total)) =>
      "\{reviewed} / \{total} レビュー済み"
    (Spanish, DReviewedFiles(reviewed, total)) =>
      "\{reviewed} / \{total} revisados"
    (English, DLoadingDiff(p0)) => "Loading diff for \{p0}…"
    (Spanish, DLoadingDiff(p0)) => "Cargando diferencias de \{p0}…"
    (SimplifiedChinese, DLoadingDiff(p0)) => "正在加载 \{p0} 的差异…"
    (TraditionalChinese, DLoadingDiff(p0)) => "正在載入 \{p0} 的差異…"
    (Japanese, DLoadingDiff(p0)) => "\{p0} の差分を読み込み中…"
    (English, DLoadingBaseline(p0)) =>
      "Loading the review baseline for \{p0}…"
    (Spanish, DLoadingBaseline(p0)) =>
      "Cargando la base de revisión de \{p0}…"
    (SimplifiedChinese, DLoadingBaseline(p0)) =>
      "正在加载 \{p0} 的审阅基准…"
    (TraditionalChinese, DLoadingBaseline(p0)) =>
      "正在載入 \{p0} 的審閱基準…"
    (Japanese, DLoadingBaseline(p0)) =>
      "\{p0} のレビュー基準を読み込み中…"
    (English, DBinaryBaseline(p0)) =>
      "The review baseline for \{p0} is binary and cannot be previewed."
    (Spanish, DBinaryBaseline(p0)) =>
      "La base de revisión de \{p0} es binaria y no se puede previsualizar."
    (SimplifiedChinese, DBinaryBaseline(p0)) =>
      "\{p0} 的审阅基准为二进制文件，无法预览。"
    (TraditionalChinese, DBinaryBaseline(p0)) =>
      "\{p0} 的審閱基準為二進位制檔案，無法預覽。"
    (Japanese, DBinaryBaseline(p0)) =>
      "\{p0} のレビュー基準はバイナリファイルのためプレビューできません。"
    (English, DLargeBaseline(p0)) =>
      "The review baseline for \{p0} is too large to preview."
    (Spanish, DLargeBaseline(p0)) =>
      "La base de revisión de \{p0} es demasiado grande para previsualizarla."
    (SimplifiedChinese, DLargeBaseline(p0)) =>
      "\{p0} 的审阅基准过大，无法预览。"
    (TraditionalChinese, DLargeBaseline(p0)) =>
      "\{p0} 的審閱基準過大，無法預覽。"
    (Japanese, DLargeBaseline(p0)) =>
      "\{p0} のレビュー基準は大きすぎるためプレビューできません。"
    (English, DBaselineFailed(p0, p1)) =>
      "Could not load the review baseline for \{p0}: \{p1}."
    (Spanish, DBaselineFailed(p0, p1)) =>
      "No se pudo cargar la base de revisión de \{p0}: \{p1}."
    (SimplifiedChinese, DBaselineFailed(p0, p1)) =>
      "无法加载 \{p0} 的审阅基准：\{p1}。"
    (TraditionalChinese, DBaselineFailed(p0, p1)) =>
      "無法載入 \{p0} 的審閱基準：\{p1}。"
    (Japanese, DBaselineFailed(p0, p1)) =>
      "\{p0} のレビュー基準を読み込めません：\{p1}。"
    (English, DReadFailed(p0, p1)) => "Could not read \{p0}: \{p1}."
    (Spanish, DReadFailed(p0, p1)) => "No se pudo leer \{p0}: \{p1}."
    (SimplifiedChinese, DReadFailed(p0, p1)) => "无法读取 \{p0}：\{p1}。"
    (TraditionalChinese, DReadFailed(p0, p1)) => "無法讀取 \{p0}：\{p1}。"
    (Japanese, DReadFailed(p0, p1)) =>
      "\{p0} を読み取れません：\{p1}。"
    (English, DLoadingHistoryDiff(p0)) => "Loading historical diff for \{p0}…"
    (Spanish, DLoadingHistoryDiff(p0)) =>
      "Cargando diferencias históricas de \{p0}…"
    (SimplifiedChinese, DLoadingHistoryDiff(p0)) =>
      "正在加载 \{p0} 的历史差异…"
    (TraditionalChinese, DLoadingHistoryDiff(p0)) =>
      "正在載入 \{p0} 的歷史差異…"
    (Japanese, DLoadingHistoryDiff(p0)) =>
      "\{p0} の履歴差分を読み込み中…"
    (English, DHistoryDiffFailed(p0, p1)) =>
      "Could not load historical diff for \{p0}: \{p1}."
    (Spanish, DHistoryDiffFailed(p0, p1)) =>
      "No se pudieron cargar las diferencias históricas de \{p0}: \{p1}."
    (SimplifiedChinese, DHistoryDiffFailed(p0, p1)) =>
      "无法加载 \{p0} 的历史差异：\{p1}。"
    (TraditionalChinese, DHistoryDiffFailed(p0, p1)) =>
      "無法載入 \{p0} 的歷史差異：\{p1}。"
    (Japanese, DHistoryDiffFailed(p0, p1)) =>
      "\{p0} の履歴差分を読み込めません：\{p1}。"
    (English, DHistoryFailed(p0)) => "Could not load Git history: \{p0}."
    (Spanish, DHistoryFailed(p0)) =>
      "No se pudo cargar el historial de Git: \{p0}."
    (SimplifiedChinese, DHistoryFailed(p0)) =>
      "无法加载 Git 历史：\{p0}。"
    (TraditionalChinese, DHistoryFailed(p0)) =>
      "無法載入 Git 歷史：\{p0}。"
    (Japanese, DHistoryFailed(p0)) =>
      "Git 履歴を読み込めません：\{p0}。"
    (English, DLoadMoreFailed(p0)) => "Could not load more: \{p0}"
    (Spanish, DLoadMoreFailed(p0)) => "No se pudo cargar más: \{p0}"
    (SimplifiedChinese, DLoadMoreFailed(p0)) => "无法加载更多：\{p0}"
    (TraditionalChinese, DLoadMoreFailed(p0)) => "無法載入更多：\{p0}"
    (Japanese, DLoadMoreFailed(p0)) =>
      "追加の項目を読み込めません：\{p0}"
    (English, DCommitFailed(p0)) => "Could not load this commit: \{p0}."
    (Spanish, DCommitFailed(p0)) => "No se pudo cargar este commit: \{p0}."
    (SimplifiedChinese, DCommitFailed(p0)) => "无法加载此提交：\{p0}。"
    (TraditionalChinese, DCommitFailed(p0)) =>
      "無法載入此提交：\{p0}。"
    (Japanese, DCommitFailed(p0)) =>
      "このコミットを読み込めません：\{p0}。"
    (English, DOpenHistoryDiff(p0)) => "Open historical diff for \{p0}"
    (Spanish, DOpenHistoryDiff(p0)) => "Abrir diferencias históricas de \{p0}"
    (SimplifiedChinese, DOpenHistoryDiff(p0)) => "打开 \{p0} 的历史差异"
    (TraditionalChinese, DOpenHistoryDiff(p0)) => "開啟 \{p0} 的歷史差異"
    (Japanese, DOpenHistoryDiff(p0)) => "\{p0} の履歴差分を開く"
    (English, DChangesFailed(p0)) =>
      "Could not load changed files: \{p0}. Click Changes to retry."
    (Spanish, DChangesFailed(p0)) =>
      "No se pudieron cargar los archivos modificados: \{p0}. Haz clic en Cambios para reintentar."
    (SimplifiedChinese, DChangesFailed(p0)) =>
      "无法加载更改的文件：\{p0}。点击“更改”重试。"
    (TraditionalChinese, DChangesFailed(p0)) =>
      "無法載入更改的檔案：\{p0}。點選“更改”重試。"
    (Japanese, DChangesFailed(p0)) =>
      "変更したファイルを読み込めません：\{p0}。「変更」をクリックして再試行してください。"
    (English, DShowFiles(p0)) => "Show files in \{p0}"
    (Spanish, DShowFiles(p0)) => "Mostrar archivos de \{p0}"
    (SimplifiedChinese, DShowFiles(p0)) => "显示 \{p0} 中的文件"
    (TraditionalChinese, DShowFiles(p0)) => "顯示 \{p0} 中的檔案"
    (Japanese, DShowFiles(p0)) => "\{p0} 内のファイルを表示"
    (English, DFilePosition(p0, p1)) => "File \{p0} of \{p1}"
    (Spanish, DFilePosition(p0, p1)) => "Archivo \{p0} de \{p1}"
    (SimplifiedChinese, DFilePosition(p0, p1)) => "第 \{p0}/\{p1} 个文件"
    (TraditionalChinese, DFilePosition(p0, p1)) => "第 \{p0}/\{p1} 個檔案"
    (Japanese, DFilePosition(p0, p1)) => "ファイル \{p0}/\{p1}"
    (English, DHunkPosition(p0, p1)) => "Hunk \{p0} of \{p1}"
    (Spanish, DHunkPosition(p0, p1)) => "Bloque \{p0} de \{p1}"
    (SimplifiedChinese, DHunkPosition(p0, p1)) => "第 \{p0}/\{p1} 个差异块"
    (TraditionalChinese, DHunkPosition(p0, p1)) =>
      "第 \{p0}/\{p1} 個差異塊"
    (Japanese, DHunkPosition(p0, p1)) => "差分ブロック \{p0}/\{p1}"
    (English, DChangePosition(p0, p1)) => "Change \{p0} of \{p1}"
    (Spanish, DChangePosition(p0, p1)) => "Cambio \{p0} de \{p1}"
    (SimplifiedChinese, DChangePosition(p0, p1)) => "第 \{p0}/\{p1} 处更改"
    (TraditionalChinese, DChangePosition(p0, p1)) => "第 \{p0}/\{p1} 處更改"
    (Japanese, DChangePosition(p0, p1)) => "変更 \{p0}/\{p1}"
    (English, DFolderFailed(p0)) => "Could not load this folder: \{p0}"
    (Spanish, DFolderFailed(p0)) => "No se pudo cargar esta carpeta: \{p0}"
    (SimplifiedChinese, DFolderFailed(p0)) => "无法加载此文件夹：\{p0}"
    (TraditionalChinese, DFolderFailed(p0)) =>
      "無法載入此資料夾：\{p0}"
    (Japanese, DFolderFailed(p0)) =>
      "このフォルダーを読み込めません：\{p0}"
    (English, DFilesIn(p0)) => "Files in \{p0}"
    (Spanish, DFilesIn(p0)) => "Archivos de \{p0}"
    (SimplifiedChinese, DFilesIn(p0)) => "\{p0} 中的文件"
    (TraditionalChinese, DFilesIn(p0)) => "\{p0} 中的檔案"
    (Japanese, DFilesIn(p0)) => "\{p0} 内のファイル"
    (English, DShowingFiles(p0, p1)) => "Showing \{p0} of \{p1} files"
    (Spanish, DShowingFiles(p0, p1)) => "Mostrando \{p0} de \{p1} archivos"
    (SimplifiedChinese, DShowingFiles(p0, p1)) => "显示 \{p0}/\{p1} 个文件"
    (TraditionalChinese, DShowingFiles(p0, p1)) =>
      "顯示 \{p0}/\{p1} 個檔案"
    (Japanese, DShowingFiles(p0, p1)) => "\{p0}/\{p1} ファイルを表示"
    (English, DTopLevel(p0)) => "Top-level #\{p0}"
    (Spanish, DTopLevel(p0)) => "Nivel superior n.º \{p0}"
    (SimplifiedChinese, DTopLevel(p0)) => "顶层声明 #\{p0}"
    (TraditionalChinese, DTopLevel(p0)) => "頂層宣告 #\{p0}"
    (Japanese, DTopLevel(p0)) => "最上位宣言 #\{p0}"
    (English, DExpand(p0)) => "Expand \{p0}"
    (Spanish, DExpand(p0)) => "Expandir \{p0}"
    (SimplifiedChinese, DExpand(p0)) => "展开 \{p0}"
    (TraditionalChinese, DExpand(p0)) => "展開 \{p0}"
    (Japanese, DExpand(p0)) => "\{p0} を展開"
    (English, DCollapse(p0)) => "Collapse \{p0}"
    (Spanish, DCollapse(p0)) => "Contraer \{p0}"
    (SimplifiedChinese, DCollapse(p0)) => "折叠 \{p0}"
    (TraditionalChinese, DCollapse(p0)) => "摺疊 \{p0}"
    (Japanese, DCollapse(p0)) => "\{p0} を折りたたむ"
    (English, DIgnoredChanges(p0)) =>
      "No changes besides ignored \{p0} were found. Turn off the relevant Ignore filter to view them."
    (Spanish, DIgnoredChanges(p0)) =>
      "Solo se encontraron cambios en \{p0} que se han ignorado. Desactiva el filtro correspondiente para verlos."
    (SimplifiedChinese, DIgnoredChanges(p0)) =>
      "除已忽略的\{p0}外，未发现其他更改。关闭相应的忽略筛选条件即可查看。"
    (TraditionalChinese, DIgnoredChanges(p0)) =>
      "除已忽略的\{p0}外，未發現其他更改。關閉相應的忽略篩選條件即可檢視。"
    (Japanese, DIgnoredChanges(p0)) =>
      "無視された\{p0}以外に変更はありません。表示するには該当する無視フィルターを無効にしてください。"
  }
}
