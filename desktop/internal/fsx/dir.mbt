///|
struct Directory(@fs.Directory)

///|
pub async fn Directory::try_open(path : @path.Path) -> Directory? {
  Some(Directory(@fs.opendir(path.to_string()))) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
}

///|
pub async fn Directory::collect(self : Directory) -> Array[DirectoryEntry] {
  let entries = []
  // The underlying handle holds a directory descriptor; close it once drained
  // (and even if iteration raises) so repeated Skills-panel refreshes don't
  // leak descriptors until the process can no longer open files.
  defer self.0.close()
  while self.next() is Some(entry) {
    entries.push(entry)
  }
  entries
}

///|
struct DirectoryEntry(@fs.DirectoryEntry)

///|
pub async fn Directory::next(self : Directory) -> DirectoryEntry? {
  if self.0.next() is Some(entry) {
    Some(DirectoryEntry(entry))
  } else {
    None
  }
}

///|
pub fn DirectoryEntry::name(self : DirectoryEntry) -> String {
  self.0.name
}

///|
pub fn DirectoryEntry::is_dir(self : DirectoryEntry) -> Bool {
  self.0.is_dir
}

///|
pub async fn rmdir(path : @path.Path, recursive? : Bool = false) -> Unit {
  @fs.rmdir(path.to_string(), recursive~)
}
