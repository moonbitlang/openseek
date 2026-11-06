# Creating session file artifacts

These cases exercise the public artifact scripts on real temporary MoonBit
projects. Each command selects one [standalone MoonBit script](fixtures/)
with its own directory, removed on success or failure. Each scenario prints observed exit
statuses, diagnostics, and generated-file properties; testcli compares them
with the snapshots below.

Run this document from the repository root:

```sh
moon testcli test tests/cram/file-artifacts.md --timeout-ms 300000
```

## Build, retain sources, and refuse overwrites

[`build.mbtx`](../../share/artifact/build.mbtx) takes a project directory, an
output directory, and a new HTML filename. The page contains the compiled
JavaScript. Its sibling `.source` directory retains the editable project,
excluding `_build` and `.mooncakes` caches. Reusing the filename fails and leaves
the original page unchanged.

````mooncram
$ moonx fixtures/artifact-build.mbtx
exit=0
```openseek-file artifact
scratch/artifact/chart-v1.html
```
has_script=true
has_application=true
source_preserved=true
saved_build_cache=false
saved_dependency_cache=false
exit=1
Failure(build.mbtx:* FAILED: artifact already exists; choose a new filename) (glob)
original_page_preserved=true
````

## Reject invalid output paths

An empty output directory or a filename containing a parent-directory path is
rejected before anything is published.

```mooncram
$ moonx fixtures/artifact-invalid-output.mbtx
exit=1
Failure(build.mbtx:* FAILED: output directory must not be empty) (glob)
html_exists=false
source_exists=false
exit=1
Failure(build.mbtx:* FAILED: choose one new .html filename, without a directory) (glob)
outside_html_exists=false
```

## Preserve a custom template and restore its source

A custom `index.html` supplies its mount element and styles. The build replaces
one `<!-- openseek:script -->` marker and escapes closing script tags in JavaScript
strings, including mixed-case tags. The scenario then copies the retained source,
deletes the original project, and builds a new version from the restored copy.
The first page must remain byte-for-byte unchanged.

````mooncram
$ moonx fixtures/artifact-restore.mbtx
exit=0
```openseek-file artifact
scratch/artifact/chart-v1.html
```
exit=0
```openseek-file artifact
scratch/artifact/answer-v2.html
```
has_mount=true
has_styles=true
script_tag_escaped=true
marker_remaining=false
exit=0
```openseek-file artifact
scratch/artifact/answer-v3.html
```
restored_page_exists=true
original_page_preserved=true
````

## Require exactly one template marker

Missing and repeated markers both fail without leaving an HTML file or retained
source directory.

```mooncram
$ moonx fixtures/artifact-invalid-markers.mbtx
exit=1
Failure(build.mbtx:* FAILED: index.html must contain exactly one <!-- openseek:script --> marker) (glob)
html_exists=false
source_exists=false
exit=1
Failure(build.mbtx:* FAILED: index.html must contain exactly one <!-- openseek:script --> marker) (glob)
html_exists=false
source_exists=false
```

## Do not publish after compiler errors or warnings

The scenario compiles an undefined function and then an unused variable. It
prints whether the diagnostics name the invalid source and whether either
attempt leaves an HTML/source pair. The expected values are recorded below.

```mooncram
$ moonx fixtures/artifact-compile-errors.mbtx
exit=1
undefined_function_reported=true
diagnostic_names_source=true
html_exists=false
source_exists=false
exit=1
unused_value_reported=true
html_exists=false
source_exists=false
```

## Respect an existing source directory

A retained source directory reserves its artifact's name even if the HTML file
is absent. A failed build must preserve that directory.

```mooncram
$ moonx fixtures/artifact-reserved-source.mbtx
exit=1
Failure(build.mbtx:* FAILED: artifact already exists; choose a new filename) (glob)
html_exists=false
source_directory_preserved=true
```

## Enforce the UTF-8 size limit

Three million `界` characters exceed eight MiB in UTF-8. The build rejects this
page without publishing an HTML/source pair.

```mooncram
$ moonx fixtures/artifact-size-limit.mbtx
exit=1
Failure(build.mbtx:* FAILED: component HTML exceeds the 8 MiB inline preview limit) (glob)
html_exists=false
source_exists=false
```

## Initialize and edit a working project

[`init.mbtx`](../../share/artifact/init.mbtx) copies the Rabbita template into
session scratch without caches. [`write.mbtx`](../../share/artifact/write.mbtx)
applies a staged file to that working project. Reinitialization must refuse to
overwrite the project and preserve the staged data. Writing to a directory
outside session scratch is refused.

```mooncram
$ moonx fixtures/artifact-author.mbtx
exit=0
template_copied=true
build_cache_copied=false
dependency_cache_copied=false
exit=0
staged_data_preserved=true
exit=1
staged_data_preserved=true
exit=1
Failure(write.mbtx:* FAILED: project must be a working directory inside session scratch) (glob)
```
