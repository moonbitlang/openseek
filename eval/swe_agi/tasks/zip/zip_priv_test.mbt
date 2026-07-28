///|
async test "zip invalid 0003 invalid_cde_number_of_files_allocation_smaller_offset.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/zip-rs/tests/data/invalid_cde_number_of_files_allocation_smaller_offset.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/invalid_cde_number_of_files_allocation_smaller_offset.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/invalid_cde_number_of_files_allocation_smaller_offset.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0004 zip64_demo.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/zip-rs/tests/data/zip64_demo.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/zip64_demo.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/zip64_demo.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0005 invalid_offset2.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/zip-rs/tests/data/invalid_offset2.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/invalid_offset2.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/invalid_offset2.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0006 comment_garbage.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/zip-rs/tests/data/comment_garbage.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/comment_garbage.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/comment_garbage.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0007 invalid_offset.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/zip-rs/tests/data/invalid_offset.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/invalid_offset.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/invalid_offset.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0008 invalid_cde_number_of_files_allocation_greater_offset.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/zip-rs/tests/data/invalid_cde_number_of_files_allocation_greater_offset.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/invalid_cde_number_of_files_allocation_greater_offset.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/invalid_cde_number_of_files_allocation_greater_offset.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0009 bogus.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/bogus.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/bogus.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/bogus.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0010 incons-file-count-low.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-file-count-low.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-file-count-low.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-file-count-low.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0011 incons-file-count-overflow.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-file-count-overflow.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-file-count-overflow.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-file-count-overflow.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0012 incons-eocd-magic-bad.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-eocd-magic-bad.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-eocd-magic-bad.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-eocd-magic-bad.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0013 testempty.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testempty.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testempty.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testempty.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0014 incons-central-file-comment-longer.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-file-comment-longer.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-file-comment-longer.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-file-comment-longer.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0015 zip64-in-archive-comment.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/zip64-in-archive-comment.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/zip64-in-archive-comment.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/zip64-in-archive-comment.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0016 testfile-truncated.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-truncated.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-truncated.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-truncated.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0017 zip-in-archive-comment.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/zip-in-archive-comment.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/zip-in-archive-comment.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/zip-in-archive-comment.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0018 incons-cdsize-small.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-cdsize-small.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-cdsize-small.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-cdsize-small.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0019 incons-file-count-high.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-file-count-high.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-file-count-high.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-file-count-high.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0020 incons-central-file-comment-shorter.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-file-comment-shorter.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-file-comment-shorter.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-file-comment-shorter.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0021 incons-cdsize-large.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-cdsize-large.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-cdsize-large.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-cdsize-large.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0022 incons-central-magic-bad2.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-magic-bad2.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-magic-bad2.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-magic-bad2.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0023 incons-cdoffset.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-cdoffset.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-cdoffset.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-cdoffset.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0024 junk-at-start.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/junk-at-start.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/junk-at-start.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/junk-at-start.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0025 incons-eocd64.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-eocd64.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-eocd64.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-eocd64.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0026 incons-gap-before-eocd.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-gap-before-eocd.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-gap-before-eocd.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-gap-before-eocd.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0027 incons-central-magic-bad.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-magic-bad.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-magic-bad.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-magic-bad.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0028 plain.txt" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/manual/nonzip/plain.txt.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/manual/nonzip/plain.txt",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/manual/nonzip/plain.txt",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0029 note.md" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/manual/nonzip/note.md.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/manual/nonzip/note.md",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/manual/nonzip/note.md",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0030 data.json" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/manual/nonzip/data.json.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/manual/nonzip/data.json",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/manual/nonzip/data.json",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0031 config.ini" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/manual/nonzip/config.ini.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/manual/nonzip/config.ini",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/manual/nonzip/config.ini",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0032 random.bin" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/manual/nonzip/random.bin.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/manual/nonzip/random.bin",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/manual/nonzip/random.bin",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip invalid 0033 empty.bin" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/manual/nonzip/empty.bin.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/manual/nonzip/empty.bin",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/manual/nonzip/empty.bin",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0106 httpasyncclient-4.0-beta2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta2/httpasyncclient-4.0-beta2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta2/httpasyncclient-4.0-beta2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta2/httpasyncclient-4.0-beta2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0107 httpasyncclient-4.0-beta2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta2/httpasyncclient-4.0-beta2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta2/httpasyncclient-4.0-beta2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta2/httpasyncclient-4.0-beta2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0108 httpasyncclient-4.0-beta4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta4/httpasyncclient-4.0-beta4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta4/httpasyncclient-4.0-beta4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta4/httpasyncclient-4.0-beta4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0109 httpasyncclient-4.0-beta4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta4/httpasyncclient-4.0-beta4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta4/httpasyncclient-4.0-beta4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta4/httpasyncclient-4.0-beta4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0110 httpasyncclient-4.0-beta3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta3/httpasyncclient-4.0-beta3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta3/httpasyncclient-4.0-beta3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta3/httpasyncclient-4.0-beta3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0111 httpasyncclient-4.0-beta3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta3/httpasyncclient-4.0-beta3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta3/httpasyncclient-4.0-beta3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0-beta3/httpasyncclient-4.0-beta3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0112 httpasyncclient-4.0.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.2/httpasyncclient-4.0.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.2/httpasyncclient-4.0.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.2/httpasyncclient-4.0.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0113 httpasyncclient-4.0.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.2/httpasyncclient-4.0.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.2/httpasyncclient-4.0.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0.2/httpasyncclient-4.0.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0114 httpasyncclient-4.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1/httpasyncclient-4.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1/httpasyncclient-4.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1/httpasyncclient-4.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0115 httpasyncclient-4.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1/httpasyncclient-4.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1/httpasyncclient-4.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.1/httpasyncclient-4.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0116 httpasyncclient-4.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0/httpasyncclient-4.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0/httpasyncclient-4.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0/httpasyncclient-4.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0117 httpasyncclient-4.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0/httpasyncclient-4.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0/httpasyncclient-4.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpasyncclient/4.0/httpasyncclient-4.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0118 httpclient-osgi-4.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-osgi/4.5/httpclient-osgi-4.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-osgi/4.5/httpclient-osgi-4.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-osgi/4.5/httpclient-osgi-4.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0119 httpclient-osgi-4.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-osgi/4.5/httpclient-osgi-4.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-osgi/4.5/httpclient-osgi-4.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-osgi/4.5/httpclient-osgi-4.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0120 httpclient-osgi-4.5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-osgi/4.5/httpclient-osgi-4.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-osgi/4.5/httpclient-osgi-4.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-osgi/4.5/httpclient-osgi-4.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0121 httpclient-android-4.3.5.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5.1/httpclient-android-4.3.5.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5.1/httpclient-android-4.3.5.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5.1/httpclient-android-4.3.5.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0122 httpclient-android-4.3.5.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5.1/httpclient-android-4.3.5.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5.1/httpclient-android-4.3.5.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5.1/httpclient-android-4.3.5.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0123 httpclient-android-4.3.5.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5.1/httpclient-android-4.3.5.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5.1/httpclient-android-4.3.5.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5.1/httpclient-android-4.3.5.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0124 httpclient-android-4.3.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5/httpclient-android-4.3.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5/httpclient-android-4.3.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5/httpclient-android-4.3.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0125 httpclient-android-4.3.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5/httpclient-android-4.3.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5/httpclient-android-4.3.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5/httpclient-android-4.3.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0126 httpclient-android-4.3.5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5/httpclient-android-4.3.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5/httpclient-android-4.3.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.5/httpclient-android-4.3.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0127 httpclient-android-4.3.3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.3/httpclient-android-4.3.3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.3/httpclient-android-4.3.3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.3/httpclient-android-4.3.3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0128 httpclient-android-4.3.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.3/httpclient-android-4.3.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.3/httpclient-android-4.3.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-android/4.3.3/httpclient-android-4.3.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0129 fluent-hc-4.5.14-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.14/fluent-hc-4.5.14-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.14/fluent-hc-4.5.14-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.14/fluent-hc-4.5.14-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0130 fluent-hc-4.5.14-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.14/fluent-hc-4.5.14-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.14/fluent-hc-4.5.14-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.14/fluent-hc-4.5.14-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0131 fluent-hc-4.5.14.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.14/fluent-hc-4.5.14.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.14/fluent-hc-4.5.14.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.14/fluent-hc-4.5.14.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0132 fluent-hc-4.5.13.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.13/fluent-hc-4.5.13.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.13/fluent-hc-4.5.13.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.13/fluent-hc-4.5.13.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0133 fluent-hc-4.5.13-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.13/fluent-hc-4.5.13-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.13/fluent-hc-4.5.13-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.13/fluent-hc-4.5.13-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0134 fluent-hc-4.5.13-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.13/fluent-hc-4.5.13-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.13/fluent-hc-4.5.13-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.13/fluent-hc-4.5.13-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0135 fluent-hc-4.5.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.3/fluent-hc-4.5.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.3/fluent-hc-4.5.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.3/fluent-hc-4.5.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0136 fluent-hc-4.5.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.3/fluent-hc-4.5.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.3/fluent-hc-4.5.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.3/fluent-hc-4.5.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0137 fluent-hc-4.5.3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.3/fluent-hc-4.5.3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.3/fluent-hc-4.5.3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.3/fluent-hc-4.5.3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0138 fluent-hc-4.5.4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.4/fluent-hc-4.5.4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.4/fluent-hc-4.5.4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.4/fluent-hc-4.5.4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0139 fluent-hc-4.5.4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.4/fluent-hc-4.5.4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.4/fluent-hc-4.5.4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.4/fluent-hc-4.5.4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0140 fluent-hc-4.5.4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.4/fluent-hc-4.5.4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.4/fluent-hc-4.5.4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.4/fluent-hc-4.5.4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0141 fluent-hc-4.5.5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.5/fluent-hc-4.5.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.5/fluent-hc-4.5.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.5/fluent-hc-4.5.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0142 fluent-hc-4.5.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.5/fluent-hc-4.5.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.5/fluent-hc-4.5.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.5/fluent-hc-4.5.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0143 fluent-hc-4.5.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.5/fluent-hc-4.5.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.5/fluent-hc-4.5.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.5/fluent-hc-4.5.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0144 fluent-hc-4.5.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.2/fluent-hc-4.5.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.2/fluent-hc-4.5.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.2/fluent-hc-4.5.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0145 fluent-hc-4.5.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.2/fluent-hc-4.5.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.2/fluent-hc-4.5.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.2/fluent-hc-4.5.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0146 fluent-hc-4.5.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.2/fluent-hc-4.5.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.2/fluent-hc-4.5.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.2/fluent-hc-4.5.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0147 fluent-hc-4.5.12.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.12/fluent-hc-4.5.12.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.12/fluent-hc-4.5.12.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.12/fluent-hc-4.5.12.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0148 fluent-hc-4.5.12-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.12/fluent-hc-4.5.12-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.12/fluent-hc-4.5.12-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.12/fluent-hc-4.5.12-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0149 fluent-hc-4.5.12-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.12/fluent-hc-4.5.12-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.12/fluent-hc-4.5.12-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.12/fluent-hc-4.5.12-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0150 fluent-hc-4.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5/fluent-hc-4.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5/fluent-hc-4.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5/fluent-hc-4.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0151 fluent-hc-4.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5/fluent-hc-4.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5/fluent-hc-4.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5/fluent-hc-4.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0152 fluent-hc-4.5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5/fluent-hc-4.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5/fluent-hc-4.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5/fluent-hc-4.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0153 fluent-hc-4.5.10.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.10/fluent-hc-4.5.10.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.10/fluent-hc-4.5.10.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.10/fluent-hc-4.5.10.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0154 fluent-hc-4.5.10-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.10/fluent-hc-4.5.10-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.10/fluent-hc-4.5.10-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.10/fluent-hc-4.5.10-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0155 fluent-hc-4.5.10-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.10/fluent-hc-4.5.10-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.10/fluent-hc-4.5.10-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.10/fluent-hc-4.5.10-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0156 fluent-hc-4.5.9.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.9/fluent-hc-4.5.9.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.9/fluent-hc-4.5.9.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.9/fluent-hc-4.5.9.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0157 fluent-hc-4.5.9-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.9/fluent-hc-4.5.9-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.9/fluent-hc-4.5.9-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.9/fluent-hc-4.5.9-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0158 fluent-hc-4.5.9-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.9/fluent-hc-4.5.9-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.9/fluent-hc-4.5.9-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.9/fluent-hc-4.5.9-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0159 fluent-hc-4.5.7-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.7/fluent-hc-4.5.7-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.7/fluent-hc-4.5.7-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.7/fluent-hc-4.5.7-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0160 fluent-hc-4.5.7-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.7/fluent-hc-4.5.7-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.7/fluent-hc-4.5.7-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.7/fluent-hc-4.5.7-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0161 fluent-hc-4.5.7.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.7/fluent-hc-4.5.7.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.7/fluent-hc-4.5.7.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.7/fluent-hc-4.5.7.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0162 fluent-hc-4.5.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.1/fluent-hc-4.5.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.1/fluent-hc-4.5.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.1/fluent-hc-4.5.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0163 fluent-hc-4.5.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.1/fluent-hc-4.5.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.1/fluent-hc-4.5.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.1/fluent-hc-4.5.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0164 fluent-hc-4.5.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.1/fluent-hc-4.5.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.1/fluent-hc-4.5.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.1/fluent-hc-4.5.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0165 fluent-hc-4.5.6.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.6/fluent-hc-4.5.6.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.6/fluent-hc-4.5.6.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.6/fluent-hc-4.5.6.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0166 fluent-hc-4.5.6-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.6/fluent-hc-4.5.6-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.6/fluent-hc-4.5.6-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.6/fluent-hc-4.5.6-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0167 fluent-hc-4.5.6-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.6/fluent-hc-4.5.6-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.6/fluent-hc-4.5.6-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.6/fluent-hc-4.5.6-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0168 fluent-hc-4.5.8-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.8/fluent-hc-4.5.8-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.8/fluent-hc-4.5.8-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.8/fluent-hc-4.5.8-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0169 fluent-hc-4.5.8-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.8/fluent-hc-4.5.8-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.8/fluent-hc-4.5.8-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.8/fluent-hc-4.5.8-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0170 fluent-hc-4.5.8.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.8/fluent-hc-4.5.8.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.8/fluent-hc-4.5.8.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.8/fluent-hc-4.5.8.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0171 fluent-hc-4.5.11.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.11/fluent-hc-4.5.11.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.11/fluent-hc-4.5.11.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.11/fluent-hc-4.5.11.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0172 fluent-hc-4.5.11-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.11/fluent-hc-4.5.11-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.11/fluent-hc-4.5.11-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.11/fluent-hc-4.5.11-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0173 fluent-hc-4.5.11-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.11/fluent-hc-4.5.11-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.11/fluent-hc-4.5.11-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/fluent-hc/4.5.11/fluent-hc-4.5.11-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0174 httpclient-cache-4.5.14-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.14/httpclient-cache-4.5.14-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.14/httpclient-cache-4.5.14-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.14/httpclient-cache-4.5.14-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0175 httpclient-cache-4.5.14-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.14/httpclient-cache-4.5.14-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.14/httpclient-cache-4.5.14-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.14/httpclient-cache-4.5.14-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0176 httpclient-cache-4.5.14.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.14/httpclient-cache-4.5.14.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.14/httpclient-cache-4.5.14.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.14/httpclient-cache-4.5.14.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0177 httpclient-cache-4.5.13.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.13/httpclient-cache-4.5.13.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.13/httpclient-cache-4.5.13.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.13/httpclient-cache-4.5.13.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0178 httpclient-cache-4.5.13-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.13/httpclient-cache-4.5.13-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.13/httpclient-cache-4.5.13-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.13/httpclient-cache-4.5.13-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0179 httpclient-cache-4.5.13-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.13/httpclient-cache-4.5.13-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.13/httpclient-cache-4.5.13-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.13/httpclient-cache-4.5.13-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0180 httpclient-cache-4.5.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.3/httpclient-cache-4.5.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.3/httpclient-cache-4.5.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.3/httpclient-cache-4.5.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0181 httpclient-cache-4.5.3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.3/httpclient-cache-4.5.3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.3/httpclient-cache-4.5.3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.3/httpclient-cache-4.5.3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0182 httpclient-cache-4.5.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.3/httpclient-cache-4.5.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.3/httpclient-cache-4.5.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.3/httpclient-cache-4.5.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0183 httpclient-cache-4.5.4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.4/httpclient-cache-4.5.4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.4/httpclient-cache-4.5.4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.4/httpclient-cache-4.5.4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0184 httpclient-cache-4.5.4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.4/httpclient-cache-4.5.4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.4/httpclient-cache-4.5.4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.4/httpclient-cache-4.5.4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0185 httpclient-cache-4.5.4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.4/httpclient-cache-4.5.4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.4/httpclient-cache-4.5.4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.4/httpclient-cache-4.5.4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0186 httpclient-cache-4.5.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.5/httpclient-cache-4.5.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.5/httpclient-cache-4.5.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.5/httpclient-cache-4.5.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0187 httpclient-cache-4.5.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.5/httpclient-cache-4.5.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.5/httpclient-cache-4.5.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.5/httpclient-cache-4.5.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0188 httpclient-cache-4.5.5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.5/httpclient-cache-4.5.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.5/httpclient-cache-4.5.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.5/httpclient-cache-4.5.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0189 httpclient-cache-4.5.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.2/httpclient-cache-4.5.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.2/httpclient-cache-4.5.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.2/httpclient-cache-4.5.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0190 httpclient-cache-4.5.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.2/httpclient-cache-4.5.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.2/httpclient-cache-4.5.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.2/httpclient-cache-4.5.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0191 httpclient-cache-4.5.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.2/httpclient-cache-4.5.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.2/httpclient-cache-4.5.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.2/httpclient-cache-4.5.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0192 httpclient-cache-4.5.12.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.12/httpclient-cache-4.5.12.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.12/httpclient-cache-4.5.12.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.12/httpclient-cache-4.5.12.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0193 httpclient-cache-4.5.12-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.12/httpclient-cache-4.5.12-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.12/httpclient-cache-4.5.12-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.12/httpclient-cache-4.5.12-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0194 httpclient-cache-4.5.12-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.12/httpclient-cache-4.5.12-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.12/httpclient-cache-4.5.12-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.12/httpclient-cache-4.5.12-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0195 httpclient-cache-4.5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5/httpclient-cache-4.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5/httpclient-cache-4.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5/httpclient-cache-4.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0196 httpclient-cache-4.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5/httpclient-cache-4.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5/httpclient-cache-4.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5/httpclient-cache-4.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0197 httpclient-cache-4.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5/httpclient-cache-4.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5/httpclient-cache-4.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5/httpclient-cache-4.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0198 httpclient-cache-4.5.10.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.10/httpclient-cache-4.5.10.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.10/httpclient-cache-4.5.10.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.10/httpclient-cache-4.5.10.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0199 httpclient-cache-4.5.10-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.10/httpclient-cache-4.5.10-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.10/httpclient-cache-4.5.10-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.10/httpclient-cache-4.5.10-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0200 httpclient-cache-4.5.10-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.10/httpclient-cache-4.5.10-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.10/httpclient-cache-4.5.10-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.10/httpclient-cache-4.5.10-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0201 httpclient-cache-4.5.9-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.9/httpclient-cache-4.5.9-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.9/httpclient-cache-4.5.9-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.9/httpclient-cache-4.5.9-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0202 httpclient-cache-4.5.9-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.9/httpclient-cache-4.5.9-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.9/httpclient-cache-4.5.9-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.9/httpclient-cache-4.5.9-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0203 httpclient-cache-4.5.9.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.9/httpclient-cache-4.5.9.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.9/httpclient-cache-4.5.9.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.9/httpclient-cache-4.5.9.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0204 httpclient-cache-4.5.7.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.7/httpclient-cache-4.5.7.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.7/httpclient-cache-4.5.7.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.7/httpclient-cache-4.5.7.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0205 httpclient-cache-4.5.7-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.7/httpclient-cache-4.5.7-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.7/httpclient-cache-4.5.7-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.7/httpclient-cache-4.5.7-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0206 httpclient-cache-4.5.7-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.7/httpclient-cache-4.5.7-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.7/httpclient-cache-4.5.7-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.7/httpclient-cache-4.5.7-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0207 httpclient-cache-4.5.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.1/httpclient-cache-4.5.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.1/httpclient-cache-4.5.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.1/httpclient-cache-4.5.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0208 httpclient-cache-4.5.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.1/httpclient-cache-4.5.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.1/httpclient-cache-4.5.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.1/httpclient-cache-4.5.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0209 httpclient-cache-4.5.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.1/httpclient-cache-4.5.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.1/httpclient-cache-4.5.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.1/httpclient-cache-4.5.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0210 httpclient-cache-4.5.6-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.6/httpclient-cache-4.5.6-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.6/httpclient-cache-4.5.6-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.6/httpclient-cache-4.5.6-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0211 httpclient-cache-4.5.6-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.6/httpclient-cache-4.5.6-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.6/httpclient-cache-4.5.6-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.6/httpclient-cache-4.5.6-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0212 httpclient-cache-4.5.6.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.6/httpclient-cache-4.5.6.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.6/httpclient-cache-4.5.6.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.6/httpclient-cache-4.5.6.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0213 httpclient-cache-4.5.8.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.8/httpclient-cache-4.5.8.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.8/httpclient-cache-4.5.8.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.8/httpclient-cache-4.5.8.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0214 httpclient-cache-4.5.8-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.8/httpclient-cache-4.5.8-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.8/httpclient-cache-4.5.8-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.8/httpclient-cache-4.5.8-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0215 httpclient-cache-4.5.8-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.8/httpclient-cache-4.5.8-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.8/httpclient-cache-4.5.8-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.8/httpclient-cache-4.5.8-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0216 httpclient-cache-4.5.11-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.11/httpclient-cache-4.5.11-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.11/httpclient-cache-4.5.11-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.11/httpclient-cache-4.5.11-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0217 httpclient-cache-4.5.11-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.11/httpclient-cache-4.5.11-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.11/httpclient-cache-4.5.11-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.11/httpclient-cache-4.5.11-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0218 httpclient-cache-4.5.11.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.11/httpclient-cache-4.5.11.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.11/httpclient-cache-4.5.11.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/httpcomponents/httpclient-cache/4.5.11/httpclient-cache-4.5.11.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0219 commons-jci-eclipse-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-eclipse/1.0/commons-jci-eclipse-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.0/commons-jci-eclipse-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.0/commons-jci-eclipse-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0220 commons-jci-eclipse-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-eclipse/1.0/commons-jci-eclipse-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.0/commons-jci-eclipse-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.0/commons-jci-eclipse-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0221 commons-jci-eclipse-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-eclipse/1.0/commons-jci-eclipse-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.0/commons-jci-eclipse-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.0/commons-jci-eclipse-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0222 commons-jci-eclipse-1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-eclipse/1.1/commons-jci-eclipse-1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.1/commons-jci-eclipse-1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.1/commons-jci-eclipse-1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0223 commons-jci-eclipse-1.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-eclipse/1.1/commons-jci-eclipse-1.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.1/commons-jci-eclipse-1.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.1/commons-jci-eclipse-1.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0224 commons-jci-eclipse-1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-eclipse/1.1/commons-jci-eclipse-1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.1/commons-jci-eclipse-1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-eclipse/1.1/commons-jci-eclipse-1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0225 commons-email2-javax-2.0.0-M1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email2-javax/2.0.0-M1/commons-email2-javax-2.0.0-M1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-javax/2.0.0-M1/commons-email2-javax-2.0.0-M1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-javax/2.0.0-M1/commons-email2-javax-2.0.0-M1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0226 commons-email2-javax-2.0.0-M1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email2-javax/2.0.0-M1/commons-email2-javax-2.0.0-M1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-javax/2.0.0-M1/commons-email2-javax-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-javax/2.0.0-M1/commons-email2-javax-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0227 commons-email2-javax-2.0.0-M1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email2-javax/2.0.0-M1/commons-email2-javax-2.0.0-M1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-javax/2.0.0-M1/commons-email2-javax-2.0.0-M1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-javax/2.0.0-M1/commons-email2-javax-2.0.0-M1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0228 commons-jci-examples-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-examples/1.0/commons-jci-examples-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-examples/1.0/commons-jci-examples-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-examples/1.0/commons-jci-examples-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0229 commons-jci-examples-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-examples/1.0/commons-jci-examples-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-examples/1.0/commons-jci-examples-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-examples/1.0/commons-jci-examples-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0230 commons-jci-examples-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-examples/1.0/commons-jci-examples-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-examples/1.0/commons-jci-examples-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-examples/1.0/commons-jci-examples-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0231 commons-compress-1.24.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.24.0/commons-compress-1.24.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.24.0/commons-compress-1.24.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.24.0/commons-compress-1.24.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0232 commons-compress-1.24.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.24.0/commons-compress-1.24.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.24.0/commons-compress-1.24.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.24.0/commons-compress-1.24.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0233 commons-compress-1.24.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.24.0/commons-compress-1.24.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.24.0/commons-compress-1.24.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.24.0/commons-compress-1.24.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0234 commons-compress-1.9.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.9/commons-compress-1.9.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.9/commons-compress-1.9.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.9/commons-compress-1.9.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0235 commons-compress-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.0/commons-compress-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.0/commons-compress-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.0/commons-compress-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0236 commons-compress-1.7.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.7/commons-compress-1.7.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.7/commons-compress-1.7.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.7/commons-compress-1.7.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0237 commons-compress-1.6.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.6/commons-compress-1.6.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.6/commons-compress-1.6.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.6/commons-compress-1.6.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0238 commons-compress-1.26.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.26.2/commons-compress-1.26.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.2/commons-compress-1.26.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.2/commons-compress-1.26.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0239 commons-compress-1.26.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.26.2/commons-compress-1.26.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.2/commons-compress-1.26.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.2/commons-compress-1.26.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0240 commons-compress-1.26.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.26.2/commons-compress-1.26.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.2/commons-compress-1.26.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.2/commons-compress-1.26.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0241 commons-compress-1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.1/commons-compress-1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.1/commons-compress-1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.1/commons-compress-1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0242 commons-compress-1.8.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.8/commons-compress-1.8.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.8/commons-compress-1.8.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.8/commons-compress-1.8.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0243 commons-compress-1.12.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.12/commons-compress-1.12.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.12/commons-compress-1.12.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.12/commons-compress-1.12.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0244 commons-compress-1.15-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.15/commons-compress-1.15-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.15/commons-compress-1.15-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.15/commons-compress-1.15-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0245 commons-compress-1.15-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.15/commons-compress-1.15-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.15/commons-compress-1.15-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.15/commons-compress-1.15-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0246 commons-compress-1.15.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.15/commons-compress-1.15.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.15/commons-compress-1.15.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.15/commons-compress-1.15.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0247 commons-compress-1.16.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.16.1/commons-compress-1.16.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16.1/commons-compress-1.16.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16.1/commons-compress-1.16.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0248 commons-compress-1.16.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.16.1/commons-compress-1.16.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16.1/commons-compress-1.16.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16.1/commons-compress-1.16.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0249 commons-compress-1.16.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.16.1/commons-compress-1.16.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16.1/commons-compress-1.16.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16.1/commons-compress-1.16.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0250 commons-compress-1.22-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.22/commons-compress-1.22-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.22/commons-compress-1.22-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.22/commons-compress-1.22-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0251 commons-compress-1.22-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.22/commons-compress-1.22-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.22/commons-compress-1.22-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.22/commons-compress-1.22-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0252 commons-compress-1.22.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.22/commons-compress-1.22.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.22/commons-compress-1.22.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.22/commons-compress-1.22.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0253 commons-compress-1.14.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.14/commons-compress-1.14.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.14/commons-compress-1.14.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.14/commons-compress-1.14.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0254 commons-compress-1.14-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.14/commons-compress-1.14-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.14/commons-compress-1.14-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.14/commons-compress-1.14-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0255 commons-compress-1.14-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.14/commons-compress-1.14-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.14/commons-compress-1.14-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.14/commons-compress-1.14-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0256 commons-compress-1.13-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.13/commons-compress-1.13-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.13/commons-compress-1.13-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.13/commons-compress-1.13-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0257 commons-compress-1.13.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.13/commons-compress-1.13.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.13/commons-compress-1.13.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.13/commons-compress-1.13.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0258 commons-compress-1.13-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.13/commons-compress-1.13-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.13/commons-compress-1.13-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.13/commons-compress-1.13-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0259 commons-compress-1.27.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.27.0/commons-compress-1.27.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.0/commons-compress-1.27.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.0/commons-compress-1.27.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0260 commons-compress-1.27.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.27.0/commons-compress-1.27.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.0/commons-compress-1.27.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.0/commons-compress-1.27.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0261 commons-compress-1.27.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.27.0/commons-compress-1.27.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.0/commons-compress-1.27.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.0/commons-compress-1.27.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0262 commons-compress-1.4.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.4.1/commons-compress-1.4.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.4.1/commons-compress-1.4.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.4.1/commons-compress-1.4.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0263 commons-compress-1.27.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.27.1/commons-compress-1.27.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.1/commons-compress-1.27.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.1/commons-compress-1.27.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0264 commons-compress-1.27.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.27.1/commons-compress-1.27.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.1/commons-compress-1.27.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.1/commons-compress-1.27.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0265 commons-compress-1.27.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.27.1/commons-compress-1.27.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.1/commons-compress-1.27.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.27.1/commons-compress-1.27.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0266 commons-compress-1.23.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.23.0/commons-compress-1.23.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.23.0/commons-compress-1.23.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.23.0/commons-compress-1.23.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0267 commons-compress-1.23.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.23.0/commons-compress-1.23.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.23.0/commons-compress-1.23.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.23.0/commons-compress-1.23.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0268 commons-compress-1.23.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.23.0/commons-compress-1.23.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.23.0/commons-compress-1.23.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.23.0/commons-compress-1.23.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0269 commons-compress-1.4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.4/commons-compress-1.4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.4/commons-compress-1.4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.4/commons-compress-1.4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0270 commons-compress-1.26.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.26.0/commons-compress-1.26.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.0/commons-compress-1.26.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.0/commons-compress-1.26.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0271 commons-compress-1.26.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.26.0/commons-compress-1.26.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.0/commons-compress-1.26.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.0/commons-compress-1.26.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0272 commons-compress-1.26.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.26.0/commons-compress-1.26.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.0/commons-compress-1.26.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.0/commons-compress-1.26.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0273 commons-compress-1.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.3/commons-compress-1.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.3/commons-compress-1.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.3/commons-compress-1.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0274 commons-compress-1.26.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.26.1/commons-compress-1.26.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.1/commons-compress-1.26.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.1/commons-compress-1.26.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0275 commons-compress-1.26.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.26.1/commons-compress-1.26.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.1/commons-compress-1.26.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.1/commons-compress-1.26.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0276 commons-compress-1.26.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.26.1/commons-compress-1.26.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.1/commons-compress-1.26.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.26.1/commons-compress-1.26.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0277 commons-compress-1.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.2/commons-compress-1.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.2/commons-compress-1.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.2/commons-compress-1.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0278 commons-compress-1.5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.5/commons-compress-1.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.5/commons-compress-1.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.5/commons-compress-1.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0279 commons-compress-1.28.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.28.0/commons-compress-1.28.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.28.0/commons-compress-1.28.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.28.0/commons-compress-1.28.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0280 commons-compress-1.28.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.28.0/commons-compress-1.28.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.28.0/commons-compress-1.28.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.28.0/commons-compress-1.28.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0281 commons-compress-1.16-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.16/commons-compress-1.16-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16/commons-compress-1.16-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16/commons-compress-1.16-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0282 commons-compress-1.16.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.16/commons-compress-1.16.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16/commons-compress-1.16.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16/commons-compress-1.16.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0283 commons-compress-1.16-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.16/commons-compress-1.16-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16/commons-compress-1.16-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.16/commons-compress-1.16-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0284 commons-compress-1.11.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.11/commons-compress-1.11.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.11/commons-compress-1.11.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.11/commons-compress-1.11.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0285 commons-compress-1.18-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.18/commons-compress-1.18-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.18/commons-compress-1.18-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.18/commons-compress-1.18-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0286 commons-compress-1.18-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.18/commons-compress-1.18-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.18/commons-compress-1.18-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.18/commons-compress-1.18-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0287 commons-compress-1.18.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.18/commons-compress-1.18.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.18/commons-compress-1.18.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.18/commons-compress-1.18.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0288 commons-compress-1.20.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.20/commons-compress-1.20.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.20/commons-compress-1.20.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.20/commons-compress-1.20.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0289 commons-compress-1.20-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.20/commons-compress-1.20-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.20/commons-compress-1.20-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.20/commons-compress-1.20-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0290 commons-compress-1.20-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.20/commons-compress-1.20-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.20/commons-compress-1.20-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.20/commons-compress-1.20-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0291 commons-compress-1.21-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.21/commons-compress-1.21-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.21/commons-compress-1.21-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.21/commons-compress-1.21-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0292 commons-compress-1.21-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.21/commons-compress-1.21-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.21/commons-compress-1.21-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.21/commons-compress-1.21-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0293 commons-compress-1.21.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.21/commons-compress-1.21.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.21/commons-compress-1.21.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.21/commons-compress-1.21.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0294 commons-compress-1.19-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.19/commons-compress-1.19-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.19/commons-compress-1.19-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.19/commons-compress-1.19-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0295 commons-compress-1.19-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.19/commons-compress-1.19-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.19/commons-compress-1.19-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.19/commons-compress-1.19-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0296 commons-compress-1.19.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.19/commons-compress-1.19.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.19/commons-compress-1.19.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.19/commons-compress-1.19.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0297 commons-compress-1.10.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.10/commons-compress-1.10.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.10/commons-compress-1.10.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.10/commons-compress-1.10.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0298 commons-compress-1.17.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.17/commons-compress-1.17.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.17/commons-compress-1.17.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.17/commons-compress-1.17.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0299 commons-compress-1.17-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.17/commons-compress-1.17-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.17/commons-compress-1.17-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.17/commons-compress-1.17-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0300 commons-compress-1.17-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.17/commons-compress-1.17-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.17/commons-compress-1.17-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.17/commons-compress-1.17-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0301 commons-compress-1.25.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.25.0/commons-compress-1.25.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.25.0/commons-compress-1.25.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.25.0/commons-compress-1.25.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0302 commons-compress-1.25.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.25.0/commons-compress-1.25.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.25.0/commons-compress-1.25.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.25.0/commons-compress-1.25.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0303 commons-compress-1.25.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.25.0/commons-compress-1.25.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.25.0/commons-compress-1.25.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.25.0/commons-compress-1.25.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0304 commons-compress-1.8.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-compress/1.8.1/commons-compress-1.8.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.8.1/commons-compress-1.8.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-compress/1.8.1/commons-compress-1.8.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0305 commons-jci-fam-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-fam/1.0/commons-jci-fam-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.0/commons-jci-fam-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.0/commons-jci-fam-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0306 commons-jci-fam-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-fam/1.0/commons-jci-fam-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.0/commons-jci-fam-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.0/commons-jci-fam-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0307 commons-jci-fam-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-fam/1.0/commons-jci-fam-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.0/commons-jci-fam-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.0/commons-jci-fam-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0308 commons-jci-fam-1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-fam/1.1/commons-jci-fam-1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.1/commons-jci-fam-1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.1/commons-jci-fam-1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0309 commons-jci-fam-1.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-fam/1.1/commons-jci-fam-1.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.1/commons-jci-fam-1.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.1/commons-jci-fam-1.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0310 commons-jci-fam-1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-fam/1.1/commons-jci-fam-1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.1/commons-jci-fam-1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-fam/1.1/commons-jci-fam-1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0311 commons-geometry-examples-tutorials-1.0-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-examples-tutorials/1.0-beta1/commons-geometry-examples-tutorials-1.0-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-tutorials/1.0-beta1/commons-geometry-examples-tutorials-1.0-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-tutorials/1.0-beta1/commons-geometry-examples-tutorials-1.0-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0312 commons-geometry-examples-tutorials-1.0-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-examples-tutorials/1.0-beta1/commons-geometry-examples-tutorials-1.0-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-tutorials/1.0-beta1/commons-geometry-examples-tutorials-1.0-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-tutorials/1.0-beta1/commons-geometry-examples-tutorials-1.0-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0313 commons-geometry-examples-tutorials-1.0-beta1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-examples-tutorials/1.0-beta1/commons-geometry-examples-tutorials-1.0-beta1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-tutorials/1.0-beta1/commons-geometry-examples-tutorials-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-tutorials/1.0-beta1/commons-geometry-examples-tutorials-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0314 commons-jcs3-jcache-extras-3.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2/commons-jcs3-jcache-extras-3.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2/commons-jcs3-jcache-extras-3.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2/commons-jcs3-jcache-extras-3.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0315 commons-jcs3-jcache-extras-3.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2/commons-jcs3-jcache-extras-3.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2/commons-jcs3-jcache-extras-3.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2/commons-jcs3-jcache-extras-3.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0316 commons-jcs3-jcache-extras-3.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2/commons-jcs3-jcache-extras-3.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2/commons-jcs3-jcache-extras-3.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2/commons-jcs3-jcache-extras-3.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0317 commons-jcs3-jcache-extras-3.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.0/commons-jcs3-jcache-extras-3.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.0/commons-jcs3-jcache-extras-3.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.0/commons-jcs3-jcache-extras-3.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0318 commons-jcs3-jcache-extras-3.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.0/commons-jcs3-jcache-extras-3.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.0/commons-jcs3-jcache-extras-3.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.0/commons-jcs3-jcache-extras-3.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0319 commons-jcs3-jcache-extras-3.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.0/commons-jcs3-jcache-extras-3.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.0/commons-jcs3-jcache-extras-3.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.0/commons-jcs3-jcache-extras-3.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0320 commons-jcs3-jcache-extras-3.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.1/commons-jcs3-jcache-extras-3.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.1/commons-jcs3-jcache-extras-3.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.1/commons-jcs3-jcache-extras-3.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0321 commons-jcs3-jcache-extras-3.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.1/commons-jcs3-jcache-extras-3.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.1/commons-jcs3-jcache-extras-3.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.1/commons-jcs3-jcache-extras-3.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0322 commons-jcs3-jcache-extras-3.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.1/commons-jcs3-jcache-extras-3.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.1/commons-jcs3-jcache-extras-3.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.1/commons-jcs3-jcache-extras-3.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0323 commons-jcs3-jcache-extras-3.2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2.1/commons-jcs3-jcache-extras-3.2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2.1/commons-jcs3-jcache-extras-3.2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2.1/commons-jcs3-jcache-extras-3.2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0324 commons-jcs3-jcache-extras-3.2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2.1/commons-jcs3-jcache-extras-3.2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2.1/commons-jcs3-jcache-extras-3.2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2.1/commons-jcs3-jcache-extras-3.2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0325 commons-jcs3-jcache-extras-3.2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2.1/commons-jcs3-jcache-extras-3.2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2.1/commons-jcs3-jcache-extras-3.2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-extras/3.2.1/commons-jcs3-jcache-extras-3.2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0326 commons-jcs3-jcache-3.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2/commons-jcs3-jcache-3.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2/commons-jcs3-jcache-3.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2/commons-jcs3-jcache-3.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0327 commons-jcs3-jcache-3.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2/commons-jcs3-jcache-3.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2/commons-jcs3-jcache-3.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2/commons-jcs3-jcache-3.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0328 commons-jcs3-jcache-3.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2/commons-jcs3-jcache-3.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2/commons-jcs3-jcache-3.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2/commons-jcs3-jcache-3.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0329 commons-jcs3-jcache-3.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.0/commons-jcs3-jcache-3.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.0/commons-jcs3-jcache-3.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.0/commons-jcs3-jcache-3.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0330 commons-jcs3-jcache-3.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.0/commons-jcs3-jcache-3.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.0/commons-jcs3-jcache-3.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.0/commons-jcs3-jcache-3.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0331 commons-jcs3-jcache-3.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.0/commons-jcs3-jcache-3.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.0/commons-jcs3-jcache-3.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.0/commons-jcs3-jcache-3.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0332 commons-jcs3-jcache-3.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.1/commons-jcs3-jcache-3.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.1/commons-jcs3-jcache-3.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.1/commons-jcs3-jcache-3.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0333 commons-jcs3-jcache-3.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.1/commons-jcs3-jcache-3.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.1/commons-jcs3-jcache-3.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.1/commons-jcs3-jcache-3.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0334 commons-jcs3-jcache-3.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.1/commons-jcs3-jcache-3.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.1/commons-jcs3-jcache-3.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.1/commons-jcs3-jcache-3.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0335 commons-jcs3-jcache-3.2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2.1/commons-jcs3-jcache-3.2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2.1/commons-jcs3-jcache-3.2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2.1/commons-jcs3-jcache-3.2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0336 commons-jcs3-jcache-3.2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2.1/commons-jcs3-jcache-3.2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2.1/commons-jcs3-jcache-3.2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2.1/commons-jcs3-jcache-3.2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0337 commons-jcs3-jcache-3.2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2.1/commons-jcs3-jcache-3.2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2.1/commons-jcs3-jcache-3.2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache/3.2.1/commons-jcs3-jcache-3.2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0338 commons-email2-jakarta-2.0.0-M1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email2-jakarta/2.0.0-M1/commons-email2-jakarta-2.0.0-M1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-jakarta/2.0.0-M1/commons-email2-jakarta-2.0.0-M1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-jakarta/2.0.0-M1/commons-email2-jakarta-2.0.0-M1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0339 commons-email2-jakarta-2.0.0-M1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email2-jakarta/2.0.0-M1/commons-email2-jakarta-2.0.0-M1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-jakarta/2.0.0-M1/commons-email2-jakarta-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-jakarta/2.0.0-M1/commons-email2-jakarta-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0340 commons-email2-jakarta-2.0.0-M1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email2-jakarta/2.0.0-M1/commons-email2-jakarta-2.0.0-M1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-jakarta/2.0.0-M1/commons-email2-jakarta-2.0.0-M1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-jakarta/2.0.0-M1/commons-email2-jakarta-2.0.0-M1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0341 commons-jci-janino-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-janino/1.0/commons-jci-janino-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.0/commons-jci-janino-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.0/commons-jci-janino-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0342 commons-jci-janino-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-janino/1.0/commons-jci-janino-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.0/commons-jci-janino-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.0/commons-jci-janino-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0343 commons-jci-janino-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-janino/1.0/commons-jci-janino-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.0/commons-jci-janino-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.0/commons-jci-janino-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0344 commons-jci-janino-1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-janino/1.1/commons-jci-janino-1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.1/commons-jci-janino-1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.1/commons-jci-janino-1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0345 commons-jci-janino-1.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-janino/1.1/commons-jci-janino-1.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.1/commons-jci-janino-1.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.1/commons-jci-janino-1.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0346 commons-jci-janino-1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-janino/1.1/commons-jci-janino-1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.1/commons-jci-janino-1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-janino/1.1/commons-jci-janino-1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0347 commons-jci-groovy-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-groovy/1.0/commons-jci-groovy-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.0/commons-jci-groovy-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.0/commons-jci-groovy-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0348 commons-jci-groovy-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-groovy/1.0/commons-jci-groovy-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.0/commons-jci-groovy-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.0/commons-jci-groovy-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0349 commons-jci-groovy-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-groovy/1.0/commons-jci-groovy-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.0/commons-jci-groovy-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.0/commons-jci-groovy-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0350 commons-jci-groovy-1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-groovy/1.1/commons-jci-groovy-1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.1/commons-jci-groovy-1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.1/commons-jci-groovy-1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0351 commons-jci-groovy-1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-groovy/1.1/commons-jci-groovy-1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.1/commons-jci-groovy-1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.1/commons-jci-groovy-1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0352 commons-jci-groovy-1.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-groovy/1.1/commons-jci-groovy-1.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.1/commons-jci-groovy-1.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-groovy/1.1/commons-jci-groovy-1.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0353 commons-crypto-1.0.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-crypto/1.0.0/commons-crypto-1.0.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.0.0/commons-crypto-1.0.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.0.0/commons-crypto-1.0.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0354 commons-crypto-1.0.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-crypto/1.0.0/commons-crypto-1.0.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.0.0/commons-crypto-1.0.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.0.0/commons-crypto-1.0.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0355 commons-crypto-1.0.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-crypto/1.0.0/commons-crypto-1.0.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.0.0/commons-crypto-1.0.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.0.0/commons-crypto-1.0.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0356 commons-crypto-1.1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-crypto/1.1.0/commons-crypto-1.1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.1.0/commons-crypto-1.1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.1.0/commons-crypto-1.1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0357 commons-crypto-1.1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-crypto/1.1.0/commons-crypto-1.1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.1.0/commons-crypto-1.1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.1.0/commons-crypto-1.1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0358 commons-crypto-1.1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-crypto/1.1.0/commons-crypto-1.1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.1.0/commons-crypto-1.1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.1.0/commons-crypto-1.1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0359 commons-crypto-1.2.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-crypto/1.2.0/commons-crypto-1.2.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.2.0/commons-crypto-1.2.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.2.0/commons-crypto-1.2.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0360 commons-crypto-1.2.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-crypto/1.2.0/commons-crypto-1.2.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.2.0/commons-crypto-1.2.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.2.0/commons-crypto-1.2.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0361 commons-crypto-1.2.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-crypto/1.2.0/commons-crypto-1.2.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.2.0/commons-crypto-1.2.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-crypto/1.2.0/commons-crypto-1.2.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0362 commons-geometry-hull-1.0-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-hull/1.0-beta1/commons-geometry-hull-1.0-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-hull/1.0-beta1/commons-geometry-hull-1.0-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-hull/1.0-beta1/commons-geometry-hull-1.0-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0363 commons-geometry-hull-1.0-beta1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-hull/1.0-beta1/commons-geometry-hull-1.0-beta1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-hull/1.0-beta1/commons-geometry-hull-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-hull/1.0-beta1/commons-geometry-hull-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0364 commons-geometry-hull-1.0-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-hull/1.0-beta1/commons-geometry-hull-1.0-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-hull/1.0-beta1/commons-geometry-hull-1.0-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-hull/1.0-beta1/commons-geometry-hull-1.0-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0365 commons-jcs3-jcache-openjpa-3.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2/commons-jcs3-jcache-openjpa-3.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2/commons-jcs3-jcache-openjpa-3.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2/commons-jcs3-jcache-openjpa-3.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0366 commons-jcs3-jcache-openjpa-3.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2/commons-jcs3-jcache-openjpa-3.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2/commons-jcs3-jcache-openjpa-3.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2/commons-jcs3-jcache-openjpa-3.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0367 commons-jcs3-jcache-openjpa-3.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2/commons-jcs3-jcache-openjpa-3.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2/commons-jcs3-jcache-openjpa-3.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2/commons-jcs3-jcache-openjpa-3.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0368 commons-jcs3-jcache-openjpa-3.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.0/commons-jcs3-jcache-openjpa-3.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.0/commons-jcs3-jcache-openjpa-3.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.0/commons-jcs3-jcache-openjpa-3.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0369 commons-jcs3-jcache-openjpa-3.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.0/commons-jcs3-jcache-openjpa-3.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.0/commons-jcs3-jcache-openjpa-3.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.0/commons-jcs3-jcache-openjpa-3.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0370 commons-jcs3-jcache-openjpa-3.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.0/commons-jcs3-jcache-openjpa-3.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.0/commons-jcs3-jcache-openjpa-3.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.0/commons-jcs3-jcache-openjpa-3.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0371 commons-jcs3-jcache-openjpa-3.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.1/commons-jcs3-jcache-openjpa-3.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.1/commons-jcs3-jcache-openjpa-3.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.1/commons-jcs3-jcache-openjpa-3.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0372 commons-jcs3-jcache-openjpa-3.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.1/commons-jcs3-jcache-openjpa-3.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.1/commons-jcs3-jcache-openjpa-3.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.1/commons-jcs3-jcache-openjpa-3.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0373 commons-jcs3-jcache-openjpa-3.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.1/commons-jcs3-jcache-openjpa-3.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.1/commons-jcs3-jcache-openjpa-3.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.1/commons-jcs3-jcache-openjpa-3.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0374 commons-jcs3-jcache-openjpa-3.2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2.1/commons-jcs3-jcache-openjpa-3.2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2.1/commons-jcs3-jcache-openjpa-3.2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2.1/commons-jcs3-jcache-openjpa-3.2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0375 commons-jcs3-jcache-openjpa-3.2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2.1/commons-jcs3-jcache-openjpa-3.2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2.1/commons-jcs3-jcache-openjpa-3.2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2.1/commons-jcs3-jcache-openjpa-3.2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0376 commons-jcs3-jcache-openjpa-3.2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2.1/commons-jcs3-jcache-openjpa-3.2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2.1/commons-jcs3-jcache-openjpa-3.2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-openjpa/3.2.1/commons-jcs3-jcache-openjpa-3.2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0377 commons-geometry-euclidean-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0/commons-geometry-euclidean-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0/commons-geometry-euclidean-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0/commons-geometry-euclidean-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0378 commons-geometry-euclidean-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0/commons-geometry-euclidean-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0/commons-geometry-euclidean-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0/commons-geometry-euclidean-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0379 commons-geometry-euclidean-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0/commons-geometry-euclidean-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0/commons-geometry-euclidean-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0/commons-geometry-euclidean-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0380 commons-geometry-euclidean-1.0-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0-beta1/commons-geometry-euclidean-1.0-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0-beta1/commons-geometry-euclidean-1.0-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0-beta1/commons-geometry-euclidean-1.0-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0381 commons-geometry-euclidean-1.0-beta1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0-beta1/commons-geometry-euclidean-1.0-beta1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0-beta1/commons-geometry-euclidean-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0-beta1/commons-geometry-euclidean-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0382 commons-geometry-euclidean-1.0-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0-beta1/commons-geometry-euclidean-1.0-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0-beta1/commons-geometry-euclidean-1.0-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-euclidean/1.0-beta1/commons-geometry-euclidean-1.0-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0383 commons-email2-core-2.0.0-M1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email2-core/2.0.0-M1/commons-email2-core-2.0.0-M1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-core/2.0.0-M1/commons-email2-core-2.0.0-M1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-core/2.0.0-M1/commons-email2-core-2.0.0-M1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0384 commons-email2-core-2.0.0-M1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email2-core/2.0.0-M1/commons-email2-core-2.0.0-M1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-core/2.0.0-M1/commons-email2-core-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-core/2.0.0-M1/commons-email2-core-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0385 commons-email2-core-2.0.0-M1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email2-core/2.0.0-M1/commons-email2-core-2.0.0-M1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-core/2.0.0-M1/commons-email2-core-2.0.0-M1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email2-core/2.0.0-M1/commons-email2-core-2.0.0-M1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0386 commons-geometry-examples-jmh-1.0-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-examples-jmh/1.0-beta1/commons-geometry-examples-jmh-1.0-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-jmh/1.0-beta1/commons-geometry-examples-jmh-1.0-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-jmh/1.0-beta1/commons-geometry-examples-jmh-1.0-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0387 commons-geometry-examples-jmh-1.0-beta1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-examples-jmh/1.0-beta1/commons-geometry-examples-jmh-1.0-beta1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-jmh/1.0-beta1/commons-geometry-examples-jmh-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-jmh/1.0-beta1/commons-geometry-examples-jmh-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0388 commons-geometry-examples-jmh-1.0-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-examples-jmh/1.0-beta1/commons-geometry-examples-jmh-1.0-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-jmh/1.0-beta1/commons-geometry-examples-jmh-1.0-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-jmh/1.0-beta1/commons-geometry-examples-jmh-1.0-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0389 commons-collections4-4.5.0-M2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.5.0-M2/commons-collections4-4.5.0-M2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M2/commons-collections4-4.5.0-M2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M2/commons-collections4-4.5.0-M2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0390 commons-collections4-4.5.0-M2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.5.0-M2/commons-collections4-4.5.0-M2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M2/commons-collections4-4.5.0-M2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M2/commons-collections4-4.5.0-M2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0391 commons-collections4-4.5.0-M3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.5.0-M3/commons-collections4-4.5.0-M3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M3/commons-collections4-4.5.0-M3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M3/commons-collections4-4.5.0-M3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0392 commons-collections4-4.5.0-M3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.5.0-M3/commons-collections4-4.5.0-M3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M3/commons-collections4-4.5.0-M3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M3/commons-collections4-4.5.0-M3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0393 commons-collections4-4.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.2/commons-collections4-4.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.2/commons-collections4-4.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.2/commons-collections4-4.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0394 commons-collections4-4.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.2/commons-collections4-4.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.2/commons-collections4-4.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.2/commons-collections4-4.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0395 commons-collections4-4.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.2/commons-collections4-4.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.2/commons-collections4-4.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.2/commons-collections4-4.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0396 commons-collections4-4.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.3/commons-collections4-4.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.3/commons-collections4-4.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.3/commons-collections4-4.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0397 commons-collections4-4.3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.3/commons-collections4-4.3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.3/commons-collections4-4.3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.3/commons-collections4-4.3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0398 commons-collections4-4.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.3/commons-collections4-4.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.3/commons-collections4-4.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.3/commons-collections4-4.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0399 commons-collections4-4.4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.4/commons-collections4-4.4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.4/commons-collections4-4.4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.4/commons-collections4-4.4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0400 commons-collections4-4.4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.4/commons-collections4-4.4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.4/commons-collections4-4.4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.4/commons-collections4-4.4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0401 commons-collections4-4.4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.4/commons-collections4-4.4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.4/commons-collections4-4.4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.4/commons-collections4-4.4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0402 commons-collections4-4.5.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.5.0/commons-collections4-4.5.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0/commons-collections4-4.5.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0/commons-collections4-4.5.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0403 commons-collections4-4.5.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.5.0/commons-collections4-4.5.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0/commons-collections4-4.5.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0/commons-collections4-4.5.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0404 commons-collections4-4.5.0-M1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.5.0-M1/commons-collections4-4.5.0-M1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M1/commons-collections4-4.5.0-M1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M1/commons-collections4-4.5.0-M1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0405 commons-collections4-4.5.0-M1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.5.0-M1/commons-collections4-4.5.0-M1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M1/commons-collections4-4.5.0-M1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M1/commons-collections4-4.5.0-M1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0406 commons-collections4-4.5.0-M1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.5.0-M1/commons-collections4-4.5.0-M1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M1/commons-collections4-4.5.0-M1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.5.0-M1/commons-collections4-4.5.0-M1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0407 commons-collections4-4.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.1/commons-collections4-4.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.1/commons-collections4-4.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.1/commons-collections4-4.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0408 commons-collections4-4.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.1/commons-collections4-4.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.1/commons-collections4-4.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.1/commons-collections4-4.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0409 commons-collections4-4.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.1/commons-collections4-4.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.1/commons-collections4-4.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.1/commons-collections4-4.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0410 commons-collections4-4.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.0/commons-collections4-4.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.0/commons-collections4-4.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.0/commons-collections4-4.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0411 commons-collections4-4.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.0/commons-collections4-4.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.0/commons-collections4-4.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.0/commons-collections4-4.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0412 commons-collections4-4.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-collections4/4.0/commons-collections4-4.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.0/commons-collections4-4.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-collections4/4.0/commons-collections4-4.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0413 commons-jcs-jcache-tck-2.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.0/commons-jcs-jcache-tck-2.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.0/commons-jcs-jcache-tck-2.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.0/commons-jcs-jcache-tck-2.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0414 commons-jcs-jcache-tck-2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.1/commons-jcs-jcache-tck-2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.1/commons-jcs-jcache-tck-2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.1/commons-jcs-jcache-tck-2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0415 commons-jcs-jcache-tck-2.0-beta-1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.0-beta-1/commons-jcs-jcache-tck-2.0-beta-1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.0-beta-1/commons-jcs-jcache-tck-2.0-beta-1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.0-beta-1/commons-jcs-jcache-tck-2.0-beta-1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0416 commons-jcs-jcache-tck-2.2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.2.1/commons-jcs-jcache-tck-2.2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.2.1/commons-jcs-jcache-tck-2.2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.2.1/commons-jcs-jcache-tck-2.2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0417 commons-jcs-jcache-tck-2.0-beta-2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.0-beta-2/commons-jcs-jcache-tck-2.0-beta-2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.0-beta-2/commons-jcs-jcache-tck-2.0-beta-2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.0-beta-2/commons-jcs-jcache-tck-2.0-beta-2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0418 commons-jcs-jcache-tck-2.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.2/commons-jcs-jcache-tck-2.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.2/commons-jcs-jcache-tck-2.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-tck/2.2/commons-jcs-jcache-tck-2.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0419 commons-exec-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.0/commons-exec-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0/commons-exec-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0/commons-exec-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0420 commons-exec-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.0/commons-exec-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0/commons-exec-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0/commons-exec-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0421 commons-exec-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.0/commons-exec-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0/commons-exec-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0/commons-exec-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0422 commons-exec-1.0.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.0.1/commons-exec-1.0.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0.1/commons-exec-1.0.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0.1/commons-exec-1.0.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0423 commons-exec-1.0.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.0.1/commons-exec-1.0.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0.1/commons-exec-1.0.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0.1/commons-exec-1.0.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0424 commons-exec-1.0.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.0.1/commons-exec-1.0.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0.1/commons-exec-1.0.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.0.1/commons-exec-1.0.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0425 commons-exec-1.4.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.4.0/commons-exec-1.4.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.4.0/commons-exec-1.4.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.4.0/commons-exec-1.4.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0426 commons-exec-1.4.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.4.0/commons-exec-1.4.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.4.0/commons-exec-1.4.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.4.0/commons-exec-1.4.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0427 commons-exec-1.4.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.4.0/commons-exec-1.4.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.4.0/commons-exec-1.4.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.4.0/commons-exec-1.4.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0428 commons-exec-1.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.3/commons-exec-1.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.3/commons-exec-1.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.3/commons-exec-1.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0429 commons-exec-1.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.3/commons-exec-1.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.3/commons-exec-1.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.3/commons-exec-1.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0430 commons-exec-1.3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.3/commons-exec-1.3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.3/commons-exec-1.3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.3/commons-exec-1.3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0431 commons-exec-1.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.2/commons-exec-1.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.2/commons-exec-1.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.2/commons-exec-1.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0432 commons-exec-1.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.2/commons-exec-1.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.2/commons-exec-1.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.2/commons-exec-1.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0433 commons-exec-1.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.2/commons-exec-1.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.2/commons-exec-1.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.2/commons-exec-1.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0434 commons-exec-1.5.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.5.0/commons-exec-1.5.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.5.0/commons-exec-1.5.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.5.0/commons-exec-1.5.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0435 commons-exec-1.5.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.5.0/commons-exec-1.5.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.5.0/commons-exec-1.5.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.5.0/commons-exec-1.5.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0436 commons-exec-1.5.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.5.0/commons-exec-1.5.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.5.0/commons-exec-1.5.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.5.0/commons-exec-1.5.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0437 commons-exec-1.6.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.6.0/commons-exec-1.6.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.6.0/commons-exec-1.6.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.6.0/commons-exec-1.6.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0438 commons-exec-1.6.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.6.0/commons-exec-1.6.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.6.0/commons-exec-1.6.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.6.0/commons-exec-1.6.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0439 commons-exec-1.6.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-exec/1.6.0/commons-exec-1.6.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.6.0/commons-exec-1.6.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-exec/1.6.0/commons-exec-1.6.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0440 commons-geometry-core-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-core/1.0/commons-geometry-core-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0/commons-geometry-core-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0/commons-geometry-core-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0441 commons-geometry-core-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-core/1.0/commons-geometry-core-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0/commons-geometry-core-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0/commons-geometry-core-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0442 commons-geometry-core-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-core/1.0/commons-geometry-core-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0/commons-geometry-core-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0/commons-geometry-core-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0443 commons-geometry-core-1.0-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-core/1.0-beta1/commons-geometry-core-1.0-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0-beta1/commons-geometry-core-1.0-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0-beta1/commons-geometry-core-1.0-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0444 commons-geometry-core-1.0-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-core/1.0-beta1/commons-geometry-core-1.0-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0-beta1/commons-geometry-core-1.0-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0-beta1/commons-geometry-core-1.0-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0445 commons-geometry-core-1.0-beta1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-core/1.0-beta1/commons-geometry-core-1.0-beta1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0-beta1/commons-geometry-core-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-core/1.0-beta1/commons-geometry-core-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0446 commons-csv-1.11.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.11.0/commons-csv-1.11.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.11.0/commons-csv-1.11.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.11.0/commons-csv-1.11.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0447 commons-csv-1.11.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.11.0/commons-csv-1.11.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.11.0/commons-csv-1.11.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.11.0/commons-csv-1.11.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0448 commons-csv-1.11.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.11.0/commons-csv-1.11.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.11.0/commons-csv-1.11.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.11.0/commons-csv-1.11.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0449 commons-csv-1.9.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.9.0/commons-csv-1.9.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.9.0/commons-csv-1.9.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.9.0/commons-csv-1.9.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0450 commons-csv-1.9.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.9.0/commons-csv-1.9.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.9.0/commons-csv-1.9.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.9.0/commons-csv-1.9.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0451 commons-csv-1.9.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.9.0/commons-csv-1.9.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.9.0/commons-csv-1.9.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.9.0/commons-csv-1.9.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0452 commons-csv-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.0/commons-csv-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.0/commons-csv-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.0/commons-csv-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0453 commons-csv-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.0/commons-csv-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.0/commons-csv-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.0/commons-csv-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0454 commons-csv-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.0/commons-csv-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.0/commons-csv-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.0/commons-csv-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0455 commons-csv-1.7.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.7/commons-csv-1.7.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.7/commons-csv-1.7.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.7/commons-csv-1.7.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0456 commons-csv-1.7-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.7/commons-csv-1.7-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.7/commons-csv-1.7-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.7/commons-csv-1.7-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0457 commons-csv-1.7-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.7/commons-csv-1.7-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.7/commons-csv-1.7-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.7/commons-csv-1.7-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0458 commons-csv-1.6.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.6/commons-csv-1.6.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.6/commons-csv-1.6.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.6/commons-csv-1.6.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0459 commons-csv-1.6-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.6/commons-csv-1.6-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.6/commons-csv-1.6-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.6/commons-csv-1.6-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0460 commons-csv-1.6-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.6/commons-csv-1.6-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.6/commons-csv-1.6-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.6/commons-csv-1.6-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0461 commons-csv-1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.1/commons-csv-1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.1/commons-csv-1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.1/commons-csv-1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0462 commons-csv-1.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.1/commons-csv-1.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.1/commons-csv-1.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.1/commons-csv-1.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0463 commons-csv-1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.1/commons-csv-1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.1/commons-csv-1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.1/commons-csv-1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0464 commons-csv-1.8-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.8/commons-csv-1.8-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.8/commons-csv-1.8-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.8/commons-csv-1.8-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0465 commons-csv-1.8-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.8/commons-csv-1.8-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.8/commons-csv-1.8-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.8/commons-csv-1.8-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0466 commons-csv-1.8.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.8/commons-csv-1.8.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.8/commons-csv-1.8.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.8/commons-csv-1.8.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0467 commons-csv-1.12.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.12.0/commons-csv-1.12.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.12.0/commons-csv-1.12.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.12.0/commons-csv-1.12.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0468 commons-csv-1.12.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.12.0/commons-csv-1.12.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.12.0/commons-csv-1.12.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.12.0/commons-csv-1.12.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0469 commons-csv-1.12.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.12.0/commons-csv-1.12.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.12.0/commons-csv-1.12.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.12.0/commons-csv-1.12.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0470 commons-csv-1.13.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.13.0/commons-csv-1.13.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.13.0/commons-csv-1.13.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.13.0/commons-csv-1.13.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0471 commons-csv-1.13.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.13.0/commons-csv-1.13.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.13.0/commons-csv-1.13.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.13.0/commons-csv-1.13.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0472 commons-csv-1.13.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.13.0/commons-csv-1.13.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.13.0/commons-csv-1.13.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.13.0/commons-csv-1.13.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0473 commons-csv-1.4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.4/commons-csv-1.4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.4/commons-csv-1.4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.4/commons-csv-1.4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0474 commons-csv-1.4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.4/commons-csv-1.4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.4/commons-csv-1.4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.4/commons-csv-1.4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0475 commons-csv-1.4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.4/commons-csv-1.4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.4/commons-csv-1.4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.4/commons-csv-1.4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0476 commons-csv-1.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.3/commons-csv-1.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.3/commons-csv-1.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.3/commons-csv-1.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0477 commons-csv-1.3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.3/commons-csv-1.3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.3/commons-csv-1.3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.3/commons-csv-1.3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0478 commons-csv-1.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.3/commons-csv-1.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.3/commons-csv-1.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.3/commons-csv-1.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0479 commons-csv-1.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.2/commons-csv-1.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.2/commons-csv-1.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.2/commons-csv-1.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0480 commons-csv-1.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.2/commons-csv-1.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.2/commons-csv-1.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.2/commons-csv-1.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0481 commons-csv-1.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.2/commons-csv-1.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.2/commons-csv-1.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.2/commons-csv-1.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0482 commons-csv-1.5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.5/commons-csv-1.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.5/commons-csv-1.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.5/commons-csv-1.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0483 commons-csv-1.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.5/commons-csv-1.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.5/commons-csv-1.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.5/commons-csv-1.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0484 commons-csv-1.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.5/commons-csv-1.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.5/commons-csv-1.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.5/commons-csv-1.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0485 commons-csv-1.14.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.14.0/commons-csv-1.14.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.0/commons-csv-1.14.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.0/commons-csv-1.14.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0486 commons-csv-1.14.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.14.0/commons-csv-1.14.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.0/commons-csv-1.14.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.0/commons-csv-1.14.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0487 commons-csv-1.14.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.14.0/commons-csv-1.14.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.0/commons-csv-1.14.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.0/commons-csv-1.14.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0488 commons-csv-1.10.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.10.0/commons-csv-1.10.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.10.0/commons-csv-1.10.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.10.0/commons-csv-1.10.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0489 commons-csv-1.10.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.10.0/commons-csv-1.10.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.10.0/commons-csv-1.10.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.10.0/commons-csv-1.10.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0490 commons-csv-1.10.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.10.0/commons-csv-1.10.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.10.0/commons-csv-1.10.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.10.0/commons-csv-1.10.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0491 commons-csv-1.14.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.14.1/commons-csv-1.14.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.1/commons-csv-1.14.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.1/commons-csv-1.14.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0492 commons-csv-1.14.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.14.1/commons-csv-1.14.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.1/commons-csv-1.14.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.1/commons-csv-1.14.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0493 commons-csv-1.14.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-csv/1.14.1/commons-csv-1.14.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.1/commons-csv-1.14.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-csv/1.14.1/commons-csv-1.14.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0494 commons-jexl-2.0.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.0.1/commons-jexl-2.0.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0.1/commons-jexl-2.0.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0.1/commons-jexl-2.0.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0495 commons-jexl-2.0.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.0.1/commons-jexl-2.0.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0.1/commons-jexl-2.0.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0.1/commons-jexl-2.0.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0496 commons-jexl-2.0.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.0.1/commons-jexl-2.0.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0.1/commons-jexl-2.0.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0.1/commons-jexl-2.0.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0497 commons-jexl-2.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.0/commons-jexl-2.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0/commons-jexl-2.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0/commons-jexl-2.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0498 commons-jexl-2.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.0/commons-jexl-2.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0/commons-jexl-2.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0/commons-jexl-2.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0499 commons-jexl-2.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.0/commons-jexl-2.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0/commons-jexl-2.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.0/commons-jexl-2.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0500 commons-jexl-2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.1/commons-jexl-2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1/commons-jexl-2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1/commons-jexl-2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0501 commons-jexl-2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.1/commons-jexl-2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1/commons-jexl-2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1/commons-jexl-2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0502 commons-jexl-2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.1/commons-jexl-2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1/commons-jexl-2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1/commons-jexl-2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0503 commons-jexl-2.1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.1.1/commons-jexl-2.1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1.1/commons-jexl-2.1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1.1/commons-jexl-2.1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0504 commons-jexl-2.1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.1.1/commons-jexl-2.1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1.1/commons-jexl-2.1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1.1/commons-jexl-2.1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0505 commons-jexl-2.1.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl/2.1.1/commons-jexl-2.1.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1.1/commons-jexl-2.1.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl/2.1.1/commons-jexl-2.1.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0506 commons-jcs-core-2.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.0/commons-jcs-core-2.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0/commons-jcs-core-2.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0/commons-jcs-core-2.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0507 commons-jcs-core-2.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.0/commons-jcs-core-2.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0/commons-jcs-core-2.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0/commons-jcs-core-2.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0508 commons-jcs-core-2.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.0/commons-jcs-core-2.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0/commons-jcs-core-2.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0/commons-jcs-core-2.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0509 commons-jcs-core-2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.1/commons-jcs-core-2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.1/commons-jcs-core-2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.1/commons-jcs-core-2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0510 commons-jcs-core-2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.1/commons-jcs-core-2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.1/commons-jcs-core-2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.1/commons-jcs-core-2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0511 commons-jcs-core-2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.1/commons-jcs-core-2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.1/commons-jcs-core-2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.1/commons-jcs-core-2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0512 commons-jcs-core-2.0-beta-1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-1/commons-jcs-core-2.0-beta-1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-1/commons-jcs-core-2.0-beta-1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-1/commons-jcs-core-2.0-beta-1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0513 commons-jcs-core-2.0-beta-1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-1/commons-jcs-core-2.0-beta-1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-1/commons-jcs-core-2.0-beta-1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-1/commons-jcs-core-2.0-beta-1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0514 commons-jcs-core-2.0-beta-1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-1/commons-jcs-core-2.0-beta-1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-1/commons-jcs-core-2.0-beta-1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-1/commons-jcs-core-2.0-beta-1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0515 commons-jcs-core-2.2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.2.1/commons-jcs-core-2.2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2.1/commons-jcs-core-2.2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2.1/commons-jcs-core-2.2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0516 commons-jcs-core-2.2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.2.1/commons-jcs-core-2.2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2.1/commons-jcs-core-2.2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2.1/commons-jcs-core-2.2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0517 commons-jcs-core-2.2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.2.1/commons-jcs-core-2.2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2.1/commons-jcs-core-2.2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2.1/commons-jcs-core-2.2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0518 commons-jcs-core-2.0-beta-2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-2/commons-jcs-core-2.0-beta-2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-2/commons-jcs-core-2.0-beta-2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-2/commons-jcs-core-2.0-beta-2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0519 commons-jcs-core-2.0-beta-2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-2/commons-jcs-core-2.0-beta-2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-2/commons-jcs-core-2.0-beta-2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-2/commons-jcs-core-2.0-beta-2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0520 commons-jcs-core-2.0-beta-2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-2/commons-jcs-core-2.0-beta-2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-2/commons-jcs-core-2.0-beta-2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.0-beta-2/commons-jcs-core-2.0-beta-2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0521 commons-jcs-core-2.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.2/commons-jcs-core-2.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2/commons-jcs-core-2.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2/commons-jcs-core-2.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0522 commons-jcs-core-2.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.2/commons-jcs-core-2.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2/commons-jcs-core-2.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2/commons-jcs-core-2.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0523 commons-jcs-core-2.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-core/2.2/commons-jcs-core-2.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2/commons-jcs-core-2.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-core/2.2/commons-jcs-core-2.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0524 commons-jcs3-core-3.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.2/commons-jcs3-core-3.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2/commons-jcs3-core-3.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2/commons-jcs3-core-3.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0525 commons-jcs3-core-3.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.2/commons-jcs3-core-3.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2/commons-jcs3-core-3.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2/commons-jcs3-core-3.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0526 commons-jcs3-core-3.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.2/commons-jcs3-core-3.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2/commons-jcs3-core-3.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2/commons-jcs3-core-3.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0527 commons-jcs3-core-3.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.0/commons-jcs3-core-3.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.0/commons-jcs3-core-3.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.0/commons-jcs3-core-3.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0528 commons-jcs3-core-3.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.0/commons-jcs3-core-3.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.0/commons-jcs3-core-3.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.0/commons-jcs3-core-3.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0529 commons-jcs3-core-3.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.0/commons-jcs3-core-3.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.0/commons-jcs3-core-3.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.0/commons-jcs3-core-3.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0530 commons-jcs3-core-3.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.1/commons-jcs3-core-3.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.1/commons-jcs3-core-3.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.1/commons-jcs3-core-3.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0531 commons-jcs3-core-3.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.1/commons-jcs3-core-3.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.1/commons-jcs3-core-3.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.1/commons-jcs3-core-3.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0532 commons-jcs3-core-3.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.1/commons-jcs3-core-3.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.1/commons-jcs3-core-3.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.1/commons-jcs3-core-3.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0533 commons-jcs3-core-3.2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.2.1/commons-jcs3-core-3.2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2.1/commons-jcs3-core-3.2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2.1/commons-jcs3-core-3.2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0534 commons-jcs3-core-3.2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.2.1/commons-jcs3-core-3.2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2.1/commons-jcs3-core-3.2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2.1/commons-jcs3-core-3.2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0535 commons-jcs3-core-3.2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-core/3.2.1/commons-jcs3-core-3.2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2.1/commons-jcs3-core-3.2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-core/3.2.1/commons-jcs3-core-3.2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0536 commons-beanutils2-2.0.0-M1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M1/commons-beanutils2-2.0.0-M1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M1/commons-beanutils2-2.0.0-M1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M1/commons-beanutils2-2.0.0-M1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0537 commons-beanutils2-2.0.0-M1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M1/commons-beanutils2-2.0.0-M1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M1/commons-beanutils2-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M1/commons-beanutils2-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0538 commons-beanutils2-2.0.0-M1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M1/commons-beanutils2-2.0.0-M1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M1/commons-beanutils2-2.0.0-M1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M1/commons-beanutils2-2.0.0-M1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0539 commons-beanutils2-2.0.0-M2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M2/commons-beanutils2-2.0.0-M2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M2/commons-beanutils2-2.0.0-M2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M2/commons-beanutils2-2.0.0-M2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0540 commons-beanutils2-2.0.0-M2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M2/commons-beanutils2-2.0.0-M2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M2/commons-beanutils2-2.0.0-M2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M2/commons-beanutils2-2.0.0-M2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0541 commons-beanutils2-2.0.0-M2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M2/commons-beanutils2-2.0.0-M2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M2/commons-beanutils2-2.0.0-M2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-beanutils2/2.0.0-M2/commons-beanutils2-2.0.0-M2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0542 commons-jcs-jcache-openjpa-2.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0/commons-jcs-jcache-openjpa-2.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0/commons-jcs-jcache-openjpa-2.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0/commons-jcs-jcache-openjpa-2.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0543 commons-jcs-jcache-openjpa-2.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0/commons-jcs-jcache-openjpa-2.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0/commons-jcs-jcache-openjpa-2.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0/commons-jcs-jcache-openjpa-2.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0544 commons-jcs-jcache-openjpa-2.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0/commons-jcs-jcache-openjpa-2.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0/commons-jcs-jcache-openjpa-2.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0/commons-jcs-jcache-openjpa-2.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0545 commons-jcs-jcache-openjpa-2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.1/commons-jcs-jcache-openjpa-2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.1/commons-jcs-jcache-openjpa-2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.1/commons-jcs-jcache-openjpa-2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0546 commons-jcs-jcache-openjpa-2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.1/commons-jcs-jcache-openjpa-2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.1/commons-jcs-jcache-openjpa-2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.1/commons-jcs-jcache-openjpa-2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0547 commons-jcs-jcache-openjpa-2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.1/commons-jcs-jcache-openjpa-2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.1/commons-jcs-jcache-openjpa-2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.1/commons-jcs-jcache-openjpa-2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0548 commons-jcs-jcache-openjpa-2.0-beta-1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-1/commons-jcs-jcache-openjpa-2.0-beta-1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-1/commons-jcs-jcache-openjpa-2.0-beta-1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-1/commons-jcs-jcache-openjpa-2.0-beta-1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0549 commons-jcs-jcache-openjpa-2.0-beta-1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-1/commons-jcs-jcache-openjpa-2.0-beta-1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-1/commons-jcs-jcache-openjpa-2.0-beta-1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-1/commons-jcs-jcache-openjpa-2.0-beta-1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0550 commons-jcs-jcache-openjpa-2.0-beta-1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-1/commons-jcs-jcache-openjpa-2.0-beta-1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-1/commons-jcs-jcache-openjpa-2.0-beta-1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-1/commons-jcs-jcache-openjpa-2.0-beta-1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0551 commons-jcs-jcache-openjpa-2.2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2.1/commons-jcs-jcache-openjpa-2.2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2.1/commons-jcs-jcache-openjpa-2.2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2.1/commons-jcs-jcache-openjpa-2.2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0552 commons-jcs-jcache-openjpa-2.2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2.1/commons-jcs-jcache-openjpa-2.2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2.1/commons-jcs-jcache-openjpa-2.2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2.1/commons-jcs-jcache-openjpa-2.2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0553 commons-jcs-jcache-openjpa-2.2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2.1/commons-jcs-jcache-openjpa-2.2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2.1/commons-jcs-jcache-openjpa-2.2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2.1/commons-jcs-jcache-openjpa-2.2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0554 commons-jcs-jcache-openjpa-2.0-beta-2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-2/commons-jcs-jcache-openjpa-2.0-beta-2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-2/commons-jcs-jcache-openjpa-2.0-beta-2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-2/commons-jcs-jcache-openjpa-2.0-beta-2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0555 commons-jcs-jcache-openjpa-2.0-beta-2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-2/commons-jcs-jcache-openjpa-2.0-beta-2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-2/commons-jcs-jcache-openjpa-2.0-beta-2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-2/commons-jcs-jcache-openjpa-2.0-beta-2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0556 commons-jcs-jcache-openjpa-2.0-beta-2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-2/commons-jcs-jcache-openjpa-2.0-beta-2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-2/commons-jcs-jcache-openjpa-2.0-beta-2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.0-beta-2/commons-jcs-jcache-openjpa-2.0-beta-2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0557 commons-jcs-jcache-openjpa-2.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2/commons-jcs-jcache-openjpa-2.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2/commons-jcs-jcache-openjpa-2.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2/commons-jcs-jcache-openjpa-2.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0558 commons-jcs-jcache-openjpa-2.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2/commons-jcs-jcache-openjpa-2.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2/commons-jcs-jcache-openjpa-2.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2/commons-jcs-jcache-openjpa-2.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0559 commons-jcs-jcache-openjpa-2.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2/commons-jcs-jcache-openjpa-2.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2/commons-jcs-jcache-openjpa-2.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-openjpa/2.2/commons-jcs-jcache-openjpa-2.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0560 commons-jcs-jcache-2.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.0/commons-jcs-jcache-2.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0/commons-jcs-jcache-2.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0/commons-jcs-jcache-2.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0561 commons-jcs-jcache-2.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.0/commons-jcs-jcache-2.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0/commons-jcs-jcache-2.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0/commons-jcs-jcache-2.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0562 commons-jcs-jcache-2.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.0/commons-jcs-jcache-2.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0/commons-jcs-jcache-2.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0/commons-jcs-jcache-2.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0563 commons-jcs-jcache-2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.1/commons-jcs-jcache-2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.1/commons-jcs-jcache-2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.1/commons-jcs-jcache-2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0564 commons-jcs-jcache-2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.1/commons-jcs-jcache-2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.1/commons-jcs-jcache-2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.1/commons-jcs-jcache-2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0565 commons-jcs-jcache-2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.1/commons-jcs-jcache-2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.1/commons-jcs-jcache-2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.1/commons-jcs-jcache-2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0566 commons-jcs-jcache-2.0-beta-1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-1/commons-jcs-jcache-2.0-beta-1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-1/commons-jcs-jcache-2.0-beta-1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-1/commons-jcs-jcache-2.0-beta-1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0567 commons-jcs-jcache-2.0-beta-1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-1/commons-jcs-jcache-2.0-beta-1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-1/commons-jcs-jcache-2.0-beta-1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-1/commons-jcs-jcache-2.0-beta-1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0568 commons-jcs-jcache-2.0-beta-1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-1/commons-jcs-jcache-2.0-beta-1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-1/commons-jcs-jcache-2.0-beta-1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-1/commons-jcs-jcache-2.0-beta-1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0569 commons-jcs-jcache-2.2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.2.1/commons-jcs-jcache-2.2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2.1/commons-jcs-jcache-2.2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2.1/commons-jcs-jcache-2.2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0570 commons-jcs-jcache-2.2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.2.1/commons-jcs-jcache-2.2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2.1/commons-jcs-jcache-2.2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2.1/commons-jcs-jcache-2.2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0571 commons-jcs-jcache-2.2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.2.1/commons-jcs-jcache-2.2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2.1/commons-jcs-jcache-2.2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2.1/commons-jcs-jcache-2.2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0572 commons-jcs-jcache-2.0-beta-2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-2/commons-jcs-jcache-2.0-beta-2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-2/commons-jcs-jcache-2.0-beta-2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-2/commons-jcs-jcache-2.0-beta-2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0573 commons-jcs-jcache-2.0-beta-2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-2/commons-jcs-jcache-2.0-beta-2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-2/commons-jcs-jcache-2.0-beta-2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-2/commons-jcs-jcache-2.0-beta-2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0574 commons-jcs-jcache-2.0-beta-2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-2/commons-jcs-jcache-2.0-beta-2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-2/commons-jcs-jcache-2.0-beta-2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.0-beta-2/commons-jcs-jcache-2.0-beta-2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0575 commons-jcs-jcache-2.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.2/commons-jcs-jcache-2.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2/commons-jcs-jcache-2.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2/commons-jcs-jcache-2.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0576 commons-jcs-jcache-2.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.2/commons-jcs-jcache-2.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2/commons-jcs-jcache-2.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2/commons-jcs-jcache-2.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0577 commons-jcs-jcache-2.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache/2.2/commons-jcs-jcache-2.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2/commons-jcs-jcache-2.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache/2.2/commons-jcs-jcache-2.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0578 commons-jcs3-jcache-tck-3.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.2/commons-jcs3-jcache-tck-3.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.2/commons-jcs3-jcache-tck-3.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.2/commons-jcs3-jcache-tck-3.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0579 commons-jcs3-jcache-tck-3.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.0/commons-jcs3-jcache-tck-3.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.0/commons-jcs3-jcache-tck-3.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.0/commons-jcs3-jcache-tck-3.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0580 commons-jcs3-jcache-tck-3.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.1/commons-jcs3-jcache-tck-3.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.1/commons-jcs3-jcache-tck-3.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.1/commons-jcs3-jcache-tck-3.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0581 commons-jcs3-jcache-tck-3.2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.2.1/commons-jcs3-jcache-tck-3.2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.2.1/commons-jcs3-jcache-tck-3.2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs3-jcache-tck/3.2.1/commons-jcs3-jcache-tck-3.2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0582 commons-fileupload2-jakarta-servlet5-2.0.0-M4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M4/commons-fileupload2-jakarta-servlet5-2.0.0-M4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M4/commons-fileupload2-jakarta-servlet5-2.0.0-M4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M4/commons-fileupload2-jakarta-servlet5-2.0.0-M4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0583 commons-fileupload2-jakarta-servlet5-2.0.0-M4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M4/commons-fileupload2-jakarta-servlet5-2.0.0-M4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M4/commons-fileupload2-jakarta-servlet5-2.0.0-M4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M4/commons-fileupload2-jakarta-servlet5-2.0.0-M4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0584 commons-fileupload2-jakarta-servlet5-2.0.0-M4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M4/commons-fileupload2-jakarta-servlet5-2.0.0-M4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M4/commons-fileupload2-jakarta-servlet5-2.0.0-M4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M4/commons-fileupload2-jakarta-servlet5-2.0.0-M4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0585 commons-fileupload2-jakarta-servlet5-2.0.0-M3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M3/commons-fileupload2-jakarta-servlet5-2.0.0-M3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M3/commons-fileupload2-jakarta-servlet5-2.0.0-M3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M3/commons-fileupload2-jakarta-servlet5-2.0.0-M3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0586 commons-fileupload2-jakarta-servlet5-2.0.0-M3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M3/commons-fileupload2-jakarta-servlet5-2.0.0-M3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M3/commons-fileupload2-jakarta-servlet5-2.0.0-M3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M3/commons-fileupload2-jakarta-servlet5-2.0.0-M3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0587 commons-fileupload2-jakarta-servlet5-2.0.0-M3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M3/commons-fileupload2-jakarta-servlet5-2.0.0-M3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M3/commons-fileupload2-jakarta-servlet5-2.0.0-M3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M3/commons-fileupload2-jakarta-servlet5-2.0.0-M3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0588 commons-fileupload2-jakarta-servlet5-2.0.0-M2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M2/commons-fileupload2-jakarta-servlet5-2.0.0-M2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M2/commons-fileupload2-jakarta-servlet5-2.0.0-M2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M2/commons-fileupload2-jakarta-servlet5-2.0.0-M2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0589 commons-fileupload2-jakarta-servlet5-2.0.0-M2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M2/commons-fileupload2-jakarta-servlet5-2.0.0-M2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M2/commons-fileupload2-jakarta-servlet5-2.0.0-M2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet5/2.0.0-M2/commons-fileupload2-jakarta-servlet5-2.0.0-M2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0590 commons-dbcp2-2.7.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.7.0/commons-dbcp2-2.7.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.7.0/commons-dbcp2-2.7.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.7.0/commons-dbcp2-2.7.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0591 commons-dbcp2-2.7.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.7.0/commons-dbcp2-2.7.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.7.0/commons-dbcp2-2.7.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.7.0/commons-dbcp2-2.7.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0592 commons-dbcp2-2.7.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.7.0/commons-dbcp2-2.7.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.7.0/commons-dbcp2-2.7.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.7.0/commons-dbcp2-2.7.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0593 commons-dbcp2-2.10.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.10.0/commons-dbcp2-2.10.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.10.0/commons-dbcp2-2.10.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.10.0/commons-dbcp2-2.10.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0594 commons-dbcp2-2.10.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.10.0/commons-dbcp2-2.10.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.10.0/commons-dbcp2-2.10.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.10.0/commons-dbcp2-2.10.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0595 commons-dbcp2-2.10.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.10.0/commons-dbcp2-2.10.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.10.0/commons-dbcp2-2.10.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.10.0/commons-dbcp2-2.10.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0596 commons-dbcp2-2.9.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.9.0/commons-dbcp2-2.9.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.9.0/commons-dbcp2-2.9.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.9.0/commons-dbcp2-2.9.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0597 commons-dbcp2-2.9.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.9.0/commons-dbcp2-2.9.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.9.0/commons-dbcp2-2.9.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.9.0/commons-dbcp2-2.9.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0598 commons-dbcp2-2.9.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.9.0/commons-dbcp2-2.9.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.9.0/commons-dbcp2-2.9.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.9.0/commons-dbcp2-2.9.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0599 commons-dbcp2-2.14.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.14.0/commons-dbcp2-2.14.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.14.0/commons-dbcp2-2.14.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.14.0/commons-dbcp2-2.14.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0600 commons-dbcp2-2.14.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.14.0/commons-dbcp2-2.14.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.14.0/commons-dbcp2-2.14.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.14.0/commons-dbcp2-2.14.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0601 commons-dbcp2-2.14.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.14.0/commons-dbcp2-2.14.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.14.0/commons-dbcp2-2.14.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.14.0/commons-dbcp2-2.14.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0602 commons-dbcp2-2.3.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.3.0/commons-dbcp2-2.3.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.3.0/commons-dbcp2-2.3.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.3.0/commons-dbcp2-2.3.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0603 commons-dbcp2-2.3.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.3.0/commons-dbcp2-2.3.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.3.0/commons-dbcp2-2.3.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.3.0/commons-dbcp2-2.3.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0604 commons-dbcp2-2.3.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.3.0/commons-dbcp2-2.3.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.3.0/commons-dbcp2-2.3.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.3.0/commons-dbcp2-2.3.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0605 commons-dbcp2-2.0.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.0.1/commons-dbcp2-2.0.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0.1/commons-dbcp2-2.0.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0.1/commons-dbcp2-2.0.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0606 commons-dbcp2-2.0.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.0.1/commons-dbcp2-2.0.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0.1/commons-dbcp2-2.0.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0.1/commons-dbcp2-2.0.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0607 commons-dbcp2-2.0.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.0.1/commons-dbcp2-2.0.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0.1/commons-dbcp2-2.0.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0.1/commons-dbcp2-2.0.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0608 commons-dbcp2-2.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.0/commons-dbcp2-2.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0/commons-dbcp2-2.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0/commons-dbcp2-2.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0609 commons-dbcp2-2.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.0/commons-dbcp2-2.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0/commons-dbcp2-2.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0/commons-dbcp2-2.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0610 commons-dbcp2-2.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.0/commons-dbcp2-2.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0/commons-dbcp2-2.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.0/commons-dbcp2-2.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0611 commons-dbcp2-2.4.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.4.0/commons-dbcp2-2.4.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.4.0/commons-dbcp2-2.4.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.4.0/commons-dbcp2-2.4.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0612 commons-dbcp2-2.4.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.4.0/commons-dbcp2-2.4.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.4.0/commons-dbcp2-2.4.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.4.0/commons-dbcp2-2.4.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0613 commons-dbcp2-2.4.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.4.0/commons-dbcp2-2.4.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.4.0/commons-dbcp2-2.4.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.4.0/commons-dbcp2-2.4.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0614 commons-dbcp2-2.13.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.13.0/commons-dbcp2-2.13.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.13.0/commons-dbcp2-2.13.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.13.0/commons-dbcp2-2.13.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0615 commons-dbcp2-2.13.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.13.0/commons-dbcp2-2.13.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.13.0/commons-dbcp2-2.13.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.13.0/commons-dbcp2-2.13.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0616 commons-dbcp2-2.13.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.13.0/commons-dbcp2-2.13.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.13.0/commons-dbcp2-2.13.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.13.0/commons-dbcp2-2.13.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0617 commons-dbcp2-2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.1/commons-dbcp2-2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1/commons-dbcp2-2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1/commons-dbcp2-2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0618 commons-dbcp2-2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.1/commons-dbcp2-2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1/commons-dbcp2-2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1/commons-dbcp2-2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0619 commons-dbcp2-2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.1/commons-dbcp2-2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1/commons-dbcp2-2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1/commons-dbcp2-2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0620 commons-dbcp2-2.1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.1.1/commons-dbcp2-2.1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1.1/commons-dbcp2-2.1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1.1/commons-dbcp2-2.1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0621 commons-dbcp2-2.1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.1.1/commons-dbcp2-2.1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1.1/commons-dbcp2-2.1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1.1/commons-dbcp2-2.1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0622 commons-dbcp2-2.1.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.1.1/commons-dbcp2-2.1.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1.1/commons-dbcp2-2.1.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.1.1/commons-dbcp2-2.1.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0623 commons-dbcp2-2.12.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.12.0/commons-dbcp2-2.12.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.12.0/commons-dbcp2-2.12.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.12.0/commons-dbcp2-2.12.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0624 commons-dbcp2-2.12.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.12.0/commons-dbcp2-2.12.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.12.0/commons-dbcp2-2.12.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.12.0/commons-dbcp2-2.12.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0625 commons-dbcp2-2.12.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.12.0/commons-dbcp2-2.12.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.12.0/commons-dbcp2-2.12.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.12.0/commons-dbcp2-2.12.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0626 commons-dbcp2-2.5.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.5.0/commons-dbcp2-2.5.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.5.0/commons-dbcp2-2.5.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.5.0/commons-dbcp2-2.5.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0627 commons-dbcp2-2.5.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.5.0/commons-dbcp2-2.5.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.5.0/commons-dbcp2-2.5.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.5.0/commons-dbcp2-2.5.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0628 commons-dbcp2-2.5.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.5.0/commons-dbcp2-2.5.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.5.0/commons-dbcp2-2.5.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.5.0/commons-dbcp2-2.5.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0629 commons-dbcp2-2.11.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.11.0/commons-dbcp2-2.11.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.11.0/commons-dbcp2-2.11.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.11.0/commons-dbcp2-2.11.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0630 commons-dbcp2-2.11.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.11.0/commons-dbcp2-2.11.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.11.0/commons-dbcp2-2.11.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.11.0/commons-dbcp2-2.11.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0631 commons-dbcp2-2.11.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.11.0/commons-dbcp2-2.11.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.11.0/commons-dbcp2-2.11.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.11.0/commons-dbcp2-2.11.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0632 commons-dbcp2-2.6.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.6.0/commons-dbcp2-2.6.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.6.0/commons-dbcp2-2.6.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.6.0/commons-dbcp2-2.6.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0633 commons-dbcp2-2.6.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.6.0/commons-dbcp2-2.6.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.6.0/commons-dbcp2-2.6.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.6.0/commons-dbcp2-2.6.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0634 commons-dbcp2-2.6.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.6.0/commons-dbcp2-2.6.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.6.0/commons-dbcp2-2.6.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.6.0/commons-dbcp2-2.6.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0635 commons-dbcp2-2.2.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.2.0/commons-dbcp2-2.2.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.2.0/commons-dbcp2-2.2.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.2.0/commons-dbcp2-2.2.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0636 commons-dbcp2-2.2.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.2.0/commons-dbcp2-2.2.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.2.0/commons-dbcp2-2.2.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.2.0/commons-dbcp2-2.2.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0637 commons-dbcp2-2.2.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.2.0/commons-dbcp2-2.2.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.2.0/commons-dbcp2-2.2.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.2.0/commons-dbcp2-2.2.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0638 commons-dbcp2-2.8.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.8.0/commons-dbcp2-2.8.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.8.0/commons-dbcp2-2.8.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.8.0/commons-dbcp2-2.8.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0639 commons-dbcp2-2.8.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.8.0/commons-dbcp2-2.8.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.8.0/commons-dbcp2-2.8.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.8.0/commons-dbcp2-2.8.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0640 commons-dbcp2-2.8.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-dbcp2/2.8.0/commons-dbcp2-2.8.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.8.0/commons-dbcp2-2.8.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-dbcp2/2.8.0/commons-dbcp2-2.8.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0641 commons-jci-core-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-core/1.0/commons-jci-core-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.0/commons-jci-core-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.0/commons-jci-core-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0642 commons-jci-core-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-core/1.0/commons-jci-core-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.0/commons-jci-core-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.0/commons-jci-core-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0643 commons-jci-core-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-core/1.0/commons-jci-core-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.0/commons-jci-core-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.0/commons-jci-core-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0644 commons-jci-core-1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-core/1.1/commons-jci-core-1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.1/commons-jci-core-1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.1/commons-jci-core-1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0645 commons-jci-core-1.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-core/1.1/commons-jci-core-1.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.1/commons-jci-core-1.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.1/commons-jci-core-1.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0646 commons-jci-core-1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-core/1.1/commons-jci-core-1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.1/commons-jci-core-1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-core/1.1/commons-jci-core-1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0647 commons-jci-javac-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-javac/1.0/commons-jci-javac-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-javac/1.0/commons-jci-javac-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-javac/1.0/commons-jci-javac-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0648 commons-jci-javac-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-javac/1.0/commons-jci-javac-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-javac/1.0/commons-jci-javac-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-javac/1.0/commons-jci-javac-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0649 commons-jci-javac-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-javac/1.0/commons-jci-javac-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-javac/1.0/commons-jci-javac-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-javac/1.0/commons-jci-javac-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0650 commons-geometry-io-euclidean-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-io-euclidean/1.0/commons-geometry-io-euclidean-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-euclidean/1.0/commons-geometry-io-euclidean-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-euclidean/1.0/commons-geometry-io-euclidean-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0651 commons-geometry-io-euclidean-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-io-euclidean/1.0/commons-geometry-io-euclidean-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-euclidean/1.0/commons-geometry-io-euclidean-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-euclidean/1.0/commons-geometry-io-euclidean-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0652 commons-geometry-io-euclidean-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-io-euclidean/1.0/commons-geometry-io-euclidean-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-euclidean/1.0/commons-geometry-io-euclidean-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-euclidean/1.0/commons-geometry-io-euclidean-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0653 commons-geometry-io-core-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-io-core/1.0/commons-geometry-io-core-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-core/1.0/commons-geometry-io-core-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-core/1.0/commons-geometry-io-core-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0654 commons-geometry-io-core-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-io-core/1.0/commons-geometry-io-core-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-core/1.0/commons-geometry-io-core-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-core/1.0/commons-geometry-io-core-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0655 commons-geometry-io-core-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-io-core/1.0/commons-geometry-io-core-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-core/1.0/commons-geometry-io-core-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-io-core/1.0/commons-geometry-io-core-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0656 commons-io-1.3.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-io/1.3.2/commons-io-1.3.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-io/1.3.2/commons-io-1.3.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-io/1.3.2/commons-io-1.3.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0657 commons-io-1.3.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-io/1.3.2/commons-io-1.3.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-io/1.3.2/commons-io-1.3.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-io/1.3.2/commons-io-1.3.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0658 commons-io-1.3.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-io/1.3.2/commons-io-1.3.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-io/1.3.2/commons-io-1.3.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-io/1.3.2/commons-io-1.3.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0659 commons-digester3-3.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-digester3/3.2/commons-digester3-3.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.2/commons-digester3-3.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.2/commons-digester3-3.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0660 commons-digester3-3.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-digester3/3.2/commons-digester3-3.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.2/commons-digester3-3.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.2/commons-digester3-3.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0661 commons-digester3-3.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-digester3/3.2/commons-digester3-3.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.2/commons-digester3-3.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.2/commons-digester3-3.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0662 commons-digester3-3.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-digester3/3.0/commons-digester3-3.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.0/commons-digester3-3.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.0/commons-digester3-3.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0663 commons-digester3-3.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-digester3/3.0/commons-digester3-3.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.0/commons-digester3-3.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.0/commons-digester3-3.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0664 commons-digester3-3.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-digester3/3.0/commons-digester3-3.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.0/commons-digester3-3.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.0/commons-digester3-3.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0665 commons-digester3-3.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-digester3/3.1/commons-digester3-3.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.1/commons-digester3-3.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.1/commons-digester3-3.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0666 commons-digester3-3.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-digester3/3.1/commons-digester3-3.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.1/commons-digester3-3.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.1/commons-digester3-3.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0667 commons-digester3-3.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-digester3/3.1/commons-digester3-3.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.1/commons-digester3-3.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-digester3/3.1/commons-digester3-3.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0668 commons-build-plugin-1.15.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.15.0/commons-build-plugin-1.15.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.15.0/commons-build-plugin-1.15.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.15.0/commons-build-plugin-1.15.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0669 commons-build-plugin-1.15.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.15.0/commons-build-plugin-1.15.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.15.0/commons-build-plugin-1.15.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.15.0/commons-build-plugin-1.15.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0670 commons-build-plugin-1.9.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.9/commons-build-plugin-1.9.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.9/commons-build-plugin-1.9.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.9/commons-build-plugin-1.9.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0671 commons-build-plugin-1.9-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.9/commons-build-plugin-1.9-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.9/commons-build-plugin-1.9-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.9/commons-build-plugin-1.9-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0672 commons-build-plugin-1.9-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.9/commons-build-plugin-1.9-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.9/commons-build-plugin-1.9-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.9/commons-build-plugin-1.9-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0673 commons-build-plugin-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.0/commons-build-plugin-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.0/commons-build-plugin-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.0/commons-build-plugin-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0674 commons-build-plugin-1.7-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.7/commons-build-plugin-1.7-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.7/commons-build-plugin-1.7-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.7/commons-build-plugin-1.7-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0675 commons-build-plugin-1.7.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.7/commons-build-plugin-1.7.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.7/commons-build-plugin-1.7.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.7/commons-build-plugin-1.7.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0676 commons-build-plugin-1.7-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.7/commons-build-plugin-1.7-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.7/commons-build-plugin-1.7-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.7/commons-build-plugin-1.7-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0677 commons-build-plugin-1.6-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.6/commons-build-plugin-1.6-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.6/commons-build-plugin-1.6-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.6/commons-build-plugin-1.6-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0678 commons-build-plugin-1.6-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.6/commons-build-plugin-1.6-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.6/commons-build-plugin-1.6-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.6/commons-build-plugin-1.6-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0679 commons-build-plugin-1.6.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.6/commons-build-plugin-1.6.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.6/commons-build-plugin-1.6.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.6/commons-build-plugin-1.6.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0680 commons-build-plugin-1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.1/commons-build-plugin-1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.1/commons-build-plugin-1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.1/commons-build-plugin-1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0681 commons-build-plugin-1.8.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.8/commons-build-plugin-1.8.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.8/commons-build-plugin-1.8.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.8/commons-build-plugin-1.8.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0682 commons-build-plugin-1.8-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.8/commons-build-plugin-1.8-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.8/commons-build-plugin-1.8-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.8/commons-build-plugin-1.8-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0683 commons-build-plugin-1.8-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.8/commons-build-plugin-1.8-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.8/commons-build-plugin-1.8-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.8/commons-build-plugin-1.8-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0684 commons-build-plugin-1.12.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.12/commons-build-plugin-1.12.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.12/commons-build-plugin-1.12.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.12/commons-build-plugin-1.12.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0685 commons-build-plugin-1.12-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.12/commons-build-plugin-1.12-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.12/commons-build-plugin-1.12-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.12/commons-build-plugin-1.12-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0686 commons-build-plugin-1.12-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.12/commons-build-plugin-1.12-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.12/commons-build-plugin-1.12-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.12/commons-build-plugin-1.12-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0687 commons-build-plugin-1.16.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.16.0/commons-build-plugin-1.16.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.16.0/commons-build-plugin-1.16.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.16.0/commons-build-plugin-1.16.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0688 commons-build-plugin-1.16.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.16.0/commons-build-plugin-1.16.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.16.0/commons-build-plugin-1.16.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.16.0/commons-build-plugin-1.16.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0689 commons-build-plugin-1.13.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.13/commons-build-plugin-1.13.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.13/commons-build-plugin-1.13.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.13/commons-build-plugin-1.13.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0690 commons-build-plugin-1.13-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.13/commons-build-plugin-1.13-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.13/commons-build-plugin-1.13-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.13/commons-build-plugin-1.13-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0691 commons-build-plugin-1.13-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.13/commons-build-plugin-1.13-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.13/commons-build-plugin-1.13-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.13/commons-build-plugin-1.13-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0692 commons-build-plugin-1.4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.4/commons-build-plugin-1.4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.4/commons-build-plugin-1.4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.4/commons-build-plugin-1.4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0693 commons-build-plugin-1.4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.4/commons-build-plugin-1.4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.4/commons-build-plugin-1.4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.4/commons-build-plugin-1.4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0694 commons-build-plugin-1.4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.4/commons-build-plugin-1.4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.4/commons-build-plugin-1.4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.4/commons-build-plugin-1.4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0695 commons-build-plugin-1.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.3/commons-build-plugin-1.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.3/commons-build-plugin-1.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.3/commons-build-plugin-1.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0696 commons-build-plugin-1.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.2/commons-build-plugin-1.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.2/commons-build-plugin-1.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.2/commons-build-plugin-1.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0697 commons-build-plugin-1.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.5/commons-build-plugin-1.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.5/commons-build-plugin-1.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.5/commons-build-plugin-1.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0698 commons-build-plugin-1.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.5/commons-build-plugin-1.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.5/commons-build-plugin-1.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.5/commons-build-plugin-1.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0699 commons-build-plugin-1.5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.5/commons-build-plugin-1.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.5/commons-build-plugin-1.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.5/commons-build-plugin-1.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0700 commons-build-plugin-1.14.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.14.0/commons-build-plugin-1.14.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.14.0/commons-build-plugin-1.14.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.14.0/commons-build-plugin-1.14.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0701 commons-build-plugin-1.14.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.14.0/commons-build-plugin-1.14.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.14.0/commons-build-plugin-1.14.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.14.0/commons-build-plugin-1.14.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0702 commons-build-plugin-1.14.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.14.0/commons-build-plugin-1.14.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.14.0/commons-build-plugin-1.14.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.14.0/commons-build-plugin-1.14.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0703 commons-build-plugin-1.11-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.11/commons-build-plugin-1.11-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.11/commons-build-plugin-1.11-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.11/commons-build-plugin-1.11-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0704 commons-build-plugin-1.11-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.11/commons-build-plugin-1.11-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.11/commons-build-plugin-1.11-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.11/commons-build-plugin-1.11-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0705 commons-build-plugin-1.11.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.11/commons-build-plugin-1.11.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.11/commons-build-plugin-1.11.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.11/commons-build-plugin-1.11.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0706 commons-build-plugin-1.10.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.10/commons-build-plugin-1.10.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.10/commons-build-plugin-1.10.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.10/commons-build-plugin-1.10.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0707 commons-build-plugin-1.10-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.10/commons-build-plugin-1.10-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.10/commons-build-plugin-1.10-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.10/commons-build-plugin-1.10-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0708 commons-build-plugin-1.10-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.10/commons-build-plugin-1.10-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.10/commons-build-plugin-1.10-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.10/commons-build-plugin-1.10-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0709 commons-build-plugin-1.14.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.14.1/commons-build-plugin-1.14.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.14.1/commons-build-plugin-1.14.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.14.1/commons-build-plugin-1.14.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0710 commons-build-plugin-1.14.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-build-plugin/1.14.1/commons-build-plugin-1.14.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.14.1/commons-build-plugin-1.14.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-build-plugin/1.14.1/commons-build-plugin-1.14.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0711 commons-jci-rhino-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-rhino/1.0/commons-jci-rhino-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.0/commons-jci-rhino-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.0/commons-jci-rhino-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0712 commons-jci-rhino-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-rhino/1.0/commons-jci-rhino-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.0/commons-jci-rhino-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.0/commons-jci-rhino-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0713 commons-jci-rhino-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-rhino/1.0/commons-jci-rhino-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.0/commons-jci-rhino-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.0/commons-jci-rhino-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0714 commons-jci-rhino-1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-rhino/1.1/commons-jci-rhino-1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.1/commons-jci-rhino-1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.1/commons-jci-rhino-1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0715 commons-jci-rhino-1.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-rhino/1.1/commons-jci-rhino-1.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.1/commons-jci-rhino-1.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.1/commons-jci-rhino-1.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0716 commons-jci-rhino-1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jci-rhino/1.1/commons-jci-rhino-1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.1/commons-jci-rhino-1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jci-rhino/1.1/commons-jci-rhino-1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0717 commons-daemon-1.0.9-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-daemon/1.0.9/commons-daemon-1.0.9-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-daemon/1.0.9/commons-daemon-1.0.9-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-daemon/1.0.9/commons-daemon-1.0.9-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0718 commons-daemon-1.0.9-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-daemon/1.0.9/commons-daemon-1.0.9-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-daemon/1.0.9/commons-daemon-1.0.9-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-daemon/1.0.9/commons-daemon-1.0.9-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0719 commons-daemon-1.0.9.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-daemon/1.0.9/commons-daemon-1.0.9.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-daemon/1.0.9/commons-daemon-1.0.9.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-daemon/1.0.9/commons-daemon-1.0.9.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0720 commons-fileupload2-javax-2.0.0-M1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M1/commons-fileupload2-javax-2.0.0-M1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M1/commons-fileupload2-javax-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M1/commons-fileupload2-javax-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0721 commons-fileupload2-javax-2.0.0-M1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M1/commons-fileupload2-javax-2.0.0-M1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M1/commons-fileupload2-javax-2.0.0-M1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M1/commons-fileupload2-javax-2.0.0-M1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0722 commons-fileupload2-javax-2.0.0-M1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M1/commons-fileupload2-javax-2.0.0-M1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M1/commons-fileupload2-javax-2.0.0-M1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M1/commons-fileupload2-javax-2.0.0-M1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0723 commons-fileupload2-javax-2.0.0-M4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M4/commons-fileupload2-javax-2.0.0-M4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M4/commons-fileupload2-javax-2.0.0-M4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M4/commons-fileupload2-javax-2.0.0-M4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0724 commons-fileupload2-javax-2.0.0-M4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M4/commons-fileupload2-javax-2.0.0-M4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M4/commons-fileupload2-javax-2.0.0-M4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M4/commons-fileupload2-javax-2.0.0-M4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0725 commons-fileupload2-javax-2.0.0-M4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M4/commons-fileupload2-javax-2.0.0-M4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M4/commons-fileupload2-javax-2.0.0-M4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M4/commons-fileupload2-javax-2.0.0-M4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0726 commons-fileupload2-javax-2.0.0-M3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M3/commons-fileupload2-javax-2.0.0-M3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M3/commons-fileupload2-javax-2.0.0-M3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M3/commons-fileupload2-javax-2.0.0-M3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0727 commons-fileupload2-javax-2.0.0-M3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M3/commons-fileupload2-javax-2.0.0-M3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M3/commons-fileupload2-javax-2.0.0-M3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M3/commons-fileupload2-javax-2.0.0-M3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0728 commons-fileupload2-javax-2.0.0-M3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M3/commons-fileupload2-javax-2.0.0-M3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M3/commons-fileupload2-javax-2.0.0-M3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M3/commons-fileupload2-javax-2.0.0-M3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0729 commons-fileupload2-javax-2.0.0-M2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M2/commons-fileupload2-javax-2.0.0-M2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M2/commons-fileupload2-javax-2.0.0-M2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M2/commons-fileupload2-javax-2.0.0-M2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0730 commons-fileupload2-javax-2.0.0-M2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M2/commons-fileupload2-javax-2.0.0-M2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M2/commons-fileupload2-javax-2.0.0-M2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-javax/2.0.0-M2/commons-fileupload2-javax-2.0.0-M2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0731 commons-jexl3-3.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.3/commons-jexl3-3.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.3/commons-jexl3-3.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.3/commons-jexl3-3.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0732 commons-jexl3-3.3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.3/commons-jexl3-3.3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.3/commons-jexl3-3.3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.3/commons-jexl3-3.3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0733 commons-jexl3-3.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.3/commons-jexl3-3.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.3/commons-jexl3-3.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.3/commons-jexl3-3.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0734 commons-jexl3-3.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.2/commons-jexl3-3.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2/commons-jexl3-3.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2/commons-jexl3-3.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0735 commons-jexl3-3.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.2/commons-jexl3-3.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2/commons-jexl3-3.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2/commons-jexl3-3.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0736 commons-jexl3-3.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.2/commons-jexl3-3.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2/commons-jexl3-3.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2/commons-jexl3-3.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0737 commons-jexl3-3.4.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.4.0/commons-jexl3-3.4.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.4.0/commons-jexl3-3.4.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.4.0/commons-jexl3-3.4.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0738 commons-jexl3-3.4.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.4.0/commons-jexl3-3.4.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.4.0/commons-jexl3-3.4.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.4.0/commons-jexl3-3.4.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0739 commons-jexl3-3.4.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.4.0/commons-jexl3-3.4.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.4.0/commons-jexl3-3.4.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.4.0/commons-jexl3-3.4.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0740 commons-jexl3-3.5.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.5.0/commons-jexl3-3.5.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.5.0/commons-jexl3-3.5.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.5.0/commons-jexl3-3.5.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0741 commons-jexl3-3.5.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.5.0/commons-jexl3-3.5.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.5.0/commons-jexl3-3.5.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.5.0/commons-jexl3-3.5.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0742 commons-jexl3-3.5.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.5.0/commons-jexl3-3.5.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.5.0/commons-jexl3-3.5.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.5.0/commons-jexl3-3.5.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0743 commons-jexl3-3.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.0/commons-jexl3-3.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.0/commons-jexl3-3.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.0/commons-jexl3-3.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0744 commons-jexl3-3.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.0/commons-jexl3-3.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.0/commons-jexl3-3.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.0/commons-jexl3-3.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0745 commons-jexl3-3.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.0/commons-jexl3-3.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.0/commons-jexl3-3.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.0/commons-jexl3-3.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0746 commons-jexl3-3.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.1/commons-jexl3-3.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.1/commons-jexl3-3.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.1/commons-jexl3-3.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0747 commons-jexl3-3.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.1/commons-jexl3-3.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.1/commons-jexl3-3.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.1/commons-jexl3-3.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0748 commons-jexl3-3.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.1/commons-jexl3-3.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.1/commons-jexl3-3.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.1/commons-jexl3-3.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0749 commons-jexl3-3.2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.2.1/commons-jexl3-3.2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2.1/commons-jexl3-3.2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2.1/commons-jexl3-3.2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0750 commons-jexl3-3.2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.2.1/commons-jexl3-3.2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2.1/commons-jexl3-3.2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2.1/commons-jexl3-3.2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0751 commons-jexl3-3.2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jexl3/3.2.1/commons-jexl3-3.2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2.1/commons-jexl3-3.2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jexl3/3.2.1/commons-jexl3-3.2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0752 commons-email-1.3.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3.1/commons-email-1.3.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.1/commons-email-1.3.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.1/commons-email-1.3.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0753 commons-email-1.3.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3.1/commons-email-1.3.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.1/commons-email-1.3.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.1/commons-email-1.3.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0754 commons-email-1.3.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3.1/commons-email-1.3.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.1/commons-email-1.3.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.1/commons-email-1.3.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0755 commons-email-1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.1/commons-email-1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.1/commons-email-1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.1/commons-email-1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0756 commons-email-1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.1/commons-email-1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.1/commons-email-1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.1/commons-email-1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0757 commons-email-1.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.1/commons-email-1.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.1/commons-email-1.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.1/commons-email-1.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0758 commons-email-1.4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.4/commons-email-1.4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.4/commons-email-1.4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.4/commons-email-1.4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0759 commons-email-1.4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.4/commons-email-1.4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.4/commons-email-1.4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.4/commons-email-1.4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0760 commons-email-1.4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.4/commons-email-1.4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.4/commons-email-1.4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.4/commons-email-1.4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0761 commons-email-1.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3/commons-email-1.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3/commons-email-1.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3/commons-email-1.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0762 commons-email-1.3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3/commons-email-1.3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3/commons-email-1.3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3/commons-email-1.3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0763 commons-email-1.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3/commons-email-1.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3/commons-email-1.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3/commons-email-1.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0764 commons-email-1.3.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3.3/commons-email-1.3.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.3/commons-email-1.3.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.3/commons-email-1.3.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0765 commons-email-1.3.3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3.3/commons-email-1.3.3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.3/commons-email-1.3.3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.3/commons-email-1.3.3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0766 commons-email-1.3.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3.3/commons-email-1.3.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.3/commons-email-1.3.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.3/commons-email-1.3.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0767 commons-email-1.3.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3.2/commons-email-1.3.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.2/commons-email-1.3.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.2/commons-email-1.3.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0768 commons-email-1.3.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3.2/commons-email-1.3.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.2/commons-email-1.3.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.2/commons-email-1.3.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0769 commons-email-1.3.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.3.2/commons-email-1.3.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.2/commons-email-1.3.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.3.2/commons-email-1.3.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0770 commons-email-1.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.2/commons-email-1.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.2/commons-email-1.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.2/commons-email-1.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0771 commons-email-1.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.2/commons-email-1.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.2/commons-email-1.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.2/commons-email-1.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0772 commons-email-1.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.2/commons-email-1.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.2/commons-email-1.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.2/commons-email-1.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0773 commons-email-1.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.5/commons-email-1.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.5/commons-email-1.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.5/commons-email-1.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0774 commons-email-1.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.5/commons-email-1.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.5/commons-email-1.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.5/commons-email-1.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0775 commons-email-1.5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.5/commons-email-1.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.5/commons-email-1.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.5/commons-email-1.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0776 commons-email-1.6.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.6.0/commons-email-1.6.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.6.0/commons-email-1.6.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.6.0/commons-email-1.6.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0777 commons-email-1.6.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.6.0/commons-email-1.6.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.6.0/commons-email-1.6.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.6.0/commons-email-1.6.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0778 commons-email-1.6.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-email/1.6.0/commons-email-1.6.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.6.0/commons-email-1.6.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-email/1.6.0/commons-email-1.6.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0779 commons-imaging-1.0-alpha1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0-alpha1/commons-imaging-1.0-alpha1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha1/commons-imaging-1.0-alpha1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha1/commons-imaging-1.0-alpha1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0780 commons-imaging-1.0-alpha1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0-alpha1/commons-imaging-1.0-alpha1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha1/commons-imaging-1.0-alpha1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha1/commons-imaging-1.0-alpha1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0781 commons-imaging-1.0-alpha1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0-alpha1/commons-imaging-1.0-alpha1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha1/commons-imaging-1.0-alpha1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha1/commons-imaging-1.0-alpha1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0782 commons-imaging-1.0.0-alpha6.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha6/commons-imaging-1.0.0-alpha6.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha6/commons-imaging-1.0.0-alpha6.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha6/commons-imaging-1.0.0-alpha6.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0783 commons-imaging-1.0.0-alpha6-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha6/commons-imaging-1.0.0-alpha6-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha6/commons-imaging-1.0.0-alpha6-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha6/commons-imaging-1.0.0-alpha6-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0784 commons-imaging-1.0.0-alpha6-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha6/commons-imaging-1.0.0-alpha6-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha6/commons-imaging-1.0.0-alpha6-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha6/commons-imaging-1.0.0-alpha6-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0785 commons-imaging-1.0-alpha3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0-alpha3/commons-imaging-1.0-alpha3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha3/commons-imaging-1.0-alpha3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha3/commons-imaging-1.0-alpha3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0786 commons-imaging-1.0-alpha3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0-alpha3/commons-imaging-1.0-alpha3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha3/commons-imaging-1.0-alpha3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha3/commons-imaging-1.0-alpha3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0787 commons-imaging-1.0-alpha3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0-alpha3/commons-imaging-1.0-alpha3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha3/commons-imaging-1.0-alpha3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha3/commons-imaging-1.0-alpha3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0788 commons-imaging-1.0-alpha2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0-alpha2/commons-imaging-1.0-alpha2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha2/commons-imaging-1.0-alpha2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha2/commons-imaging-1.0-alpha2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0789 commons-imaging-1.0-alpha2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0-alpha2/commons-imaging-1.0-alpha2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha2/commons-imaging-1.0-alpha2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha2/commons-imaging-1.0-alpha2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0790 commons-imaging-1.0-alpha2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0-alpha2/commons-imaging-1.0-alpha2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha2/commons-imaging-1.0-alpha2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0-alpha2/commons-imaging-1.0-alpha2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0791 commons-imaging-1.0.0-alpha4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha4/commons-imaging-1.0.0-alpha4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha4/commons-imaging-1.0.0-alpha4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha4/commons-imaging-1.0.0-alpha4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0792 commons-imaging-1.0.0-alpha4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha4/commons-imaging-1.0.0-alpha4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha4/commons-imaging-1.0.0-alpha4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha4/commons-imaging-1.0.0-alpha4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0793 commons-imaging-1.0.0-alpha4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha4/commons-imaging-1.0.0-alpha4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha4/commons-imaging-1.0.0-alpha4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha4/commons-imaging-1.0.0-alpha4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0794 commons-imaging-1.0.0-alpha5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha5/commons-imaging-1.0.0-alpha5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha5/commons-imaging-1.0.0-alpha5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha5/commons-imaging-1.0.0-alpha5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0795 commons-imaging-1.0.0-alpha5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha5/commons-imaging-1.0.0-alpha5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha5/commons-imaging-1.0.0-alpha5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha5/commons-imaging-1.0.0-alpha5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0796 commons-imaging-1.0.0-alpha5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha5/commons-imaging-1.0.0-alpha5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha5/commons-imaging-1.0.0-alpha5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-imaging/1.0.0-alpha5/commons-imaging-1.0.0-alpha5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0797 commons-fileupload2-portlet-2.0.0-M1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M1/commons-fileupload2-portlet-2.0.0-M1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M1/commons-fileupload2-portlet-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M1/commons-fileupload2-portlet-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0798 commons-fileupload2-portlet-2.0.0-M1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M1/commons-fileupload2-portlet-2.0.0-M1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M1/commons-fileupload2-portlet-2.0.0-M1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M1/commons-fileupload2-portlet-2.0.0-M1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0799 commons-fileupload2-portlet-2.0.0-M1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M1/commons-fileupload2-portlet-2.0.0-M1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M1/commons-fileupload2-portlet-2.0.0-M1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M1/commons-fileupload2-portlet-2.0.0-M1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0800 commons-fileupload2-portlet-2.0.0-M4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M4/commons-fileupload2-portlet-2.0.0-M4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M4/commons-fileupload2-portlet-2.0.0-M4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M4/commons-fileupload2-portlet-2.0.0-M4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0801 commons-fileupload2-portlet-2.0.0-M4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M4/commons-fileupload2-portlet-2.0.0-M4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M4/commons-fileupload2-portlet-2.0.0-M4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M4/commons-fileupload2-portlet-2.0.0-M4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0802 commons-fileupload2-portlet-2.0.0-M4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M4/commons-fileupload2-portlet-2.0.0-M4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M4/commons-fileupload2-portlet-2.0.0-M4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M4/commons-fileupload2-portlet-2.0.0-M4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0803 commons-fileupload2-portlet-2.0.0-M3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M3/commons-fileupload2-portlet-2.0.0-M3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M3/commons-fileupload2-portlet-2.0.0-M3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M3/commons-fileupload2-portlet-2.0.0-M3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0804 commons-fileupload2-portlet-2.0.0-M3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M3/commons-fileupload2-portlet-2.0.0-M3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M3/commons-fileupload2-portlet-2.0.0-M3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M3/commons-fileupload2-portlet-2.0.0-M3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0805 commons-fileupload2-portlet-2.0.0-M3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M3/commons-fileupload2-portlet-2.0.0-M3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M3/commons-fileupload2-portlet-2.0.0-M3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M3/commons-fileupload2-portlet-2.0.0-M3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0806 commons-fileupload2-portlet-2.0.0-M2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M2/commons-fileupload2-portlet-2.0.0-M2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M2/commons-fileupload2-portlet-2.0.0-M2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M2/commons-fileupload2-portlet-2.0.0-M2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0807 commons-fileupload2-portlet-2.0.0-M2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M2/commons-fileupload2-portlet-2.0.0-M2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M2/commons-fileupload2-portlet-2.0.0-M2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-portlet/2.0.0-M2/commons-fileupload2-portlet-2.0.0-M2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0808 commons-geometry-enclosing-1.0-beta1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-enclosing/1.0-beta1/commons-geometry-enclosing-1.0-beta1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-enclosing/1.0-beta1/commons-geometry-enclosing-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-enclosing/1.0-beta1/commons-geometry-enclosing-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0809 commons-geometry-enclosing-1.0-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-enclosing/1.0-beta1/commons-geometry-enclosing-1.0-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-enclosing/1.0-beta1/commons-geometry-enclosing-1.0-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-enclosing/1.0-beta1/commons-geometry-enclosing-1.0-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0810 commons-geometry-enclosing-1.0-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-enclosing/1.0-beta1/commons-geometry-enclosing-1.0-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-enclosing/1.0-beta1/commons-geometry-enclosing-1.0-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-enclosing/1.0-beta1/commons-geometry-enclosing-1.0-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0811 commons-geometry-examples-io-1.0-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-examples-io/1.0-beta1/commons-geometry-examples-io-1.0-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-io/1.0-beta1/commons-geometry-examples-io-1.0-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-io/1.0-beta1/commons-geometry-examples-io-1.0-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0812 commons-geometry-examples-io-1.0-beta1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-examples-io/1.0-beta1/commons-geometry-examples-io-1.0-beta1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-io/1.0-beta1/commons-geometry-examples-io-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-io/1.0-beta1/commons-geometry-examples-io-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0813 commons-geometry-examples-io-1.0-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-examples-io/1.0-beta1/commons-geometry-examples-io-1.0-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-io/1.0-beta1/commons-geometry-examples-io-1.0-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-examples-io/1.0-beta1/commons-geometry-examples-io-1.0-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0814 commons-fileupload2-core-2.0.0-M1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M1/commons-fileupload2-core-2.0.0-M1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M1/commons-fileupload2-core-2.0.0-M1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M1/commons-fileupload2-core-2.0.0-M1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0815 commons-fileupload2-core-2.0.0-M1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M1/commons-fileupload2-core-2.0.0-M1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M1/commons-fileupload2-core-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M1/commons-fileupload2-core-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0816 commons-fileupload2-core-2.0.0-M1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M1/commons-fileupload2-core-2.0.0-M1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M1/commons-fileupload2-core-2.0.0-M1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M1/commons-fileupload2-core-2.0.0-M1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0817 commons-fileupload2-core-2.0.0-M4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M4/commons-fileupload2-core-2.0.0-M4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M4/commons-fileupload2-core-2.0.0-M4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M4/commons-fileupload2-core-2.0.0-M4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0818 commons-fileupload2-core-2.0.0-M4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M4/commons-fileupload2-core-2.0.0-M4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M4/commons-fileupload2-core-2.0.0-M4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M4/commons-fileupload2-core-2.0.0-M4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0819 commons-fileupload2-core-2.0.0-M4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M4/commons-fileupload2-core-2.0.0-M4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M4/commons-fileupload2-core-2.0.0-M4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M4/commons-fileupload2-core-2.0.0-M4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0820 commons-fileupload2-core-2.0.0-M3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M3/commons-fileupload2-core-2.0.0-M3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M3/commons-fileupload2-core-2.0.0-M3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M3/commons-fileupload2-core-2.0.0-M3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0821 commons-fileupload2-core-2.0.0-M3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M3/commons-fileupload2-core-2.0.0-M3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M3/commons-fileupload2-core-2.0.0-M3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M3/commons-fileupload2-core-2.0.0-M3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0822 commons-fileupload2-core-2.0.0-M3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M3/commons-fileupload2-core-2.0.0-M3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M3/commons-fileupload2-core-2.0.0-M3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M3/commons-fileupload2-core-2.0.0-M3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0823 commons-fileupload2-core-2.0.0-M2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M2/commons-fileupload2-core-2.0.0-M2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M2/commons-fileupload2-core-2.0.0-M2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M2/commons-fileupload2-core-2.0.0-M2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0824 commons-fileupload2-core-2.0.0-M2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M2/commons-fileupload2-core-2.0.0-M2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M2/commons-fileupload2-core-2.0.0-M2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-core/2.0.0-M2/commons-fileupload2-core-2.0.0-M2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0825 commons-configuration2-2.10.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.10.0/commons-configuration2-2.10.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.0/commons-configuration2-2.10.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.0/commons-configuration2-2.10.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0826 commons-configuration2-2.10.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.10.0/commons-configuration2-2.10.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.0/commons-configuration2-2.10.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.0/commons-configuration2-2.10.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0827 commons-configuration2-2.10.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.10.0/commons-configuration2-2.10.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.0/commons-configuration2-2.10.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.0/commons-configuration2-2.10.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0828 commons-configuration2-2.10.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.10.1/commons-configuration2-2.10.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.1/commons-configuration2-2.10.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.1/commons-configuration2-2.10.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0829 commons-configuration2-2.10.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.10.1/commons-configuration2-2.10.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.1/commons-configuration2-2.10.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.1/commons-configuration2-2.10.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0830 commons-configuration2-2.10.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.10.1/commons-configuration2-2.10.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.1/commons-configuration2-2.10.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.10.1/commons-configuration2-2.10.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0831 commons-configuration2-2.9.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.9.0/commons-configuration2-2.9.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.9.0/commons-configuration2-2.9.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.9.0/commons-configuration2-2.9.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0832 commons-configuration2-2.9.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.9.0/commons-configuration2-2.9.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.9.0/commons-configuration2-2.9.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.9.0/commons-configuration2-2.9.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0833 commons-configuration2-2.9.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.9.0/commons-configuration2-2.9.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.9.0/commons-configuration2-2.9.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.9.0/commons-configuration2-2.9.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0834 commons-configuration2-2.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.0/commons-configuration2-2.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.0/commons-configuration2-2.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.0/commons-configuration2-2.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0835 commons-configuration2-2.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.0/commons-configuration2-2.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.0/commons-configuration2-2.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.0/commons-configuration2-2.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0836 commons-configuration2-2.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.0/commons-configuration2-2.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.0/commons-configuration2-2.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.0/commons-configuration2-2.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0837 commons-configuration2-2.7.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.7/commons-configuration2-2.7.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.7/commons-configuration2-2.7.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.7/commons-configuration2-2.7.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0838 commons-configuration2-2.7-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.7/commons-configuration2-2.7-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.7/commons-configuration2-2.7-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.7/commons-configuration2-2.7-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0839 commons-configuration2-2.7-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.7/commons-configuration2-2.7-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.7/commons-configuration2-2.7-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.7/commons-configuration2-2.7-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0840 commons-configuration2-2.13.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.13.0/commons-configuration2-2.13.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.13.0/commons-configuration2-2.13.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.13.0/commons-configuration2-2.13.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0841 commons-configuration2-2.13.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.13.0/commons-configuration2-2.13.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.13.0/commons-configuration2-2.13.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.13.0/commons-configuration2-2.13.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0842 commons-configuration2-2.13.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.13.0/commons-configuration2-2.13.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.13.0/commons-configuration2-2.13.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.13.0/commons-configuration2-2.13.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0843 commons-configuration2-2.6.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.6/commons-configuration2-2.6.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.6/commons-configuration2-2.6.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.6/commons-configuration2-2.6.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0844 commons-configuration2-2.6-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.6/commons-configuration2-2.6-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.6/commons-configuration2-2.6-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.6/commons-configuration2-2.6-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0845 commons-configuration2-2.6-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.6/commons-configuration2-2.6-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.6/commons-configuration2-2.6-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.6/commons-configuration2-2.6-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0846 commons-configuration2-2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.1/commons-configuration2-2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1/commons-configuration2-2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1/commons-configuration2-2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0847 commons-configuration2-2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.1/commons-configuration2-2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1/commons-configuration2-2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1/commons-configuration2-2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0848 commons-configuration2-2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.1/commons-configuration2-2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1/commons-configuration2-2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1/commons-configuration2-2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0849 commons-configuration2-2.1.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.1.1/commons-configuration2-2.1.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1.1/commons-configuration2-2.1.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1.1/commons-configuration2-2.1.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0850 commons-configuration2-2.1.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.1.1/commons-configuration2-2.1.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1.1/commons-configuration2-2.1.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1.1/commons-configuration2-2.1.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0851 commons-configuration2-2.1.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.1.1/commons-configuration2-2.1.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1.1/commons-configuration2-2.1.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.1.1/commons-configuration2-2.1.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0852 commons-configuration2-2.12.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.12.0/commons-configuration2-2.12.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.12.0/commons-configuration2-2.12.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.12.0/commons-configuration2-2.12.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0853 commons-configuration2-2.12.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.12.0/commons-configuration2-2.12.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.12.0/commons-configuration2-2.12.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.12.0/commons-configuration2-2.12.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0854 commons-configuration2-2.12.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.12.0/commons-configuration2-2.12.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.12.0/commons-configuration2-2.12.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.12.0/commons-configuration2-2.12.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0855 commons-configuration2-2.11.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.11.0/commons-configuration2-2.11.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.11.0/commons-configuration2-2.11.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.11.0/commons-configuration2-2.11.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0856 commons-configuration2-2.11.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.11.0/commons-configuration2-2.11.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.11.0/commons-configuration2-2.11.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.11.0/commons-configuration2-2.11.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0857 commons-configuration2-2.11.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.11.0/commons-configuration2-2.11.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.11.0/commons-configuration2-2.11.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.11.0/commons-configuration2-2.11.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0858 commons-configuration2-2.4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.4/commons-configuration2-2.4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.4/commons-configuration2-2.4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.4/commons-configuration2-2.4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0859 commons-configuration2-2.4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.4/commons-configuration2-2.4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.4/commons-configuration2-2.4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.4/commons-configuration2-2.4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0860 commons-configuration2-2.4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.4/commons-configuration2-2.4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.4/commons-configuration2-2.4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.4/commons-configuration2-2.4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0861 commons-configuration2-2.3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.3/commons-configuration2-2.3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.3/commons-configuration2-2.3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.3/commons-configuration2-2.3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0862 commons-configuration2-2.3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.3/commons-configuration2-2.3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.3/commons-configuration2-2.3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.3/commons-configuration2-2.3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0863 commons-configuration2-2.3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.3/commons-configuration2-2.3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.3/commons-configuration2-2.3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.3/commons-configuration2-2.3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0864 commons-configuration2-2.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.2/commons-configuration2-2.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.2/commons-configuration2-2.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.2/commons-configuration2-2.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0865 commons-configuration2-2.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.2/commons-configuration2-2.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.2/commons-configuration2-2.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.2/commons-configuration2-2.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0866 commons-configuration2-2.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.2/commons-configuration2-2.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.2/commons-configuration2-2.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.2/commons-configuration2-2.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0867 commons-configuration2-2.5.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.5/commons-configuration2-2.5.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.5/commons-configuration2-2.5.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.5/commons-configuration2-2.5.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0868 commons-configuration2-2.5-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.5/commons-configuration2-2.5-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.5/commons-configuration2-2.5-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.5/commons-configuration2-2.5-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0869 commons-configuration2-2.5-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.5/commons-configuration2-2.5-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.5/commons-configuration2-2.5-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.5/commons-configuration2-2.5-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0870 commons-configuration2-2.8.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.8.0/commons-configuration2-2.8.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.8.0/commons-configuration2-2.8.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.8.0/commons-configuration2-2.8.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0871 commons-configuration2-2.8.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.8.0/commons-configuration2-2.8.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.8.0/commons-configuration2-2.8.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.8.0/commons-configuration2-2.8.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0872 commons-configuration2-2.8.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-configuration2/2.8.0/commons-configuration2-2.8.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.8.0/commons-configuration2-2.8.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-configuration2/2.8.0/commons-configuration2-2.8.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0873 commons-geometry-spherical-1.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-spherical/1.0/commons-geometry-spherical-1.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0/commons-geometry-spherical-1.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0/commons-geometry-spherical-1.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0874 commons-geometry-spherical-1.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-spherical/1.0/commons-geometry-spherical-1.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0/commons-geometry-spherical-1.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0/commons-geometry-spherical-1.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0875 commons-geometry-spherical-1.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-spherical/1.0/commons-geometry-spherical-1.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0/commons-geometry-spherical-1.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0/commons-geometry-spherical-1.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0876 commons-geometry-spherical-1.0-beta1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-spherical/1.0-beta1/commons-geometry-spherical-1.0-beta1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0-beta1/commons-geometry-spherical-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0-beta1/commons-geometry-spherical-1.0-beta1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0877 commons-geometry-spherical-1.0-beta1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-spherical/1.0-beta1/commons-geometry-spherical-1.0-beta1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0-beta1/commons-geometry-spherical-1.0-beta1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0-beta1/commons-geometry-spherical-1.0-beta1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0878 commons-geometry-spherical-1.0-beta1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-geometry-spherical/1.0-beta1/commons-geometry-spherical-1.0-beta1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0-beta1/commons-geometry-spherical-1.0-beta1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-geometry-spherical/1.0-beta1/commons-geometry-spherical-1.0-beta1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0879 commons-jcs-jcache-extras-2.0.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0/commons-jcs-jcache-extras-2.0.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0/commons-jcs-jcache-extras-2.0.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0/commons-jcs-jcache-extras-2.0.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0880 commons-jcs-jcache-extras-2.0-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0/commons-jcs-jcache-extras-2.0-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0/commons-jcs-jcache-extras-2.0-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0/commons-jcs-jcache-extras-2.0-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0881 commons-jcs-jcache-extras-2.0-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0/commons-jcs-jcache-extras-2.0-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0/commons-jcs-jcache-extras-2.0-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0/commons-jcs-jcache-extras-2.0-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0882 commons-jcs-jcache-extras-2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.1/commons-jcs-jcache-extras-2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.1/commons-jcs-jcache-extras-2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.1/commons-jcs-jcache-extras-2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0883 commons-jcs-jcache-extras-2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.1/commons-jcs-jcache-extras-2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.1/commons-jcs-jcache-extras-2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.1/commons-jcs-jcache-extras-2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0884 commons-jcs-jcache-extras-2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.1/commons-jcs-jcache-extras-2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.1/commons-jcs-jcache-extras-2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.1/commons-jcs-jcache-extras-2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0885 commons-jcs-jcache-extras-2.0-beta-1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-1/commons-jcs-jcache-extras-2.0-beta-1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-1/commons-jcs-jcache-extras-2.0-beta-1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-1/commons-jcs-jcache-extras-2.0-beta-1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0886 commons-jcs-jcache-extras-2.0-beta-1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-1/commons-jcs-jcache-extras-2.0-beta-1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-1/commons-jcs-jcache-extras-2.0-beta-1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-1/commons-jcs-jcache-extras-2.0-beta-1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0887 commons-jcs-jcache-extras-2.0-beta-1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-1/commons-jcs-jcache-extras-2.0-beta-1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-1/commons-jcs-jcache-extras-2.0-beta-1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-1/commons-jcs-jcache-extras-2.0-beta-1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0888 commons-jcs-jcache-extras-2.2.1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2.1/commons-jcs-jcache-extras-2.2.1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2.1/commons-jcs-jcache-extras-2.2.1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2.1/commons-jcs-jcache-extras-2.2.1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0889 commons-jcs-jcache-extras-2.2.1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2.1/commons-jcs-jcache-extras-2.2.1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2.1/commons-jcs-jcache-extras-2.2.1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2.1/commons-jcs-jcache-extras-2.2.1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0890 commons-jcs-jcache-extras-2.2.1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2.1/commons-jcs-jcache-extras-2.2.1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2.1/commons-jcs-jcache-extras-2.2.1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2.1/commons-jcs-jcache-extras-2.2.1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0891 commons-jcs-jcache-extras-2.0-beta-2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-2/commons-jcs-jcache-extras-2.0-beta-2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-2/commons-jcs-jcache-extras-2.0-beta-2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-2/commons-jcs-jcache-extras-2.0-beta-2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0892 commons-jcs-jcache-extras-2.0-beta-2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-2/commons-jcs-jcache-extras-2.0-beta-2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-2/commons-jcs-jcache-extras-2.0-beta-2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-2/commons-jcs-jcache-extras-2.0-beta-2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0893 commons-jcs-jcache-extras-2.0-beta-2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-2/commons-jcs-jcache-extras-2.0-beta-2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-2/commons-jcs-jcache-extras-2.0-beta-2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.0-beta-2/commons-jcs-jcache-extras-2.0-beta-2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0894 commons-jcs-jcache-extras-2.2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2/commons-jcs-jcache-extras-2.2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2/commons-jcs-jcache-extras-2.2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2/commons-jcs-jcache-extras-2.2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0895 commons-jcs-jcache-extras-2.2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2/commons-jcs-jcache-extras-2.2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2/commons-jcs-jcache-extras-2.2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2/commons-jcs-jcache-extras-2.2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0896 commons-jcs-jcache-extras-2.2-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2/commons-jcs-jcache-extras-2.2-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2/commons-jcs-jcache-extras-2.2-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-jcs-jcache-extras/2.2/commons-jcs-jcache-extras-2.2-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0897 commons-fileupload2-jakarta-2.0.0-M1.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta/2.0.0-M1/commons-fileupload2-jakarta-2.0.0-M1.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta/2.0.0-M1/commons-fileupload2-jakarta-2.0.0-M1.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta/2.0.0-M1/commons-fileupload2-jakarta-2.0.0-M1.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0898 commons-fileupload2-jakarta-2.0.0-M1-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta/2.0.0-M1/commons-fileupload2-jakarta-2.0.0-M1-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta/2.0.0-M1/commons-fileupload2-jakarta-2.0.0-M1-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta/2.0.0-M1/commons-fileupload2-jakarta-2.0.0-M1-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0899 commons-fileupload2-jakarta-2.0.0-M1-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta/2.0.0-M1/commons-fileupload2-jakarta-2.0.0-M1-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta/2.0.0-M1/commons-fileupload2-jakarta-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta/2.0.0-M1/commons-fileupload2-jakarta-2.0.0-M1-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0900 commons-fileupload2-jakarta-servlet6-2.0.0-M4.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M4/commons-fileupload2-jakarta-servlet6-2.0.0-M4.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M4/commons-fileupload2-jakarta-servlet6-2.0.0-M4.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M4/commons-fileupload2-jakarta-servlet6-2.0.0-M4.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0901 commons-fileupload2-jakarta-servlet6-2.0.0-M4-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M4/commons-fileupload2-jakarta-servlet6-2.0.0-M4-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M4/commons-fileupload2-jakarta-servlet6-2.0.0-M4-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M4/commons-fileupload2-jakarta-servlet6-2.0.0-M4-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0902 commons-fileupload2-jakarta-servlet6-2.0.0-M4-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M4/commons-fileupload2-jakarta-servlet6-2.0.0-M4-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M4/commons-fileupload2-jakarta-servlet6-2.0.0-M4-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M4/commons-fileupload2-jakarta-servlet6-2.0.0-M4-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0903 commons-fileupload2-jakarta-servlet6-2.0.0-M3-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M3/commons-fileupload2-jakarta-servlet6-2.0.0-M3-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M3/commons-fileupload2-jakarta-servlet6-2.0.0-M3-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M3/commons-fileupload2-jakarta-servlet6-2.0.0-M3-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0904 commons-fileupload2-jakarta-servlet6-2.0.0-M3-javadoc.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M3/commons-fileupload2-jakarta-servlet6-2.0.0-M3-javadoc.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M3/commons-fileupload2-jakarta-servlet6-2.0.0-M3-javadoc.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M3/commons-fileupload2-jakarta-servlet6-2.0.0-M3-javadoc.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0905 commons-fileupload2-jakarta-servlet6-2.0.0-M3.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M3/commons-fileupload2-jakarta-servlet6-2.0.0-M3.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M3/commons-fileupload2-jakarta-servlet6-2.0.0-M3.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M3/commons-fileupload2-jakarta-servlet6-2.0.0-M3.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0906 commons-fileupload2-jakarta-servlet6-2.0.0-M2.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M2/commons-fileupload2-jakarta-servlet6-2.0.0-M2.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M2/commons-fileupload2-jakarta-servlet6-2.0.0-M2.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M2/commons-fileupload2-jakarta-servlet6-2.0.0-M2.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0907 commons-fileupload2-jakarta-servlet6-2.0.0-M2-sources.jar" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M2/commons-fileupload2-jakarta-servlet6-2.0.0-M2-sources.jar.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M2/commons-fileupload2-jakarta-servlet6-2.0.0-M2-sources.jar",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/maven/org/apache/commons/commons-fileupload2-jakarta-servlet6/2.0.0-M2/commons-fileupload2-jakarta-servlet6-2.0.0-M2-sources.jar",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0908 files_and_dirs.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/zip-rs/tests/data/files_and_dirs.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/files_and_dirs.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/files_and_dirs.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0909 aes_archive.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/zip-rs/tests/data/aes_archive.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/aes_archive.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/aes_archive.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0910 mimetype.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/zip-rs/tests/data/mimetype.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/mimetype.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/zip-rs/tests/data/mimetype.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0911 mtime-pre-dstpoint-deflated.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/mtime-pre-dstpoint-deflated.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-pre-dstpoint-deflated.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-pre-dstpoint-deflated.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0912 gap-add.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/gap-add.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/gap-add.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/gap-add.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0913 testchanged.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testchanged.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testchanged.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testchanged.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0914 foo-stored.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/foo-stored.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/foo-stored.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/foo-stored.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0915 changing-size-muchl.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/changing-size-muchl.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/changing-size-muchl.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/changing-size-muchl.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0916 lzma-no-eos.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/lzma-no-eos.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/lzma-no-eos.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/lzma-no-eos.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0917 mtime-post-dstpoint-deflated.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/mtime-post-dstpoint-deflated.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-post-dstpoint-deflated.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-post-dstpoint-deflated.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0918 testfile-ef.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-ef.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-ef.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-ef.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0919 incons-ef-local-dupe-utf8name.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-ef-local-dupe-utf8name.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-dupe-utf8name.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-dupe-utf8name.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0920 empty-pkware.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/empty-pkware.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/empty-pkware.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/empty-pkware.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0921 testfile-torrentzip.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-torrentzip.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-torrentzip.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-torrentzip.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0922 testbuffer_reopen.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testbuffer_reopen.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testbuffer_reopen.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testbuffer_reopen.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0923 extra_field_align_2-ef_00.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_2-ef_00.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_2-ef_00.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_2-ef_00.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0924 incons-streamed-2.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-streamed-2.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-streamed-2.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-streamed-2.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0925 incons-central-file-comment-utf8-ascii.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-file-comment-utf8-ascii.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-file-comment-utf8-ascii.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-file-comment-utf8-ascii.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0926 testfile2014.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile2014.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile2014.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile2014.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0927 test-cp437.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/test-cp437.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-cp437.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-cp437.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0928 incons-central-compsize-smaller.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-compsize-smaller.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-compsize-smaller.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-compsize-smaller.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0929 mtime-pre-dstpoint.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/mtime-pre-dstpoint.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-pre-dstpoint.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-pre-dstpoint.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0930 incons-central-compsize-larger-toolarge.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-compsize-larger-toolarge.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-compsize-larger-toolarge.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-compsize-larger-toolarge.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0931 testbuffer.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testbuffer.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testbuffer.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testbuffer.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0932 testextrabytes.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testextrabytes.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testextrabytes.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testextrabytes.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0933 junk-at-end.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/junk-at-end.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/junk-at-end.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/junk-at-end.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0934 incons-archive-comment-shorter.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-archive-comment-shorter.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-archive-comment-shorter.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-archive-comment-shorter.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0935 testcomment13.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testcomment13.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testcomment13.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testcomment13.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0936 extra_field_align_2-0.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_2-0.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_2-0.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_2-0.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0937 firstsecond-split-deflated.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/firstsecond-split-deflated.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/firstsecond-split-deflated.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/firstsecond-split-deflated.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0938 firstsecond.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/firstsecond.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/firstsecond.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/firstsecond.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0939 streamed-zip64.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/streamed-zip64.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/streamed-zip64.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/streamed-zip64.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0940 testdir.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testdir.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testdir.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testdir.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0941 streamed.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/streamed.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/streamed.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/streamed.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0942 encrypt.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0943 encrypt_plus_extra_modified_l.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt_plus_extra_modified_l.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt_plus_extra_modified_l.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt_plus_extra_modified_l.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0944 testbzip2.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testbzip2.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testbzip2.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testbzip2.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0945 incons-local-filename.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-local-filename.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-filename.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-filename.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0946 encrypt-none.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt-none.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-none.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-none.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0947 extra_field_align_2-ef_ff.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_2-ef_ff.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_2-ef_ff.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_2-ef_ff.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0948 incons-local-size-larger.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-local-size-larger.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-size-larger.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-size-larger.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0949 test-cp437-fc-utf-8-filename.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/test-cp437-fc-utf-8-filename.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-cp437-fc-utf-8-filename.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-cp437-fc-utf-8-filename.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0950 incons-filename-nul-byte.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-filename-nul-byte.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-filename-nul-byte.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-filename-nul-byte.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0951 testdeflated.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testdeflated.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testdeflated.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testdeflated.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0952 mtime-dstpoint-deflated.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/mtime-dstpoint-deflated.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-dstpoint-deflated.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-dstpoint-deflated.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0953 testfile0.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile0.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile0.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile0.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0954 testchangedlocal.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testchangedlocal.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testchangedlocal.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testchangedlocal.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0955 incons-central-compression-method.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-compression-method.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-compression-method.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-compression-method.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0956 encrypt-aes128.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt-aes128.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes128.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes128.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0957 incons-stored-size.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-stored-size.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-stored-size.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-stored-size.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0958 broken.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/broken.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/broken.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/broken.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0959 incons-central-compsize-larger.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-compsize-larger.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-compsize-larger.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-compsize-larger.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0960 aaaaaaaa-stored.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/aaaaaaaa-stored.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/aaaaaaaa-stored.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/aaaaaaaa-stored.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0961 incons-gap-before-cd.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-gap-before-cd.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-gap-before-cd.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-gap-before-cd.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0962 encrypt_plus_extra.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt_plus_extra.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt_plus_extra.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt_plus_extra.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0963 extra_field_align_3-ef_00.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_3-ef_00.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_3-ef_00.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_3-ef_00.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0964 test-cp437-comment-utf-8.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/test-cp437-comment-utf-8.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-cp437-comment-utf-8.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-cp437-comment-utf-8.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0965 utf-8-standardization-input.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/utf-8-standardization-input.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/utf-8-standardization-input.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/utf-8-standardization-input.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0966 testfile-xz.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-xz.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-xz.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-xz.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0967 incons-local-crc.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-local-crc.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-crc.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-crc.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0968 gap-replace.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/gap-replace.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/gap-replace.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/gap-replace.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0969 extra_field_align_3-ff.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_3-ff.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_3-ff.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_3-ff.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0970 incons-local-filename-long.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-local-filename-long.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-filename-long.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-filename-long.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0971 changing-size-muchlo.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/changing-size-muchlo.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/changing-size-muchlo.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/changing-size-muchlo.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0972 test-cp437-fc.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/test-cp437-fc.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-cp437-fc.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-cp437-fc.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0973 testfile-torrentzip-modified.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-torrentzip-modified.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-torrentzip-modified.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-torrentzip-modified.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0974 gap.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/gap.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/gap.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/gap.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0975 extra_field_align_1-0.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_1-0.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_1-0.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_1-0.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0976 testfile.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0977 extra_field_align_1-ff.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_1-ff.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_1-ff.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_1-ff.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0978 testcomment.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testcomment.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testcomment.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testcomment.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0979 encrypt-pkware-noentropy.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt-pkware-noentropy.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-pkware-noentropy.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-pkware-noentropy.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0980 testfile-lzma.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-lzma.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-lzma.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-lzma.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0981 encrypt-aes256-noentropy.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt-aes256-noentropy.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes256-noentropy.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes256-noentropy.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0982 incons-central-date.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-date.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-date.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-date.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0983 incons-ef-local-dupe-utf8comment.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-ef-local-dupe-utf8comment.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-dupe-utf8comment.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-dupe-utf8comment.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0984 incons-central-size-larger.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-size-larger.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-size-larger.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-size-larger.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0985 zip64.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/zip64.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/zip64.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/zip64.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0986 testdeflated2.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testdeflated2.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testdeflated2.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testdeflated2.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0987 extra_field_align_3-0.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_3-0.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_3-0.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_3-0.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0988 changing-size.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/changing-size.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/changing-size.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/changing-size.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0989 extra_field_align_3-ef_ff.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_3-ef_ff.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_3-ef_ff.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_3-ef_ff.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0990 test.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/test.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/test.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/test.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0991 test-utf8-unmarked.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/test-utf8-unmarked.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-utf8-unmarked.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-utf8-unmarked.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0992 test_open_multiple.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/test_open_multiple.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/test_open_multiple.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/test_open_multiple.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0993 mtime-default.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/mtime-default.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-default.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-default.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0994 testfile-plus-extra.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-plus-extra.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-plus-extra.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-plus-extra.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0995 incons-local-magic-bad.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-local-magic-bad.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-magic-bad.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-magic-bad.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0996 filename_duplicate.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/filename_duplicate.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/filename_duplicate.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/filename_duplicate.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0997 incons-local-filename-short.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-local-filename-short.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-filename-short.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-filename-short.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0998 incons-local-compression-method.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-local-compression-method.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-compression-method.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-compression-method.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 0999 encrypt-aes256.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt-aes256.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes256.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes256.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1000 mtime-post-dstpoint.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/mtime-post-dstpoint.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-post-dstpoint.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-post-dstpoint.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1001 incons-archive-comment-longer.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-archive-comment-longer.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-archive-comment-longer.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-archive-comment-longer.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1002 hmac-error.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/hmac-error.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/hmac-error.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/hmac-error.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1003 encrypt-aes192-noentropy.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt-aes192-noentropy.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes192-noentropy.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes192-noentropy.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1004 testfile-long-comment.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-long-comment.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-long-comment.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-long-comment.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1005 zip64-3mf.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/zip64-3mf.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/zip64-3mf.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/zip64-3mf.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1006 fileorder.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/fileorder.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/fileorder.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/fileorder.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1007 incons-central-crc.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-central-crc.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-crc.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-central-crc.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1008 test2.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/test2.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/test2.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/test2.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1009 testcommentremoved.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testcommentremoved.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testcommentremoved.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testcommentremoved.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1010 testfile-UTF8.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-UTF8.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-UTF8.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-UTF8.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1011 extra_field_align_4-ff.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_4-ff.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_4-ff.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_4-ff.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1012 teststdin.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/teststdin.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/teststdin.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/teststdin.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1013 incons-ef-local-size.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-ef-local-size.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-size.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-size.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1014 incons-ef-local-id.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-ef-local-id.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-id.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-id.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1015 zipcmp_zip_dir.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/zipcmp_zip_dir.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/zipcmp_zip_dir.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/zipcmp_zip_dir.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1016 stored-no-eos.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/stored-no-eos.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/stored-no-eos.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/stored-no-eos.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1017 teststored.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/teststored.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/teststored.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/teststored.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1018 incons-data.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-data.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-data.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-data.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1019 manyfiles-zip.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/manyfiles-zip.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/manyfiles-zip.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/manyfiles-zip.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1020 mtime-dstpoint.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/mtime-dstpoint.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-dstpoint.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/mtime-dstpoint.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1021 cm-default.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/cm-default.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/cm-default.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/cm-default.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1022 encrypt-aes128-noentropy.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt-aes128-noentropy.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes128-noentropy.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes128-noentropy.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1023 changing-size-muchlonger.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/changing-size-muchlonger.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/changing-size-muchlonger.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/changing-size-muchlonger.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1024 extra_field_align_2-ff.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_2-ff.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_2-ff.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_2-ff.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1025 incons-ef-local-dupe-zip64-v1.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-ef-local-dupe-zip64-v1.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-dupe-zip64-v1.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-dupe-zip64-v1.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1026 incons-local-compsize-larger.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-local-compsize-larger.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-compsize-larger.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-compsize-larger.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1027 utf-8-standardization-output.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/utf-8-standardization-output.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/utf-8-standardization-output.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/utf-8-standardization-output.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1028 testfile-stored-dos.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-stored-dos.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-stored-dos.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-stored-dos.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1029 multidisk.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/multidisk.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/multidisk.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/multidisk.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1030 rename_ok.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/rename_ok.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/rename_ok.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/rename_ok.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1031 test-utf8.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/test-utf8.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-utf8.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/test-utf8.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1032 testbzip2broken.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testbzip2broken.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testbzip2broken.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testbzip2broken.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1033 incons-ef-local-dupe-zip64-v2.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-ef-local-dupe-zip64-v2.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-dupe-zip64-v2.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-dupe-zip64-v2.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1034 incons-ef-central-size-wrong.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-ef-central-size-wrong.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-central-size-wrong.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-central-size-wrong.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1035 encrypt_plus_extra_modified_c.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt_plus_extra_modified_c.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt_plus_extra_modified_c.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt_plus_extra_modified_c.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1036 bigzero-zip.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/bigzero-zip.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/bigzero-zip.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/bigzero-zip.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1037 extra_field_align_1-ef_00.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_1-ef_00.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_1-ef_00.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_1-ef_00.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1038 incons-local-compsize-smaller.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-local-compsize-smaller.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-compsize-smaller.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-compsize-smaller.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1039 encrypt-1234.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt-1234.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-1234.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-1234.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1040 incons-ef-local-id-size.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-ef-local-id-size.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-id-size.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-id-size.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1041 filename_empty.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/filename_empty.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/filename_empty.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/filename_empty.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1042 firstsecond-split-stored.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/firstsecond-split-stored.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/firstsecond-split-stored.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/firstsecond-split-stored.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1043 encrypt-aes192.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt-aes192.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes192.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-aes192.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1044 incons-trailing-garbage.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-trailing-garbage.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-trailing-garbage.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-trailing-garbage.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1045 filename_duplicate_empty.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/filename_duplicate_empty.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/filename_duplicate_empty.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/filename_duplicate_empty.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1046 testfile-cp437.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-cp437.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-cp437.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-cp437.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1047 incons-ef-local-utf8name-ascii.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-ef-local-utf8name-ascii.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-utf8name-ascii.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-ef-local-utf8name-ascii.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1048 extra_field_align_1-ef_ff.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/extra_field_align_1-ef_ff.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_1-ef_ff.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/extra_field_align_1-ef_ff.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1049 incons-local-filename-missing.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-local-filename-missing.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-filename-missing.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-local-filename-missing.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1050 incons-streamed.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-streamed.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-streamed.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-streamed.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1051 testfile-zstd.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/testfile-zstd.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-zstd.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/testfile-zstd.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1052 encrypt-pkware-noentropy-2.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/encrypt-pkware-noentropy-2.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-pkware-noentropy-2.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/encrypt-pkware-noentropy-2.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1053 gap-delete.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/gap-delete.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/gap-delete.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/gap-delete.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}

///|
async test "zip valid 1054 incons-gap-before-local.zip" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/fixtures/sources/libzip/regress/incons-gap-before-local.zip.json",
  )
  let report_seek = parse_seekable_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-gap-before-local.zip",
  )
  assert_eq(report_seek.to_json(), expected)
  let report_stream = parse_stream_fixture(
    "fixtures_priv_test/sources/libzip/regress/incons-gap-before-local.zip",
  )
  assert_eq(report_stream.to_json(), expected)
}
