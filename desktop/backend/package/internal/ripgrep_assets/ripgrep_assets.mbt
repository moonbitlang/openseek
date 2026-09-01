///|
const RipgrepVersion : String = "15.1.0"

///|
const VendorDir : String = "target/vendor-ripgrep"

///|
/// One official upstream release archive. The type is opaque so platform
/// packagers can select only a pinned target defined in this package.
struct Target {
  triple : String
  extension : String
  binary_name : String
  sha256 : String
}

///|
/// Select ripgrep's official macOS arm64 release archive.
pub fn macos_arm64_target() -> Target {
  {
    triple: "aarch64-apple-darwin",
    extension: "tar.gz",
    binary_name: "rg",
    sha256: "378e973289176ca0c6054054ee7f631a065874a352bf43f0fa60ef079b6ba715",
  }
}

///|
/// Select ripgrep's official Windows x64 MSVC release archive.
pub fn windows_x64_target() -> Target {
  {
    triple: "x86_64-pc-windows-msvc",
    extension: "zip",
    binary_name: "rg.exe",
    sha256: "124510b94b6baa3380d051fdf4650eaa80a302c876d611e9dba0b2e18d87493a",
  }
}

///|
/// Select ripgrep's official Linux x64 static-musl release archive.
pub fn linux_x64_target() -> Target {
  {
    triple: "x86_64-unknown-linux-musl",
    extension: "tar.gz",
    binary_name: "rg",
    sha256: "1c9297be4a084eea7ecaedf93eb03d058d6faae29bbc57ecdaf5063921491599",
  }
}

///|
/// Verified files a platform packager must stage into its application layout.
pub struct Assets {
  /// The target-native ripgrep executable.
  binary : String
  /// ripgrep's MIT license text.
  license_mit : String
  /// ripgrep's public-domain dedication alternative.
  unlicense : String
}

///|
fn Target::basename(self : Target) -> String {
  "ripgrep-\{RipgrepVersion}-\{self.triple}"
}

///|
fn Target::filename(self : Target) -> String {
  "\{self.basename()}.\{self.extension}"
}

///|
fn Target::url(self : Target) -> String {
  "https://github.com/BurntSushi/ripgrep/releases/download/\{RipgrepVersion}/\{self.filename()}"
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
async fn download_archive(url : String, path : String, redirects : Int) -> Unit {
  guard url.has_prefix("https://") else {
    raise @packaging.PackageError(
      "refusing to download ripgrep over a non-HTTPS URL: \{url}",
    )
  }
  let (response, body) = @http.get(url) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      raise @packaging.PackageError("failed to download \{url}: \{error}")
  }
  if response.code >= 200 && response.code < 300 {
    @asyncfs.write_file(path, body, create_mode=CreateOrTruncate)
    return
  }
  if response.code >= 300 && response.code < 400 && redirects > 0 {
    match response.headers.get("location") {
      Some(location) => {
        download_archive(location, path, redirects - 1)
        return
      }
      None => ()
    }
  }
  raise @packaging.PackageError(
    "failed to download \{url}: HTTP \{response.code} \{response.reason}",
  )
}

///|
async fn AssetBuilder::ensure_archive(
  self : AssetBuilder,
  target : Target,
) -> String {
  let path = self.at("cache/\{target.filename()}")
  if @asyncfs.exists(path) {
    let actual = archive_digest(path)
    if actual == target.sha256 {
      return path
    }
    println(
      "cached \{target.filename()} failed SHA-256 verification; downloading it again",
    )
    @packaging.remove_path_if_exists(path)
  }
  println("downloading \{target.url()}")
  download_archive(target.url(), path, 5)
  let actual = archive_digest(path)
  if actual != target.sha256 {
    @packaging.remove_path_if_exists(path)
    raise @packaging.PackageError(
      "SHA-256 mismatch for \{target.filename()}: expected \{target.sha256}, got \{actual}",
    )
  }
  path
}

///|
/// Download, verify, and extract one official ripgrep release. `tar` is the
/// existing cross-platform archive dependency used by the desktop packagers;
/// bsdtar handles both the release ZIP and tar.gz formats.
pub async fn build(workspace : @packaging.Workspace, target : Target) -> Assets {
  let builder : AssetBuilder = { workspace, }
  @packaging.ensure_dir(builder.at("cache"))
  let archive = builder.ensure_archive(target)
  let work = builder.at("work/\{target.triple}")
  @packaging.remove_path_if_exists(work)
  @packaging.ensure_dir(work)
  @packaging.run_checked(
    "tar",
    ["-xf", archive, "-C", work, "--strip-components=1"],
    dir=workspace.dir(),
  )
  let binary = "\{work}/\{target.binary_name}"
  let license_mit = "\{work}/LICENSE-MIT"
  let unlicense = "\{work}/UNLICENSE"
  for required in [binary, license_mit, unlicense] {
    if !@asyncfs.exists(required) {
      raise @packaging.PackageError(
        "ripgrep archive \{target.filename()} is missing \{required}",
      )
    }
  }
  { binary, license_mit, unlicense, }
}

///|
test "ripgrep release targets pin official names and hashes" {
  let mac = macos_arm64_target()
  assert_eq(mac.filename(), "ripgrep-15.1.0-aarch64-apple-darwin.tar.gz")
  assert_eq(
    mac.sha256,
    "378e973289176ca0c6054054ee7f631a065874a352bf43f0fa60ef079b6ba715",
  )
  let windows = windows_x64_target()
  assert_eq(windows.filename(), "ripgrep-15.1.0-x86_64-pc-windows-msvc.zip")
  assert_eq(
    windows.sha256,
    "124510b94b6baa3380d051fdf4650eaa80a302c876d611e9dba0b2e18d87493a",
  )
  let linux = linux_x64_target()
  assert_eq(linux.filename(), "ripgrep-15.1.0-x86_64-unknown-linux-musl.tar.gz")
  assert_eq(
    linux.sha256,
    "1c9297be4a084eea7ecaedf93eb03d058d6faae29bbc57ecdaf5063921491599",
  )
}
