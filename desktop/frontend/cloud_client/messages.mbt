///|
pub fn Failure::text(self : Failure, locale : @i18n.Locale) -> String {
  match (locale, self) {
    (English, Unauthorized) =>
      "Your account sign-in expired. Sign in again to continue."
    (SimplifiedChinese, Unauthorized) =>
      "账户登录已过期。请重新登录以继续。"
    (TraditionalChinese, Unauthorized) =>
      "帳戶登入已過期。請重新登入以繼續。"
    (Japanese, Unauthorized) =>
      "アカウントのログインが期限切れです。続行するには再度ログインしてください。"
    (Spanish, Unauthorized) =>
      "Tu sesión ha caducado. Vuelve a iniciar sesión para continuar."
    (English, Busy) =>
      "This conversation is already generating. Loading its history…"
    (SimplifiedChinese, Busy) =>
      "此对话正在生成回复。正在加载对话历史…"
    (TraditionalChinese, Busy) =>
      "此對話正在產生回覆。正在載入對話歷史…"
    (Japanese, Busy) =>
      "この会話はすでに生成中です。履歴を読み込み中…"
    (Spanish, Busy) =>
      "Esta conversación ya está generando una respuesta. Cargando su historial…"
    (English, Http(status)) => "Cloud answered HTTP \{status}. Try again."
    (SimplifiedChinese, Http(status)) =>
      "云端返回 HTTP \{status}。请重试。"
    (TraditionalChinese, Http(status)) =>
      "雲端回傳 HTTP \{status}。請重試。"
    (Japanese, Http(status)) =>
      "クラウドが HTTP \{status} を返しました。再試行してください。"
    (Spanish, Http(status)) =>
      "Cloud respondió con HTTP \{status}. Inténtalo de nuevo."
    (English, Unreachable) =>
      "Cloud is unreachable. Check your connection and try again."
    (SimplifiedChinese, Unreachable) =>
      "无法连接云端。请检查网络连接后重试。"
    (TraditionalChinese, Unreachable) =>
      "無法連線至雲端。請檢查網路連線後重試。"
    (Japanese, Unreachable) =>
      "クラウドに接続できません。接続を確認して再試行してください。"
    (Spanish, Unreachable) =>
      "No se puede conectar con Cloud. Comprueba tu conexión e inténtalo de nuevo."
    (English, Malformed) => "Cloud returned an invalid response. Try again."
    (SimplifiedChinese, Malformed) =>
      "云端返回了无效响应。请重试。"
    (TraditionalChinese, Malformed) =>
      "雲端回傳了無效回應。請重試。"
    (Japanese, Malformed) =>
      "クラウドが無効な応答を返しました。再試行してください。"
    (Spanish, Malformed) =>
      "Cloud devolvió una respuesta no válida. Inténtalo de nuevo."
    (English, ExportUnavailable) =>
      "This conversation has no complete original log to export."
    (SimplifiedChinese, ExportUnavailable) =>
      "此对话没有可导出的完整原始日志。"
    (TraditionalChinese, ExportUnavailable) =>
      "此對話沒有可匯出的完整原始記錄。"
    (Japanese, ExportUnavailable) =>
      "この会話にはエクスポートできる完全な元のログがありません。"
    (Spanish, ExportUnavailable) =>
      "Esta conversación no tiene un registro original completo para exportar."
    (English, ServiceNotConfigured) =>
      "Cloud model credentials are not configured. Contact the service administrator."
    (SimplifiedChinese, ServiceNotConfigured) =>
      "尚未配置云端模型凭据。请联系服务管理员。"
    (TraditionalChinese, ServiceNotConfigured) =>
      "尚未設定雲端模型憑證。請聯絡服務管理員。"
    (Japanese, ServiceNotConfigured) =>
      "クラウドモデルの認証情報が設定されていません。サービス管理者にお問い合わせください。"
    (Spanish, ServiceNotConfigured) =>
      "Las credenciales del modelo de Cloud no están configuradas. Contacta con el administrador del servicio."
    (_, SignInFailed(detail)) => detail
    (English, InvalidImage) =>
      "Choose a valid PNG, JPEG, GIF or WebP image up to 5 MiB."
    (SimplifiedChinese, InvalidImage) =>
      "请选择不超过 5 MiB 的有效 PNG、JPEG、GIF 或 WebP 图片。"
    (TraditionalChinese, InvalidImage) =>
      "請選擇不超過 5 MiB 的有效 PNG、JPEG、GIF 或 WebP 圖片。"
    (Japanese, InvalidImage) =>
      "5 MiB 以下の有効な PNG、JPEG、GIF、WebP 画像を選択してください。"
    (Spanish, InvalidImage) =>
      "Elige una imagen PNG, JPEG, GIF o WebP válida de hasta 5 MiB."
  }
}
