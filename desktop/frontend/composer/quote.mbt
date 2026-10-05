// Replies that quote text selected elsewhere on screen. A reply is a message:
// the component adds it to the prompt draft itself and, when asked, submits
// that draft through its ordinary submit, so a draft keeps one writer and one
// sender.

///|
const MessageInputId : String = "task"

///|
/// A reply quoting on-screen text, addressed to one conversation's composer.
pub(all) struct QuoteReply {
  identity : Identity
  quote : String
  comment : String
  // Submit the message once the reply is in it; otherwise it waits there.
  send : Bool
  // Run when the composer takes the reply. A composer that declines it — it
  // now serves another conversation, or is not editing a message — runs
  // nothing, so the caller still holds what was typed.
  accepted : @cmd.Cmd
}

///|
/// The identity a quoted reply to this composer must carry, when the composer
/// is editing a message at all: a goal being edited is not one.
pub fn Input::quote_target(self : Input) -> Identity? {
  guard !self.presentation.disabled && self.goal.draft is None else {
    return None
  }
  Some(self.identity)
}

///|
/// Move to the message input and show the end of its text.
extern "js" fn reveal_message_end(id : String) -> Unit =
  #| id => {
  #|   const input = document.getElementById(id)
  #|   if (!(input instanceof HTMLTextAreaElement)) return
  #|   input.focus({ preventScroll: true })
  #|   input.setSelectionRange(input.value.length, input.value.length)
  #|   input.scrollTop = input.scrollHeight
  #| }

///|
/// What replying to `text` with `comment` writes after a draft holding
/// `existing`: a Markdown block quote in its own paragraph, the comment when
/// there is one, then a blank line for whatever follows.
fn quote_insertion(
  existing : String,
  text : String,
  comment : String,
) -> String {
  let quote = text
    .trim()
    .split("\n")
    .map(line => {
      let line = line.trim_end()
      if line.is_empty() {
        ">"
      } else {
        "> \{line}"
      }
    })
    .join("\n")
  let lead = if existing.is_empty() || existing.has_suffix("\n\n") {
    ""
  } else if existing.has_suffix("\n") {
    "\n"
  } else {
    "\n\n"
  }
  let comment = comment.trim()
  if comment.is_empty() {
    "\{lead}\{quote}\n\n"
  } else {
    "\{lead}\{quote}\n\n\{comment}\n\n"
  }
}

///|
/// Take a quoted reply into the active prompt draft and, when it asks, submit
/// that draft as Enter would. A reply this composer is not the addressee of is
/// declined untouched.
fn Model::quote_replied(
  self : Model,
  entry : Entry,
  input : Input,
  reply : QuoteReply,
  emit : @cmd.Emit[Msg],
  action_emit : @cmd.Emit[Action],
) -> (Model, @cmd.Cmd) {
  // A `!` draft is a shell command; a reply appended to it would run as one.
  guard input.quote_target() == Some(reply.identity) &&
    input.shell_command(entry.draft) is None else {
    return (self, @cmd.none)
  }
  let task = entry.draft.task +
    quote_insertion(entry.draft.task, reply.quote, reply.comment)
  let (model, changed) = self.commit_entry_change(
    entry,
    {
      ..entry,
      draft: { ..entry.draft, task, },
      completion: None,
      pending_submission: None,
    },
    @cmd.none,
    action_emit,
  )
  let (model, submitted) = if reply.send {
    model.update(input, SubmitRequested, emit, action_emit)
  } else {
    (model, @cmd.none)
  }
  (
    model,
    @cmd.batch([
      changed,
      submitted,
      reply.accepted,
      @cmd.custom_cmd(
        _ => reveal_message_end(MessageInputId),
        kind=@cmd.after_render,
      ),
    ]),
  )
}
