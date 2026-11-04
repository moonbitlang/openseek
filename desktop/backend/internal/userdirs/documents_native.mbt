///|
extern "C" fn known_folder_documents() -> Bytes = "openseek_desktop_documents_dir"

///|
/// The Windows Documents known folder as UTF-8, `None` when the lookup fails.
/// The native stub reports failure (and every non-Windows host) as empty
/// bytes.
fn known_folder_documents_utf8() -> Bytes? {
  let path = known_folder_documents()
  guard path.length() > 0 else { return None }
  Some(path)
}
