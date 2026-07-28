# ZIP Fixtures

Fixtures are collected from official or widely used ZIP/JAR sources:

- Python `zipfile` regression data (`cpython` repo)
- Go `archive/zip` testdata (`golang/go` repo)
- libzip regression files (`nih-at/libzip` repo)
- libarchive test suite (`libarchive/libarchive` repo)
- zip-rs test data (`zip-rs/zip` repo)
- Maven Central JAR artifacts (Apache, Spring, Eclipse, Google, JetBrains)
- Small non-zip fixtures in `fixtures/sources/manual/nonzip` to validate error paths

All fixtures are checked in under `fixtures/sources/` and indexed in
`fixtures/manifest.json` with SHA-256 hashes.
