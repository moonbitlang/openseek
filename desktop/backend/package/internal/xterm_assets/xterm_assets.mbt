///|
const XtermVersion : String = "5.5.0"

///|
const FitVersion : String = "0.10.0"

///|
const WebLinksVersion : String = "0.11.0"

///|
const EsbuildVersion : String = "0.28.1"

///|
const VendorDir : String = "target/vendor-xterm"

///|
/// Records which raw upstream browser files are present in the development
/// cache. A version change invalidates the extracted tree without requiring a
/// separate clean command.
const DevelopmentStamp : String = "xterm=\{XtermVersion}\naddon-fit=\{FitVersion}\naddon-web-links=\{WebLinksVersion}\n"

///|
const XtermSha256 : String = "bd954fa721872170188cc5d7e83e88db3c83c9a18a4e8d24c2783d26491f59d2"

///|
const FitSha256 : String = "917ac44972453d5eed52edc1e50260c76398ce48cf2290c2e60671102bba0b33"

///|
const WebLinksSha256 : String = "cad54687a1447f87cd8dd9ce454d4d657d18cc7179e9179908f391b4512f74a0"

///|
const EntrySource : String =
  #|import { Terminal } from "./xterm/lib/xterm.js";
  #|import { FitAddon } from "./fit/lib/addon-fit.js";
  #|import { WebLinksAddon } from "./web-links/lib/addon-web-links.js";
  #|
  #|// Decode one base64 chunk of raw PTY bytes into the terminal; report the
  #|// byte count through `done` once xterm has rendered it (the flow-control
  #|// acknowledgement the OpenSeek frontend sends back).
  #|const writeBase64 = (term, b64, done) => {
  #|  const bin = atob(b64);
  #|  const out = new Uint8Array(bin.length);
  #|  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  #|  term.write(out, () => done(out.length));
  #|};
  #|
  #|globalThis.__openseek_xterm = { Terminal, FitAddon, WebLinksAddon, writeBase64 };
  #|

///|
/// The platform-specific npm package containing esbuild's native executable.
/// The type is opaque so callers can only select one of the supported desktop
/// packaging targets below.
struct EsbuildTarget {
  package_name : String
  binary_path : String
  sha256 : String
}

///|
/// Select esbuild's macOS arm64 executable package.
pub fn macos_arm64_target() -> EsbuildTarget {
  {
    package_name: "darwin-arm64",
    binary_path: "bin/esbuild",
    sha256: "5d64cc9bc527d598450b5f8d47ff293eb9f3aea38dd9eff67fd55d228c5ccb43",
  }
}

///|
/// Select esbuild's Linux x64 executable package.
pub fn linux_x64_target() -> EsbuildTarget {
  {
    package_name: "linux-x64",
    binary_path: "bin/esbuild",
    sha256: "9ed00ab5330c94386f3273eda99a1fb0e8f37cfd6cb5270e4ad2fe3527da3546",
  }
}

///|
/// Select esbuild's Windows x64 executable package.
pub fn windows_x64_target() -> EsbuildTarget {
  {
    package_name: "win32-x64",
    binary_path: "esbuild.exe",
    sha256: "5c5d62da7572b57ddc1fa3caedc36c1218b5d8d02ce9c7ee70e3339fce4453c4",
  }
}

///|
/// The generated files a platform packager must copy beside `index.html`.
pub struct Assets {
  /// The self-contained xterm.js and addon-fit browser bundle.
  javascript : String
  /// The upstream xterm.js stylesheet.
  stylesheet : String
}

///|
priv struct Archive {
  filename : String
  url : String
  sha256 : String
}

///|
fn Archive::xterm() -> Archive {
  {
    filename: "xterm-\{XtermVersion}.tgz",
    url: "https://registry.npmjs.org/@xterm/xterm/-/xterm-\{XtermVersion}.tgz",
    sha256: XtermSha256,
  }
}

///|
fn Archive::fit() -> Archive {
  {
    filename: "addon-fit-\{FitVersion}.tgz",
    url: "https://registry.npmjs.org/@xterm/addon-fit/-/addon-fit-\{FitVersion}.tgz",
    sha256: FitSha256,
  }
}

///|
fn Archive::web_links() -> Archive {
  {
    filename: "addon-web-links-\{WebLinksVersion}.tgz",
    url: "https://registry.npmjs.org/@xterm/addon-web-links/-/addon-web-links-\{WebLinksVersion}.tgz",
    sha256: WebLinksSha256,
  }
}

///|
fn Archive::esbuild(target : EsbuildTarget) -> Archive {
  {
    filename: "esbuild-\{target.package_name}-\{EsbuildVersion}.tgz",
    url: "https://registry.npmjs.org/@esbuild/\{target.package_name}/-/\{target.package_name}-\{EsbuildVersion}.tgz",
    sha256: target.sha256,
  }
}

///|
priv struct AssetBuilder {
  workspace : @packaging.Workspace
}

///|
fn AssetBuilder::at(self : AssetBuilder, relative : String) -> String {
  self.workspace.at("\{VendorDir}/\{relative}")
}

///|
async fn archive_digest(path : String) -> String {
  let bytes = @asyncfs.read_file(path).binary()
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes)).to_lower()
}

