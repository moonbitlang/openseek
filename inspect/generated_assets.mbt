// The viewer assets built into a published `moonbitlang/inspect`. This
// committed copy is deliberately empty so git never carries the 2 MB bundle:
// `node scripts/embed_inspect_assets.mjs` overwrites it with the real
// `web/index.html` and release `viz_app.js` when `scripts/publish.mjs inspect`
// stages the package. A build from a checkout serves both files from disk.

///|
/// The viewer shell (`web/index.html`), or empty in a source checkout.
let embedded_index_html : String = ""

///|
/// The release frontend bundle (`viz_app.js`), or empty in a source checkout.
let embedded_viz_app_js : String = ""
