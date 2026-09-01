///|
/// The complete Browser application directory. Release CI archives this for
/// openseek-api's same-origin `/console/` deployment.
const BrowserDistDir : String = "dist/browser"

///|
/// The browser JS bundle's path below its selected debug/release directory.
const BrowserBundleArtifact : String = "build/openseek_desktop/frontend/browser/browser.js"

///|
/// Build and stage every browser asset behind one MoonBit packaging command.
///
/// xterm's standalone esbuild executable must match the machine running this
/// packager. Production runs inside a Linux x64 Docker build; the other
/// selections keep the same command usable by the supported desktop hosts.
async fn main {
  let matches = @argparse.Command(
    "backend/package/browser",
    about="Build and stage the browser frontend assets.",
    flags=[
      FlagArg(
        "release",
        about="Build optimized release artifacts instead of debug artifacts.",
      ),
    ],
  ).parse()
  let release = matches.flags.get("release").unwrap_or(false)
  let release_args = if release { ["--release"] } else { [] }
  let mode = if release { "release" } else { "debug" }
  let ws = @packaging.locate_workspace()
  @packaging.remove_path_if_exists(ws.at(BrowserDistDir))
  @packaging.ensure_dir(ws.at(BrowserDistDir))
  @packaging.run_checked(
    "moon",
    ["build", "frontend/browser", "--target", "js", ..release_args],
    dir=ws.dir(),
  )
  @packaging.build_app_stylesheet(ws)
  @packaging.build_viewer_stylesheet(ws)
  @packaging.build_mermaid_assets(ws)
  let esbuild_target = if @platform.linux {
    @xterm_assets.linux_x64_target()
  } else if @platform.apple_os_mac {
    @xterm_assets.macos_arm64_target()
  } else if @platform.win64 {
    @xterm_assets.windows_x64_target()
  } else {
    raise @packaging.PackageError(
      "browser packaging supports Linux x64, macOS arm64, and Windows x64 hosts",
    )
  }
  let terminal_assets = @xterm_assets.build(ws, esbuild_target)
  @packaging.copy_file(
    ws.at("frontend/browser/index.html"),
    ws.at(BrowserDistDir + "/index.html"),
  )
  @packaging.copy_file(
    ws.repo_at("_build/js/\{mode}/\{BrowserBundleArtifact}"),
    ws.at(BrowserDistDir + "/browser.js"),
  )
  @packaging.copy_file(ws.app_stylesheet(), ws.at(BrowserDistDir + "/app.css"))
  @packaging.copy_file(
    ws.at("viewer.css"),
    ws.at(BrowserDistDir + "/viewer.css"),
  )
  @packaging.copy_file(
    ws.at("codicon.ttf"),
    ws.at(BrowserDistDir + "/codicon.ttf"),
  )
  @packaging.copy_file(
    terminal_assets.javascript,
    ws.at(BrowserDistDir + "/xterm.js"),
  )
  @packaging.copy_file(
    terminal_assets.stylesheet,
    ws.at(BrowserDistDir + "/xterm.css"),
  )
  @packaging.copy_tree(ws.mermaid_assets(), ws.at(BrowserDistDir + "/mermaid"))
  @packaging.copy_tree(ws.at("fonts"), ws.at(BrowserDistDir + "/fonts"))
  println("generated \{ws.at(BrowserDistDir)}")
}
