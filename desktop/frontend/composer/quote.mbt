// Quoting text selected elsewhere on screen into the message input. The reply
// is written into the textarea and, when it is to be sent, submitted with the
// textarea's own Enter, so the component stays the single writer and sender
// of whichever draft the textarea is editing.

///|
const MessageInputId : String = "task"

///|
#external
priv type MessageInput

///|
/// The message input, when the screen has one that accepts text.
extern "js" fn message_input(id : String) -> @js.Nullable[MessageInput] =
  #| id => {
  #|   const input = document.getElementById(id)
  #|   return input instanceof HTMLTextAreaElement && !input.disabled
  #|     ? input
  #|     : null
  #| }

///|
extern "js" fn MessageInput::value(self : MessageInput) -> String =
  #| input => input.value

///|
/// Write `text` after the input's current content and tell the component, as
/// typing would. The page's focus and selection are left alone.
extern "js" fn MessageInput::append(self : MessageInput, text : String) -> Unit =
  #| (input, text) => {
  #|   const end = input.value.length
  #|   input.setRangeText(text, end, end, "end")
  #|   input.dispatchEvent(new InputEvent("input", { bubbles: true }))
  #|   input.scrollTop = input.scrollHeight
  #| }

///|
/// Press Enter in the input: the component's own submit, with every rule it
/// applies to one.
extern "js" fn MessageInput::press_enter(self : MessageInput) -> Unit =
  #| input => input.dispatchEvent(new KeyboardEvent("keydown", {
  #|   key: "Enter",
  #|   bubbles: true,
  #|   cancelable: true,
  #| }))

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
/// Whether `quote_reply` has a message input to write into right now.
pub fn quote_available() -> Bool {
  message_input(MessageInputId).to_option() is Some(_)
}

///|
/// Add a reply quoting `text` to the message input. With `send`, the message
/// is then submitted as Enter would submit it, together with anything already
/// written there; otherwise it waits for the reader to send it.
pub fn quote_reply(text : String, comment : String, send~ : Bool) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    guard message_input(MessageInputId).to_option() is Some(input) else {
      return
    }
    input.append(quote_insertion(input.value(), text, comment))
    if send {
      input.press_enter()
    }
  })
}
