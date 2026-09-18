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
    (SimplifiedChinese, Starting) => "正在启动 Codex…"
    (Japanese, Starting) => "Codex を起動中…"
    (English, Running) => "Running"
    (SimplifiedChinese, Running) => "运行中"
    (Japanese, Running) => "実行中"
    (English, Connected) => "Connected"
    (SimplifiedChinese, Connected) => "已连接"
    (Japanese, Connected) => "接続済み"
    (English, CheckingAccount) => "Checking account…"
    (SimplifiedChinese, CheckingAccount) => "正在检查账户…"
    (Japanese, CheckingAccount) => "アカウントを確認中…"
    (English, SignInRequired) => "Sign in required"
    (SimplifiedChinese, SignInRequired) => "需要登录"
    (Japanese, SignInRequired) => "ログインが必要です"
    (English, NoAccountRequired) => "No account required"
    (SimplifiedChinese, NoAccountRequired) => "无需账户"
    (Japanese, NoAccountRequired) => "アカウントは不要です"
  }
}
