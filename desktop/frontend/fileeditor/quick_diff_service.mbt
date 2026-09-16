// Desktop-owned adapter for the Viewer's public QuickDiffHandle. The Viewer
// deliberately exposes only a capability interface; the concrete service in
// editor/internal remains editor-owned and cannot cross this package boundary.

///|
priv struct DesktopQuickDiffService {
  originals : Map[String, String]
  did_change_original : @common.Emitter[@common.Uri]
}

///|
fn DesktopQuickDiffService::DesktopQuickDiffService() -> DesktopQuickDiffService {
  { originals: Map([]), did_change_original: Emitter(), }
}

///|
fn DesktopQuickDiffService::quick_diff_handle(
  self : DesktopQuickDiffService,
) -> @quick_diff_api.QuickDiffHandle {
  QuickDiffHandle(
    get_original_content=resource => self.originals.get(resource.to_string()),
    on_did_change_original=listener => self.did_change_original.event(listener),
  )
}

///|
/// Store or clear one resource's HEAD baseline and notify the attached Viewer.
/// The empty string is a real value: it represents a new file with no HEAD
/// side, so quick diff decorates every working-tree line as added.
fn DesktopQuickDiffService::set_original_content(
  self : DesktopQuickDiffService,
  resource : @common.Uri,
  content : String?,
) -> Unit {
  let key = resource.to_string()
  // Showing an already-mounted document also notifies the Viewer through its
  // model event. Avoid a second synchronous full diff when the HEAD side did
  // not change.
  if self.originals.get(key) == content {
    return
  }
  match content {
    Some(text) => self.originals[key] = text
    None => self.originals.remove(key)
  }
  self.did_change_original.fire(resource)
}

///|
test "desktop quick-diff adapter stores empty baselines and clears resources" {
  let service = DesktopQuickDiffService()
  let resource = try! @common.Uri::parse("openseek://local/work/main.mbt")
  let handle = service.quick_diff_handle()
  let fired : Array[String] = []
  let listener = handle.on_did_change_original(uri => {
    fired.push(uri.to_string())
  })
  assert_true(handle.get_original_content(resource) is None)
  service.set_original_content(resource, Some(""))
  assert_eq(handle.get_original_content(resource), Some(""))
  service.set_original_content(resource, Some("old"))
  assert_eq(handle.get_original_content(resource), Some("old"))
  service.set_original_content(resource, Some("old"))
  assert_eq(fired.length(), 2)
  service.set_original_content(resource, None)
  assert_true(handle.get_original_content(resource) is None)
  service.set_original_content(resource, None)
  assert_eq(fired.length(), 3)
  listener.dispose()
}
