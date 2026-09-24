///|
/// Map compact UUID handles to lowercase filenames on case-insensitive filesystems.
/// Historical job IDs retain their original filenames.
pub fn job_storage_name(id : String) -> String {
  guard id.length() == 22 else { return id }
  let encoded = id.replace_all(old="-", new="+").replace_all(old="_", new="/")
  let bytes = @base64.decode(encoded + "==") catch { _ => return id }
  guard bytes.length() == 16 else { return id }
  "uuid-" + @hex.encode(bytes)
}

///|
/// Recover a compact job handle from its reversible on-disk name.
pub fn job_id_from_storage(name : String) -> String {
  guard name.length() == 37 && name.has_prefix("uuid-") else { return name }
  let bytes = @hex.decode(name[5:]) catch { _ => return name }
  @base64.encode(bytes, padding=false)
  .replace_all(old="+", new="-")
  .replace_all(old="/", new="_")
}
