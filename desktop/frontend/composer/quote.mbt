// Replies to selected text or Office content. A reply is part of a message:
// the component adds it to the prompt draft itself and, when asked, submits
// that draft through its ordinary submit, so a draft keeps one writer and one
// sender.

///|
const MessageInputId : String = "task"

///|
/// A reply with selected text or captured images, addressed to one composer.
pub(all) struct QuoteReply {
  identity : Identity
  content : ReplyContent
  images : Array[Image]
  // Submit the message once the reply is in it; otherwise it waits there.
  send : Bool
  // The composer runs one of these. It declines a reply it is not the
  // addressee of, and one that arrives while it is not editing a message; the
  // caller then still holds what was typed.
  accepted : @cmd.Cmd
  declined : @cmd.Cmd
}

///|
/// Office feedback already carries its comment in the structured selection.
pub(all) enum ReplyContent {
  Text(quote~ : String?, comment~ : String)
  OfficeSelection(String)
  Annotation(Mention)
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
    input.shell_command(entry.draft) is None &&
    (reply.images.is_empty() || input.presentation.images_enabled) else {
    return (self, reply.declined)
  }
  let insertion = match reply.content {
    OfficeSelection(_) | Annotation(_) => ""
    Text(quote=Some(quote), comment~) =>
      quote_insertion(entry.draft.task, quote, comment)
    Text(quote=None, comment~) => {
      let comment = comment.trim().to_owned()
      if comment.is_empty() {
        ""
      } else {
        (if entry.draft.task.is_empty() { "" } else { "\n\n" }) +
        comment +
        "\n\n"
      }
    }
  }
  let task = entry.draft.task + insertion
  let draft = match reply.content {
    OfficeSelection(materialized) =>
      entry.draft.with_office_selection(Some(materialized))
    Annotation(mention) => entry.draft.with_mention(mention)
    Text(..) => entry.draft
  }
  let (model, changed) = self.commit_entry_change(
    entry,
    {
      ..entry,
      draft: { ..draft, task, images: [..entry.draft.images, ..reply.images], },
      completion: None,
    },
    @cmd.none,
    action_emit,
  )
  let (model, submitted) = if reply.send {
    model.update(input, SubmitRequested, emit, action_emit)
  } else {
    (model, @cmd.none)
  }
  (model, @cmd.batch([changed, submitted, reply.accepted, focus_message_end()]))
}

///|
/// Focus the message composer after its draft has rendered, preserving text.
pub fn focus_message_end() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => reveal_message_end(MessageInputId),
    kind=@cmd.after_render,
  )
}
