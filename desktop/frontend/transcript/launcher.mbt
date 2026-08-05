// Projection of the host's typed `list_apps` reply into launcher rows.

///|
/// One launcher app the host reports as installed. `icon` is a
/// `data:image/png` URL, or empty when the host could not extract one.
pub(all) struct LauncherAppItem {
  id : String
  name : String
  icon : String
} derive(Eq)

///|
/// Project a `list_apps` reply. Entries without an id are skipped so a stale
/// host row cannot create an unlaunchable menu item.
pub fn apps_from_reply(
  reply : @desktop_protocol.ListAppsReply,
) -> Array[LauncherAppItem] {
  let items : Array[LauncherAppItem] = []
  for entry in reply.apps {
    guard !entry.id.is_empty() else { continue }
    items.push({
      id: entry.id,
      name: if entry.name.trim().is_empty() {
        entry.id
      } else {
        entry.name
      },
      icon: entry.icon,
    })
  }
  items
}
