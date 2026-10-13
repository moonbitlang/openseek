///|
pub(all) enum PdfStatus {
  PdfLoading
  PdfReady
  PdfPasswordRequired(incorrect~ : Bool)
  PdfFailed(String)
} derive(Eq)

///|
pub extend PdfStatus with Eq::{equal, not_equal}

///|
/// A tab owns its bytes and reading position; one generation owns the mounted
/// PDF.js session. Password input is cleared after submission and every load.
pub(all) struct PdfDocument {
  bytes : Bytes
  generation : Int32
  status : PdfStatus
  page : Int32
  pages : Int32?
  rotation : Int32
  search : (Int32, Int32)?
  password : String
} derive(Eq)

///|
pub extend PdfDocument with Eq::{equal, not_equal}

///|
fn decode_pdf_document(
  locale~ : @i18n.Locale = English,
  data_base64 : String,
  generation : Int32,
) -> Result[PdfDocument, String] {
  let bytes = @base64.decode(data_base64) catch {
    _ => return Err(ui(locale, PdfPreviewFailed))
  }
  Ok({
    bytes,
    generation,
    status: PdfLoading,
    page: 1,
    pages: None,
    rotation: 0,
    search: None,
    password: "",
  })
}

///|
fn active_pdf_document(
  state : State,
  ctx : Ctx,
) -> (@common.Uri, PdfDocument, String)? {
  guard ctx.active_history_diff is None && ctx.active_file is Some(path) else {
    return None
  }
  match state.docs.get(path) {
    Some({ state: TabPdf(document~, sig~), .. }) => Some((path, document, sig))
    _ => None
  }
}

///|
/// Validate asynchronous PDF callbacks before consuming state or a selection.
/// A reload, placement change, closed tab, or conversation switch retires them.
pub fn State::accepts_pdf_callback(
  self : State,
  ctx : Ctx,
  owner : @interop.ConversationKey,
  epoch : Int32,
  path : @common.Uri,
  sig : String,
  generation : Int32,
) -> Bool {
  self.owner == Some(owner) &&
  ctx.owner == owner &&
  self.request_epoch == epoch &&
  ctx.active_history_diff is None &&
  ctx.active_file == Some(path) &&
  (match self.docs.get(path) {
    Some({ state: TabPdf(document~, sig=current), stale: false, .. }) =>
      current == sig &&
      document.generation == generation &&
      !(document.status is PdfFailed(_))
    _ => false
  })
}

///|
fn pdf_surface_config(
  state : State,
  path : @common.Uri,
) -> @office_viewer.SurfaceConfig {
  {
    surface_id: OfficeSurfaceId,
    kind: Some(@office_viewer.Pdf),
    document_file: path.path,
    surface_html: @office_viewer.pdf_surface_html(),
    zoom: state.office_zoom,
    query: state.office_query,
    prefer_system_fonts: false,
  }
}

///|
fn show_pdf_document(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  path : @common.Uri,
  document : PdfDocument,
  sig : String,
) -> @cmd.Cmd {
  let config = pdf_surface_config(state, path)
  let load = @office_viewer.load_pdf_command(
    config,
    document.bytes,
    selection => {
      dispatch(
        PdfSelectionChanged(
          owner=ctx.owner,
          epoch=state.request_epoch,
          path~,
          sig~,
          generation=document.generation,
          selection~,
        ),
      )
    },
    event => {
      dispatch(
        PdfStateChanged(
          owner=ctx.owner,
          epoch=state.request_epoch,
          path~,
          sig~,
          generation=document.generation,
          event~,
        ),
      )
    },
  )
  @cmd.batch([load, office_pinch_command(dispatch, config)])
}

///|
fn State::with_pdf_document(
  self : State,
  path : @common.Uri,
  document : PdfDocument,
) -> State {
  guard self.docs.get(path) is Some(doc) && doc.state is TabPdf(sig~, ..) else {
    return self
  }
  let docs = self.docs.copy()
  docs[path] = { ..doc, state: TabPdf(document~, sig~), }
  { ..self, docs, }
}

///|
fn Doc::prepare_pdf_runtime(self : Doc, generation : Int32) -> Doc {
  match self.state {
    TabPdf(document~, sig~) => {
      let document = {
        ..document,
        generation,
        status: PdfLoading,
        password: "",
      }
      { ..self, state: TabPdf(document~, sig~), }
    }
    _ => self
  }
}

///|
fn State::record_pdf_generation(self : State, doc : Doc) -> State {
  match doc.state {
    TabPdf(document~, ..) if document.generation > self.pdf_generation =>
      { ..self, pdf_generation: document.generation, }
    _ => self
  }
}

///|
/// PDF.js emits JSON events through the reusable viewer's String callback.
/// Reject missing, null, fractional, non-finite, and out-of-range counts.
fn pdf_event_int(value : Json, allow_zero~ : Bool = false) -> Int32? {
  guard value is Number(number, ..) &&
    !number.is_nan() &&
    !number.is_inf() &&
    number >= (if allow_zero { 0.0 } else { 1.0 }) &&
    number <= 2147483647.0 &&
    number == number.to_int().to_double() else {
    return None
  }
  Some(number.to_int())
}

