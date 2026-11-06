#!/usr/bin/env bash
# One isolated lifecycle: every command retains its original exit assertion.
expect_status() {
  actual=$?
  if [ "$actual" -ne "$1" ]; then
    printf 'Expected exit %s, got %s near fixture line %s\n' "$1" "$actual" "${BASH_LINENO[0]}" >&2
    exit 1
  fi
}

PACKAGE="$TESTDIR/../../share/artifact/build.mbtx"
expect_status 0

mkdir -p session/scratch/app
expect_status 0

PROJECT="$PWD/session/scratch/app"
expect_status 0

OUTPUT="$PWD/session/scratch/artifact"
expect_status 0

cat > "$PROJECT/moon.mod" <<'EOF'
name = "example/artifact"
version = "0.0.0"
EOF
expect_status 0

cat > "$PROJECT/moon.pkg" <<'EOF'
pkgtype(kind: "executable")
options(link: { "js": { "format": "iife" } })
EOF
expect_status 0

cat > "$PROJECT/main.mbt" <<'EOF'
fn main { println("The application has loaded") }
EOF
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" chart-v1.html
expect_status 0

test -f "$OUTPUT/chart-v1.html"
expect_status 0

grep -q '<script>' "$OUTPUT/chart-v1.html"
expect_status 0

grep -q 'The application has loaded' "$OUTPUT/chart-v1.html"
expect_status 0

cp "$OUTPUT/chart-v1.html" previous.html
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" chart-v1.html 2> duplicate.err
expect_status 1

grep -o 'artifact already exists; choose a new filename' duplicate.err
expect_status 0

cmp previous.html "$OUTPUT/chart-v1.html"
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "" chart-v2.html 2> directory.err
expect_status 1

grep -o 'output directory must not be empty' directory.err
expect_status 0

test ! -e "$OUTPUT/chart-v2.html"
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" ../outside.html 2> filename.err
expect_status 1

grep -o 'choose one new .html filename, without a directory' filename.err
expect_status 0

test ! -e session/scratch/outside.html
expect_status 0

cmp "$PROJECT/main.mbt" "$OUTPUT/chart-v1.html.source/main.mbt"
expect_status 0

test ! -e "$OUTPUT/chart-v1.html.source/_build" && test ! -e "$OUTPUT/chart-v1.html.source/.mooncakes"
expect_status 0

cat > "$PROJECT/index.html" <<'EOF'
<!doctype html><html><head><style>.answer{padding:1rem}</style></head><body><div id="app"></div><!-- openseek:script --></body></html>
EOF
expect_status 0

cat > "$PROJECT/main.mbt" <<'EOF'
fn main { println("</ScRiPt><p>Still application data</p>") }
EOF
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" answer-v2.html
expect_status 0

grep -Fq '<div id="app"></div><script>' "$OUTPUT/answer-v2.html"
expect_status 0

grep -Fq '.answer{padding:1rem}' "$OUTPUT/answer-v2.html"
expect_status 0

grep -Fq '<\/ScRiPt>' "$OUTPUT/answer-v2.html"
expect_status 0

! grep -Fq '<!-- openseek:script -->' "$OUTPUT/answer-v2.html"
expect_status 0

cp -R "$OUTPUT/answer-v2.html.source" restored-app && rm -r "$PROJECT"
expect_status 0

PROJECT="$PWD/restored-app"
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" answer-v3.html
expect_status 0

cmp previous.html "$OUTPUT/chart-v1.html"
expect_status 0

cp "$PROJECT/index.html" valid.html && printf '<div id="app"></div>' > "$PROJECT/index.html"
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" missing-marker.html 2> marker.err
expect_status 1

grep -Fo 'index.html must contain exactly one <!-- openseek:script --> marker' marker.err
expect_status 0

test ! -e "$OUTPUT/missing-marker.html" && test ! -e "$OUTPUT/missing-marker.html.source"
expect_status 0

printf '<!-- openseek:script --><!-- openseek:script -->' > "$PROJECT/index.html"
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" repeated-marker.html 2> repeated.err
expect_status 1

