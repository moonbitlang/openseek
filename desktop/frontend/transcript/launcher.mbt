// Decoding of the host's `list_apps` reply: the launcher apps detected as
// installed, with their display names and (optionally) an embedded icon.

///|
/// One launcher app the host reports as installed. `icon` is a
/// `data:image/png` URL, or empty when the host could not extract one.
pub(all) struct LauncherAppItem {
  id : String
  name : String
  icon : String
}

///|
/// Parse a `list_apps` reply. `None` only for structurally unusable JSON;
/// entries without an id are skipped so one odd row cannot blank the menu.
pub fn decode_apps_reply(text : String) -> Array[LauncherAppItem]? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("apps") is Some(Array(entries)) else { return None }
  let items : Array[LauncherAppItem] = []
  for entry in entries {
    guard entry is Object(fields) else { continue }
    let id = json_text(fields, "id")
    guard !id.is_empty() else { continue }
    items.push({
      id,
      name: non_empty_or(json_text(fields, "name"), id),
      icon: json_text(fields, "icon"),
    })
  }
  Some(items)
}
