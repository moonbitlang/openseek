///|
/// A claimed session holds this file, and nothing of its own yet, until the
/// run it was claimed for accepts it.
let claim_file_name : String = "claim.json"

///|
/// An accepted claim leaves this marker until the run's first record, so a
/// session that was claimed and accepted but never recorded anything is
/// still known for what it is: a reserved id, not a session.
let accepted_claim_file_name : String = "claim.accepted"

///|
/// What `SessionStore::claim` did with an id.
pub(all) enum SessionClaim {
  /// The directory was created by this call; the run that accepts it must
  /// present this token.
  Claimed(token~ : String)
  /// A directory with this id already exists. Nothing was created.
  Taken
}

///|
/// Reserve a new session id for a run that another process will start.
///
/// The session's directory is created exclusively, so of two claimants for
/// one id exactly one gets `Claimed`. The directory then holds only a claim
/// file with the SHA-256 of a fresh random token, never the token itself:
/// the token goes only to the run, which presents it to
/// `SessionStore::accept_claim` before writing its first record, so reading
/// a pending claim does not let anyone else accept it. A claim that is never
/// accepted stays: its id is never handed out again.
///
/// Only an existing directory is `Taken`. Every other failure, including one
/// after the directory was created, raises; the id is then consumed.
pub async fn SessionStore::claim(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> SessionClaim {
  let dir = self.session_dir(id)
  ensure_dir_exists(self.sessions_dir())
  @fs.mkdir(dir) catch {
    @os_error.OSError(_) as error if error.is_EEXIST() => return Taken
    error => raise error
  }
  guard @env.rand(16) is Some(entropy) else {
    fail("claiming session \{id.value()}: no secure randomness available")
  }
  let token = @hex.encode(entropy)
  let claim : Json = { "sha256": token_digest(token) }
  @fs.write_file(
    "\{dir}/\{claim_file_name}",
    claim.stringify(),
    create_mode=CreateNew,
    sync=Data,
    permission=0o600,
  )
  for entry in self.session_dir_chain(id) {
    sync_dir_best_effort(entry)
  }
  Claimed(token~)
}

///|
/// Accept the claim on `id` made for this run, once.
///
/// The directory must hold the claim file for `token` and no transcript
/// (a reader may have left the session lock beside it). Acceptance is
/// renaming the claim file to the accepted marker: of two runs presenting
/// the same token, only the one whose rename succeeds is accepted. (A
/// rename, not a removal: concurrent removals of one file have been seen to
/// report success more than once.) The directory is synced before this
/// returns, as the store syncs directories elsewhere, so an accepted claim
/// does not reappear after a crash. The run removes the marker with
/// `SessionStore::settle_claim` once it has recorded something. Every
/// refusal raises and changes nothing.
pub async fn SessionStore::accept_claim(
  self : SessionStore,
  id : @agent_session.SessionId,
  token : String,
) -> Unit {
  let dir = self.session_dir(id)
  let entries = @fs.readdir(dir) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() =>
      fail("session \{id.value()} was not claimed: it does not exist")
    error => raise error
  }
  guard entries.contains(claim_file_name) else {
    fail("session \{id.value()} holds no claim; it was accepted already")
  }
  guard entries.all(name => name == claim_file_name || name == lock_file_name) else {
    fail("session \{id.value()} already has records of its own")
  }
  let path = "\{dir}/\{claim_file_name}"
  let recorded = @json.parse(@fs.read_file(path).text()) catch {
    error => fail("session \{id.value()}: unreadable claim file: \{error}")
  }
  guard recorded is { "sha256": String(expected), .. } &&
    expected == token_digest(token) else {
    fail("session \{id.value()} was claimed for another run")
  }
  @fs.rename(path, "\{dir}/\{accepted_claim_file_name}", replace=false) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() || error.is_EEXIST() =>
      fail("session \{id.value()} holds no claim; it was accepted already")
    error => raise error
  }
  sync_dir_best_effort(dir)
}

///|
/// Drop the accepted-claim marker of `id` once its run has recorded
/// something: the session is an ordinary one from then on. Absent marker
/// is fine; any other failure raises, and leaves only a stray marker in a
/// session that lists normally.
pub async fn SessionStore::settle_claim(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> Unit {
  @fs.remove("\{self.session_dir(id)}/\{accepted_claim_file_name}") catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => ()
    error => raise error
  }
}

///|
/// Whether `id`'s directory holds nothing of a session yet, only a claim
/// (pending or accepted) and perhaps a reader's lock: a reserved id that
/// listings leave out.
async fn SessionStore::only_claimed(
  self : SessionStore,
  id : @agent_session.SessionId,
) -> Bool {
  let entries = @fs.readdir(self.session_dir(id)) catch { _ => return false }
  entries.any(name => {
    name == claim_file_name || name == accepted_claim_file_name
  }) &&
  entries.all(name => {
    name == claim_file_name ||
    name == accepted_claim_file_name ||
    name == lock_file_name
  })
}

///|
/// What a claim file records of its token.
fn token_digest(token : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(token)))
}
