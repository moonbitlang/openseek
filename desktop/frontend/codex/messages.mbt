///|
priv enum StatusMessage {
  Starting
  Running
  Connected
  CheckingAccount
  SignInRequired
  NoAccountRequired
}

///|
fn status_text(locale : @i18n.Locale, message : StatusMessage) -> String {
  match (locale, message) {
    (English, Starting) => "Starting Codex…"
    (Spanish, Starting) => "Iniciando Codex…"
    (SimplifiedChinese, Starting) => "正在启动 Codex…"
    (TraditionalChinese, Starting) => "正在啟動 Codex…"
    (Japanese, Starting) => "Codex を起動中…"
    (English, Running) => "Running"
    (Spanish, Running) => "En ejecución"
    (SimplifiedChinese, Running) => "运行中"
    (TraditionalChinese, Running) => "執行中"
    (Japanese, Running) => "実行中"
    (English, Connected) => "Connected"
    (Spanish, Connected) => "Conectado"
    (SimplifiedChinese, Connected) => "已连接"
    (TraditionalChinese, Connected) => "已連線"
    (Japanese, Connected) => "接続済み"
    (English, CheckingAccount) => "Checking account…"
    (Spanish, CheckingAccount) => "Comprobando la cuenta…"
    (SimplifiedChinese, CheckingAccount) => "正在检查账户…"
    (TraditionalChinese, CheckingAccount) => "正在檢查帳戶…"
    (Japanese, CheckingAccount) => "アカウントを確認中…"
    (English, SignInRequired) => "Sign in required"
    (Spanish, SignInRequired) => "Es necesario iniciar sesión"
    (SimplifiedChinese, SignInRequired) => "需要登录"
    (TraditionalChinese, SignInRequired) => "需要登入"
    (Japanese, SignInRequired) => "ログインが必要です"
    (English, NoAccountRequired) => "No account required"
    (Spanish, NoAccountRequired) => "No se necesita una cuenta"
    (SimplifiedChinese, NoAccountRequired) => "无需账户"
    (TraditionalChinese, NoAccountRequired) => "無需帳戶"
    (Japanese, NoAccountRequired) => "アカウントは不要です"
  }
}
