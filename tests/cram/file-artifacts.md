# Creating session file artifacts

These executable cases package an ordinary MoonBit JavaScript application without a chart or component library.

```mooncram
$ PACKAGE="$TESTDIR/../../share/artifact/build.mbtx"
```

```mooncram
$ mkdir -p session/scratch/app
```

```mooncram
$ PROJECT="$PWD/session/scratch/app"
```

```mooncram
$ OUTPUT="$PWD/session/scratch/artifact"
```

```mooncram
$ cat > "$PROJECT/moon.mod" <<'EOF'
> name = "example/artifact"
> version = "0.0.0"
> EOF
```

```mooncram
$ cat > "$PROJECT/moon.pkg" <<'EOF'
> pkgtype(kind: "executable")
> options(link: { "js": { "format": "iife" } })
> EOF
```

```mooncram
$ cat > "$PROJECT/main.mbt" <<'EOF'
> fn main { println("The application has loaded") }
> EOF
```

Packaging builds the ordinary application and prints the exact reference to
place in the answer. Its JavaScript is included in the generated HTML file.

````mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" chart-v1.html
```openseek-file
artifact://chart-v1.html
```
````

```mooncram
$ test -f "$OUTPUT/chart-v1.html"
```

```mooncram
$ grep -q '<script>' "$OUTPUT/chart-v1.html"
```

```mooncram
$ grep -q 'The application has loaded' "$OUTPUT/chart-v1.html"
```

A new version uses a new filename. Reusing a name fails before building or
changing the earlier file.

```mooncram
$ cp "$OUTPUT/chart-v1.html" previous.html
```

```mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" chart-v1.html 2> duplicate.err
[1]
```

```mooncram
$ grep -o 'artifact already exists; choose a new filename' duplicate.err
artifact already exists; choose a new filename
```

```mooncram
$ cmp previous.html "$OUTPUT/chart-v1.html"
```

The recipe requires an explicit output directory argument. Use the session
scratch path from Environment; no additional environment variable is needed.

```mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "" chart-v2.html 2> directory.err
[1]
```

```mooncram
$ grep -o 'output directory must not be empty' directory.err
output directory must not be empty
```

```mooncram
$ test ! -e "$OUTPUT/chart-v2.html"
```

The recipe accepts one filename inside that directory. Parent-directory paths
are rejected before an output file is created.

```mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" ../outside.html 2> filename.err
[1]
```

```mooncram
$ grep -o 'choose one new .html filename, without a directory' filename.err
choose one new .html filename, without a directory
```

```mooncram
$ test ! -e session/scratch/outside.html
```

Successful builds retain editable inputs beside each page without retaining
compiler caches. These files follow the artifact tree into a fork.

```mooncram
$ cmp "$PROJECT/main.mbt" "$OUTPUT/chart-v1.html.source/main.mbt"
```

```mooncram
$ test ! -e "$OUTPUT/chart-v1.html.source/_build" && test ! -e "$OUTPUT/chart-v1.html.source/.mooncakes"
```

A component can choose its own mount element and inline styles. The compiled
executable replaces exactly one marker; strings containing closing script tags
must remain JavaScript data.

```mooncram
$ cat > "$PROJECT/index.html" <<'EOF'
> <!doctype html><html><head><style>.answer{padding:1rem}</style></head><body><div id="app"></div><!-- openseek:script --></body></html>
> EOF
```

```mooncram
$ cat > "$PROJECT/main.mbt" <<'EOF'
> fn main { println("</ScRiPt><p>Still application data</p>") }
> EOF
```

````mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" answer-v2.html
```openseek-file
artifact://answer-v2.html
```
````

```mooncram
$ grep -Fq '<div id="app"></div><script>' "$OUTPUT/answer-v2.html"
```

```mooncram
$ grep -Fq '.answer{padding:1rem}' "$OUTPUT/answer-v2.html"
```

```mooncram
$ grep -Fq '<\/ScRiPt>' "$OUTPUT/answer-v2.html"
```

```mooncram
$ ! grep -Fq '<!-- openseek:script -->' "$OUTPUT/answer-v2.html"
```

Restore a working copy using only a retained source revision. Deleting the
original project must not prevent a new build or change an earlier answer.

```mooncram
$ cp -R "$OUTPUT/answer-v2.html.source" restored-app && rm -r "$PROJECT"
```

