///|
fn builtin_skills() -> Array[RegistrySkillIdentity] {
  [
    { module_name: "moonbitlang/typst", package_path: "", },
    { module_name: "moonbitlang/office-cli", package_path: "", },
  ]
}

///|
/// The standalone registry uses SKILL.md names. Recognize the two built-ins
/// installed by the module registry so updates retain their library entries.
fn standalone_identity(
  identity : RegistrySkillIdentity,
) -> RegistrySkillIdentity {
  match (identity.module_name, identity.package_path) {
    ("moonbitlang/typst", "cli") =>
      { module_name: "moonbitlang/typst", package_path: "", }
    ("moonbitlang/office", "") =>
      { module_name: "moonbitlang/office-cli", package_path: "", }
    _ => identity
  }
}

///|
fn legacy_builtin_slug(identity : RegistrySkillIdentity) -> String? {
  match (identity.module_name, identity.package_path) {
    ("moonbitlang/typst", "") => Some("moonbitlang-typst-cli")
    ("moonbitlang/office-cli", "") => Some("moonbitlang-office")
    _ => None
  }
}

///|
/// Whether `identity` is one of OpenSeek's registry-synced built-in skills.
pub fn is_builtin(identity : RegistrySkillIdentity) -> Bool {
  builtin_skills().contains(identity)
}

///|
/// A recorded sync failure for one built-in skill.
#derive(Eq, Debug)
pub(all) struct BuiltinSkillError {
  /// The built-in skill that failed to sync.
  registry : RegistrySkillIdentity
  /// Human-readable reason for the failure.
  message : String
}

///|
/// Default bounded grace period for a cold-start host session to let the
/// initial built-in skills sync finish before spawning an engine that freezes
/// its `## Skills` prompt section.
const DefaultColdWaitMs : Int32 = 5_000

///|
/// Tracks the built-in skills managed by an OpenSeek host, their background
/// sync lifecycle, and any sync errors encountered while installing or
/// updating them.
struct BuiltinSkills {
  entries : Array[RegistrySkillIdentity]
  mut errors : Array[BuiltinSkillError]
  mut running : Bool
  mut completed_once : Bool
  waiters : Array[@async.Queue[Unit]]
}

///|
/// Create a built-in skills tracker for OpenSeek's default built-in catalog.
pub fn BuiltinSkills::BuiltinSkills() -> BuiltinSkills {
  {
    entries: builtin_skills(),
    errors: [],
    running: false,
    completed_once: false,
    waiters: [],
  }
}

///|
/// Whether a built-in skills sync pass is currently running.
pub fn BuiltinSkills::is_syncing(self : BuiltinSkills) -> Bool {
  self.running
}

///|
/// Current built-in sync failures (copy).
pub fn BuiltinSkills::errors(self : BuiltinSkills) -> Array[BuiltinSkillError] {
  self.errors.copy()
}

///|
fn BuiltinSkills::wake_waiters(self : BuiltinSkills) -> Unit {
  for waiter in self.waiters {
    ignore(waiter.try_put(()) catch { _ => false })
  }
  self.waiters.clear()
}

///|
fn BuiltinSkills::clear_error(
  self : BuiltinSkills,
  module_name~ : String,
  package_path~ : String,
) -> Unit {
  self.errors = self.errors.filter(error => {
    error.registry.module_name != module_name ||
    error.registry.package_path != package_path
  })
}

///|
fn BuiltinSkills::record_error(
  self : BuiltinSkills,
  identity : RegistrySkillIdentity,
  error : Error,
  on_changed : (() -> Unit)?,
) -> Unit {
  let message = "\{error}"
  self.clear_error(
    module_name=identity.module_name,
    package_path=identity.package_path,
  )
  self.errors.push({ registry: identity, message, })
  if on_changed is Some(callback) {
    callback()
  }
}

///|
fn installed_source(
  skills : Array[InstalledSkill],
  identity : RegistrySkillIdentity,
) -> String? {
  skills
  .iter()
  .find_first(skill => skill.registry == Some(identity))
  .bind(skill => skill.source)
}

///|
/// Whether every built-in skill already has an installed copy in the library
/// (enabled or disabled). Propagates library access/lock failures so callers
/// never confuse an unreadable library with absent built-ins.
async fn BuiltinSkills::has_all_installed(
  self : BuiltinSkills,
  library_dir? : String,
) -> Bool {
  guard !self.entries.is_empty() else { return true }
  let installed = installed_skills(library_dir?)
  self.entries
  .iter()
  .all(identity => installed_source(installed, identity) is Some(_))
}

