///|
pub struct Journal {
  priv root : String
  priv directory : String
  priv owner : Json
  priv pending : Map[String, Json]
}

///|
let current : Ref[Journal?] = Ref(None)

///|
pub async fn atomic_json(path : String, value : Json) -> Unit {
  let temp = path + "." + @uuid.mint() + ".tmp"
  @fs.write_file(
    temp,
    value.stringify(),
    create_mode=CreateNew,
    permission=0o600,
    sync=Full,
  )
  defer (@fs.remove(temp) catch {
    @os_error.OSError(_) as e if e.is_ENOENT() => ()
    e => raise e
  })
  @fs.rename(temp, path)
  let directory = @fs.open(
    @pathx.Path(path).dirname().to_string(),
    mode=ReadOnly,
  )
  defer directory.close()
  directory.sync()
}

///|
pub async fn read_json(path : String) -> Json? {
  let text = @fs.read_file(path).text() catch {
    @os_error.OSError(_) as e if e.is_ENOENT() => return None
    e => raise e
  }
  Some(@json.parse(text))
}

///|
pub async fn Journal::open(
  data_dir~ : String,
  instance_id~ : String,
  build_id~ : String,
) -> Journal {
  guard current.val is None else { fail("journal is already configured") }
  let root = data_dir + "/recovery"
  @fs.mkdir(root, permission=0o700, allow_exist=true)
  let pending : Map[String, Json] = Map([])
  for id in @fs.readdir(root) {
    let directory = root + "/" + id
    guard @fs.kind(directory, follow_symlink=false) is Directory else {
      fail("invalid recovery record directory")
    }
    if is_cleared(directory) {
      continue
    }
    let owner = read_json(directory + "/owner.json")
    pending[id] = owner.unwrap_or(Json::null())
  }
  let directory = root + "/" + instance_id
  @fs.mkdir(directory, permission=0o700)
  let owner : Json = {
    "instance_id": instance_id,
    "build_id": build_id,
    "data_dir": data_dir,
    "process": Json::null(),
  }
  let root_fd = @fs.open(root, mode=ReadOnly)
  defer root_fd.close()
  root_fd.sync()
  atomic_json(directory + "/owner.json", owner)
  atomic_json(data_dir + "/owner.json", owner)
  let journal : Journal = { root, directory, owner, pending, }
  current.val = Some(journal)
  journal
}

///|
pub fn Journal::needs_recovery(self : Journal) -> Bool {
  !self.pending.is_empty()
}

///|
pub fn Journal::diagnostics(self : Journal) -> Json {
  let instances : Array[Json] = []
  for id in self.pending.keys() {
    instances.push({
      "instance_id": id,
      "owner": self.pending.get(id),
      "process_inspection": "unavailable",
      "records_directory": self.root + "/" + id,
      "execution_outcome": "requires_inspection",
    })
  }
  {
    "unsettled_instances": instances,
    "message": "External tools may still be running. Inspect records and tools before explicit acknowledgement; then restart.",
  }
}

///|
pub async fn Journal::acknowledge(
  self : Journal,
  instance_id : String,
  confirmed : Bool,
) -> Unit {
  guard confirmed && self.pending.contains(instance_id) else {
    fail("explicit acknowledgement of a listed instance is required")
  }
  atomic_json(self.root + "/" + instance_id + "/acknowledged.json", {
    "reason": "user_acknowledged_external_tools",
    "by_owner": self.owner,
  })
  self.pending.remove(instance_id)
}

///|
/// Only call after every owned resource has joined and all admitted work settled.
pub async fn Journal::clean(self : Journal) -> Unit {
  atomic_json(self.directory + "/clean.json", { "owner": self.owner })
}

///|
/// An intent reaches durable storage before the effect or spawn. A missing
/// process identity means unknown execution, never evidence of non-execution.
pub async fn before(kind : String, subject? : String) -> String? {
  guard current.val is Some(journal) else { return None }
  let id = @uuid.mint()
  let run_id : String? = if kind == "agent.run" ||
    kind == "agent.command" ||
    kind == "schedule.admit" ||
    kind == "schedule.spawn" {
    subject
  } else {
    None
  }
  atomic_json(journal.directory + "/" + id + ".intent.json", {
    "operation_id": id,
    "subject": subject,
    "run_id": run_id,
    "kind": kind,
    "owner": journal.owner,
    "process": Json::null(),
  })
  Some(id)
}

///|
pub async fn spawned(id : String?, pid : Int32) -> Unit {
  guard current.val is Some(journal) && id is Some(id) else { return }
  // PID is diagnostic only: it cannot safely establish process identity.
  atomic_json(journal.directory + "/" + id + ".process.json", {
    "pid": pid,
    "process_identity": Json::null(),
  })
}

///|
pub async fn returned(id : String?, result : Json) -> Unit {
  guard current.val is Some(journal) && id is Some(id) else { return }
  let run_id = match result {
    { "run_id": String(id), .. } | { "turn": { "id": String(id), .. }, .. } =>
      Some(id)
    _ => None
  }
  // RPC return is deliberately distinct from durable Agent/run settlement.
  atomic_json(journal.directory + "/" + id + ".returned.json", {
    "rpc_returned": true,
    "run_id": run_id,
  })
}

///|
pub async fn is_cleared(directory : String) -> Bool {
  cleared_marker(
    read_json(directory + "/clean.json"),
    read_json(directory + "/acknowledged.json"),
  )
}

///|
fn cleared_marker(clean : Json?, acknowledged : Json?) -> Bool raise {
  match clean {
    Some(
      {
        "owner": { "instance_id": String(_), "process": Object(_) | Null, .. },
        ..
      }
    ) => return true
    Some(_) => fail("invalid clean shutdown marker")
    None => ()
  }
  match acknowledged {
    Some(
      {
        "reason": "host_reboot",
        "previous_boot": String(previous),
        "current_boot": String(now),
        ..
      }
    ) if previous != now => true
    Some(
      {
        "reason": "user_acknowledged_external_tools",
        "by_owner": { "instance_id": String(_), .. },
        ..
      }
    ) => true
    Some(_) => fail("invalid recovery acknowledgement")
    None => false
  }
}