///|
async fn AssetBuilder::ensure_cached_archive(
  self : AssetBuilder,
  archive : Archive,
) -> String {
  let path = self.at("cache/\{archive.filename}")
  if @asyncfs.exists(path) {
    let actual = archive_digest(path)
    if actual == archive.sha256 {
      return path
    }
    println(
      "cached \{archive.filename} failed SHA-256 verification; downloading it again",
    )
    @packaging.remove_path_if_exists(path)
  }
  println("downloading \{archive.url}")
  let (response, body) = @http.get(archive.url) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      raise @packaging.PackageError(
        "failed to download \{archive.url}: \{error}",
      )
  }
  if response.code < 200 || response.code >= 300 {
    raise @packaging.PackageError(
      "failed to download \{archive.url}: HTTP \{response.code} \{response.reason}",
    )
  }
  @asyncfs.write_file(path, body, create_mode=CreateOrTruncate)
  let actual = archive_digest(path)
  if actual != archive.sha256 {
    @packaging.remove_path_if_exists(path)
    raise @packaging.PackageError(
      "SHA-256 mismatch for \{archive.filename}: expected \{archive.sha256}, got \{actual}",
    )
  }
  path
}

///|
async fn AssetBuilder::extract_archive(
  self : AssetBuilder,
  archive : String,
  destination : String,
) -> Unit {
  @packaging.remove_path_if_exists(destination)
  @packaging.ensure_dir(destination)
  @packaging.run_checked(
    "tar",
    ["-xzf", archive, "-C", destination, "--strip-components=1"],
    dir=self.workspace.dir(),
  )
}

///|
fn AssetBuilder::esbuild_binary(
  self : AssetBuilder,
  target : EsbuildTarget,
) -> String {
  self.at("work/esbuild/\{target.binary_path}")
}

///|
/// Prepare xterm's already browser-ready upstream UMD files for development.
/// No JavaScript is bundled or minified: the dev HTML loads xterm and
/// addon-fit/addon-web-links separately, then installs OpenSeek's small global
/// adapter.
pub async fn stage_development(workspace : @packaging.Workspace) -> Unit {
  let builder : AssetBuilder = { workspace, }
  let stamp = builder.at("work/development-versions")
  let xterm_javascript = builder.at("work/xterm/lib/xterm.js")
  let xterm_stylesheet = builder.at("work/xterm/css/xterm.css")
  let fit_javascript = builder.at("work/fit/lib/addon-fit.js")
  let web_links_javascript = builder.at("work/web-links/lib/addon-web-links.js")
  let mut reusable = @asyncfs.exists(stamp) &&
    @asyncfs.exists(xterm_javascript) &&
    @asyncfs.exists(xterm_stylesheet) &&
    @asyncfs.exists(fit_javascript) &&
    @asyncfs.exists(web_links_javascript)
  if reusable {
    reusable = @asyncfs.read_file(stamp).text() == DevelopmentStamp
  }
  if reusable {
    return
  }
  @packaging.ensure_dir(builder.at("cache"))
  let xterm_archive = builder.ensure_cached_archive(Archive::xterm())
  let fit_archive = builder.ensure_cached_archive(Archive::fit())
  let web_links_archive = builder.ensure_cached_archive(Archive::web_links())
  builder.extract_archive(xterm_archive, builder.at("work/xterm"))
  builder.extract_archive(fit_archive, builder.at("work/fit"))
  builder.extract_archive(web_links_archive, builder.at("work/web-links"))
  @packaging.write_text(stamp, DevelopmentStamp)
}

///|
/// Download verified, pinned xterm.js, addons, and native esbuild archives,
/// then generate the browser bundle and stylesheet under `target/vendor-xterm`.
///
/// Only downloaded archives are reused. Each packaging run recreates the
/// extracted sources and final files so a stale partial build cannot ship.
pub async fn build(
  workspace : @packaging.Workspace,
  esbuild_target : EsbuildTarget,
) -> Assets {
  let builder : AssetBuilder = { workspace, }
  @packaging.ensure_dir(builder.at("cache"))
  let xterm_archive = builder.ensure_cached_archive(Archive::xterm())
  let fit_archive = builder.ensure_cached_archive(Archive::fit())
  let web_links_archive = builder.ensure_cached_archive(Archive::web_links())
  let esbuild_archive = builder.ensure_cached_archive(
    Archive::esbuild(esbuild_target),
  )
  @packaging.remove_path_if_exists(builder.at("work"))
  builder.extract_archive(xterm_archive, builder.at("work/xterm"))
  builder.extract_archive(fit_archive, builder.at("work/fit"))
  builder.extract_archive(web_links_archive, builder.at("work/web-links"))
  builder.extract_archive(esbuild_archive, builder.at("work/esbuild"))
  @packaging.write_text(builder.at("work/entry.js"), EntrySource)
  @packaging.remove_path_if_exists(builder.at("dist"))
  @packaging.ensure_dir(builder.at("dist"))
  let javascript = builder.at("dist/xterm.js")
  let stylesheet = builder.at("dist/xterm.css")
  @packaging.run_checked(
    builder.esbuild_binary(esbuild_target),
    [
      builder.at("work/entry.js"),
      "--bundle",
      "--format=iife",
      "--platform=browser",
      "--minify",
      "--outfile=\{javascript}",
    ],
    dir=workspace.dir(),
  )
  @packaging.copy_file(builder.at("work/xterm/css/xterm.css"), stylesheet)
  { javascript, stylesheet, }
}
