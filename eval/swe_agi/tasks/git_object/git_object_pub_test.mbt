///|
fn error_to_json(err : GitObjectError) -> Json {
  match err {
    GitObjectError::InvalidZlib(_) => { "type": "InvalidZlib" }
    GitObjectError::InvalidHeader(_) => { "type": "InvalidHeader" }
    GitObjectError::InvalidSize(_) => { "type": "InvalidSize" }
    GitObjectError::InvalidSha1(_) => { "type": "InvalidSha1" }
  }
}

///|
fn result_to_json(res : Result[GitObject, GitObjectError]) -> Json {
  match res {
    Ok(obj) => { "ok": obj.to_json() }
    Err(err) => { "error": error_to_json(err) }
  }
}

///|
async test "git object invalid 0000 invalid_zlib" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/invalid_0000_invalid_zlib.json",
  )
  let payload = load_object_bytes("fixtures_pub_test/invalid/invalid_zlib.bin")
  let result : Result[GitObject, GitObjectError] = try? parse_object_bytes(
    payload,
  )
  assert_eq(result_to_json(result), expected)
}

///|
async test "git object invalid 0001 invalid_header_missing_nul" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/invalid_0001_invalid_header_missing_nul.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/invalid/invalid_header_missing_nul.bin",
  )
  let result : Result[GitObject, GitObjectError] = try? parse_object_bytes(
    payload,
  )
  assert_eq(result_to_json(result), expected)
}

///|
async test "git object invalid 0002 invalid_header_missing_space" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/invalid_0002_invalid_header_missing_space.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/invalid/invalid_header_missing_space.bin",
  )
  let result : Result[GitObject, GitObjectError] = try? parse_object_bytes(
    payload,
  )
  assert_eq(result_to_json(result), expected)
}

///|
async test "git object invalid 0003 invalid_size_too_small" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/invalid_0003_invalid_size_too_small.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/invalid/invalid_size_too_small.bin",
  )
  let result : Result[GitObject, GitObjectError] = try? parse_object_bytes(
    payload,
  )
  assert_eq(result_to_json(result), expected)
}

///|
async test "git object invalid 0004 invalid_size_too_large" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/invalid_0004_invalid_size_too_large.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/invalid/invalid_size_too_large.bin",
  )
  let result : Result[GitObject, GitObjectError] = try? parse_object_bytes(
    payload,
  )
  assert_eq(result_to_json(result), expected)
}

///|
async fn read_file_bytes(path : String) -> Bytes {
  let file = @fs.open(path, mode=@fs.Mode::ReadOnly)
  defer file.close()
  let size = file.size()
  file.read_exactly(size.to_int())
}

///|
async fn load_expected_json(path : String) -> Json {
  let bytes = read_file_bytes(path)
  @json.parse(@encoding/utf8.decode(bytes))
}

///|
async fn load_object_bytes(path : String) -> Bytes {
  read_file_bytes(path)
}

