// The release-assembly step: regenerate `dist/releases/latest.json` from
// the artifacts staged under `dist/releases/v<AppVersion>/`. Each platform
// packager stages only its own artifact; for a multi-platform release,
// collect every platform's `OpenSeek-Desktop-<platform>.<ext>` into that
// directory (CI artifacts, other machines' dist trees) and run
//
//   moon run --target native package/release
//
// last — the manifest is derived from the directory, so it always lists
// exactly what will be published, with digests computed from the actual
// files.

///|
async fn main {
  let ws = @packaging.locate_workspace()
  @packaging.write_release_manifest(ws, @version.AppVersion)
}
