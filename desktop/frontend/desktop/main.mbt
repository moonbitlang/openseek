// The desktop shell: the bundle the proton webview loads as
// `assets/frontend.js` (packaging copies `desktop.js` there). It shares
// everything with the browser shell today; desktop-only features will
// migrate here as the core splits.

///|
fn main {
  @frontend.boot()
}
