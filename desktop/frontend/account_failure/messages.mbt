///|
priv enum Message {
  StorageUnavailable
  StorageReadFailed(String)
  SignInTimedOut
}

///|
fn text(locale : @i18n.Locale, message : Message) -> String {
  match (locale, message) {
    (English, SignInTimedOut) => "Sign-in wasn't completed. Try again."
    (Spanish, SignInTimedOut) =>
      "No se completó el inicio de sesión. Inténtalo de nuevo."
    (SimplifiedChinese, SignInTimedOut) => "登录未完成，请重试。"
    (TraditionalChinese, SignInTimedOut) => "登入未完成，請重試。"
    (Japanese, SignInTimedOut) =>
      "ログインが完了しませんでした。もう一度お試しください。"
    (English, StorageUnavailable) => "Account storage is unavailable."
    (Spanish, StorageUnavailable) =>
      "El almacenamiento de la cuenta no está disponible."
    (SimplifiedChinese, StorageUnavailable) => "账户存储不可用。"
    (TraditionalChinese, StorageUnavailable) =>
      "帳戶儲存空間無法使用。"
    (Japanese, StorageUnavailable) =>
      "アカウントのストレージを利用できません。"
    (English, StorageReadFailed(detail)) =>
      "Could not read account storage: \{detail}"
    (Spanish, StorageReadFailed(detail)) =>
      "No se pudo leer el almacenamiento de la cuenta: \{detail}"
    (SimplifiedChinese, StorageReadFailed(detail)) =>
      "无法读取账户存储：\{detail}"
    (TraditionalChinese, StorageReadFailed(detail)) =>
      "無法讀取帳戶儲存空間：\{detail}"
    (Japanese, StorageReadFailed(detail)) =>
      "アカウントのストレージを読み取れませんでした：\{detail}"
  }
}
