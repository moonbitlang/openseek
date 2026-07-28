///|
async test "zip invalid 0000 test-badbase.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/test-badbase.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/test-badbase.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/test-badbase.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0001 test-prefix.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/test-prefix.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/test-prefix.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/test-prefix.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0002 test-baddirsz.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/test-baddirsz.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/test-baddirsz.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/test-baddirsz.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async fn load_expected_json(path : String) -> Json {
  let data = @fs.read_file(path)
  @json.parse(data.text())
}

///|
async fn parse_seekable_fixture(path : String) -> ZipReport {
  let file = @fs.open(path, mode=@fs.Mode::ReadOnly)
  defer file.close()
  // The first path component is only the fixture container. The API receives
  // the stable archive name recorded in the generated oracle.
  let archive_name = match path.split_once("/") {
    Some((_, suffix)) => "fixtures/\{suffix}"
    None => path
  }
  parse_file(file, name=archive_name)
}

///|
async fn parse_stream_fixture(path : String) -> ZipReport {
  // Keep seekable and streaming reports independent of their container name.
  let archive_name = match path.split_once("/") {
    Some((_, suffix)) => "fixtures/\{suffix}"
    None => path
  }
  @async.with_task_group(group => {
    let (reader, writer) = @io.pipe()
    defer reader.close()
    group.spawn_bg(() => {
      defer writer.close()
      let file = @fs.open(path, mode=@fs.Mode::ReadOnly)
      defer file.close()
      // A parser may finish after the ZIP records it needs. Closing the reader
      // then is normal and must not turn the producer task into a test failure.
      writer.write_reader(file) catch {
        @io.PipeClosed => ()
        error => raise error
      }
    })
    parse_stream(reader, name=archive_name)
  })
}

