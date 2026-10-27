///|
pub struct OfficeCitationNavigation {
  owner : @interop.ConversationIdentity
  epoch : Int32
  generation : Int32
  path : @common.Uri
  target : @office_location.Target
} derive(Eq, Debug)

///|
pub extend OfficeCitationNavigation with Eq::{equal, not_equal}

///|
pub extend OfficeCitationNavigation with Debug::{to_repr}

///|
fn OfficeCitationNavigation::is_current(
  self : OfficeCitationNavigation,
  state : State,
  ctx : Ctx,
) -> Bool {
  state.owner == Some(self.owner) &&
  ctx.owner == self.owner &&
  state.request_epoch == self.epoch &&
  state.file_link_generation == self.generation &&
  ctx.panel_open &&
  ctx.active_history_diff is None &&
  ctx.active_file == Some(self.path)
}

///|
/// Wait for the file and PDF session, then consume this click exactly once.
/// New navigation, tab/conversation changes and reload epochs retire it.
fn State::sync_office_navigation(
  self : State,
  dispatch : @cmd.Emit[Msg],
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  guard self.office_navigation is Some(navigation) else {
    return (@cmd.none, self)
  }
  guard navigation.is_current(self, ctx) else {
    return (@cmd.none, { ..self, office_navigation: None, })
  }
  let page_command = match self.docs.get(navigation.path) {
    None | Some({ state: TabLoading, .. }) => return (@cmd.none, self)
    Some({ state: TabPdf(document~, ..), stale: false, .. }) =>
      match document.status {
        PdfLoading | PdfPasswordRequired(..) => return (@cmd.none, self)
        PdfReady => {
          guard navigation.target is PdfPage(page) &&
            document.pages is Some(pages) &&
            page <= pages else {
            return (
              @cmd.none,
              {
                ..self,
                office_navigation: None,
                error: Some(ui(ctx.locale, OfficeCitationUnavailable)),
              },
            )
          }
          @office_viewer.pdf_page_command(OfficeSurfaceId, page)
        }
        PdfFailed(_) => return (@cmd.none, { ..self, office_navigation: None, })
      }
    Some({ state: TabOffice(..), stale: false, .. }) => @cmd.none
    Some({ stale: true, .. }) => return (@cmd.none, self)
    _ =>
      return (
        @cmd.none,
        {
          ..self,
          office_navigation: None,
          error: Some(ui(ctx.locale, OfficeCitationUnavailable)),
        },
      )
  }
  let reveal = @cmd.custom_cmd(
    scheduler => {
      // A cold-opened panel may not be laid out yet. Re-arm through the
      // update loop so `is_current` still fences the later reveal.
      if @office_location.wait_for_layout(OfficeSurfaceId, navigation.target, () => {
          scheduler.add(dispatch(OfficeCitationLaidOut(navigation)))
        }) {
        return
      }
      let found = @js.Error_::wrap(
        () => {
          @js.Value::cast_from(
            @office_location.reveal(OfficeSurfaceId, navigation.target),
          )
        },
        map_ok=value => value.cast(),
      ) catch {
        _ => false
      }
      scheduler.add(dispatch(OfficeCitationLocated(navigation, found)))
    },
    kind=@cmd.after_render,
  )
  (@cmd.batch([page_command, reveal]), { ..self, office_navigation: None, })
}
