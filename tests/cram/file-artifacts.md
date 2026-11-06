# Creating session file artifacts

These cases exercise the public artifact scripts on real temporary MoonBit
projects. Each command selects one [standalone MoonBit script](fixtures/)
with its own directory, removed on success or failure. The scenario checks exit
statuses and generated files; testcli checks the output shown here.

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
```openseek-file artifact
scratch/artifact/chart-v1.html
```
artifact already exists; choose a new filename
````

## Reject invalid output paths

An empty output directory or a filename containing a parent-directory path is
rejected before anything is published.

```mooncram
$ moonx fixtures/artifact-invalid-output.mbtx
output directory must not be empty
choose one new .html filename, without a directory
```

## Preserve a custom template and restore its source

A custom `index.html` supplies its mount element and styles. The build replaces
one `<!-- openseek:script -->` marker and escapes closing script tags in JavaScript
strings, including mixed-case tags. The scenario then copies the retained source,
deletes the original project, and builds a new version from the restored copy.
The first page must remain byte-for-byte unchanged.

````mooncram
$ moonx fixtures/artifact-restore.mbtx
```openseek-file artifact
scratch/artifact/chart-v1.html
```
```openseek-file artifact
scratch/artifact/answer-v2.html
```
```openseek-file artifact
scratch/artifact/answer-v3.html
```
````

## Require exactly one template marker

Missing and repeated markers both fail without leaving an HTML file or retained
source directory.

```mooncram
$ moonx fixtures/artifact-invalid-markers.mbtx
index.html must contain exactly one <!-- openseek:script --> marker
index.html must contain exactly one <!-- openseek:script --> marker
```

## Do not publish after compiler errors or warnings

The scenario compiles an undefined function and then an unused variable. It
checks the compiler diagnostics and verifies that neither attempt publishes
an HTML/source pair. These summaries are printed only after those assertions.

```mooncram
$ moonx fixtures/artifact-compile-errors.mbtx
compiler error: no artifact published
compiler warning: no artifact published
```

## Respect an existing source directory

A retained source directory reserves its artifact's name even if the HTML file
is absent. A failed build must preserve that directory.

```mooncram
$ moonx fixtures/artifact-reserved-source.mbtx
artifact already exists; choose a new filename
```

## Enforce the UTF-8 size limit

Three million `界` characters exceed eight MiB in UTF-8. The build rejects this
page without publishing an HTML/source pair.

```mooncram
$ moonx fixtures/artifact-size-limit.mbtx
component HTML exceeds the 8 MiB inline preview limit
```

## Initialize and edit a working project

[`init.mbtx`](../../share/artifact/init.mbtx) copies the Rabbita template into
session scratch without caches. [`write.mbtx`](../../share/artifact/write.mbtx)
applies a staged file to that working project. Reinitialization must refuse to
overwrite the project and preserve the staged data. Writing to a directory
outside session scratch is refused.

```mooncram
$ moonx fixtures/artifact-author.mbtx
initialized project and wrote staged data
reinitialization refused; existing data preserved
project must be a working directory inside session scratch
```
