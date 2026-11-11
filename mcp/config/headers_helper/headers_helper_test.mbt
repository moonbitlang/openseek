// Use pinned MoonBit CLI tools through moonx so these process tests also
// run on Windows without depending on a host shell or Unix utilities.

///|
async test "helper returns headers with literal arguments workspace cwd and stdin EOF" {
  let dir = @fs.tmpdir(prefix="headers-helper-")
  defer @fs.rmdir(dir, recursive=true)
  let filename = "headers $(never-execute); literal.json"
  @fs.write_text(dir + "/" + filename, "{\"Authorization\":\"Bearer fixture\"}")
  @fs.write_text(
    dir + "/helper.sh",
    "moonx cli/cat@0.1.0 -\nmoonx cli/cat@0.1.0 \"$1\"\n",
  )
  assert_eq(
    @headers_helper.run(
      { command: "moonx", arguments: ["cli/sh@0.1.1", "helper.sh", filename], },
      cwd=dir,
    ),
    { "Authorization": "Bearer fixture" },
  )
}
