///|
/// Notifications for this window's native browser tabs. These have no
/// NotificationKind: relay clients do not own native WebContents. Keep the
/// wire codecs here so the native producer and frontend consumer share the
/// same contract, including the request that precedes allocation of a tab id.
pub(all) enum BrowserEventPayload {
  OpenRequested(request~ : String, session~ : String, url~ : String)
  Navigated(id~ : Int32, url~ : String)
  LoadingChanged(id~ : Int32, loading~ : Bool)
  TitleUpdated(id~ : Int32, title~ : String)
  LoadFailed(id~ : Int32, url~ : String, code~ : Int32, text~ : String)
  RendererProcessTerminated(
    id~ : Int32,
    url~ : String,
    code~ : Int32,
    text~ : String
  )
} derive(Debug, Eq)

///|
pub impl @json.FromJson for BrowserEventPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "browser event")
  match object.required_string("kind") {
    "open_requested" =>
      OpenRequested(
        request=object.required_string("request"),
        session=object.required_string("session"),
        url=object.required_string("url"),
      )
    "navigated" =>
      Navigated(id=object.required_int("id"), url=object.required_string("url"))
    "loading" =>
      LoadingChanged(
        id=object.required_int("id"),
        loading=object.required_bool("loading"),
      )
    "title" =>
      TitleUpdated(
        id=object.required_int("id"),
        title=object.required_string("title"),
      )
    "load_failed" =>
      LoadFailed(
        id=object.required_int("id"),
        url=object.required_string("url"),
        code=object.required_int("code"),
        text=object.required_string("text"),
      )
    "renderer_process_terminated" =>
      RendererProcessTerminated(
        id=object.required_int("id"),
        url=object.required_string("url"),
        code=object.required_int("code"),
        text=object.required_string("text"),
      )
    _ =>
      raise JsonDecodeError(
        (path.add_key("kind"), "unknown browser event kind"),
      )
  }
}

///|
pub impl ToJson for BrowserEventPayload with fn to_json(self) {
  match self {
    OpenRequested(request~, session~, url~) =>
      {
        "kind": "open_requested",
        "request": Json(request),
        "session": Json(session),
        "url": Json(url),
      }
    Navigated(id~, url~) =>
      { "id": Json(id), "kind": "navigated", "url": Json(url) }
    LoadingChanged(id~, loading~) =>
      { "id": Json(id), "kind": "loading", "loading": Json(loading) }
    TitleUpdated(id~, title~) =>
      { "id": Json(id), "kind": "title", "title": Json(title) }
    LoadFailed(id~, url~, code~, text~) =>
      {
        "id": Json(id),
        "kind": "load_failed",
        "url": Json(url),
        "code": Json(code),
        "text": Json(text),
      }
    RendererProcessTerminated(id~, url~, code~, text~) =>
      {
        "id": Json(id),
        "kind": "renderer_process_terminated",
        "url": Json(url),
        "code": Json(code),
        "text": Json(text),
      }
  }
}

///|
pub extend BrowserEventPayload with Debug::{to_repr}

///|
pub extend BrowserEventPayload with Eq::{equal, not_equal}

///|
pub extend BrowserEventPayload with ToJson::{to_json}

///|
pub extend BrowserEventPayload with FromJson::{from_json}