```mooncram
$ PROJECT="$PWD/restored-app"
```

````mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" answer-v3.html
```openseek-file
artifact://answer-v3.html
```
````

```mooncram
$ cmp previous.html "$OUTPUT/chart-v1.html"
```

A missing or repeated marker fails without publishing either part of a revision.

```mooncram
$ cp "$PROJECT/index.html" valid.html && printf '<div id="app"></div>' > "$PROJECT/index.html"
```

```mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" missing-marker.html 2> marker.err
[1]
```

```mooncram
$ grep -Fo 'index.html must contain exactly one <!-- openseek:script --> marker' marker.err
index.html must contain exactly one <!-- openseek:script --> marker
```

```mooncram
$ test ! -e "$OUTPUT/missing-marker.html" && test ! -e "$OUTPUT/missing-marker.html.source"
```

```mooncram
$ printf '<!-- openseek:script --><!-- openseek:script -->' > "$PROJECT/index.html"
```

```mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" repeated-marker.html 2> repeated.err
[1]
```

```mooncram
$ grep -Fo 'index.html must contain exactly one <!-- openseek:script --> marker' repeated.err
index.html must contain exactly one <!-- openseek:script --> marker
```

```mooncram
$ test ! -e "$OUTPUT/repeated-marker.html" && test ! -e "$OUTPUT/repeated-marker.html.source"
```

Compiler errors also leave no published revision, and reserving a source name
must protect it from being overwritten even if no HTML exists yet.

```mooncram
$ cp valid.html "$PROJECT/index.html" && printf 'fn main { missing_function() }' > "$PROJECT/main.mbt"
```

```mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" broken.html 2> compile.err
[1]
```

```mooncram
$ grep -q 'missing_function' compile.err
```

```mooncram
$ grep -Fq "$PROJECT/main.mbt" compile.err
```

```mooncram
$ test ! -e "$OUTPUT/broken.html" && test ! -e "$OUTPUT/broken.html.source"
```

```mooncram
$ mkdir "$OUTPUT/reserved.html.source"
```

```mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" reserved.html 2> reserved.err
[1]
```

```mooncram
$ grep -o 'artifact already exists; choose a new filename' reserved.err
artifact already exists; choose a new filename
```

```mooncram
$ test ! -e "$OUTPUT/reserved.html" && test -d "$OUTPUT/reserved.html.source"
```

The preview limit counts UTF-8 bytes, including a custom HTML template. This
template is below eight million characters but above eight MiB in UTF-8.

```mooncram
$ cp "$OUTPUT/answer-v2.html.source/main.mbt" "$PROJECT/main.mbt"
```

```mooncram
$ cat > make-large.mbtx <<'EOF'
> ---
> import { "moonbitlang/core/async", "moonbitlang/core/async/fs", "moonbitlang/core/env" }
> ---
> async fn main {
>   let page = StringBuilder()
>   page.write_string("<!doctype html><p>")
>   for _ in 0..<3_000_000 { page.write_string("界") }
>   page.write_string("</p><!-- openseek:script -->")
>   @fs.write_text(@env.args()[1], page.to_string(), create_mode=CreateOrTruncate)
> }
> EOF
```

```mooncram
$ moon run --target-dir "$PWD/large-script-build" make-large.mbtx "$PROJECT/index.html"
```

```mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" oversized.html 2> size.err
[1]
```

```mooncram
$ grep -o 'component HTML exceeds the 8 MiB inline preview limit' size.err
component HTML exceeds the 8 MiB inline preview limit
```

```mooncram
$ test ! -e "$OUTPUT/oversized.html" && test ! -e "$OUTPUT/oversized.html.source"
```

The recipe also requires a clean check before building. An otherwise buildable
program with an unused variable fails that check and publishes no revision.

```mooncram
$ cp valid.html "$PROJECT/index.html"
```

```mooncram
$ cat > "$PROJECT/main.mbt" <<'EOF'
> fn main {
>   let unused = 42
>   println("Would otherwise build")
> }
> EOF
```

```mooncram
$ moon run --target-dir "$PWD/script-build" "$PACKAGE" "$PROJECT" "$OUTPUT" warning.html 2> warning.err
[1]
```

```mooncram
$ grep -q 'unused_value' warning.err
```

```mooncram
$ test ! -e "$OUTPUT/warning.html" && test ! -e "$OUTPUT/warning.html.source"
```
