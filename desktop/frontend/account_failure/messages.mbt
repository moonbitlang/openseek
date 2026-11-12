///|
priv enum Message {
  StorageUnavailable
  StorageReadFailed(String)
  SignInTimedOut
  SignInCheckHttp(Int32)
  SignInCheckMalformed
  RelayUnreachable(String)
  RelayHttp(Int32)
  DeviceListHttp(Int32)
  DeviceListMalformed
}

///|
fn text(locale : @i18n.Locale, message : Message) -> String {
  match (locale, message) {
    (English, SignInCheckHttp(status)) =>
      "the sign-in check answered HTTP \{status}"
    (Spanish, SignInCheckHttp(status)) =>
      "la comprobación de inicio de sesión respondió con HTTP \{status}"
    (SimplifiedChinese, SignInCheckHttp(status)) =>
      "登录检查返回 HTTP \{status}"
    (TraditionalChinese, SignInCheckHttp(status)) =>
      "登入檢查回傳 HTTP \{status}"
    (Japanese, SignInCheckHttp(status)) =>
      "ログイン確認が HTTP \{status} を返しました"
    (English, SignInCheckMalformed) =>
      "the sign-in check answered malformed JSON"
    (Spanish, SignInCheckMalformed) =>
      "la comprobación de inicio de sesión devolvió JSON no válido"
    (SimplifiedChinese, SignInCheckMalformed) =>
      "登录检查返回了无效的 JSON"
    (TraditionalChinese, SignInCheckMalformed) =>
      "登入檢查回傳了無效的 JSON"
    (Japanese, SignInCheckMalformed) =>
      "ログイン確認が不正な JSON を返しました"
    (English, RelayUnreachable(detail)) => "the relay is unreachable: \{detail}"
    (Spanish, RelayUnreachable(detail)) =>
      "no se puede conectar con el relay: \{detail}"
    (SimplifiedChinese, RelayUnreachable(detail)) =>
      "无法连接中继服务：\{detail}"
    (TraditionalChinese, RelayUnreachable(detail)) =>
      "無法連線至轉送服務：\{detail}"
    (Japanese, RelayUnreachable(detail)) =>
      "リレーに接続できません：\{detail}"
    (English, RelayHttp(status)) => "the relay answered HTTP \{status}"
    (Spanish, RelayHttp(status)) => "el relay respondió con HTTP \{status}"
    (SimplifiedChinese, RelayHttp(status)) =>
      "中继服务返回 HTTP \{status}"
    (TraditionalChinese, RelayHttp(status)) =>
      "轉送服務回傳 HTTP \{status}"
    (Japanese, RelayHttp(status)) =>
      "リレーが HTTP \{status} を返しました"
    (English, DeviceListHttp(status)) =>
      "the device list answered HTTP \{status}"
    (Spanish, DeviceListHttp(status)) =>
      "la lista de dispositivos respondió con HTTP \{status}"
    (SimplifiedChinese, DeviceListHttp(status)) =>
      "设备列表返回 HTTP \{status}"
    (TraditionalChinese, DeviceListHttp(status)) =>
      "裝置清單回傳 HTTP \{status}"
    (Japanese, DeviceListHttp(status)) =>
      "デバイス一覧が HTTP \{status} を返しました"
    (English, DeviceListMalformed) => "the device list answered malformed JSON"
    (Spanish, DeviceListMalformed) =>
      "la lista de dispositivos devolvió JSON no válido"
    (SimplifiedChinese, DeviceListMalformed) =>
      "设备列表返回了无效的 JSON"
    (TraditionalChinese, DeviceListMalformed) =>
      "裝置清單回傳了無效的 JSON"
    (Japanese, DeviceListMalformed) =>
      "デバイス一覧が不正な JSON を返しました"
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