///|
fn apply_pdf_event(
  locale~ : @i18n.Locale = English,
  state : State,
  path : @common.Uri,
  document : PdfDocument,
  raw : String,
) -> (@cmd.Cmd, State) {
  let event = @json.parse(raw) catch { _ => return (@cmd.none, state) }
  let mut command = @cmd.none
  let next = match event {
    { "status": String("ready"), "pages": pages, .. } => {
      guard pdf_event_int(pages) is Some(pages) else {
        return (@cmd.none, state)
      }
      let page = if document.page > pages { pages } else { document.page }
      command = @cmd.batch([
        @office_viewer.pdf_page_command(OfficeSurfaceId, page),
        @office_viewer.pdf_rotation_command(OfficeSurfaceId, document.rotation),
      ])
      { ..document, status: PdfReady, pages: Some(pages), page, password: "", }
    }
    { "status": String("page"), "page": page, .. } => {
      // pagesinit emits page 1 before ready. Preserve a parked tab's page
      // until ready restores it, rather than overwriting it during mounting.
      if document.status is PdfLoading {
        return (@cmd.none, state)
      }
      guard pdf_event_int(page) is Some(page) &&
        document.pages.map(pages => page <= pages).unwrap_or(true) else {
        return (@cmd.none, state)
      }
      { ..document, page, }
    }
    { "status": String("scale"), "zoom": zoom, .. } => {
      guard pdf_event_int(zoom) is Some(zoom) else { return (@cmd.none, state) }
      return (@cmd.none, { ..state, office_zoom: zoom, })
    }
    { "status": String("rotation"), "rotation": rotation, .. } => {
      guard pdf_event_int(rotation, allow_zero=true) is Some(rotation) &&
        rotation < 360 &&
        rotation % 90 == 0 else {
        return (@cmd.none, state)
      }
      { ..document, rotation, }
    }
    { "status": String("search"), "current": current, "total": total, .. } => {
      guard pdf_event_int(current, allow_zero=true) is Some(current) &&
        pdf_event_int(total, allow_zero=true) is Some(total) &&
        current <= total else {
        return (@cmd.none, state)
      }
      { ..document, search: Some((current, total)), }
    }
    { "status": String("password"), "incorrect": True, .. } =>
      { ..document, status: PdfPasswordRequired(incorrect=true), password: "", }
    { "status": String("password"), "incorrect": False, .. } =>
      {
        ..document,
        status: PdfPasswordRequired(incorrect=false),
        password: "",
      }
    { "status": String("error"), "message": String(_), .. } => {
      command = clear_office_surface()
      {
        ..document,
        status: PdfFailed(ui(locale, PdfPreviewFailed)),
        password: "",
      }
    }
    { "status": String("selection-error"), "message": String(_), .. } =>
      return (
        @cmd.none,
        { ..state, error: Some(ui(locale, OfficeSelectionFailed)), },
      )
    // Progress does not erase a password prompt or a ready document. Unknown
    // statuses and malformed events deliberately leave the tab unchanged.
    _ => return (@cmd.none, state)
  }
  (command, state.with_pdf_document(path, next))
}

///|
fn update_pdf(state : State, ctx : Ctx, msg : Msg) -> (@cmd.Cmd, State) {
  guard active_pdf_document(state, ctx) is Some((path, document, _)) else {
    return (@cmd.none, state)
  }
  match msg {
    PdfStateChanged(owner~, epoch~, path=event_path, sig~, generation~, event~) => {
      guard state.accepts_pdf_callback(
        ctx, owner, epoch, event_path, sig, generation,
      ) else {
        return (@cmd.none, state)
      }
      apply_pdf_event(locale=ctx.locale, state, path, document, event)
    }
    PdfPageChanged(raw) => {
      guard document.status is PdfReady && document.pages is Some(pages) else {
        return (@cmd.none, state)
      }
      let page = @string.parse_int(raw) catch { _ => return (@cmd.none, state) }
      let page = if page < 1 { 1 } else if page > pages { pages } else { page }
      (@office_viewer.pdf_page_command(OfficeSurfaceId, page), state)
    }
    PdfFitWidth if document.status is PdfReady =>
      (@office_viewer.pdf_fit_width_command(OfficeSurfaceId), state)
    PdfRotated if document.status is PdfReady =>
      (
        @office_viewer.pdf_rotation_command(
          OfficeSurfaceId,
          (document.rotation + 90) % 360,
        ),
        state,
      )
    PdfFind(previous) if document.status is PdfReady =>
      (@office_viewer.pdf_find_command(OfficeSurfaceId, previous), state)
    PdfPasswordChanged(password) if document.status is PdfPasswordRequired(_) =>
      (@cmd.none, state.with_pdf_document(path, { ..document, password, }))
    PdfPasswordSubmitted if document.status is PdfPasswordRequired(_) &&
      !document.password.is_empty() =>
      (
        @office_viewer.pdf_password_command(OfficeSurfaceId, document.password),
        state.with_pdf_document(path, {
          ..document,
          status: PdfLoading,
          password: "",
        }),
      )
    PdfPasswordCancelled if document.status is PdfPasswordRequired(_) =>
      (
        clear_document(),
        state.with_pdf_document(path, {
          ..document,
          status: PdfFailed(ui(ctx.locale, PdfPreviewCancelled)),
          password: "",
        }),
      )
    _ => (@cmd.none, state)
  }
}
