///|
fn ssh_protocol_mismatch(
  locale : @i18n.Locale,
  host : String,
  remote : Int32?,
) -> String {
  let expected = @protocol.HostProtocolRevision
  let reported = match remote {
    Some(revision) => revision.to_string()
    None =>
      match locale {
        English => "not provided or invalid"
        Spanish => "ausente o no válido"
        SimplifiedChinese => "未提供有效协议版本"
        TraditionalChinese => "未提供有效協定版本"
        Japanese => "有効なバージョンがありません"
      }
  }
  let reason = match locale {
    English =>
      "Cannot connect to SSH host “\{host}”: the local SeekMoon and remote openseek-app-server use incompatible protocol versions. Local requires: \{expected}; remote reported: \{reported}. "
    Spanish =>
      "No se puede conectar al host SSH «\{host}»: SeekMoon local y openseek-app-server remoto usan versiones de protocolo incompatibles. Versión requerida localmente: \{expected}; indicada por el servidor: \{reported}. "
    SimplifiedChinese =>
      "无法连接 SSH 主机“\{host}”：本机 SeekMoon 与远端 openseek-app-server 的通信协议不兼容。本机需要协议版本：\{expected}；远端报告：\{reported}。"
    TraditionalChinese =>
      "無法連線 SSH 主機「\{host}」：本機 SeekMoon 與遠端 openseek-app-server 的通訊協定不相容。本機需要協定版本：\{expected}；遠端回報：\{reported}。"
    Japanese =>
      "SSH ホスト「\{host}」に接続できません。ローカルの SeekMoon とリモートの openseek-app-server の通信プロトコルに互換性がありません。ローカルが必要とするバージョン：\{expected}、リモートの報告：\{reported}。"
  }
  let action = if remote is Some(revision) && revision > expected {
    match locale {
      English =>
        "Update SeekMoon on this computer to a version compatible with the remote server, then reconnect."
      Spanish =>
        "Actualiza SeekMoon en este equipo a una versión compatible con el servidor remoto y vuelve a conectar."
      SimplifiedChinese =>
        "请将本机 SeekMoon 更新到与远端服务兼容的版本，然后重新连接。"
      TraditionalChinese =>
        "請將本機 SeekMoon 更新至與遠端服務相容的版本，然後重新連線。"
      Japanese =>
        "このコンピュータの SeekMoon をリモートサーバーと互換性のあるバージョンに更新して、再接続してください。"
    }
  } else {
    match locale {
      English =>
        "Update the remote openseek-app-server to a version compatible with this SeekMoon build, then reconnect. If using a custom remote command, check which executable it starts."
      Spanish =>
        "Actualiza openseek-app-server remoto a una versión compatible con esta compilación de SeekMoon y vuelve a conectar. Si usas un comando remoto personalizado, comprueba qué ejecutable inicia."
      SimplifiedChinese =>
        "请将远端 openseek-app-server 更新到与本机 SeekMoon 兼容的版本，然后重新连接。如果配置了自定义远端启动命令，请检查它实际启动的程序。"
      TraditionalChinese =>
        "請將遠端 openseek-app-server 更新至與本機 SeekMoon 相容的版本，然後重新連線。如果設定了自訂遠端啟動命令，請檢查它實際啟動的程式。"
      Japanese =>
        "リモートの openseek-app-server をこの SeekMoon と互換性のあるバージョンに更新して、再接続してください。カスタムのリモート起動コマンドを使用している場合は、実際に起動する実行ファイルを確認してください。"
    }
  }
  reason + action
}
