///|
/// Parsed, inert browser content. MoonBit owns all policy applied to this tree;
/// the browser owns only HTML parsing and fragment insertion.
#external
priv type MarkdownParsedContent

///|
#external
priv type MarkdownTargetRegistry

///|
#external
priv type MarkdownTargetToken

///|
#external
priv type MermaidModuleLoader

///|
#external
priv type MermaidApi

///|
#external
priv type MermaidRenderResult

///|
extern "js" fn new_local_mermaid_module_loader() -> MermaidModuleLoader =
  #| () => (path) => import(new URL(path, document.baseURI).href)

///|
let local_mermaid_module_loader : MermaidModuleLoader = new_local_mermaid_module_loader()

///|
extern "js" fn new_markdown_target_registry() -> MarkdownTargetRegistry =
  #| () => {
  #|   const slot = Symbol.for(
  #|     "moonbitlang/editor/internal/viewer/browser/markdown/target-registry",
  #|   );
  #|   return globalThis[slot] || (globalThis[slot] = new WeakMap());
  #| }

///|
let markdown_target_registry : MarkdownTargetRegistry = new_markdown_target_registry()

///|
/// Installs one active lifetime per reusable target without writing ownership
/// state onto caller DOM.
extern "js" fn install_markdown_target_lifetime(
  registry : MarkdownTargetRegistry,
  target : @rdom.Element,
  dispose : () -> Unit,
) -> MarkdownTargetToken =
  #| (registry, target, dispose) => {
  #|   const previous = registry.get(target);
  #|   if (previous) previous.dispose();
  #|   const token = { dispose };
  #|   registry.set(target, token);
  #|   return token;
  #| }

///|
extern "js" fn clear_markdown_target_lifetime(
  registry : MarkdownTargetRegistry,
  target : @rdom.Element,
  token : MarkdownTargetToken,
) -> Unit =
  #| (registry, target, token) => {
  #|   if (registry.get(target) === token) registry.delete(target);
  #| }

///|
extern "js" fn markdown_target_lifetime_is_current(
  registry : MarkdownTargetRegistry,
  target : @rdom.Element,
  token : MarkdownTargetToken,
) -> Bool = "(registry, target, token) => registry.get(target) === token"

///|
/// `ownerDocument` is not exposed by the current Rabbita DOM bindings.
extern "js" fn markdown_owner_document(
  target : @rdom.Element,
) -> @rdom.Document = "(target) => target.ownerDocument || globalThis.document"

///|
/// Template content stays detached until MoonBit has removed or rewritten
/// every policy-sensitive node.
extern "js" fn parse_markdown_content(
  document : @rdom.Document,
  html : String,
) -> MarkdownParsedContent =
  #| (document, html) => {
  #|   const template = document.createElement("template");
  #|   template.innerHTML = html;
  #|   return template.content || template;
  #| }

///|
extern "js" fn markdown_content_query_all(
  content : MarkdownParsedContent,
  selector : String,
) -> FixedArray[@rdom.Element] = "(content, selector) => Array.from(content.querySelectorAll(selector))"

///|
extern "js" fn replace_target_with_markdown_content(
  target : @rdom.Element,
  content : MarkdownParsedContent,
) -> Unit = "(target, content) => target.replaceChildren(content)"

///|
extern "js" fn remove_markdown_element(element : @rdom.Element) -> Unit = "(element) => element.remove()"

///|
extern "js" fn disable_markdown_input(element : @rdom.Element) -> Unit =
  #| (element) => {
  #|   element.disabled = true;
  #|   element.setAttribute("disabled", "");
  #| }

///|
/// URL parsing and base resolution are browser capabilities. MoonBit decides
/// which returned protocols are allowed for links and images.
extern "js" fn with_resolved_markdown_uri(
  raw : String,
  base_uri : String,
  has_base_uri : Bool,
  resolved : (String, String) -> Unit,
) -> Bool =
  #| (raw, baseUri, hasBaseUri, resolved) => {
  #|   if (!raw) return false;
  #|   try {
  #|     const url = hasBaseUri ? new URL(raw, baseUri) : new URL(raw);
  #|     resolved(url.href, url.protocol.toLowerCase());
  #|     return true;
  #|   } catch (_error) {
  #|     return false;
  #|   }
  #| }

///|
extern "js" fn markdown_event_button(event : @rdom.Event) -> Int = "(event) => event.button === undefined ? -1 : Number(event.button)"

///|
extern "js" fn markdown_event_key(event : @rdom.Event) -> String = "(event) => String(event.key || '')"

///|
extern "js" fn markdown_event_delta_x(event : @rdom.Event) -> Double = "(event) => Number(event.deltaX || 0)"

///|
extern "js" fn markdown_event_delta_y(event : @rdom.Event) -> Double = "(event) => Number(event.deltaY || 0)"

///|
extern "js" fn markdown_event_shift_key(event : @rdom.Event) -> Bool = "(event) => event.shiftKey === true"

