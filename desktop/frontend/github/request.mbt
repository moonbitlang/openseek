///|
pub async fn[Payload : ToJson, Reply : FromJson] CheckoutScope::request(
  self : CheckoutScope,
  command : @commands.Command[Payload, Reply],
  payload : Payload,
) -> Reply {
  match self.host {
    Desktop(channel) => @interop.bridge_request(channel, command, payload)
    Cloud(session~, token~, ..) => {
      let body = payload.to_json()
      if body is Object(fields) {
        fields.remove("cwd")
        fields.remove("session")
      }
      let (response, data) = @http.request(
        @cloud_client.CloudOrigin +
        "/v1/sessions/\{@uri.encode_component(session)}/github/\{command.name()}",
        Post,
        {
          "Authorization": "Bearer \{token}",
          "Content-Type": "application/json",
        },
        body.stringify(),
      )
      guard response.code == 200 else {
        let detail = data.text() catch { _ => "" }
        fail("HTTP \{response.code}: \{detail}")
      }
      @json.from_json(data.json())
    }
  }
}