///|
/// Wait briefly for an in-flight startup sync only when a brand-new session
/// would otherwise start without built-in skills installed locally. The entire
/// readiness check (including acquiring the library lock) stays inside
/// `wait_ms`; inspection errors skip waiting rather than blocking startup.
pub async fn BuiltinSkills::wait_if_cold(
  self : BuiltinSkills,
  library_dir? : String,
  wait_ms~ : Int32 = DefaultColdWaitMs,
) -> Unit {
  if self.completed_once || !self.running {
    return
  }
  @async.with_timeout_opt(wait_ms, () => {
    let warm = self.has_all_installed(library_dir?) catch { _ => return }
    if warm || self.completed_once || !self.running {
      return
    }
    let done : @async.Queue[Unit] = Queue(kind=Blocking(1))
    self.waiters.push(done)
    defer (if self.waiters.search_by(waiter => physical_equal(waiter, done))
      is Some(index) {
      self.waiters.remove(index) |> ignore
    })
    done.get()
  })
  |> ignore
}

///|
/// Install a registry skill and clear any recorded built-in sync failure for
/// that skill before `on_committed` runs.
pub async fn BuiltinSkills::install(
  self : BuiltinSkills,
  module_name~ : String,
  version~ : String,
  package_path~ : String,
  registry~ : String = DefaultRegistry,
  library_dir? : String,
  on_committed? : () -> Unit,
) -> InstalledSkill {
  let library_dir = resolve_library_dir(library_dir)
  install_skill_impl(
    module_name~,
    version~,
    package_path~,
    registry~,
    library_dir~,
    on_committed=() => {
      self.clear_error(module_name~, package_path~)
      if on_committed is Some(callback) {
        callback()
      }
    },
  ).unwrap()
}

///|
/// Start syncing built-in skills in the background on `group` if no sync is
/// already running. Marks `is_syncing()` synchronously before spawning so a
/// cold-start `wait_if_cold` immediately after launch observes the in-flight
/// pass. `on_finished` receives the count of committed installs/updates.
pub fn BuiltinSkills::start_sync(
  self : BuiltinSkills,
  group : @async.TaskGroup,
  registry~ : String = DefaultRegistry,
  library_dir? : String,
  on_changed? : () -> Unit,
  on_finished? : (Int32) -> Unit,
) -> Unit {
  if self.running {
    return
  }
  self.running = true
  group.spawn_bg(allow_failure=true, no_wait=true, () => {
    let committed = self.run_sync(registry~, library_dir?, on_changed?)
    if on_finished is Some(callback) {
      callback(committed)
    }
  })
}

///|
/// Run one built-in skills sync pass and return the number of committed
/// installs or updates. `on_changed` fires on both committed updates and newly
/// recorded sync errors so UI hosts can invalidate their view.
pub async fn BuiltinSkills::sync(
  self : BuiltinSkills,
  registry~ : String = DefaultRegistry,
  library_dir? : String,
  on_changed? : () -> Unit,
) -> Int32 {
  if self.running {
    return 0
  }
  self.running = true
  self.run_sync(registry~, library_dir?, on_changed?)
}

///|
async fn BuiltinSkills::run_sync(
  self : BuiltinSkills,
  registry~ : String,
  library_dir? : String,
  on_changed? : () -> Unit,
) -> Int32 {
  defer {
    self.running = false
    self.completed_once = true
    self.wake_waiters()
  }
  guard !self.entries.is_empty() else { return 0 }
  let library_dir = match library_dir {
    Some(dir) => dir
    None =>
      library_dir_from_env() catch {
        error => {
          for identity in self.entries {
            self.record_error(identity, error, on_changed)
          }
          return 0
        }
      }
  }
  let before = installed_skills(library_dir~) catch {
    error => {
      for identity in self.entries {
        self.record_error(identity, error, on_changed)
      }
      return 0
    }
  }
  let catalog = fetch_catalog(registry~) catch {
    error => {
      let current = installed_skills(library_dir~) catch { _ => before }
      for identity in self.entries {
        if installed_source(current, identity) ==
          installed_source(before, identity) {
          self.record_error(identity, error, on_changed)
        }
      }
      return 0
    }
  }
  let mut committed = 0
  for identity in self.entries {
    let expected = installed_source(before, identity)
    try {
      guard catalog
        .iter()
        .find_first(skill => {
          skill.module_name == identity.module_name &&
          skill.package_path == identity.package_path
        })
        is Some(skill) else {
        raise SkillsError("built-in skill is missing from the registry catalog")
      }
      let desired = source_label(
        skill.module_name,
        skill.version,
        skill.package_path,
      )
      if expected == Some(desired) {
        self.clear_error(
          module_name=identity.module_name,
          package_path=identity.package_path,
        )
        continue
      }
      ignore(
        install_skill_impl(
          module_name=identity.module_name,
          version=skill.version,
          package_path=identity.package_path,
          registry~,
          library_dir~,
          mode=IfUnchanged(expected),
          on_committed=() => {
            self.clear_error(
              module_name=identity.module_name,
              package_path=identity.package_path,
            )
            committed += 1
            if on_changed is Some(callback) {
              callback()
            }
          },
        ),
      )
    } catch {
      error => {
        let current = installed_skills(library_dir~) catch { _ => before }
        if installed_source(current, identity) == expected {
          self.record_error(identity, error, on_changed)
        }
      }
    }
  }
  committed
}
