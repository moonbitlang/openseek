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
    Cloud(failure) => cloud_failure_text(locale, failure)
    Diagnostic(detail) => detail
    OfficeCitationUnavailable => ui(locale, OfficeCitationUnavailable)
    ExcelCopyTooLarge => ui(locale, ExcelCopyTooLarge)
    OfficeSelectionFailed => ui(locale, OfficeSelectionFailed)
    OfficePreviewFailed => ui(locale, OfficePreviewFailed)
    PdfPreviewFailed => ui(locale, PdfPreviewFailed)
  }
}

///|
fn cloud_failure_text(
  locale : @i18n.Locale,
  failure : @cloud_client.Failure,
) -> String {
  match failure {
    Unauthorized =>
      match locale {
        English => "Your account sign-in expired. Sign in again to continue."
        SimplifiedChinese =>
          "账户登录已过期。请重新登录以继续。"
        TraditionalChinese =>
          "帳戶登入已過期。請重新登入以繼續。"
        Japanese =>
          "アカウントのログインが期限切れです。続行するには再度ログインしてください。"
        Spanish =>
          "Tu sesión ha caducado. Vuelve a iniciar sesión para continuar."
      }
    Busy =>
      match locale {
        English =>
          "This conversation is already generating. Loading its history…"
        SimplifiedChinese =>
          "此对话正在生成回复。正在加载对话历史…"
        TraditionalChinese =>
          "此對話正在產生回覆。正在載入對話歷史…"
        Japanese =>
          "この会話はすでに生成中です。履歴を読み込み中…"
        Spanish =>
          "Esta conversación ya está generando una respuesta. Cargando su historial…"
      }
    Http(status) =>
      match locale {
        English => "Cloud answered HTTP \{status}. Try again."
        SimplifiedChinese => "云端返回 HTTP \{status}。请重试。"
        TraditionalChinese => "雲端回傳 HTTP \{status}。請重試。"
        Japanese =>
          "クラウドが HTTP \{status} を返しました。再試行してください。"
        Spanish => "Cloud respondió con HTTP \{status}. Inténtalo de nuevo."
      }
    Unreachable =>
      match locale {
        English => "Cloud is unreachable. Check your connection and try again."
        SimplifiedChinese =>
          "无法连接云端。请检查网络连接后重试。"
        TraditionalChinese =>
          "無法連線至雲端。請檢查網路連線後重試。"
        Japanese =>
          "クラウドに接続できません。接続を確認して再試行してください。"
        Spanish =>
          "No se puede conectar con Cloud. Comprueba tu conexión e inténtalo de nuevo."
      }
    Malformed =>
      match locale {
        English => "Cloud returned an invalid response. Try again."
        SimplifiedChinese => "云端返回了无效响应。请重试。"
        TraditionalChinese => "雲端回傳了無效回應。請重試。"
        Japanese =>
          "クラウドが無効な応答を返しました。再試行してください。"
        Spanish =>
          "Cloud devolvió una respuesta no válida. Inténtalo de nuevo."
      }
    ExportUnavailable =>
      match locale {
        English => "This conversation has no complete original log to export."
        SimplifiedChinese => "此对话没有可导出的完整原始日志。"
        TraditionalChinese => "此對話沒有可匯出的完整原始記錄。"
        Japanese =>
          "この会話にはエクスポートできる完全な元のログがありません。"
        Spanish =>
          "Esta conversación no tiene un registro original completo para exportar."
      }
    ServiceNotConfigured =>
      match locale {
        English =>
          "Cloud model credentials are not configured. Contact the service administrator."
        SimplifiedChinese =>
          "尚未配置云端模型凭据。请联系服务管理员。"
        TraditionalChinese =>
          "尚未設定雲端模型憑證。請聯絡服務管理員。"
        Japanese =>
          "クラウドモデルの認証情報が設定されていません。サービス管理者にお問い合わせください。"
        Spanish =>
          "Las credenciales del modelo de Cloud no están configuradas. Contacta con el administrador del servicio."
      }
    SignInFailed(detail) => detail
    InvalidImage =>
      match locale {
        English => "Choose a valid PNG, JPEG, GIF or WebP image up to 5 MiB."
        SimplifiedChinese =>
          "请选择不超过 5 MiB 的有效 PNG、JPEG、GIF 或 WebP 图片。"
        TraditionalChinese =>
          "請選擇不超過 5 MiB 的有效 PNG、JPEG、GIF 或 WebP 圖片。"
        Japanese =>
          "5 MiB 以下の有効な PNG、JPEG、GIF、WebP 画像を選択してください。"
        Spanish =>
          "Elige una imagen PNG, JPEG, GIF o WebP válida de hasta 5 MiB."
      }
  }
}
