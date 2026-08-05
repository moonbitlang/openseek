// External anchor routing shared by transcript Markdown and the editor's
// foreign hover DOM. The listener runs in the capture phase because the hover
// widget stops click propagation before a document bubble listener can see it.

///|
using @cmd {trait Scheduler}

///|
priv suberror ExternalLinkSubscription {
  ExternalLinkSubscription(@cmd.Emit[String])
}

///|
fn external_link_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    ExternalLinkSubscription(emit) => {
      let mut emit = emit
      let listener = add_external_link_capture(url => scheduler.add(emit(url)))
      Some({
        unload: _ => remove_external_link_capture(listener),
        update_tagger: payload => {
          guard payload is ExternalLinkSubscription(next) else { return }
          emit = next
        },
      })
    }
    _ => None
  }
}

///|
fn external_link_subscription(emit : @cmd.Emit[String]) -> @sub.Sub {
  @sub.custom_sub(
    "external-link-capture",
    Global,
    ExternalLinkSubscription(emit),
    external_link_sub_loader,
  )
}

///|
/// Ask the Proton-local bridge to hand an external URL to the system browser.
/// Failures re-enter update as the same host-action toast used by file/app
/// openers; the browser page never emits this command.
fn open_external_link(dispatch : @cmd.Emit[Msg], url : String) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(
          @interop.ChannelId::Local,
          @commands.shell_open_external,
          { url, },
        ) catch {
          error => {
            scheduler.add(
              dispatch(HostActionFailed(@interop.bridge_error_text(error))),
            )
            return
          }
        },
      )
    })
  })
}

///|
/// Install one delegated capture listener and return its identity for removal.
/// Browser pages preserve ordinary navigation but force safe external targets
/// into a new tab. Pages with the injected Desktop bridge prevent every anchor
/// navigation (so the app frame cannot escape) and emit only allowlisted
/// external schemes.
extern "js" fn add_external_link_capture(
  on_external : (String) -> Unit,
) -> @js.Value =
  #| (onExternal) => {
  #|   const listener = (event) => {
  #|     if (event.defaultPrevented || event.button !== 0) return;
  #|     const anchor = event.target?.closest?.("a[href]");
  #|     if (!anchor || anchor.hasAttribute("download")) return;
  #|     let destination;
  #|     try {
  #|       destination = new URL(anchor.getAttribute("href"), document.baseURI);
  #|     } catch {
  #|       return;
  #|     }
  #|     const supported = destination.protocol === "http:" ||
  #|       destination.protocol === "https:" ||
  #|       destination.protocol === "mailto:";
  #|     if (globalThis.__MoonBit__?.openseek) {
  #|       event.preventDefault();
  #|       if (supported) onExternal(destination.href);
  #|       return;
  #|     }
  #|     const leavesOrigin = destination.protocol === "mailto:" ||
  #|       destination.origin !== globalThis.location?.origin;
  #|     if (supported && leavesOrigin) {
  #|       anchor.target = "_blank";
  #|       anchor.rel = "noopener noreferrer";
  #|     }
  #|   };
  #|   document.addEventListener("click", listener, true);
  #|   return listener;
  #| }

///|
extern "js" fn remove_external_link_capture(listener : @js.Value) -> Unit =
  #| (listener) => document.removeEventListener("click", listener, true)
