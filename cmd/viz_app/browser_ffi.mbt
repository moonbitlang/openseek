// Browser access for the session viewer. Prefer Rabbita's typed DOM API;
// use its JS interop for missing bindings and keep the remaining FFI here.

///|
priv struct HashParams(@js.Value)

///|
fn read_hash_params() -> HashParams? {
  let location : @js.Value = @js.globalThis.get_with_string("location")
  if location.is_undefined() {
    return None
  }
  let hash : String = location.get_with_string("hash")
  let raw = if hash.is_empty() || hash == "#" {
    initial_hash_override()
  } else {
    hash
  }
  let query = if raw.has_prefix("#") { raw[1:].to_owned() } else { raw }
  let params : @js.Value = @js.globalThis.new_with_string("URLSearchParams", [
    query,
  ])
  Some(HashParams(params))
}

///|
fn HashParams::get(self : HashParams, key : String) -> String? {
  let value : @js.Nullable[String] = self.0.apply_with_string("get", [key])
  value.to_option()
}

///|
fn HashParams::set(self : HashParams, key : String, value : String) -> Unit {
  self.0.apply_with_string("set", [key, value])
}

///|
fn HashParams::delete(self : HashParams, key : String) -> Unit {
  self.0.apply_with_string("delete", [key])
}

///|
fn HashParams::save(self : HashParams) -> Unit {
  @dom.window().replace_url("#" + self.0.to_string())
}

///|
// Keep JS coercion semantics: parseInt accepts a decimal prefix, whereas
// Number consumes the whole value and treats an empty string as zero.
fn decimal_prefix(value : String) -> Double {
  @js.globalThis.apply_with_string("parseInt", [
    @js.Value::cast_from(value),
    @js.Value::cast_from(10),
  ])
}

///|
fn browser_number(value : String) -> Double {
  @js.globalThis.apply_with_string("Number", [value])
}

///|
fn toggle_class(element : @dom.Element, name : String, enabled : Bool) -> Unit {
  let classes : @js.Value = @js.Value::cast_from(element).get_with_string(
    "classList",
  )
  let _ : Bool = classes.apply_with_string("toggle", [
    @js.Value::cast_from(name),
    @js.Value::cast_from(enabled),
  ])
}

///|
fn element_style(element : @dom.Element) -> @dom.CSSStyleDeclaration {
  @js.Value::cast_from(element).get_with_string("style")
}

///|
fn set_text_content(element : @dom.Element, text : String) -> Unit {
  @js.Value::cast_from(element).set_with_string("textContent", text)
}

///|
fn element_offset_width(element : @dom.Element) -> Double {
  @js.Value::cast_from(element).get_with_string("offsetWidth")
}

///|
fn encode_uri_component(value : String) -> String {
  @js.globalThis.apply_with_string("encodeURIComponent", [value])
}

///|
/// Set `data-theme` on the document root. `light`/`dark` pick a fixed palette;
/// `system` defers to the OS via the stylesheet's `prefers-color-scheme` query.
extern "js" fn set_document_theme(theme : String) -> Unit = "(t) => document.documentElement.setAttribute('data-theme', t)"

///|
/// Whether a self-contained export (see `inspect --export`) baked a
/// response for `url` into `window.__OPENSEEK_DATA__`. False in a normal server
/// build, where the global is absent and every lookup misses.
extern "js" fn embedded_has(url : String) -> Bool = "(url) => (typeof window !== 'undefined') && !!window.__OPENSEEK_DATA__ && Object.prototype.hasOwnProperty.call(window.__OPENSEEK_DATA__, url)"

///|
/// The baked response body for `url`. Only called after `embedded_has` is true.
extern "js" fn embedded_get(url : String) -> String = "(url) => window.__OPENSEEK_DATA__[url]"

///|
/// `rabbita/dom` binds `DataTransfer.items` but not `DataTransfer.files`; a
/// dropped `File` is a `Blob` subtype, which is all the reader needs.
extern "js" fn data_transfer_file_count(transfer : @dom.DataTransfer) -> Int32 = "(t) => (t.files ? t.files.length : 0)"

///|
extern "js" fn data_transfer_file_name(
  transfer : @dom.DataTransfer,
  index : Int32,
) -> String = "(t, i) => t.files[i].name"

///|
extern "js" fn data_transfer_file(
  transfer : @dom.DataTransfer,
  index : Int32,
) -> @dom.Blob = "(t, i) => t.files[i]"

///|
extern "js" fn format_unix_ms_local(milliseconds : Double) -> String =
  #|(milliseconds) => {
  #|  const date = new Date(milliseconds);
  #|  if (!Number.isFinite(date.getTime())) return "";
  #|  const pad = (n) => String(n).padStart(2, "0");
  #|  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
  #|}

