// A session's inbox: how another agent posts it a message while it runs.
//
// The first use is a launcher redirecting its sub-run. The launcher cannot
// reach a hosted child directly — an `mbtx` snippet sits between them and
// owns the child's stdin, which the child contract reserves for the request
// line and the cancel signal. So the channel is a FILE beside the receiver's
// transcript, one JSON record per line: senders append, the receiver reads
// at the points its turn takes new input.
//
// The file's EXISTENCE is the receiver's own statement that it reads one.
// The receiver creates it; a sender only ever appends to an existing file. A
// session that takes no messages (a reviewer, which must stay independent of
// the party it audits) never creates one, so a post to it is refused instead
// of written where nothing will read it.
//
// This is a convention between cooperating agents, not a security boundary:
// anything that can write the session store can write an inbox, and `from`
// is what the sender says it is. See docs/plans/agent-messaging.md.

///|
/// The record format this build writes and reads.
const Version : Int = 1

///|
/// The one kind of message so far: an instruction the receiver should act
/// on. A reader delivers only the kinds it knows how to present.
const Instruction : String = "instruction"

///|
/// The longest text one message may carry, in characters.
pub const MaxTextChars : Int = 8_000

///|
/// One message. `id` is the sender's tag for it, unique among that sender's
/// messages; the receiver records it on the transcript item the message
/// becomes, which is how anyone tells a delivered message from a waiting one.
/// `from` is the sender's session id.
pub(all) struct Message {
  id : String
  from : String
  text : String
} derive(Eq, Debug)

///|
/// Ids are unique within one process by the counter and across a sender's
/// processes by the clock.
let issued : Ref[Int] = { val: 0, }

///|
/// A new message from session `from`, with a fresh id.
pub fn Message::Message(from~ : String, text~ : String) -> Message {
  issued.val += 1
  { id: "m\{@env.now()}-\{issued.val}", from, text, }
}

///|
/// The tag a receiver records on the transcript item this message becomes,
/// and the only thing a delivery is ever matched by. It carries the sender as
/// well as the id: ids are unique per sender, so two senders may both have an
/// `m1`, and one's delivery must not read as the other's.
pub fn Message::receipt(self : Message) -> String {
  "\{self.id}@\{self.from}"
}

///|
/// What an inbox holds.
pub(all) struct Inbox {
  /// The messages this build can read, oldest first.
  messages : Array[Message]
  /// Whole lines it cannot: damaged by a write that failed part-way, or in a
  /// format or of a kind newer than this build. They are not delivered and
  /// not hidden — a reader that guessed at them could present someone's note
  /// as an instruction.
  unreadable : Int
} derive(Eq, Debug)

///|
/// Declare that the session whose inbox is `path` takes messages, by
/// creating the file (and the directory it lives in). An inbox that is
/// already open keeps what was posted.
pub async fn open(path : String) -> Unit {
  @fs.mkdir(@path.Path(path).dirname().to_string(), recursive=true) catch {
    _ => ()
  }
  @fs.write_file(path, "", create_mode=OpenOrCreate, append=true)
}

///|
/// Append `message` to the inbox at `path`, or return `false` — writing
/// nothing — when the receiver opened none: it has not started, or it takes
/// no messages.
///
/// Posts are serialized by a lock on the inbox itself, so two senders never
/// interleave. A tail left by a write that failed part-way is closed off
/// first, so it damages only itself and never the record appended after it.
pub async fn post(path : String, message : Message) -> Bool {
  guard @fs.exists(path) else { return false }
  let file = @fs.open(
    path,
    mode=ReadWrite,
    create_mode=OpenExisting,
    append=true,
  )
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  let size = file.size()
  let torn = size > 0L && file.read_exactly_at(1, position=size - 1L) != b"\n"
  let record : Json = {
    "v": Version.to_json(),
    "id": message.id,
    "from": message.from,
    "kind": Instruction,
    "text": message.text,
  }
  let line = (if torn { "\n" } else { "" }) + record.stringify() + "\n"
  file.write(line)
  true
}

///|
/// Everything posted to the inbox at `path`, or `None` when none was opened.
/// A final line still being written is not a message yet. The file is split
/// into lines as bytes, so a tail cut inside a character cannot spoil the
/// records before it.
pub async fn read(path : String) -> Inbox? {
  guard @fs.exists(path) else { return None }
  let bytes = {
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    file.lock(Shared)
    defer file.unlock()
    file.read_all().binary()
  }
  let messages = []
  let mut unreadable = 0
  let mut start = 0
  for index in 0..<bytes.length() {
    guard bytes[index] == b'\n' else { continue }
    let line = bytes[start:index]
    start = index + 1
    guard line.length() > 0 else { continue }
    match decode(line) {
      Some(message) => messages.push(message)
      None => unreadable += 1
    }
  }
  Some({ messages, unreadable, })
}

///|
/// One whole line as a message, or `None` when this build cannot read it.
fn decode(line : BytesView) -> Message? {
  let text = @utf8.decode(line) catch { _ => return None }
  let json = @json.parse(text) catch { _ => return None }
  guard json
    is {
      "v": Number(version, ..),
      "id": String(id),
      "from": String(from),
      "kind": String(kind),
      "text": String(text),
      ..
    } &&
    version == Version.to_double() &&
    kind == Instruction else {
    return None
  }
  Some({ id, from, text, })
}

///|
/// The receiver's side of one inbox: hands out each message once.
struct Reader {
  path : String
  taken : Set[String]
}

///|
/// A reader over the inbox at `path` that has taken nothing yet.
pub fn Reader::Reader(path : String) -> Reader {
  { path, taken: Set([]), }
}

///|
/// The messages posted since the last call, oldest first. Empty when there
/// are none, and when the inbox is not open yet. Messages are told apart by
/// their receipt — sender and id — never by position.
pub async fn Reader::take(self : Reader) -> Array[Message] {
  guard read(self.path) is Some(inbox) else { return [] }
  let fresh = []
  for message in inbox.messages {
    let key = message.receipt()
    guard !self.taken.contains(key) else { continue }
    self.taken.add(key)
    fresh.push(message)
  }
  fresh
}

///|
#doc(hidden)
#deprecated
pub extend Message with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend Message with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend Inbox with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend Inbox with Debug::{to_repr}