///|
async test "zip valid 0000 readme.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/readme.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/readme.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/readme.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0001 dupdir.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/dupdir.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/dupdir.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/dupdir.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0002 time-7zip.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/time-7zip.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-7zip.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-7zip.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0003 utf8-infozip.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/utf8-infozip.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/utf8-infozip.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/utf8-infozip.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0004 zip64-2.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/zip64-2.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/zip64-2.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/zip64-2.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0005 dd.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/dd.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/dd.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/dd.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0006 utf8-osx.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/utf8-osx.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/utf8-osx.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/utf8-osx.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0007 time-go.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/time-go.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-go.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-go.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0008 time-22738.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/time-22738.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-22738.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-22738.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0009 unix.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/unix.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/unix.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/unix.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0010 zip64.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/zip64.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/zip64.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/zip64.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0011 test.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/test.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/test.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/test.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0012 symlink.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/symlink.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/symlink.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/symlink.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0013 utf8-winrar.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/utf8-winrar.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/utf8-winrar.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/utf8-winrar.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0014 test-trailing-junk.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/test-trailing-junk.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/test-trailing-junk.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/test-trailing-junk.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0015 time-winrar.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/time-winrar.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-winrar.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-winrar.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0016 go-with-datadesc-sig.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/go-with-datadesc-sig.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/go-with-datadesc-sig.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/go-with-datadesc-sig.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0017 crc32-not-streamed.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/crc32-not-streamed.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/crc32-not-streamed.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/crc32-not-streamed.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0018 utf8-winzip.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/utf8-winzip.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/utf8-winzip.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/utf8-winzip.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0019 subdir.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/subdir.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/subdir.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/subdir.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0020 time-win7.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/time-win7.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-win7.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-win7.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0021 time-infozip.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/time-infozip.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-infozip.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-infozip.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0022 utf8-7zip.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/utf8-7zip.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/utf8-7zip.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/utf8-7zip.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0023 time-winzip.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/time-winzip.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-winzip.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-winzip.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0024 comment-truncated.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/comment-truncated.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/comment-truncated.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/comment-truncated.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0025 winxp.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/winxp.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/winxp.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/winxp.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0026 time-osx.zip" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/golang/src/archive/zip/testdata/time-osx.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-osx.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/golang/src/archive/zip/testdata/time-osx.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0027 httpasyncclient-cache-4.1.5.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.5/httpasyncclient-cache-4.1.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.5/httpasyncclient-cache-4.1.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.5/httpasyncclient-cache-4.1.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0028 httpasyncclient-cache-4.1.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.5/httpasyncclient-cache-4.1.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.5/httpasyncclient-cache-4.1.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.5/httpasyncclient-cache-4.1.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0029 httpasyncclient-cache-4.1.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.5/httpasyncclient-cache-4.1.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.5/httpasyncclient-cache-4.1.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.5/httpasyncclient-cache-4.1.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0030 httpasyncclient-cache-4.1.2.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.2/httpasyncclient-cache-4.1.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.2/httpasyncclient-cache-4.1.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.2/httpasyncclient-cache-4.1.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0031 httpasyncclient-cache-4.1.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.2/httpasyncclient-cache-4.1.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.2/httpasyncclient-cache-4.1.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.2/httpasyncclient-cache-4.1.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0032 httpasyncclient-cache-4.1.3.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.3/httpasyncclient-cache-4.1.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.3/httpasyncclient-cache-4.1.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.3/httpasyncclient-cache-4.1.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0033 httpasyncclient-cache-4.1.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.3/httpasyncclient-cache-4.1.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.3/httpasyncclient-cache-4.1.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.3/httpasyncclient-cache-4.1.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0034 httpasyncclient-cache-4.1.4.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.4/httpasyncclient-cache-4.1.4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.4/httpasyncclient-cache-4.1.4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.4/httpasyncclient-cache-4.1.4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0035 httpasyncclient-cache-4.1.4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.4/httpasyncclient-cache-4.1.4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.4/httpasyncclient-cache-4.1.4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.4/httpasyncclient-cache-4.1.4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0036 httpasyncclient-cache-4.0.1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.1/httpasyncclient-cache-4.0.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.1/httpasyncclient-cache-4.0.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.1/httpasyncclient-cache-4.0.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0037 httpasyncclient-cache-4.0.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.1/httpasyncclient-cache-4.0.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.1/httpasyncclient-cache-4.0.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.1/httpasyncclient-cache-4.0.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0038 httpasyncclient-cache-4.1-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1-beta1/httpasyncclient-cache-4.1-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1-beta1/httpasyncclient-cache-4.1-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1-beta1/httpasyncclient-cache-4.1-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0039 httpasyncclient-cache-4.1-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1-beta1/httpasyncclient-cache-4.1-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1-beta1/httpasyncclient-cache-4.1-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1-beta1/httpasyncclient-cache-4.1-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0040 httpasyncclient-cache-4.1.1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.1/httpasyncclient-cache-4.1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.1/httpasyncclient-cache-4.1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.1/httpasyncclient-cache-4.1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0041 httpasyncclient-cache-4.1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.1/httpasyncclient-cache-4.1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.1/httpasyncclient-cache-4.1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1.1/httpasyncclient-cache-4.1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0042 httpasyncclient-cache-4.0-beta2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta2/httpasyncclient-cache-4.0-beta2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta2/httpasyncclient-cache-4.0-beta2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta2/httpasyncclient-cache-4.0-beta2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0043 httpasyncclient-cache-4.0-beta2.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta2/httpasyncclient-cache-4.0-beta2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta2/httpasyncclient-cache-4.0-beta2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta2/httpasyncclient-cache-4.0-beta2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0044 httpasyncclient-cache-4.0-beta4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta4/httpasyncclient-cache-4.0-beta4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta4/httpasyncclient-cache-4.0-beta4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta4/httpasyncclient-cache-4.0-beta4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0045 httpasyncclient-cache-4.0-beta4.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta4/httpasyncclient-cache-4.0-beta4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta4/httpasyncclient-cache-4.0-beta4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta4/httpasyncclient-cache-4.0-beta4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0046 httpasyncclient-cache-4.0-beta3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta3/httpasyncclient-cache-4.0-beta3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta3/httpasyncclient-cache-4.0-beta3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta3/httpasyncclient-cache-4.0-beta3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0047 httpasyncclient-cache-4.0-beta3.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta3/httpasyncclient-cache-4.0-beta3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta3/httpasyncclient-cache-4.0-beta3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0-beta3/httpasyncclient-cache-4.0-beta3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0048 httpasyncclient-cache-4.0.2.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.2/httpasyncclient-cache-4.0.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.2/httpasyncclient-cache-4.0.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.2/httpasyncclient-cache-4.0.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0049 httpasyncclient-cache-4.0.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.2/httpasyncclient-cache-4.0.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.2/httpasyncclient-cache-4.0.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0.2/httpasyncclient-cache-4.0.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0050 httpasyncclient-cache-4.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1/httpasyncclient-cache-4.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1/httpasyncclient-cache-4.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1/httpasyncclient-cache-4.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0051 httpasyncclient-cache-4.1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1/httpasyncclient-cache-4.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1/httpasyncclient-cache-4.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.1/httpasyncclient-cache-4.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0052 httpasyncclient-cache-4.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0/httpasyncclient-cache-4.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0/httpasyncclient-cache-4.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0/httpasyncclient-cache-4.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0053 httpasyncclient-cache-4.0.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0/httpasyncclient-cache-4.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0/httpasyncclient-cache-4.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-cache/4.0/httpasyncclient-cache-4.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0054 hc-stylecheck-1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/hc-stylecheck/1/hc-stylecheck-1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/hc-stylecheck/1/hc-stylecheck-1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/hc-stylecheck/1/hc-stylecheck-1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0055 hc-stylecheck-3.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/hc-stylecheck/3/hc-stylecheck-3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/hc-stylecheck/3/hc-stylecheck-3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/hc-stylecheck/3/hc-stylecheck-3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0056 hc-stylecheck-3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/hc-stylecheck/3/hc-stylecheck-3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/hc-stylecheck/3/hc-stylecheck-3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/hc-stylecheck/3/hc-stylecheck-3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0057 hc-stylecheck-3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/hc-stylecheck/3/hc-stylecheck-3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/hc-stylecheck/3/hc-stylecheck-3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/hc-stylecheck/3/hc-stylecheck-3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0058 hc-stylecheck-2.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/hc-stylecheck/2/hc-stylecheck-2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/hc-stylecheck/2/hc-stylecheck-2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/hc-stylecheck/2/hc-stylecheck-2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0059 httpasyncclient-osgi-4.0-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta1/httpasyncclient-osgi-4.0-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta1/httpasyncclient-osgi-4.0-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta1/httpasyncclient-osgi-4.0-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0060 httpasyncclient-osgi-4.0-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta1/httpasyncclient-osgi-4.0-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta1/httpasyncclient-osgi-4.0-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta1/httpasyncclient-osgi-4.0-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0061 httpasyncclient-osgi-4.1.5.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.5/httpasyncclient-osgi-4.1.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.5/httpasyncclient-osgi-4.1.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.5/httpasyncclient-osgi-4.1.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0062 httpasyncclient-osgi-4.1.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.5/httpasyncclient-osgi-4.1.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.5/httpasyncclient-osgi-4.1.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.5/httpasyncclient-osgi-4.1.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0063 httpasyncclient-osgi-4.1.2.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.2/httpasyncclient-osgi-4.1.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.2/httpasyncclient-osgi-4.1.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.2/httpasyncclient-osgi-4.1.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0064 httpasyncclient-osgi-4.1.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.2/httpasyncclient-osgi-4.1.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.2/httpasyncclient-osgi-4.1.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.2/httpasyncclient-osgi-4.1.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0065 httpasyncclient-osgi-4.1.3.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.3/httpasyncclient-osgi-4.1.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.3/httpasyncclient-osgi-4.1.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.3/httpasyncclient-osgi-4.1.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0066 httpasyncclient-osgi-4.1.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.3/httpasyncclient-osgi-4.1.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.3/httpasyncclient-osgi-4.1.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.3/httpasyncclient-osgi-4.1.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0067 httpasyncclient-osgi-4.1.4.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.4/httpasyncclient-osgi-4.1.4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.4/httpasyncclient-osgi-4.1.4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.4/httpasyncclient-osgi-4.1.4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0068 httpasyncclient-osgi-4.1.4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.4/httpasyncclient-osgi-4.1.4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.4/httpasyncclient-osgi-4.1.4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.4/httpasyncclient-osgi-4.1.4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0069 httpasyncclient-osgi-4.0.1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.1/httpasyncclient-osgi-4.0.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.1/httpasyncclient-osgi-4.0.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.1/httpasyncclient-osgi-4.0.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0070 httpasyncclient-osgi-4.0.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.1/httpasyncclient-osgi-4.0.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.1/httpasyncclient-osgi-4.0.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.1/httpasyncclient-osgi-4.0.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0071 httpasyncclient-osgi-4.1-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1-beta1/httpasyncclient-osgi-4.1-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1-beta1/httpasyncclient-osgi-4.1-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1-beta1/httpasyncclient-osgi-4.1-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0072 httpasyncclient-osgi-4.1-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1-beta1/httpasyncclient-osgi-4.1-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1-beta1/httpasyncclient-osgi-4.1-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1-beta1/httpasyncclient-osgi-4.1-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0073 httpasyncclient-osgi-4.1.1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.1/httpasyncclient-osgi-4.1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.1/httpasyncclient-osgi-4.1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.1/httpasyncclient-osgi-4.1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0074 httpasyncclient-osgi-4.1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.1/httpasyncclient-osgi-4.1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.1/httpasyncclient-osgi-4.1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1.1/httpasyncclient-osgi-4.1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0075 httpasyncclient-osgi-4.0-beta2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta2/httpasyncclient-osgi-4.0-beta2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta2/httpasyncclient-osgi-4.0-beta2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta2/httpasyncclient-osgi-4.0-beta2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0076 httpasyncclient-osgi-4.0-beta2.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta2/httpasyncclient-osgi-4.0-beta2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta2/httpasyncclient-osgi-4.0-beta2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta2/httpasyncclient-osgi-4.0-beta2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0077 httpasyncclient-osgi-4.0-beta4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta4/httpasyncclient-osgi-4.0-beta4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta4/httpasyncclient-osgi-4.0-beta4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta4/httpasyncclient-osgi-4.0-beta4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0078 httpasyncclient-osgi-4.0-beta4.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta4/httpasyncclient-osgi-4.0-beta4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta4/httpasyncclient-osgi-4.0-beta4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta4/httpasyncclient-osgi-4.0-beta4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0079 httpasyncclient-osgi-4.0-beta3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta3/httpasyncclient-osgi-4.0-beta3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta3/httpasyncclient-osgi-4.0-beta3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta3/httpasyncclient-osgi-4.0-beta3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0080 httpasyncclient-osgi-4.0-beta3.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta3/httpasyncclient-osgi-4.0-beta3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta3/httpasyncclient-osgi-4.0-beta3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0-beta3/httpasyncclient-osgi-4.0-beta3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0081 httpasyncclient-osgi-4.0.2.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.2/httpasyncclient-osgi-4.0.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.2/httpasyncclient-osgi-4.0.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.2/httpasyncclient-osgi-4.0.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0082 httpasyncclient-osgi-4.0.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.2/httpasyncclient-osgi-4.0.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.2/httpasyncclient-osgi-4.0.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0.2/httpasyncclient-osgi-4.0.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0083 httpasyncclient-osgi-4.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1/httpasyncclient-osgi-4.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1/httpasyncclient-osgi-4.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1/httpasyncclient-osgi-4.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0084 httpasyncclient-osgi-4.1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1/httpasyncclient-osgi-4.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1/httpasyncclient-osgi-4.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.1/httpasyncclient-osgi-4.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0085 httpasyncclient-osgi-4.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0/httpasyncclient-osgi-4.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0/httpasyncclient-osgi-4.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0/httpasyncclient-osgi-4.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0086 httpasyncclient-osgi-4.0.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0/httpasyncclient-osgi-4.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0/httpasyncclient-osgi-4.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient-osgi/4.0/httpasyncclient-osgi-4.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0087 httpasyncclient-4.0-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta1/httpasyncclient-4.0-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta1/httpasyncclient-4.0-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta1/httpasyncclient-4.0-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0088 httpasyncclient-4.0-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta1/httpasyncclient-4.0-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta1/httpasyncclient-4.0-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta1/httpasyncclient-4.0-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0089 httpasyncclient-4.1.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.5/httpasyncclient-4.1.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.5/httpasyncclient-4.1.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.5/httpasyncclient-4.1.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0090 httpasyncclient-4.1.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.5/httpasyncclient-4.1.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.5/httpasyncclient-4.1.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.5/httpasyncclient-4.1.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0091 httpasyncclient-4.1.5.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.5/httpasyncclient-4.1.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.5/httpasyncclient-4.1.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.5/httpasyncclient-4.1.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0092 httpasyncclient-4.1.2.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.2/httpasyncclient-4.1.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.2/httpasyncclient-4.1.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.2/httpasyncclient-4.1.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0093 httpasyncclient-4.1.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.2/httpasyncclient-4.1.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.2/httpasyncclient-4.1.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.2/httpasyncclient-4.1.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0094 httpasyncclient-4.1.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.3/httpasyncclient-4.1.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.3/httpasyncclient-4.1.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.3/httpasyncclient-4.1.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0095 httpasyncclient-4.1.3.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.3/httpasyncclient-4.1.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.3/httpasyncclient-4.1.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.3/httpasyncclient-4.1.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0096 httpasyncclient-4.1.4.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.4/httpasyncclient-4.1.4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.4/httpasyncclient-4.1.4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.4/httpasyncclient-4.1.4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0097 httpasyncclient-4.1.4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.4/httpasyncclient-4.1.4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.4/httpasyncclient-4.1.4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.4/httpasyncclient-4.1.4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0098 httpasyncclient-4.0.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.1/httpasyncclient-4.0.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.1/httpasyncclient-4.0.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.1/httpasyncclient-4.0.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0099 httpasyncclient-4.0.1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.1/httpasyncclient-4.0.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.1/httpasyncclient-4.0.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.1/httpasyncclient-4.0.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0100 httpasyncclient-4.1-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1-beta1/httpasyncclient-4.1-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1-beta1/httpasyncclient-4.1-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1-beta1/httpasyncclient-4.1-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0101 httpasyncclient-4.1-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1-beta1/httpasyncclient-4.1-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1-beta1/httpasyncclient-4.1-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1-beta1/httpasyncclient-4.1-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0102 httpasyncclient-4.0-alpha3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-alpha3/httpasyncclient-4.0-alpha3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-alpha3/httpasyncclient-4.0-alpha3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-alpha3/httpasyncclient-4.0-alpha3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0103 httpasyncclient-4.0-alpha3.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-alpha3/httpasyncclient-4.0-alpha3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-alpha3/httpasyncclient-4.0-alpha3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-alpha3/httpasyncclient-4.0-alpha3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0104 httpasyncclient-4.1.1.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.1/httpasyncclient-4.1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.1/httpasyncclient-4.1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.1/httpasyncclient-4.1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0105 httpasyncclient-4.1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.1/httpasyncclient-4.1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.1/httpasyncclient-4.1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_pub_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1.1/httpasyncclient-4.1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}
