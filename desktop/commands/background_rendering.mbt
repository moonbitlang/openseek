///|
pub let app_background_rendering_get : Command[
  @protocol.EmptyPayload,
  @protocol.BackgroundRenderingSettings,
] = Command("app.background_rendering.get")

///|
pub let app_background_rendering_set : Command[
  @protocol.BackgroundRenderingSetPayload,
  @protocol.BackgroundRenderingSettings,
] = Command("app.background_rendering.set")
