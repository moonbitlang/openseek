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
  let query = if hash.has_prefix("#") { hash[1:].to_owned() } else { hash }
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
extern "js" fn data_transfer_file_count(transfer : @dom.DataTransfer) -> Int = "(t) => (t.files ? t.files.length : 0)"

///|
extern "js" fn data_transfer_file_name(
  transfer : @dom.DataTransfer,
  index : Int,
) -> String = "(t, i) => t.files[i].name"

///|
extern "js" fn data_transfer_file(
  transfer : @dom.DataTransfer,
  index : Int,
) -> @dom.Blob = "(t, i) => t.files[i]"

///|
extern "js" fn format_unix_ms_utc(milliseconds : Double) -> String =
  #|(milliseconds) => {
  #|  const date = new Date(milliseconds);
  #|  if (!Number.isFinite(date.getTime())) return "";
  #|  return date.toISOString().slice(0, 16).replace("T", " ") + " UTC";
  #|}