grep -Fo 'index.html must contain exactly one <!-- openseek:script --> marker' repeated.err
expect_status 0

test ! -e "$OUTPUT/repeated-marker.html" && test ! -e "$OUTPUT/repeated-marker.html.source"
expect_status 0

cp valid.html "$PROJECT/index.html" && printf 'fn main { missing_function() }' > "$PROJECT/main.mbt"
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" broken.html 2> compile.err
expect_status 1

grep -q 'missing_function' compile.err
expect_status 0

grep -Fq "$PROJECT/main.mbt" compile.err
expect_status 0

test ! -e "$OUTPUT/broken.html" && test ! -e "$OUTPUT/broken.html.source"
expect_status 0

mkdir "$OUTPUT/reserved.html.source"
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" reserved.html 2> reserved.err
expect_status 1

grep -o 'artifact already exists; choose a new filename' reserved.err
expect_status 0

test ! -e "$OUTPUT/reserved.html" && test -d "$OUTPUT/reserved.html.source"
expect_status 0

cp "$OUTPUT/answer-v2.html.source/main.mbt" "$PROJECT/main.mbt"
expect_status 0

cat > make-large.mbtx <<'EOF'
---
import { "moonbitlang/core/async", "moonbitlang/core/async/fs", "moonbitlang/core/env" }
---
async fn main {
  let page = StringBuilder()
  page.write_string("<!doctype html><p>")
  for _ in 0..<3_000_000 { page.write_string("界") }
  page.write_string("</p><!-- openseek:script -->")
  @fs.write_text(@env.args()[1], page.to_string(), create_mode=CreateOrTruncate)
}
EOF
expect_status 0

moon run --target-dir "$PWD/large-script-build" make-large.mbtx "$PROJECT/index.html"
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" oversized.html 2> size.err
expect_status 1

grep -o 'component HTML exceeds the 8 MiB inline preview limit' size.err
expect_status 0

test ! -e "$OUTPUT/oversized.html" && test ! -e "$OUTPUT/oversized.html.source"
expect_status 0

cp valid.html "$PROJECT/index.html"
expect_status 0

cat > "$PROJECT/main.mbt" <<'EOF'
fn main {
  let unused = 42
  println("Would otherwise build")
}
EOF
expect_status 0

moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" warning.html 2> warning.err
expect_status 1

grep -q 'unused_value' warning.err
expect_status 0

test ! -e "$OUTPUT/warning.html" && test ! -e "$OUTPUT/warning.html.source"
expect_status 0

SCRATCH="$PWD/session/scratch"
expect_status 0

INIT="$TESTDIR/../../share/artifact/init.mbtx"
expect_status 0

AUTHOR="$TESTDIR/../../share/artifact/write.mbtx"
expect_status 0

moon run --target-dir "$PWD/init-build" "$INIT" "$SCRATCH" "$TESTDIR/../../share/artifact/rabbita" authored > init.out
expect_status 0

WORK="$SCRATCH/component-work/authored"
expect_status 0

test -f "$WORK/bridge.mbt" && test ! -e "$WORK/.mooncakes" && test ! -e "$WORK/_build"
expect_status 0

mkdir -p "$SCRATCH/staged-sources" && printf '{"value": 2}' > "$SCRATCH/staged-sources/data.json"
expect_status 0

moon run --target-dir "$PWD/author-build" "$AUTHOR" "$SCRATCH" "$WORK" data/input.json "$SCRATCH/staged-sources/data.json" > author.out
expect_status 0

grep -Fq '"value": 2' "$WORK/data/input.json"
expect_status 0

moon run --target-dir "$PWD/init-build" "$INIT" "$SCRATCH" "$TESTDIR/../../share/artifact/rabbita" authored > duplicate-init.out 2> duplicate-init.err
expect_status 1

grep -Fq '"value": 2' "$WORK/data/input.json"
expect_status 0

moon run --target-dir "$PWD/author-build" "$AUTHOR" "$SCRATCH" "$PROJECT" main.mbt "$SCRATCH/staged-sources/data.json" 2> author-scope.err
expect_status 1

grep -Fo 'project must be a working directory inside session scratch' author-scope.err
expect_status 0
