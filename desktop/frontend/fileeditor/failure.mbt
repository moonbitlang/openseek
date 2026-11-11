///|
/// File-operation causes stay semantic until the current locale is rendered.
#derive(Eq, Debug)
pub(all) enum Failure {
  CloudFileOwnershipLost
  CloudDirectoryOwnershipLost
  HostFileOwnerChanged
  HostDirectoryOwnerChanged
  SavedButNotRevealed(String)
  BrowserDownloadFailed
  Cloud(@cloud_client.Failure)
  Bridge(@interop.BridgeProblem)
  FileWatchingFailed(@interop.BridgeProblem)
  DefinitionFailed(@interop.BridgeProblem)
  ReferencesFailed(@interop.BridgeProblem)
  CaptureUnavailable
  CaptureSubmissionDeclined
  Diagnostic(String)
  OfficeCitationUnavailable
  ExcelCopyTooLarge
  OfficeSelectionFailed
  OfficePreviewFailed
  PdfPreviewFailed
}

///|
pub extend Failure with Eq::{equal, not_equal}

///|
pub extend Failure with Debug::{to_repr}

///|
pub fn Failure::text(self : Failure, locale : @i18n.Locale) -> String {
  match self {
    CloudFileOwnershipLost =>
      match locale {
        English => "Cloud file no longer belongs to this conversation."
        SimplifiedChinese => "云端文件已不再属于此对话。"
        TraditionalChinese => "雲端檔案已不再屬於此對話。"
        Japanese =>
          "クラウドファイルはこの会話に属していません。"
        Spanish => "El archivo de Cloud ya no pertenece a esta conversación."
      }
    CloudDirectoryOwnershipLost =>
      match locale {
        English => "Cloud directory no longer belongs to this conversation."
        SimplifiedChinese => "云端目录已不再属于此对话。"
        TraditionalChinese => "雲端目錄已不再屬於此對話。"
        Japanese =>
          "クラウドディレクトリはこの会話に属していません。"
        Spanish =>
          "El directorio de Cloud ya no pertenece a esta conversación."
      }
    HostFileOwnerChanged =>
      match locale {
        English => "file root moved to another host before file read"
        SimplifiedChinese =>
          "读取文件前，文件根目录已移至另一台主机"
        TraditionalChinese =>
          "讀取檔案前，檔案根目錄已移至另一台主機"
        Japanese =>
          "ファイルの読み取り前に、ファイルのルートが別のホストに移動しました"
        Spanish =>
          "la raíz de archivos se trasladó a otro host antes de leer el archivo"
      }
    HostDirectoryOwnerChanged =>
      match locale {
        English => "file root moved to another host before directory read"
        SimplifiedChinese =>
          "读取目录前，文件根目录已移至另一台主机"
        TraditionalChinese =>
          "讀取目錄前，檔案根目錄已移至另一台主機"
        Japanese =>
          "ディレクトリの読み取り前に、ファイルのルートが別のホストに移動しました"
        Spanish =>
          "la raíz de archivos se trasladó a otro host antes de leer el directorio"
      }
    SavedButNotRevealed(path) =>
      match locale {
        English => "Saved to \{path}, but could not show the downloaded file."
        SimplifiedChinese =>
          "已保存到 \{path}，但无法显示下载的文件。"
        TraditionalChinese =>
          "已儲存至 \{path}，但無法顯示下載的檔案。"
        Japanese =>
          "\{path} に保存しましたが、ダウンロードしたファイルを表示できませんでした。"
        Spanish =>
          "Se guardó en \{path}, pero no se pudo mostrar el archivo descargado."
      }
    BrowserDownloadFailed =>
      match locale {
        English => "Could not start the browser download."
        SimplifiedChinese => "无法启动浏览器下载。"
        TraditionalChinese => "無法啟動瀏覽器下載。"
        Japanese =>
          "ブラウザーでのダウンロードを開始できませんでした。"
        Spanish => "No se pudo iniciar la descarga en el navegador."
      }
    Cloud(failure) => failure.text(locale)
    Bridge(problem) => problem.text(locale)
    FileWatchingFailed(problem) => {
      let detail = problem.text(locale)
      match locale {
        English => "File watching failed: \{detail}"
        SimplifiedChinese => "文件监听失败：\{detail}"
        TraditionalChinese => "檔案監看失敗：\{detail}"
        Japanese => "ファイルの監視に失敗しました：\{detail}"
        Spanish => "Falló la supervisión de archivos: \{detail}"
      }
    }
    DefinitionFailed(problem) => {
      let detail = problem.text(locale)
      match locale {
        English => "Go to definition failed: \{detail}"
        SimplifiedChinese => "转到定义失败：\{detail}"
        TraditionalChinese => "移至定義失敗：\{detail}"
        Japanese => "定義への移動に失敗しました：\{detail}"
        Spanish => "No se pudo ir a la definición: \{detail}"
      }
    }
    ReferencesFailed(problem) => {
      let detail = problem.text(locale)
      match locale {
        English => "Find references failed: \{detail}"
        SimplifiedChinese => "查找引用失败：\{detail}"
        TraditionalChinese => "尋找參考失敗：\{detail}"
        Japanese => "参照の検索に失敗しました：\{detail}"
        Spanish => "No se pudieron buscar referencias: \{detail}"
      }
    }
    CaptureUnavailable => capture_unavailable_message(locale)
    CaptureSubmissionDeclined => capture_submission_declined_message(locale)
    Diagnostic(detail) => detail
    OfficeCitationUnavailable => ui(locale, OfficeCitationUnavailable)
    ExcelCopyTooLarge => ui(locale, ExcelCopyTooLarge)
    OfficeSelectionFailed => ui(locale, OfficeSelectionFailed)
    OfficePreviewFailed => ui(locale, OfficePreviewFailed)
    PdfPreviewFailed => ui(locale, PdfPreviewFailed)
  }
}
