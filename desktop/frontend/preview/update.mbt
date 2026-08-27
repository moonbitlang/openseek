// The browser subsystem's pure message machine. Everything here mirrors
// either a keystroke in the address bar or a view event the host reported;
// the commands that talk to the host (open/navigate/back/close and the
// bounds sync) are the root update's business.

///|
pub(all) enum Msg {
  // The address bar's draft changed.
  InputChanged(id~ : String, value~ : String)
  // Host view events, decoded from `browser.event` notifications.
  Navigated(id~ : String, url~ : String)
  LoadingChanged(id~ : String, loading~ : Bool)
  TitleUpdated(id~ : String, title~ : String)
  LoadFailed(id~ : String, url~ : String, text~ : String)
}

///|
pub fn update(msg : Msg, state : State) -> State {
  fn patch(id : String, apply : (PageState) -> PageState) -> State {
    guard state.pages.get(id) is Some(page) else { return state }
    let pages = state.pages.copy()
    pages[id] = apply(page)
    { pages, }
  }

  match msg {
    InputChanged(id~, value~) => patch(id, page => { ..page, input: value, })
    // The committed URL replaces the draft: the bar names what the pane
    // shows, exactly like a browser's address bar after a navigation. A
    // navigation the page started itself (a link click, a redirect) arrives
    // only here, so it goes through the same commit as a typed one.
    Navigated(id~, url~) => patch(id, page => page.commit_url(url))
    LoadingChanged(id~, loading~) => patch(id, page => { ..page, loading, })
    TitleUpdated(id~, title~) => patch(id, page => { ..page, title, })
    // A failure for a URL the page has already left behind is not this
    // page's failure to show: a superseded load can report its error after
    // the replacing navigation committed (the same lateness that makes
    // ERR_ABORTED unusable — see `browser_event_msg`), and the banner would
    // then sit over a healthy page for good. Dropping it costs nothing:
    // `loading` is driven by its own event, so the new load still ends.
    LoadFailed(id~, url~, text~) =>
      patch(id, page => {
        if page.url == Some(url) {
          { ..page, loading: false, failure: Some("\{url}: \{text}"), }
        } else {
          page
        }
      })
  }
}
