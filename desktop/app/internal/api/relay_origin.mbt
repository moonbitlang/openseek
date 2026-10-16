///|
const RelayServerOrigin : String = "https://openseek-api.moonbitlang.cn"

///|
pub fn remote_server_base(_manager : @engine.EngineManager) -> String? {
  Some(RelayServerOrigin)
}
