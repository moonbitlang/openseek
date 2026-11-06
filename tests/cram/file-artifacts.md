# Creating session file artifacts

These executable cases package an ordinary MoonBit JavaScript application without
a chart or component library. Run them from the repository root:

```sh
moon testcli test tests/cram/file-artifacts.md --timeout-ms 300000
```

The [artifact fixture](fixtures/file-artifacts.sh) runs the complete lifecycle in
one temporary directory. It checks the exit status of every command, including
expected failures, and checks generated files with `test`, `grep`, and `cmp`.
`moon testcli` asserts the output below. The fixture directory is removed after
success or failure, and each invocation starts with fresh files.

## Build and retain editable sources

The fixture creates an ordinary executable MoonBit project and calls
[`build.mbtx`](../../share/artifact/build.mbtx) with an explicit project directory,
output directory, and new HTML filename. The generated page contains the compiled
JavaScript and the printed `openseek-file` reference names its session path.

A new version uses a new filename. Reusing a filename fails without changing the
previous page. Empty output directories and filenames containing parent-directory
paths are rejected before publishing. Successful builds retain editable source
beside the page, excluding `_build` and `.mooncakes` caches.

## Templates and restored projects

A custom `index.html` supplies its own mount element and styles. The build replaces
exactly one `<!-- openseek:script -->` marker. Mixed-case closing script tags in
JavaScript strings remain data. The fixture restores a project solely from the
retained source, deletes the original project, builds another version, and checks
that the first page is byte-for-byte unchanged.

Missing or repeated script markers, compiler errors, a reserved source directory,
and an unused-variable warning all fail without publishing an HTML/source pair.
The size-limit fixture writes three million `界` characters: it is below eight
million characters but exceeds the eight MiB UTF-8 preview limit.

## Initialize and edit working projects

[`init.mbtx`](../../share/artifact/init.mbtx) copies the Rabbita template into an
explicit session scratch directory. [`write.mbtx`](../../share/artifact/write.mbtx)
applies staged source files by location. The fixture verifies that initialization
excludes caches, refuses to overwrite an existing project, and preserves its
files. Writing outside a working project in session scratch is refused.

## Expected lifecycle output

All successful file assertions are silent. Expected failure statuses are checked
inside the fixture; a failed assertion makes this case fail.

````mooncram
$ moonx ../cli-fixture.mbtx fixtures/file-artifacts.sh
```openseek-file artifact
scratch/artifact/chart-v1.html
```
artifact already exists; choose a new filename
output directory must not be empty
choose one new .html filename, without a directory
```openseek-file artifact
scratch/artifact/answer-v2.html
```
```openseek-file artifact
scratch/artifact/answer-v3.html
```
index.html must contain exactly one <!-- openseek:script --> marker
index.html must contain exactly one <!-- openseek:script --> marker
artifact already exists; choose a new filename
component HTML exceeds the 8 MiB inline preview limit
project must be a working directory inside session scratch
````
