///|
/// The local cache is only a last-known sidebar catalog. It never authorizes
/// a project mutation or replaces the connected host's authoritative registry.
pub async fn Store::cached_projects(
  self : Store,
  id : String,
) -> Array[String]? {
  ignore(self.get(id))
  let path = @pathx.Path(self.directory).join("ssh-projects-" + id + ".json")
  guard @fsx.read_text_if_exists(path) is Some(text) else { return None }
  let catalog : @protocol.SshProjectCatalog = @json.from_json(@json.parse(text))
  guard catalog.id == id else {
    raise SshError("SSH project cache identity mismatch")
  }
  Some(catalog.paths)
}

///|
pub async fn Store::cache_projects(
  self : Store,
  catalog : @protocol.SshProjectCatalog,
) -> Unit {
  self.locked(() => {
    ignore(self.get(catalog.id))
    let path = self.directory + "/ssh-projects-" + catalog.id + ".json"
    let temporary = path + "." + @uuid.mint() + ".tmp"
    defer @fsx.remove_if_exists(Path(temporary))
    {
      let file = @fs.open(
        temporary,
        mode=WriteOnly,
        create_mode=CreateNew,
        permission=0o600,
      )
      defer file.close()
      file.write(catalog.to_json().stringify())
      file.sync()
    }
    @fs.rename(temporary, path)
    if !(@async.platform is Windows) {
      let directory = @fs.open(self.directory, mode=ReadOnly)
      defer directory.close()
      directory.sync()
    }
  })
}