///|
extern "js" fn local_tz_offset_ms(milliseconds : Double) -> Double =
  #|(milliseconds) => {
  #|  const date = new Date(milliseconds);
  #|  return Number.isFinite(date.getTime()) ? -date.getTimezoneOffset() * 60000 : 0;
  #|}

///|
extern "js" fn local_tz_label(milliseconds : Double) -> String =
  #|(milliseconds) => {
  #|  const date = new Date(milliseconds);
  #|  if (!Number.isFinite(date.getTime())) return "LOCAL";
  #|  const offsetMin = -date.getTimezoneOffset();
  #|  if (offsetMin === 0) return "UTC";
  #|  const sign = offsetMin > 0 ? "+" : "-";
  #|  const abs = Math.abs(offsetMin);
  #|  const h = Math.floor(abs / 60);
  #|  const m = abs % 60;
  #|  return m === 0 ? `UTC${sign}${h}` : `UTC${sign}${h}:${String(m).padStart(2, "0")}`;
  #|}

///|
/// The `inspect --watch` polling interval the server injected into the shell as
/// `window.__OPENSEEK_WATCH_MS__`, or 0 when absent (no `--watch`).
extern "js" fn watch_interval_ms() -> Int32 = "() => { const ms = (typeof window !== 'undefined') ? window.__OPENSEEK_WATCH_MS__ : undefined; return (Number.isInteger(ms) && ms > 0) ? ms : 0; }"

///|
/// Whether the scrolling `.main` pane is at (or within a few lines of) its
/// bottom, so a watch refresh knows the reader is following the log.
extern "js" fn main_scrolled_to_bottom() -> Bool = "() => { const main = document.querySelector('.main'); return !main || main.scrollHeight - main.scrollTop - main.clientHeight < 80; }"

///|
/// Scroll `.main` to its bottom once the freshly rendered events are laid out.
extern "js" fn scroll_main_to_bottom() -> Unit = "() => { requestAnimationFrame(() => requestAnimationFrame(() => { const main = document.querySelector('.main'); if (main) main.scrollTop = main.scrollHeight; })); }"

///|
/// An initial hash injected into a generated temporary HTML snapshot so
/// `file://` opens directly on `#t=<root>&job=<id>` even when the OS launcher
/// drops URL fragments.
extern "js" fn initial_hash_override() -> String = "() => (typeof window !== 'undefined' && typeof window.__OPENSEEK_INITIAL_HASH__ === 'string') ? window.__OPENSEEK_INITIAL_HASH__ : ''"

///|
/// Scroll the first failed step of the open waterfall into view: the error card
/// in the stats header is the only caller.
extern "js" fn scroll_to_first_failure() -> Unit = "() => { const row = document.querySelector('.waterfall-row.status-failed'); if (row) row.scrollIntoView({block: 'center'}); }"

///|
/// Scroll the job row named by `#t=<root>&job=<id>` into view.
extern "js" fn scroll_to_focused_job() -> Unit = "() => { const row = document.querySelector('.waterfall-row.job-focus'); if (row) row.scrollIntoView({block: 'center'}); }"

///|
/// Read the current scroll offset (px) of `.waterfall-body` relative to `.main`'s
/// top viewport edge, plus `.main`'s client height.
extern "js" fn read_waterfall_scroll_top() -> Int32 = "() => { const main = document.querySelector('.main'); const body = document.querySelector('.waterfall-body'); if (!main || !body) return 0; const mRect = main.getBoundingClientRect(); const bRect = body.getBoundingClientRect(); return Math.max(0, Math.floor(mRect.top - bRect.top)); }"

///|
extern "js" fn read_waterfall_viewport_h() -> Int32 = "() => { const main = document.querySelector('.main'); return main ? Math.max(300, Math.floor(main.clientHeight)) : 900; }"

///|
/// Scroll `.main` so the virtualized row at `index` sits near the center.
extern "js" fn scroll_to_waterfall_row(
  index : Int32,
  row_height : Int32,
) -> Unit = "(index, rowHeight) => { requestAnimationFrame(() => { const main = document.querySelector('.main'); const body = document.querySelector('.waterfall-body'); if (!main || !body) return; const mRect = main.getBoundingClientRect(); const bRect = body.getBoundingClientRect(); const bodyTop = main.scrollTop + (bRect.top - mRect.top); const target = Math.max(0, bodyTop + index * rowHeight - Math.floor(main.clientHeight / 2)); main.scrollTop = target; }); }"

///|
/// The browser's wall clock in unix milliseconds. A trace span that has not
/// ended is stretched to this instant, so its bar grows while the run is still
/// going instead of sitting frozen at its start.
///
/// `Date.now()` yields a JavaScript number, which this backend's `Int64` cannot
/// represent (it is a BigInt): hand it over as one or every conversion throws.
extern "js" fn browser_now_ms() -> Int64 = "() => BigInt(Date.now())"
