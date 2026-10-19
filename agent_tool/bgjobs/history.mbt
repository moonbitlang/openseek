///|
/// The latest record of every job of an earlier engine of this session: one
/// per job file of each generation directory under `root` other than `own`,
/// whose engine is gone (its `owner.lock` can be taken). A generation whose
/// owner cannot be checked is left out, as is a record that does not decode or
/// does not match its file. Reading creates nothing.
pub async fn earlier_job_records(
  root : String,
  own~ : String,
) -> Array[@protocol.JobRecord] {
  let generations = @fs.readdir(root, sort=true) catch { _ => return [] }
  let records = []
  for generation in generations {
    guard generation != own && @protocol.valid_job_component(generation) else {
      continue
    }
    let directory = "\{root}/\{generation}"
    guard owner_gone(directory) else { continue }
    let names = @fs.readdir(directory, sort=true) catch { _ => continue }
    for name in names {
      guard name.strip_suffix(".json") is Some(_) else { continue }
      if earlier_record("\{directory}/\{name}", generation~, name~)
        is Some(record) {
        records.push(record)
      }
    }
  }
  records
}

///|
/// Whether the engine that owned the generation `directory` is gone: its
/// `owner.lock`, held for that engine's life, can be locked now.
async fn owner_gone(directory : String) -> Bool {
  let owner = @fs.open("\{directory}/owner.lock", mode=ReadWrite) catch {
    _ => return false
  }
  defer owner.close()
  owner.try_lock(Exclusive) catch {
    _ => false
  }
}

///|
/// The record in `path`, bounded and checked against the generation and file
/// name it was stored under, as the desktop reads it.
async fn earlier_record(
  path : String,
  generation~ : String,
  name~ : String,
) -> @protocol.JobRecord? {
  let file = @fs.open(path, mode=ReadOnly) catch { _ => return None }
  defer file.close()
  let record : @protocol.JobRecord = try {
    guard file.kind() is Regular else { return None }
    let size = file.size()
    guard size <= 1048576L else { return None }
    let bytes = file.read_exactly_at(size.to_int(), position=0L)
    @json.from_json(@json.parse(@utf8.decode(bytes)))
  } catch {
    _ => return None
  }
  guard record.generation == generation &&
    "\{@protocol.job_storage_name(record.id)}.json" == name else {
    return None
  }
  Some(record)
}
