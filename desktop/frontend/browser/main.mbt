// The browser shell: the console bundle openseek-api serves under `/console/`
// (its Dockerfile builds this package and ships `browser.js` with the
// sibling `index.html`). It shares everything with the desktop shell
// today; console-only features will migrate here as the core splits.

///|
fn main {
  @frontend.boot(desktop=false)
}
