///|
#cfg(not(platform="windows"))
async test "builtin namespace refuses symlinks outside its root" {
  @vfs.with_tmpdir(root => {
    @fs.mkdir("\{root}/workflow")
    @fs.write_file("\{root}/outside.mbtx", "fn main {}")
    @fs.symlink(target="\{root}/outside.mbtx", "\{root}/workflow/escape.mbtx")
    try check_builtin_containment("\{root}/workflow/escape.mbtx", root) catch {
      error => assert_true(error.to_string().contains("inside @builtin/"))
    } noraise {
      _ => fail("namespace escape accepted")
    }
  })
}
