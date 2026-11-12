///|
#derive(Eq)
pub(all) enum BridgeProblem {
  Unavailable
  MalformedReply(String)
  SshUnavailable
  SshReplyRetired
  ConnectionDown
  ConnectionClosed
  ConnectionLost
  RequestFailed
  External(String)
}

///|
pub extend BridgeProblem with Eq::{equal, not_equal}

///|
pub fn BridgeProblem::text(
  self : BridgeProblem,
  locale : @i18n.Locale,
) -> String {
  match (locale, self) {
    (English, Unavailable) => "SeekMoon bridge unavailable"
    (Spanish, Unavailable) => "El puente de SeekMoon no está disponible"
    (SimplifiedChinese, Unavailable) => "SeekMoon 桥接服务不可用"
    (TraditionalChinese, Unavailable) => "SeekMoon 橋接服務無法使用"
    (Japanese, Unavailable) => "SeekMoon ブリッジを利用できません"
    (English, MalformedReply(op)) => "Malformed reply from \{op}"
    (Spanish, MalformedReply(op)) => "Respuesta no válida de \{op}"
    (SimplifiedChinese, MalformedReply(op)) => "\{op} 返回了无效响应"
    (TraditionalChinese, MalformedReply(op)) => "\{op} 回傳了無效回應"
    (Japanese, MalformedReply(op)) => "\{op} からの応答が不正です"
    (English, SshUnavailable) => "SSH connection is unavailable"
    (Spanish, SshUnavailable) => "La conexión SSH no está disponible"
    (SimplifiedChinese, SshUnavailable) => "SSH 连接不可用"
    (TraditionalChinese, SshUnavailable) => "SSH 連線無法使用"
    (Japanese, SshUnavailable) => "SSH 接続を利用できません"
    (English, SshReplyRetired) =>
      "SSH reply belongs to a retired connection; refresh to reconcile"
    (Spanish, SshReplyRetired) =>
      "La respuesta SSH pertenece a una conexión retirada; actualiza para reconciliar el estado"
    (SimplifiedChinese, SshReplyRetired) =>
      "SSH 响应属于已失效的连接；请刷新以同步状态"
    (TraditionalChinese, SshReplyRetired) =>
      "SSH 回應屬於已失效的連線；請重新整理以同步狀態"
    (Japanese, SshReplyRetired) =>
      "SSH 応答は無効になった接続のものです。更新して状態を同期してください"
    (English, ConnectionDown) => "SeekMoon connection is down"
    (Spanish, ConnectionDown) => "La conexión de SeekMoon no está disponible"
    (SimplifiedChinese, ConnectionDown) => "SeekMoon 连接已断开"
    (TraditionalChinese, ConnectionDown) => "SeekMoon 連線已中斷"
    (Japanese, ConnectionDown) => "SeekMoon 接続が切断されています"
    (English, ConnectionClosed) => "SeekMoon connection closed"
    (Spanish, ConnectionClosed) => "Se cerró la conexión de SeekMoon"
    (SimplifiedChinese, ConnectionClosed) => "SeekMoon 连接已关闭"
    (TraditionalChinese, ConnectionClosed) => "SeekMoon 連線已關閉"
    (Japanese, ConnectionClosed) => "SeekMoon 接続が閉じられました"
    (English, ConnectionLost) => "SeekMoon connection lost"
    (Spanish, ConnectionLost) => "Se perdió la conexión de SeekMoon"
    (SimplifiedChinese, ConnectionLost) => "SeekMoon 连接已丢失"
    (TraditionalChinese, ConnectionLost) => "SeekMoon 連線已中斷"
    (Japanese, ConnectionLost) => "SeekMoon 接続が失われました"
    (English, RequestFailed) => "request failed"
    (Spanish, RequestFailed) => "la solicitud falló"
    (SimplifiedChinese, RequestFailed) => "请求失败"
    (TraditionalChinese, RequestFailed) => "請求失敗"
    (Japanese, RequestFailed) => "リクエストに失敗しました"
    (_, External(detail)) => detail
  }
}