///|
extern "js" fn markdown_node_text_content(node : @rdom.Node) -> String = "(node) => String(node.textContent || '')"

///|
/// The focused fake DOM predates `Node.contains`; real browser targets take the
/// strict branch.
extern "js" fn markdown_target_contains_if_supported(
  target : @rdom.Element,
  child : @rdom.Element,
) -> Bool = "(target, child) => typeof target.contains !== 'function' || target.contains(child)"

///|
extern "js" fn same_mermaid_loader(
  left : MermaidModuleLoader,
  right : MermaidModuleLoader,
) -> Bool = "(left, right) => left === right"

///|
/// Only the registry is JS-owned. The value stored in it is the MoonBit
/// runtime struct, preserving realm-wide serialization across bundle copies.
extern "js" fn get_or_create_shared_mermaid_runtime(
  create : () -> MermaidRuntime,
) -> MermaidRuntime =
  #| (create) => {
  #|   const slot = Symbol.for(
  #|     "moonbitlang/editor/internal/viewer/browser/markdown/moonbit-mermaid-runtime",
  #|   );
  #|   return globalThis[slot] || (globalThis[slot] = create());
  #| }

///|
/// Loading validates the exact Mermaid API surface before exposing it to the
/// MoonBit-owned runtime.
extern "js" fn start_mermaid_module_load(
  loader : MermaidModuleLoader,
  url : String,
  loaded : (MermaidApi) -> Unit,
  failed : () -> Unit,
) -> Unit =
  #| (loader, url, loaded, failed) => {
  #|   Promise.resolve()
  #|     .then(() => loader(url))
  #|     .then(
  #|       (module) => {
  #|         const mermaid = module && module.default;
  #|         if (
  #|           !mermaid ||
  #|           typeof mermaid.initialize !== "function" ||
  #|           typeof mermaid.render !== "function"
  #|         ) {
  #|           failed();
  #|           return;
  #|         }
  #|         loaded(mermaid);
  #|       },
  #|       () => failed(),
  #|     );
  #| }

///|
/// Promise adaptation and the Mermaid object/config calls remain at the JS
/// capability boundary; queueing and result ownership remain in MoonBit.
extern "js" fn start_mermaid_api_render(
  mermaid : MermaidApi,
  theme : String,
  id : String,
  source : String,
  rendered : (MermaidRenderResult) -> Unit,
  failed : () -> Unit,
  settled : () -> Unit,
) -> Unit =
  #| (mermaid, theme, id, source, rendered, failed, settled) => {
  #|   Promise.resolve()
  #|     .then(() => {
  #|       mermaid.initialize({
  #|         startOnLoad: false,
  #|         securityLevel: "strict",
  #|         suppressErrorRendering: true,
  #|         theme,
  #|         secure: [
  #|           "secure",
  #|           "securityLevel",
  #|           "startOnLoad",
  #|           "maxTextSize",
  #|           "suppressErrorRendering",
  #|           "maxEdges",
  #|           "theme",
  #|           "darkMode",
  #|           "themeVariables",
  #|           "themeCSS",
  #|         ],
  #|       });
  #|       return mermaid.render(id, source);
  #|     })
  #|     .then(rendered, failed)
  #|     .then(settled, settled);
  #| }

///|
extern "js" fn with_mermaid_render_svg(
  result : MermaidRenderResult,
  commit : (String) -> Unit,
) -> Bool =
  #| (result, commit) => {
  #|   if (!result || typeof result.svg !== "string") return false;
  #|   commit(result.svg);
  #|   return true;
  #| }

///|
extern "js" fn try_bind_mermaid_result(
  result : MermaidRenderResult,
  wrapper : @rdom.Element,
) -> Unit =
  #| (result, wrapper) => {
  #|   if (typeof result?.bindFunctions !== "function") return;
  #|   try {
  #|     result.bindFunctions(wrapper);
  #|   } catch (_error) {
  #|     // The accepted SVG remains usable without optional bindings.
  #|   }
  #| }

///|
extern "js" fn new_mermaid_id_nonce() -> String =
  #| () => {
  #|   const crypto = globalThis.crypto;
  #|   if (crypto && typeof crypto.randomUUID === "function") {
  #|     return crypto.randomUUID();
  #|   }
  #|   if (crypto && typeof crypto.getRandomValues === "function") {
  #|     const words = crypto.getRandomValues(new Uint32Array(4));
  #|     return Array.from(words, (word) => word.toString(36)).join("-");
  #|   }
  #|   return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  #| }

///|
extern "js" fn mermaid_id_is_available(
  owner_document : @rdom.Document,
  id : String,
) -> Bool =
  #| (ownerDocument, id) => {
  #|   const documents = Array.from(
  #|     new Set([ownerDocument, globalThis.document].filter(Boolean)),
  #|   );
  #|   return documents.every((document) => {
  #|     if (typeof document.getElementById !== "function") return true;
  #|     return !document.getElementById(id) &&
  #|       !document.getElementById(`d${id}`) &&
  #|       !document.getElementById(`i${id}`);
  #|   });
  #| }