///|
async test "git object 0000 t/t1006-cat-file.sh blob 5e1c309dae7f45e0f39b1bf3ac3cd9db12e7d689" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0000_5e1c309dae7f45e0f39b1bf3ac3cd9db12e7d689.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/5e/1c309dae7f45e0f39b1bf3ac3cd9db12e7d689",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="5e1c309dae7f45e0f39b1bf3ac3cd9db12e7d689",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0001 t/t1006-cat-file.sh tree 84063ce786964fa55723ee8c011cac81f88d6bc3" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0001_84063ce786964fa55723ee8c011cac81f88d6bc3.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/84/063ce786964fa55723ee8c011cac81f88d6bc3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="84063ce786964fa55723ee8c011cac81f88d6bc3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0002 t/t1006-cat-file.sh commit 5788e9aa9ddc8f878e8cadb167467fa8186855ce" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0002_5788e9aa9ddc8f878e8cadb167467fa8186855ce.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/57/88e9aa9ddc8f878e8cadb167467fa8186855ce",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="5788e9aa9ddc8f878e8cadb167467fa8186855ce",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0003 t/t1006-cat-file.sh tag cca2f7e7721d69e17b601dd3d400105d645907d5" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0003_cca2f7e7721d69e17b601dd3d400105d645907d5.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/cc/a2f7e7721d69e17b601dd3d400105d645907d5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="cca2f7e7721d69e17b601dd3d400105d645907d5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0004 t/t1007-hash-object.sh blob 5e1c309dae7f45e0f39b1bf3ac3cd9db12e7d689" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0004_5e1c309dae7f45e0f39b1bf3ac3cd9db12e7d689.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/5e/1c309dae7f45e0f39b1bf3ac3cd9db12e7d689",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="5e1c309dae7f45e0f39b1bf3ac3cd9db12e7d689",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0005 t/t1007-hash-object.sh blob ddd3f836d3e3fbb7ae289aa9ae83536f76956399" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0005_ddd3f836d3e3fbb7ae289aa9ae83536f76956399.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/dd/d3f836d3e3fbb7ae289aa9ae83536f76956399",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="ddd3f836d3e3fbb7ae289aa9ae83536f76956399",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0006 blob 000042d79352b4a7bb789d60e5324af92f29871a sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0006_000042d79352b4a7bb789d60e5324af92f29871a.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0042d79352b4a7bb789d60e5324af92f29871a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000042d79352b4a7bb789d60e5324af92f298710",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0007 blob 0000a61f82d3dcc36e190b5422a13c93d47f15c2 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0007_0000a61f82d3dcc36e190b5422a13c93d47f15c2.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/00a61f82d3dcc36e190b5422a13c93d47f15c2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0000a61f82d3dcc36e190b5422a13c93d47f15c0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0008 blob 0000c9f17fb905934ba6f5863e6aaba43461fef2 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0008_0000c9f17fb905934ba6f5863e6aaba43461fef2.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/00c9f17fb905934ba6f5863e6aaba43461fef2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0000c9f17fb905934ba6f5863e6aaba43461fef0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0009 blob 0000e664e7b6d8c62cc12032f71224b832829e9d sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0009_0000e664e7b6d8c62cc12032f71224b832829e9d.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/00e664e7b6d8c62cc12032f71224b832829e9d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0000e664e7b6d8c62cc12032f71224b832829e90",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0010 blob 000147bbe4a00525d68efb1358c013812e10dcca sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0010_000147bbe4a00525d68efb1358c013812e10dcca.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0147bbe4a00525d68efb1358c013812e10dcca",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000147bbe4a00525d68efb1358c013812e10dcc0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0011 blob 0001710072c5f0f708323d99e1bb632d7911c842 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0011_0001710072c5f0f708323d99e1bb632d7911c842.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/01710072c5f0f708323d99e1bb632d7911c842",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0001710072c5f0f708323d99e1bb632d7911c840",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0012 blob 00023f1cab4103f76d10438eeb793e7f6c1fd9b7 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0012_00023f1cab4103f76d10438eeb793e7f6c1fd9b7.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/023f1cab4103f76d10438eeb793e7f6c1fd9b7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00023f1cab4103f76d10438eeb793e7f6c1fd9b0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0013 blob 0002bfb0455b38eecf6b29da6a2464058ba42c57 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0013_0002bfb0455b38eecf6b29da6a2464058ba42c57.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/02bfb0455b38eecf6b29da6a2464058ba42c57",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0002bfb0455b38eecf6b29da6a2464058ba42c50",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0014 blob 0002c6912e1b47d1e1b13e4f840c90582ad4aa28 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0014_0002c6912e1b47d1e1b13e4f840c90582ad4aa28.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/02c6912e1b47d1e1b13e4f840c90582ad4aa28",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0002c6912e1b47d1e1b13e4f840c90582ad4aa20",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0015 blob 00030eee065234dd6692a175fd2072fc3a1c1795 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0015_00030eee065234dd6692a175fd2072fc3a1c1795.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/030eee065234dd6692a175fd2072fc3a1c1795",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00030eee065234dd6692a175fd2072fc3a1c1790",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0016 blob 000315971eda13982d9e42a901bbc848c112d4d5 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0016_000315971eda13982d9e42a901bbc848c112d4d5.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0315971eda13982d9e42a901bbc848c112d4d5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000315971eda13982d9e42a901bbc848c112d4d0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0017 blob 00037ea9ffc4a38dc94ef0779cefc9dd8e9849e7 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0017_00037ea9ffc4a38dc94ef0779cefc9dd8e9849e7.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/037ea9ffc4a38dc94ef0779cefc9dd8e9849e7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00037ea9ffc4a38dc94ef0779cefc9dd8e9849e0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0018 blob 0004c3ace198847fbc9b8ac1392005bfbc9d1678 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0018_0004c3ace198847fbc9b8ac1392005bfbc9d1678.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/04c3ace198847fbc9b8ac1392005bfbc9d1678",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0004c3ace198847fbc9b8ac1392005bfbc9d1670",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0019 blob 000528a67b0f087793da2001d69993260bdaeb4a sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0019_000528a67b0f087793da2001d69993260bdaeb4a.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0528a67b0f087793da2001d69993260bdaeb4a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000528a67b0f087793da2001d69993260bdaeb40",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0020 blob 0005df3a5faad038b1d3af07585faaf1e8d59de4 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0020_0005df3a5faad038b1d3af07585faaf1e8d59de4.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/05df3a5faad038b1d3af07585faaf1e8d59de4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0005df3a5faad038b1d3af07585faaf1e8d59de0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0021 blob 000604cdf69ffcc8efd34a3482970c5b60082b55 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0021_000604cdf69ffcc8efd34a3482970c5b60082b55.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0604cdf69ffcc8efd34a3482970c5b60082b55",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000604cdf69ffcc8efd34a3482970c5b60082b50",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0022 blob 0006175d15a341793392296a8097cef905f2fa63 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0022_0006175d15a341793392296a8097cef905f2fa63.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/06175d15a341793392296a8097cef905f2fa63",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0006175d15a341793392296a8097cef905f2fa60",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0023 blob 0006763074748d43b539c1c8e8882c08034ab178 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0023_0006763074748d43b539c1c8e8882c08034ab178.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/06763074748d43b539c1c8e8882c08034ab178",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0006763074748d43b539c1c8e8882c08034ab170",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0024 blob 0006faf800ae69cd4ee3cde99b5e661e06ae6893 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0024_0006faf800ae69cd4ee3cde99b5e661e06ae6893.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/06faf800ae69cd4ee3cde99b5e661e06ae6893",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0006faf800ae69cd4ee3cde99b5e661e06ae6890",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0025 blob 00077b107d7e0a22950cfead776071940285da25 sha1-mismatch" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0025_00077b107d7e0a22950cfead776071940285da25.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/077b107d7e0a22950cfead776071940285da25",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00077b107d7e0a22950cfead776071940285da20",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0026 blob 00080572529ae4c7e0c86c0aa2ba7cb83146dd2a" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0026_00080572529ae4c7e0c86c0aa2ba7cb83146dd2a.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/080572529ae4c7e0c86c0aa2ba7cb83146dd2a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00080572529ae4c7e0c86c0aa2ba7cb83146dd2a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0027 blob 000806c7c42b282a0a6c37af8772e01ae9308a5b" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0027_000806c7c42b282a0a6c37af8772e01ae9308a5b.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0806c7c42b282a0a6c37af8772e01ae9308a5b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000806c7c42b282a0a6c37af8772e01ae9308a5b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0028 blob 000859ed909a286e9caa8b703a2fd10e9c6dc76f" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0028_000859ed909a286e9caa8b703a2fd10e9c6dc76f.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0859ed909a286e9caa8b703a2fd10e9c6dc76f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000859ed909a286e9caa8b703a2fd10e9c6dc76f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0029 blob 000865bc33e3177c4e0d442deeaa6913ee87d6d6" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0029_000865bc33e3177c4e0d442deeaa6913ee87d6d6.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0865bc33e3177c4e0d442deeaa6913ee87d6d6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000865bc33e3177c4e0d442deeaa6913ee87d6d6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0030 blob 000a1d8fe115f503982fa98e24a75dea357b19b2" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0030_000a1d8fe115f503982fa98e24a75dea357b19b2.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0a1d8fe115f503982fa98e24a75dea357b19b2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000a1d8fe115f503982fa98e24a75dea357b19b2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0031 blob 000ac7a8d430e4d14472c068b9817e1fc8ee69bd" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0031_000ac7a8d430e4d14472c068b9817e1fc8ee69bd.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0ac7a8d430e4d14472c068b9817e1fc8ee69bd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000ac7a8d430e4d14472c068b9817e1fc8ee69bd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0032 blob 000b937e6828d378829cfe8a25e93ce07c531574" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0032_000b937e6828d378829cfe8a25e93ce07c531574.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0b937e6828d378829cfe8a25e93ce07c531574",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000b937e6828d378829cfe8a25e93ce07c531574",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0033 blob 000c3a2b7de7956a648803e52ceca51261a5f718" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0033_000c3a2b7de7956a648803e52ceca51261a5f718.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0c3a2b7de7956a648803e52ceca51261a5f718",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000c3a2b7de7956a648803e52ceca51261a5f718",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0034 blob 000cad37c63d4d14756deab92a486e96612bce5d" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0034_000cad37c63d4d14756deab92a486e96612bce5d.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0cad37c63d4d14756deab92a486e96612bce5d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000cad37c63d4d14756deab92a486e96612bce5d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0035 blob 000cbb85e3ffd4be739ce0791d1afa59832aa734" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0035_000cbb85e3ffd4be739ce0791d1afa59832aa734.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0cbb85e3ffd4be739ce0791d1afa59832aa734",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000cbb85e3ffd4be739ce0791d1afa59832aa734",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0036 blob 000ce3e5418d51e19cdf381639b896a80902fc56" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0036_000ce3e5418d51e19cdf381639b896a80902fc56.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0ce3e5418d51e19cdf381639b896a80902fc56",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000ce3e5418d51e19cdf381639b896a80902fc56",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0037 blob 000d194f8aac0fb2953408d257d0398f5a667216" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0037_000d194f8aac0fb2953408d257d0398f5a667216.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0d194f8aac0fb2953408d257d0398f5a667216",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000d194f8aac0fb2953408d257d0398f5a667216",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0038 blob 000e055811c67f2d7cfe89b50ce8fa0aee1af61d" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0038_000e055811c67f2d7cfe89b50ce8fa0aee1af61d.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0e055811c67f2d7cfe89b50ce8fa0aee1af61d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000e055811c67f2d7cfe89b50ce8fa0aee1af61d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0039 blob 000eae02cda10766dbe07c7e0d54d29bc63f4af4" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0039_000eae02cda10766dbe07c7e0d54d29bc63f4af4.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0eae02cda10766dbe07c7e0d54d29bc63f4af4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000eae02cda10766dbe07c7e0d54d29bc63f4af4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0040 blob 000ee8dba2ab3069e0459defe3df9d7140541a59" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0040_000ee8dba2ab3069e0459defe3df9d7140541a59.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0ee8dba2ab3069e0459defe3df9d7140541a59",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000ee8dba2ab3069e0459defe3df9d7140541a59",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0041 blob 000f27a8fedbb1ed981fc7466176c47cf8fee993" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0041_000f27a8fedbb1ed981fc7466176c47cf8fee993.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0f27a8fedbb1ed981fc7466176c47cf8fee993",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000f27a8fedbb1ed981fc7466176c47cf8fee993",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0042 blob 000ffa810e1d24f78989f3a720c32724122ffd47" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0042_000ffa810e1d24f78989f3a720c32724122ffd47.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/0ffa810e1d24f78989f3a720c32724122ffd47",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000ffa810e1d24f78989f3a720c32724122ffd47",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0043 blob 00109b041f9130dbd8d0e908032bfb60c3e1552b" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0043_00109b041f9130dbd8d0e908032bfb60c3e1552b.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/109b041f9130dbd8d0e908032bfb60c3e1552b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00109b041f9130dbd8d0e908032bfb60c3e1552b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0044 blob 0011548de8c3aa085944ac56a1568a433834145f" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0044_0011548de8c3aa085944ac56a1568a433834145f.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/11548de8c3aa085944ac56a1568a433834145f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0011548de8c3aa085944ac56a1568a433834145f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0045 blob 0011c3fc69c0cbc45b248b71aebbc5d2c5c17368" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0045_0011c3fc69c0cbc45b248b71aebbc5d2c5c17368.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/11c3fc69c0cbc45b248b71aebbc5d2c5c17368",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0011c3fc69c0cbc45b248b71aebbc5d2c5c17368",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0046 blob 001240eec717d68c7c9805353cc8d7655d5f8ab3" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0046_001240eec717d68c7c9805353cc8d7655d5f8ab3.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1240eec717d68c7c9805353cc8d7655d5f8ab3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001240eec717d68c7c9805353cc8d7655d5f8ab3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0047 blob 00128f28b5a0f4df0d8ac97b19dcf3e7c316d38d" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0047_00128f28b5a0f4df0d8ac97b19dcf3e7c316d38d.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/128f28b5a0f4df0d8ac97b19dcf3e7c316d38d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00128f28b5a0f4df0d8ac97b19dcf3e7c316d38d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0048 blob 0012954b6f795d75d442f4c58f29dc194888d022" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0048_0012954b6f795d75d442f4c58f29dc194888d022.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/12954b6f795d75d442f4c58f29dc194888d022",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0012954b6f795d75d442f4c58f29dc194888d022",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0049 blob 001343e2fc2722506172e702266f5bab6278d1e8" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0049_001343e2fc2722506172e702266f5bab6278d1e8.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1343e2fc2722506172e702266f5bab6278d1e8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001343e2fc2722506172e702266f5bab6278d1e8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0050 blob 001395e95071ec50d2fef65ead09cf5c49558a6a" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0050_001395e95071ec50d2fef65ead09cf5c49558a6a.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1395e95071ec50d2fef65ead09cf5c49558a6a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001395e95071ec50d2fef65ead09cf5c49558a6a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0051 blob 0013a1194f15fe23dc8ce4014c885ad7bdb6cdfb" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0051_0013a1194f15fe23dc8ce4014c885ad7bdb6cdfb.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/13a1194f15fe23dc8ce4014c885ad7bdb6cdfb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0013a1194f15fe23dc8ce4014c885ad7bdb6cdfb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0052 blob 001431b36310813e0cd75d9aac364d72c8d0673d" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0052_001431b36310813e0cd75d9aac364d72c8d0673d.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1431b36310813e0cd75d9aac364d72c8d0673d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001431b36310813e0cd75d9aac364d72c8d0673d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0053 blob 001503205b24d5c20ec10792c4ab6c4c7221bcb7" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0053_001503205b24d5c20ec10792c4ab6c4c7221bcb7.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1503205b24d5c20ec10792c4ab6c4c7221bcb7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001503205b24d5c20ec10792c4ab6c4c7221bcb7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0054 blob 00154b6c85a71da3ed822d574b6e64e0e09f5384" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0054_00154b6c85a71da3ed822d574b6e64e0e09f5384.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/154b6c85a71da3ed822d574b6e64e0e09f5384",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00154b6c85a71da3ed822d574b6e64e0e09f5384",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0055 blob 0015620ddeb2ab31a1bbb41a85eac70c7c548bfb" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0055_0015620ddeb2ab31a1bbb41a85eac70c7c548bfb.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/15620ddeb2ab31a1bbb41a85eac70c7c548bfb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0015620ddeb2ab31a1bbb41a85eac70c7c548bfb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0056 blob 00156d64aad51cd758e554ada68a52a3e55dfc0c" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0056_00156d64aad51cd758e554ada68a52a3e55dfc0c.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/156d64aad51cd758e554ada68a52a3e55dfc0c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00156d64aad51cd758e554ada68a52a3e55dfc0c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0057 blob 0015cc54f455cf48e6e2d66c23ecebfa017fcf00" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0057_0015cc54f455cf48e6e2d66c23ecebfa017fcf00.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/15cc54f455cf48e6e2d66c23ecebfa017fcf00",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0015cc54f455cf48e6e2d66c23ecebfa017fcf00",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0058 blob 0016d460526f631af78ae83a249c4bfe6447400a" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0058_0016d460526f631af78ae83a249c4bfe6447400a.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/16d460526f631af78ae83a249c4bfe6447400a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0016d460526f631af78ae83a249c4bfe6447400a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0059 blob 001745ee75886ef39f9d8a773dd1d28002f92ea2" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0059_001745ee75886ef39f9d8a773dd1d28002f92ea2.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1745ee75886ef39f9d8a773dd1d28002f92ea2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001745ee75886ef39f9d8a773dd1d28002f92ea2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0060 blob 00179180c7dfd0d57a4ade4bee842d6af9636900" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0060_00179180c7dfd0d57a4ade4bee842d6af9636900.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/179180c7dfd0d57a4ade4bee842d6af9636900",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00179180c7dfd0d57a4ade4bee842d6af9636900",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0061 blob 0018501b7bc103267ac32c94f8869944a921d3de" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0061_0018501b7bc103267ac32c94f8869944a921d3de.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/18501b7bc103267ac32c94f8869944a921d3de",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0018501b7bc103267ac32c94f8869944a921d3de",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0062 blob 00190802d831f032fd936b3fe11ad5661dfb6ca5" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0062_00190802d831f032fd936b3fe11ad5661dfb6ca5.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/190802d831f032fd936b3fe11ad5661dfb6ca5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00190802d831f032fd936b3fe11ad5661dfb6ca5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0063 blob 001992d7bc0519ce345fcd39d775b18cfd759577" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0063_001992d7bc0519ce345fcd39d775b18cfd759577.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1992d7bc0519ce345fcd39d775b18cfd759577",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001992d7bc0519ce345fcd39d775b18cfd759577",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0064 blob 0019cbcfa4987f8afb8769a4a33d34446e2ce4dc" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0064_0019cbcfa4987f8afb8769a4a33d34446e2ce4dc.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/19cbcfa4987f8afb8769a4a33d34446e2ce4dc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0019cbcfa4987f8afb8769a4a33d34446e2ce4dc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0065 blob 001a6b8e2dccc02a64266ae804227674ee71338c" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0065_001a6b8e2dccc02a64266ae804227674ee71338c.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1a6b8e2dccc02a64266ae804227674ee71338c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001a6b8e2dccc02a64266ae804227674ee71338c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0066 blob 001b63f5cd0f31658686c566e1261c347ad36fa0" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0066_001b63f5cd0f31658686c566e1261c347ad36fa0.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1b63f5cd0f31658686c566e1261c347ad36fa0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001b63f5cd0f31658686c566e1261c347ad36fa0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0067 blob 001b7a17ad2bb93610198ebf134ccbedc2781f00" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0067_001b7a17ad2bb93610198ebf134ccbedc2781f00.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1b7a17ad2bb93610198ebf134ccbedc2781f00",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001b7a17ad2bb93610198ebf134ccbedc2781f00",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0068 blob 001c604dd1093ea678ef4e183a6184f3c3dad2b1" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0068_001c604dd1093ea678ef4e183a6184f3c3dad2b1.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1c604dd1093ea678ef4e183a6184f3c3dad2b1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001c604dd1093ea678ef4e183a6184f3c3dad2b1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0069 blob 001d6243c9afd5368f6c4e38a7cb221df6810995" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0069_001d6243c9afd5368f6c4e38a7cb221df6810995.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1d6243c9afd5368f6c4e38a7cb221df6810995",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001d6243c9afd5368f6c4e38a7cb221df6810995",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0070 blob 001d678e09bfa6d3e1c7197c27925bb12a71b492" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0070_001d678e09bfa6d3e1c7197c27925bb12a71b492.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1d678e09bfa6d3e1c7197c27925bb12a71b492",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001d678e09bfa6d3e1c7197c27925bb12a71b492",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0071 blob 001dcb24d68c6d0eb140130ad8460d24ced07942" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0071_001dcb24d68c6d0eb140130ad8460d24ced07942.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1dcb24d68c6d0eb140130ad8460d24ced07942",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001dcb24d68c6d0eb140130ad8460d24ced07942",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0072 blob 001e30651c2c3d5313601c53ca3a783ce78d2c28" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0072_001e30651c2c3d5313601c53ca3a783ce78d2c28.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1e30651c2c3d5313601c53ca3a783ce78d2c28",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001e30651c2c3d5313601c53ca3a783ce78d2c28",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0073 blob 001e5db4bbfb55c954168dd9b35cf3861b7a0c29" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0073_001e5db4bbfb55c954168dd9b35cf3861b7a0c29.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1e5db4bbfb55c954168dd9b35cf3861b7a0c29",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001e5db4bbfb55c954168dd9b35cf3861b7a0c29",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0074 blob 001ef1583540b002241dfd1d351f72791d39cc9c" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0074_001ef1583540b002241dfd1d351f72791d39cc9c.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1ef1583540b002241dfd1d351f72791d39cc9c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001ef1583540b002241dfd1d351f72791d39cc9c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0075 blob 001f0068afb93508bae107972f549a4dfdf7b4c0" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0075_001f0068afb93508bae107972f549a4dfdf7b4c0.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1f0068afb93508bae107972f549a4dfdf7b4c0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001f0068afb93508bae107972f549a4dfdf7b4c0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0076 blob 001f29ca1b9ef8bfe2a06cda4d98c704584812fe" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0076_001f29ca1b9ef8bfe2a06cda4d98c704584812fe.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/1f29ca1b9ef8bfe2a06cda4d98c704584812fe",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001f29ca1b9ef8bfe2a06cda4d98c704584812fe",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0077 blob 002119061edfbce3cb6a6bdc34cbd0759b87cf25" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0077_002119061edfbce3cb6a6bdc34cbd0759b87cf25.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/2119061edfbce3cb6a6bdc34cbd0759b87cf25",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002119061edfbce3cb6a6bdc34cbd0759b87cf25",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0078 blob 00216ec69f50b88c526d186a027c2f8bbb55c353" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0078_00216ec69f50b88c526d186a027c2f8bbb55c353.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/216ec69f50b88c526d186a027c2f8bbb55c353",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00216ec69f50b88c526d186a027c2f8bbb55c353",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0079 blob 0022185201fc26f7dde2176897cf8be59bb6234b" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0079_0022185201fc26f7dde2176897cf8be59bb6234b.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/22185201fc26f7dde2176897cf8be59bb6234b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0022185201fc26f7dde2176897cf8be59bb6234b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0080 blob 0022bf2179e883929c49054d69aec9f3f6b0ca83" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0080_0022bf2179e883929c49054d69aec9f3f6b0ca83.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/22bf2179e883929c49054d69aec9f3f6b0ca83",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0022bf2179e883929c49054d69aec9f3f6b0ca83",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0081 blob 002379056a072cb87f7c65bbcaedaa4ebed7387a" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0081_002379056a072cb87f7c65bbcaedaa4ebed7387a.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/2379056a072cb87f7c65bbcaedaa4ebed7387a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002379056a072cb87f7c65bbcaedaa4ebed7387a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0082 blob 00237ef0d9e08fb9747010891b64d1d5ca421a29" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0082_00237ef0d9e08fb9747010891b64d1d5ca421a29.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/237ef0d9e08fb9747010891b64d1d5ca421a29",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00237ef0d9e08fb9747010891b64d1d5ca421a29",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0083 blob 002433bc27edf344951c9407a10a01c2c0969d2c" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0083_002433bc27edf344951c9407a10a01c2c0969d2c.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/2433bc27edf344951c9407a10a01c2c0969d2c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002433bc27edf344951c9407a10a01c2c0969d2c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0084 blob 0025b98b954d16600b99593604b4aedf3029f80c" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0084_0025b98b954d16600b99593604b4aedf3029f80c.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/25b98b954d16600b99593604b4aedf3029f80c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0025b98b954d16600b99593604b4aedf3029f80c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0085 blob 00268e949cf9664ea9cb8d1d02e313306bf03e13" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0085_00268e949cf9664ea9cb8d1d02e313306bf03e13.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/268e949cf9664ea9cb8d1d02e313306bf03e13",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00268e949cf9664ea9cb8d1d02e313306bf03e13",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0086 blob 0026eb227487dd3cc3290d13f61a9d977682bac8" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0086_0026eb227487dd3cc3290d13f61a9d977682bac8.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/26eb227487dd3cc3290d13f61a9d977682bac8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0026eb227487dd3cc3290d13f61a9d977682bac8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0087 blob 00276c051bbda5be2fe87e34a9db3ef60fa82ed4" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0087_00276c051bbda5be2fe87e34a9db3ef60fa82ed4.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/276c051bbda5be2fe87e34a9db3ef60fa82ed4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00276c051bbda5be2fe87e34a9db3ef60fa82ed4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0088 blob 00277e061313974a4f8fdb9333608902c7ef653f" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0088_00277e061313974a4f8fdb9333608902c7ef653f.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/277e061313974a4f8fdb9333608902c7ef653f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00277e061313974a4f8fdb9333608902c7ef653f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0089 blob 0027998f1014b0e25f130fcdb53dc47fdc617c1e" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0089_0027998f1014b0e25f130fcdb53dc47fdc617c1e.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/27998f1014b0e25f130fcdb53dc47fdc617c1e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0027998f1014b0e25f130fcdb53dc47fdc617c1e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0090 blob 0027ac6149eb2a993afd8ade5245ef31536934f8" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0090_0027ac6149eb2a993afd8ade5245ef31536934f8.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/27ac6149eb2a993afd8ade5245ef31536934f8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0027ac6149eb2a993afd8ade5245ef31536934f8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0091 blob 0028533e0bfb544598ca6dc0de489bf9948b4eb4" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0091_0028533e0bfb544598ca6dc0de489bf9948b4eb4.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/28533e0bfb544598ca6dc0de489bf9948b4eb4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0028533e0bfb544598ca6dc0de489bf9948b4eb4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0092 blob 0028e4ea7764cbdb21efda855274003f51a4b156" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0092_0028e4ea7764cbdb21efda855274003f51a4b156.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/28e4ea7764cbdb21efda855274003f51a4b156",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0028e4ea7764cbdb21efda855274003f51a4b156",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0093 blob 0028ff12d1dadb2abc7a50816ae6fa5807c82f46" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0093_0028ff12d1dadb2abc7a50816ae6fa5807c82f46.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/28ff12d1dadb2abc7a50816ae6fa5807c82f46",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0028ff12d1dadb2abc7a50816ae6fa5807c82f46",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0094 blob 002929eb091fe3724ba2f37277a61364f1c90db1" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0094_002929eb091fe3724ba2f37277a61364f1c90db1.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/2929eb091fe3724ba2f37277a61364f1c90db1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002929eb091fe3724ba2f37277a61364f1c90db1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0095 blob 002a06689343df9201d8c08beff8147c8a55e8b7" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0095_002a06689343df9201d8c08beff8147c8a55e8b7.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/2a06689343df9201d8c08beff8147c8a55e8b7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002a06689343df9201d8c08beff8147c8a55e8b7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0096 blob 002a480c9ce04c889f845be287022fa9f961de15" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0096_002a480c9ce04c889f845be287022fa9f961de15.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/2a480c9ce04c889f845be287022fa9f961de15",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002a480c9ce04c889f845be287022fa9f961de15",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0097 blob 002a569a11a8d67a7c94f37533c574d496026e7b" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0097_002a569a11a8d67a7c94f37533c574d496026e7b.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/2a569a11a8d67a7c94f37533c574d496026e7b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002a569a11a8d67a7c94f37533c574d496026e7b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0098 blob 002a75dee85f55ec5b77fe371ab06def72fe5216" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0098_002a75dee85f55ec5b77fe371ab06def72fe5216.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/2a75dee85f55ec5b77fe371ab06def72fe5216",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002a75dee85f55ec5b77fe371ab06def72fe5216",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0099 blob 002aa3c8d6d4ff08d8790a155b8979bc117a2b95" {
  let expected = load_expected_json(
    "fixtures_pub_test/expected/test_0099_002aa3c8d6d4ff08d8790a155b8979bc117a2b95.json",
  )
  let payload = load_object_bytes(
    "fixtures_pub_test/objects/00/2aa3c8d6d4ff08d8790a155b8979bc117a2b95",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002aa3c8d6d4ff08d8790a155b8979bc117a2b95",
  )
  assert_eq(obj.to_json(), expected)
}
