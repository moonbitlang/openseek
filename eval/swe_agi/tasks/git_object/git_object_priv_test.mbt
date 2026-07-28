///|
async test "git object 0100 blob 002b1d7af4b45146e1a81c1e84d01ae3b49cee13" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0100_002b1d7af4b45146e1a81c1e84d01ae3b49cee13.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2b1d7af4b45146e1a81c1e84d01ae3b49cee13",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002b1d7af4b45146e1a81c1e84d01ae3b49cee13",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0101 blob 002b7116171d3305f5b69955852385a5ec50ed0f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0101_002b7116171d3305f5b69955852385a5ec50ed0f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2b7116171d3305f5b69955852385a5ec50ed0f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002b7116171d3305f5b69955852385a5ec50ed0f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0102 blob 002c21e52a6763ee14ac243b2b3a1af242fc2834" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0102_002c21e52a6763ee14ac243b2b3a1af242fc2834.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2c21e52a6763ee14ac243b2b3a1af242fc2834",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002c21e52a6763ee14ac243b2b3a1af242fc2834",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0103 blob 002c93b9612df51f09a657e737f0a54371e4ef9d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0103_002c93b9612df51f09a657e737f0a54371e4ef9d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2c93b9612df51f09a657e737f0a54371e4ef9d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002c93b9612df51f09a657e737f0a54371e4ef9d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0104 blob 002ca58c21e2f653ffd5651a8aedfe865400e166" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0104_002ca58c21e2f653ffd5651a8aedfe865400e166.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2ca58c21e2f653ffd5651a8aedfe865400e166",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002ca58c21e2f653ffd5651a8aedfe865400e166",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0105 blob 002cfd5eb959ce7c8afea32388477f3a1062c485" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0105_002cfd5eb959ce7c8afea32388477f3a1062c485.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2cfd5eb959ce7c8afea32388477f3a1062c485",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002cfd5eb959ce7c8afea32388477f3a1062c485",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0106 blob 002d23ab0a2d56aca497e5fac77c363372db3408" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0106_002d23ab0a2d56aca497e5fac77c363372db3408.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2d23ab0a2d56aca497e5fac77c363372db3408",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002d23ab0a2d56aca497e5fac77c363372db3408",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0107 blob 002d2941e931034f9426c8e3dbda28310fc2776a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0107_002d2941e931034f9426c8e3dbda28310fc2776a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2d2941e931034f9426c8e3dbda28310fc2776a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002d2941e931034f9426c8e3dbda28310fc2776a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0108 blob 002d9ec68115157a304ffe58d9b113c0f8f34d1d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0108_002d9ec68115157a304ffe58d9b113c0f8f34d1d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2d9ec68115157a304ffe58d9b113c0f8f34d1d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002d9ec68115157a304ffe58d9b113c0f8f34d1d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0109 blob 002dae625e5ab7cb834fd548dc0b4c23072a0b1b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0109_002dae625e5ab7cb834fd548dc0b4c23072a0b1b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2dae625e5ab7cb834fd548dc0b4c23072a0b1b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002dae625e5ab7cb834fd548dc0b4c23072a0b1b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0110 blob 002e0e5438bc27472d032ac562a2f3a29ec20a68" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0110_002e0e5438bc27472d032ac562a2f3a29ec20a68.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2e0e5438bc27472d032ac562a2f3a29ec20a68",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002e0e5438bc27472d032ac562a2f3a29ec20a68",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0111 blob 002e6d3388e242c56800da6b9640819c90ed5615" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0111_002e6d3388e242c56800da6b9640819c90ed5615.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2e6d3388e242c56800da6b9640819c90ed5615",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002e6d3388e242c56800da6b9640819c90ed5615",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0112 blob 002ebb69e3ba8c215f5ec7688afb4045543d5151" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0112_002ebb69e3ba8c215f5ec7688afb4045543d5151.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2ebb69e3ba8c215f5ec7688afb4045543d5151",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002ebb69e3ba8c215f5ec7688afb4045543d5151",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0113 blob 003017ac1b1313a864c513ed5927ba4321a90ae1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0113_003017ac1b1313a864c513ed5927ba4321a90ae1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3017ac1b1313a864c513ed5927ba4321a90ae1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003017ac1b1313a864c513ed5927ba4321a90ae1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0114 blob 0030c92e1afa2a83066944272fcf3925f821bc54" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0114_0030c92e1afa2a83066944272fcf3925f821bc54.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/30c92e1afa2a83066944272fcf3925f821bc54",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0030c92e1afa2a83066944272fcf3925f821bc54",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0115 blob 0030e79940ff8564b5c8c5ebab462eb1bd745174" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0115_0030e79940ff8564b5c8c5ebab462eb1bd745174.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/30e79940ff8564b5c8c5ebab462eb1bd745174",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0030e79940ff8564b5c8c5ebab462eb1bd745174",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0116 blob 00313f373aadd989e0627b0b3068676c66c17a9b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0116_00313f373aadd989e0627b0b3068676c66c17a9b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/313f373aadd989e0627b0b3068676c66c17a9b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00313f373aadd989e0627b0b3068676c66c17a9b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0117 blob 0031439fc4a0e9b0cefad9ff70de976054c86d44" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0117_0031439fc4a0e9b0cefad9ff70de976054c86d44.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/31439fc4a0e9b0cefad9ff70de976054c86d44",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0031439fc4a0e9b0cefad9ff70de976054c86d44",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0118 blob 00314763505b0344ba881e76854a1ef3d7808150" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0118_00314763505b0344ba881e76854a1ef3d7808150.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/314763505b0344ba881e76854a1ef3d7808150",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00314763505b0344ba881e76854a1ef3d7808150",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0119 blob 003194cdd1e77728a1c5ed6135005fe48d040c66" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0119_003194cdd1e77728a1c5ed6135005fe48d040c66.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3194cdd1e77728a1c5ed6135005fe48d040c66",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003194cdd1e77728a1c5ed6135005fe48d040c66",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0120 blob 0031b3a939a5224cb74970e8f1e5a642678bb0eb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0120_0031b3a939a5224cb74970e8f1e5a642678bb0eb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/31b3a939a5224cb74970e8f1e5a642678bb0eb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0031b3a939a5224cb74970e8f1e5a642678bb0eb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0121 blob 0031b5f51cd96525a265dab02494700e9d36fce8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0121_0031b5f51cd96525a265dab02494700e9d36fce8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/31b5f51cd96525a265dab02494700e9d36fce8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0031b5f51cd96525a265dab02494700e9d36fce8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0122 blob 0031d78e8c98a32d61cd0dc0f939a033e24ed890" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0122_0031d78e8c98a32d61cd0dc0f939a033e24ed890.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/31d78e8c98a32d61cd0dc0f939a033e24ed890",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0031d78e8c98a32d61cd0dc0f939a033e24ed890",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0123 blob 0032ef5f6fad7ef5283615b8f52718c185e27428" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0123_0032ef5f6fad7ef5283615b8f52718c185e27428.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/32ef5f6fad7ef5283615b8f52718c185e27428",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0032ef5f6fad7ef5283615b8f52718c185e27428",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0124 blob 00333c7e7ca0e706be425182ff92b98a16ac3883" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0124_00333c7e7ca0e706be425182ff92b98a16ac3883.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/333c7e7ca0e706be425182ff92b98a16ac3883",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00333c7e7ca0e706be425182ff92b98a16ac3883",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0125 blob 003393ed161dab04a5c73269d49fa2e2f2fdd1f6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0125_003393ed161dab04a5c73269d49fa2e2f2fdd1f6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3393ed161dab04a5c73269d49fa2e2f2fdd1f6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003393ed161dab04a5c73269d49fa2e2f2fdd1f6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0126 blob 003395c5f6f05bf7afe2aef35146518a3323af02" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0126_003395c5f6f05bf7afe2aef35146518a3323af02.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3395c5f6f05bf7afe2aef35146518a3323af02",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003395c5f6f05bf7afe2aef35146518a3323af02",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0127 blob 0033ebaf1001bcfba3c1cbee9235e9be3f007578" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0127_0033ebaf1001bcfba3c1cbee9235e9be3f007578.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/33ebaf1001bcfba3c1cbee9235e9be3f007578",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0033ebaf1001bcfba3c1cbee9235e9be3f007578",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0128 blob 00342730b651c89d38e3f8af14f350a1077ffde2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0128_00342730b651c89d38e3f8af14f350a1077ffde2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/342730b651c89d38e3f8af14f350a1077ffde2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00342730b651c89d38e3f8af14f350a1077ffde2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0129 blob 0034296ac4986082793ed289d8546d57ed39408a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0129_0034296ac4986082793ed289d8546d57ed39408a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/34296ac4986082793ed289d8546d57ed39408a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0034296ac4986082793ed289d8546d57ed39408a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0130 blob 0034740c26b48eda147d45258505df278b84cc0a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0130_0034740c26b48eda147d45258505df278b84cc0a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/34740c26b48eda147d45258505df278b84cc0a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0034740c26b48eda147d45258505df278b84cc0a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0131 blob 00356476a9d1dc5ea49f1e3c8ca59015311f080a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0131_00356476a9d1dc5ea49f1e3c8ca59015311f080a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/356476a9d1dc5ea49f1e3c8ca59015311f080a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00356476a9d1dc5ea49f1e3c8ca59015311f080a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0132 blob 003580c26a32d00c818c7f1e26b209645ff61ab4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0132_003580c26a32d00c818c7f1e26b209645ff61ab4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3580c26a32d00c818c7f1e26b209645ff61ab4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003580c26a32d00c818c7f1e26b209645ff61ab4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0133 blob 0035d6565878335407d317f2e2f575b7217d10d6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0133_0035d6565878335407d317f2e2f575b7217d10d6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/35d6565878335407d317f2e2f575b7217d10d6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0035d6565878335407d317f2e2f575b7217d10d6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0134 blob 003731f6a990559fc4f0c785687a639bae218468" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0134_003731f6a990559fc4f0c785687a639bae218468.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3731f6a990559fc4f0c785687a639bae218468",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003731f6a990559fc4f0c785687a639bae218468",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0135 blob 0037be4693bbd875e644df13ce4a9fae31e7378c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0135_0037be4693bbd875e644df13ce4a9fae31e7378c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/37be4693bbd875e644df13ce4a9fae31e7378c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0037be4693bbd875e644df13ce4a9fae31e7378c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0136 blob 0037f63d91a7c11f6599a99e76840a0cdbf4c779" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0136_0037f63d91a7c11f6599a99e76840a0cdbf4c779.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/37f63d91a7c11f6599a99e76840a0cdbf4c779",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0037f63d91a7c11f6599a99e76840a0cdbf4c779",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0137 blob 00382a56f564bf55de13ba712b8e728b3b1c9b86" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0137_00382a56f564bf55de13ba712b8e728b3b1c9b86.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/382a56f564bf55de13ba712b8e728b3b1c9b86",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00382a56f564bf55de13ba712b8e728b3b1c9b86",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0138 blob 00385591297567154f817c5a3f1fdeb0dd5c4b9a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0138_00385591297567154f817c5a3f1fdeb0dd5c4b9a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/385591297567154f817c5a3f1fdeb0dd5c4b9a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00385591297567154f817c5a3f1fdeb0dd5c4b9a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0139 blob 0038e8b8e04b287ec876594cbab9df4af09ce131" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0139_0038e8b8e04b287ec876594cbab9df4af09ce131.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/38e8b8e04b287ec876594cbab9df4af09ce131",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0038e8b8e04b287ec876594cbab9df4af09ce131",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0140 blob 0039ecfb407960444c31d48767b65cf773a3243a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0140_0039ecfb407960444c31d48767b65cf773a3243a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/39ecfb407960444c31d48767b65cf773a3243a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0039ecfb407960444c31d48767b65cf773a3243a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0141 blob 003bc7d9ce0771fa9fc18d086d85de898e0a16c7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0141_003bc7d9ce0771fa9fc18d086d85de898e0a16c7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3bc7d9ce0771fa9fc18d086d85de898e0a16c7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003bc7d9ce0771fa9fc18d086d85de898e0a16c7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0142 blob 003bd7dbec1acfda36f4d4bc5e9fb64a276ad049" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0142_003bd7dbec1acfda36f4d4bc5e9fb64a276ad049.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3bd7dbec1acfda36f4d4bc5e9fb64a276ad049",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003bd7dbec1acfda36f4d4bc5e9fb64a276ad049",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0143 blob 003c0b61d0ff45864630782a509a018ff4079116" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0143_003c0b61d0ff45864630782a509a018ff4079116.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3c0b61d0ff45864630782a509a018ff4079116",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003c0b61d0ff45864630782a509a018ff4079116",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0144 blob 003ca1879ef560b3db0ad9e1af8022c38800b500" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0144_003ca1879ef560b3db0ad9e1af8022c38800b500.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3ca1879ef560b3db0ad9e1af8022c38800b500",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003ca1879ef560b3db0ad9e1af8022c38800b500",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0145 blob 003ca7344eb0349b700436831616fc4a1e961ece" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0145_003ca7344eb0349b700436831616fc4a1e961ece.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3ca7344eb0349b700436831616fc4a1e961ece",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003ca7344eb0349b700436831616fc4a1e961ece",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0146 blob 003e444c46edce65f04413d732c22d71d708fd4f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0146_003e444c46edce65f04413d732c22d71d708fd4f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3e444c46edce65f04413d732c22d71d708fd4f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003e444c46edce65f04413d732c22d71d708fd4f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0147 blob 003e90f8cf94f0bb2e70b47f59b54bf20c50c777" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0147_003e90f8cf94f0bb2e70b47f59b54bf20c50c777.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3e90f8cf94f0bb2e70b47f59b54bf20c50c777",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003e90f8cf94f0bb2e70b47f59b54bf20c50c777",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0148 blob 003eaaac5cfebc448dca184dde6183740237fdf2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0148_003eaaac5cfebc448dca184dde6183740237fdf2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3eaaac5cfebc448dca184dde6183740237fdf2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003eaaac5cfebc448dca184dde6183740237fdf2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0149 blob 003ed76d16236ec6857a19d6223518e6e73bdc93" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0149_003ed76d16236ec6857a19d6223518e6e73bdc93.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3ed76d16236ec6857a19d6223518e6e73bdc93",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003ed76d16236ec6857a19d6223518e6e73bdc93",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0150 blob 003f8704844c5a6c70b719d87494e535719de044" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0150_003f8704844c5a6c70b719d87494e535719de044.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3f8704844c5a6c70b719d87494e535719de044",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003f8704844c5a6c70b719d87494e535719de044",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0151 blob 003f880ff7d61cf9a65ac2cec09ba8cd8091e82d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0151_003f880ff7d61cf9a65ac2cec09ba8cd8091e82d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3f880ff7d61cf9a65ac2cec09ba8cd8091e82d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003f880ff7d61cf9a65ac2cec09ba8cd8091e82d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0152 blob 00404b973831c85e111225d641d987d09e96eb5c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0152_00404b973831c85e111225d641d987d09e96eb5c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/404b973831c85e111225d641d987d09e96eb5c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00404b973831c85e111225d641d987d09e96eb5c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0153 blob 004117347eedf1d8ccee5375f4670ecb45c36b43" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0153_004117347eedf1d8ccee5375f4670ecb45c36b43.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4117347eedf1d8ccee5375f4670ecb45c36b43",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004117347eedf1d8ccee5375f4670ecb45c36b43",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0154 blob 004182c99d27a6a5825d2429f9104fc7a8f1dc80" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0154_004182c99d27a6a5825d2429f9104fc7a8f1dc80.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4182c99d27a6a5825d2429f9104fc7a8f1dc80",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004182c99d27a6a5825d2429f9104fc7a8f1dc80",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0155 blob 0041994443c42033ee7c378ffad8983b0163489e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0155_0041994443c42033ee7c378ffad8983b0163489e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/41994443c42033ee7c378ffad8983b0163489e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0041994443c42033ee7c378ffad8983b0163489e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0156 blob 0041aecae02e131bfc249ffa40ec702c865e8b45" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0156_0041aecae02e131bfc249ffa40ec702c865e8b45.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/41aecae02e131bfc249ffa40ec702c865e8b45",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0041aecae02e131bfc249ffa40ec702c865e8b45",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0157 blob 00421453ba26327b929fa7b5133a3072fce2bb03" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0157_00421453ba26327b929fa7b5133a3072fce2bb03.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/421453ba26327b929fa7b5133a3072fce2bb03",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00421453ba26327b929fa7b5133a3072fce2bb03",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0158 blob 00424c296d19e3812115659cdc3dc82a68359e85" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0158_00424c296d19e3812115659cdc3dc82a68359e85.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/424c296d19e3812115659cdc3dc82a68359e85",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00424c296d19e3812115659cdc3dc82a68359e85",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0159 blob 004289209191d0990ed2353b83338a1df05ace0c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0159_004289209191d0990ed2353b83338a1df05ace0c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4289209191d0990ed2353b83338a1df05ace0c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004289209191d0990ed2353b83338a1df05ace0c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0160 blob 004383bf9ba48b6c765834a76bf92c20713a1a62" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0160_004383bf9ba48b6c765834a76bf92c20713a1a62.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4383bf9ba48b6c765834a76bf92c20713a1a62",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004383bf9ba48b6c765834a76bf92c20713a1a62",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0161 blob 0043930ca6ab31f6cd6a0bf6464ceb281663f9e8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0161_0043930ca6ab31f6cd6a0bf6464ceb281663f9e8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/43930ca6ab31f6cd6a0bf6464ceb281663f9e8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0043930ca6ab31f6cd6a0bf6464ceb281663f9e8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0162 blob 0043c1694cbc86e78477f038ef6018e71b96983f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0162_0043c1694cbc86e78477f038ef6018e71b96983f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/43c1694cbc86e78477f038ef6018e71b96983f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0043c1694cbc86e78477f038ef6018e71b96983f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0163 blob 0044abf66952c9ed7c50e7ed20b667e6dd386681" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0163_0044abf66952c9ed7c50e7ed20b667e6dd386681.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/44abf66952c9ed7c50e7ed20b667e6dd386681",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0044abf66952c9ed7c50e7ed20b667e6dd386681",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0164 blob 0044eecd9aa39afa476dcfb8e6eeaaa89fb08b86" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0164_0044eecd9aa39afa476dcfb8e6eeaaa89fb08b86.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/44eecd9aa39afa476dcfb8e6eeaaa89fb08b86",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0044eecd9aa39afa476dcfb8e6eeaaa89fb08b86",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0165 blob 00457940cfc163fed58b0206f5167c25c2c71b8a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0165_00457940cfc163fed58b0206f5167c25c2c71b8a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/457940cfc163fed58b0206f5167c25c2c71b8a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00457940cfc163fed58b0206f5167c25c2c71b8a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0166 blob 00461ee86b3c2a4d46554dbf0354fbcbb1caeedd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0166_00461ee86b3c2a4d46554dbf0354fbcbb1caeedd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/461ee86b3c2a4d46554dbf0354fbcbb1caeedd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00461ee86b3c2a4d46554dbf0354fbcbb1caeedd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0167 blob 0046a87c579122bdb35351b7f6ac5eb2e642e585" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0167_0046a87c579122bdb35351b7f6ac5eb2e642e585.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/46a87c579122bdb35351b7f6ac5eb2e642e585",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0046a87c579122bdb35351b7f6ac5eb2e642e585",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0168 blob 0046d4e28fad8401109dffb326bb7fdc1659ea2c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0168_0046d4e28fad8401109dffb326bb7fdc1659ea2c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/46d4e28fad8401109dffb326bb7fdc1659ea2c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0046d4e28fad8401109dffb326bb7fdc1659ea2c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0169 blob 00472a47135c49de235ee59f9f43d9698c47ea18" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0169_00472a47135c49de235ee59f9f43d9698c47ea18.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/472a47135c49de235ee59f9f43d9698c47ea18",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00472a47135c49de235ee59f9f43d9698c47ea18",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0170 blob 0047b541fdd0a98aefb18ac9c1cfbaf8d22d238c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0170_0047b541fdd0a98aefb18ac9c1cfbaf8d22d238c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/47b541fdd0a98aefb18ac9c1cfbaf8d22d238c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0047b541fdd0a98aefb18ac9c1cfbaf8d22d238c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0171 blob 0048ec7b6f6759641ec0e5265b067d739d74b6ba" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0171_0048ec7b6f6759641ec0e5265b067d739d74b6ba.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/48ec7b6f6759641ec0e5265b067d739d74b6ba",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0048ec7b6f6759641ec0e5265b067d739d74b6ba",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0172 blob 0048f9ef7fee24e5e058ef226f3b0fc93703fcf1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0172_0048f9ef7fee24e5e058ef226f3b0fc93703fcf1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/48f9ef7fee24e5e058ef226f3b0fc93703fcf1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0048f9ef7fee24e5e058ef226f3b0fc93703fcf1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0173 blob 00492c19b060253f50f53b3899e3413f15d25216" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0173_00492c19b060253f50f53b3899e3413f15d25216.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/492c19b060253f50f53b3899e3413f15d25216",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00492c19b060253f50f53b3899e3413f15d25216",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0174 blob 0049342f5c0daf79f6818ac6dea89a8ea7692d8a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0174_0049342f5c0daf79f6818ac6dea89a8ea7692d8a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/49342f5c0daf79f6818ac6dea89a8ea7692d8a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0049342f5c0daf79f6818ac6dea89a8ea7692d8a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0175 blob 0049f65503eb861305ca2dc1484bba1bd950d568" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0175_0049f65503eb861305ca2dc1484bba1bd950d568.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/49f65503eb861305ca2dc1484bba1bd950d568",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0049f65503eb861305ca2dc1484bba1bd950d568",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0176 blob 004a8dc5ed28f57de76935c4f02803fe6496d4d6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0176_004a8dc5ed28f57de76935c4f02803fe6496d4d6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4a8dc5ed28f57de76935c4f02803fe6496d4d6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004a8dc5ed28f57de76935c4f02803fe6496d4d6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0177 blob 004abf415b8e5dd93eba0a9b0929587272565d37" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0177_004abf415b8e5dd93eba0a9b0929587272565d37.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4abf415b8e5dd93eba0a9b0929587272565d37",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004abf415b8e5dd93eba0a9b0929587272565d37",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0178 blob 004b21cd1535bce39b24fc3db079f92baba7c989" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0178_004b21cd1535bce39b24fc3db079f92baba7c989.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4b21cd1535bce39b24fc3db079f92baba7c989",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004b21cd1535bce39b24fc3db079f92baba7c989",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0179 blob 004b707fdf475773764083a2b349850e613f48e0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0179_004b707fdf475773764083a2b349850e613f48e0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4b707fdf475773764083a2b349850e613f48e0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004b707fdf475773764083a2b349850e613f48e0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0180 blob 004b816635bf1628bfe7697f737a22cbcd27622b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0180_004b816635bf1628bfe7697f737a22cbcd27622b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4b816635bf1628bfe7697f737a22cbcd27622b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004b816635bf1628bfe7697f737a22cbcd27622b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0181 blob 004bee5e368f24963d925af997aec051189e1acf" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0181_004bee5e368f24963d925af997aec051189e1acf.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4bee5e368f24963d925af997aec051189e1acf",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004bee5e368f24963d925af997aec051189e1acf",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0182 blob 004bfebe983928547d7944dd0343840b358ab79b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0182_004bfebe983928547d7944dd0343840b358ab79b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4bfebe983928547d7944dd0343840b358ab79b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004bfebe983928547d7944dd0343840b358ab79b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0183 blob 004c034bc09449416ff6d66b7570d48b651f96cb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0183_004c034bc09449416ff6d66b7570d48b651f96cb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4c034bc09449416ff6d66b7570d48b651f96cb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004c034bc09449416ff6d66b7570d48b651f96cb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0184 blob 004c2169c97c167ada9c8da68aad3998b61501ea" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0184_004c2169c97c167ada9c8da68aad3998b61501ea.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4c2169c97c167ada9c8da68aad3998b61501ea",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004c2169c97c167ada9c8da68aad3998b61501ea",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0185 blob 004c2bd44684c56a26e68879facdf50875b4dcf6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0185_004c2bd44684c56a26e68879facdf50875b4dcf6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4c2bd44684c56a26e68879facdf50875b4dcf6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004c2bd44684c56a26e68879facdf50875b4dcf6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0186 blob 004c365ad6b32fff16c3c96ef2b6a173157b02a8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0186_004c365ad6b32fff16c3c96ef2b6a173157b02a8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4c365ad6b32fff16c3c96ef2b6a173157b02a8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004c365ad6b32fff16c3c96ef2b6a173157b02a8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0187 blob 004d5884cd2a4e76e940e03ca011bd1a70504d97" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0187_004d5884cd2a4e76e940e03ca011bd1a70504d97.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4d5884cd2a4e76e940e03ca011bd1a70504d97",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004d5884cd2a4e76e940e03ca011bd1a70504d97",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0188 blob 004eda2acdf9b8ac5a66f9717d2244613b23768e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0188_004eda2acdf9b8ac5a66f9717d2244613b23768e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4eda2acdf9b8ac5a66f9717d2244613b23768e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004eda2acdf9b8ac5a66f9717d2244613b23768e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0189 blob 0050c62bd5e0723d2f911d2ced5edb8030a613ce" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0189_0050c62bd5e0723d2f911d2ced5edb8030a613ce.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/50c62bd5e0723d2f911d2ced5edb8030a613ce",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0050c62bd5e0723d2f911d2ced5edb8030a613ce",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0190 blob 00521fe51ed8d888afb9a21e77af38eae7e39a48" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0190_00521fe51ed8d888afb9a21e77af38eae7e39a48.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/521fe51ed8d888afb9a21e77af38eae7e39a48",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00521fe51ed8d888afb9a21e77af38eae7e39a48",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0191 blob 00528ddc389212f045a7718ba55a26d723927f06" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0191_00528ddc389212f045a7718ba55a26d723927f06.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/528ddc389212f045a7718ba55a26d723927f06",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00528ddc389212f045a7718ba55a26d723927f06",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0192 blob 0052b72d9c230d937fc66633358e7aefbe379042" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0192_0052b72d9c230d937fc66633358e7aefbe379042.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/52b72d9c230d937fc66633358e7aefbe379042",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0052b72d9c230d937fc66633358e7aefbe379042",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0193 blob 0052c6a4dce1fad808a5bdd2c92c0827c5453d18" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0193_0052c6a4dce1fad808a5bdd2c92c0827c5453d18.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/52c6a4dce1fad808a5bdd2c92c0827c5453d18",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0052c6a4dce1fad808a5bdd2c92c0827c5453d18",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0194 blob 00535d0178f1a0ee562bf008e8b072f68410dc3d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0194_00535d0178f1a0ee562bf008e8b072f68410dc3d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/535d0178f1a0ee562bf008e8b072f68410dc3d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00535d0178f1a0ee562bf008e8b072f68410dc3d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0195 blob 00537d8907872aa25c39f07513ef661b1bef1f17" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0195_00537d8907872aa25c39f07513ef661b1bef1f17.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/537d8907872aa25c39f07513ef661b1bef1f17",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00537d8907872aa25c39f07513ef661b1bef1f17",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0196 blob 0053b09549ab419ab8f2da2c519d689f5e0d83b3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0196_0053b09549ab419ab8f2da2c519d689f5e0d83b3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/53b09549ab419ab8f2da2c519d689f5e0d83b3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0053b09549ab419ab8f2da2c519d689f5e0d83b3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0197 blob 00543f720aca0237bdb3fd7b613a215f1453ac83" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0197_00543f720aca0237bdb3fd7b613a215f1453ac83.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/543f720aca0237bdb3fd7b613a215f1453ac83",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00543f720aca0237bdb3fd7b613a215f1453ac83",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0198 blob 0054883a5e18aaacc682bb8369c6f0376cf75306" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0198_0054883a5e18aaacc682bb8369c6f0376cf75306.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/54883a5e18aaacc682bb8369c6f0376cf75306",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0054883a5e18aaacc682bb8369c6f0376cf75306",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0199 blob 0055a57aeb24392de0dcf337bb93f30fceccd88f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0199_0055a57aeb24392de0dcf337bb93f30fceccd88f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/55a57aeb24392de0dcf337bb93f30fceccd88f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0055a57aeb24392de0dcf337bb93f30fceccd88f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0200 blob 0055da965ca189f8ecb220e1a916c0b6714eb2b2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0200_0055da965ca189f8ecb220e1a916c0b6714eb2b2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/55da965ca189f8ecb220e1a916c0b6714eb2b2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0055da965ca189f8ecb220e1a916c0b6714eb2b2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0201 blob 0055ebba46d539f30b9484335501571c3b4879bd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0201_0055ebba46d539f30b9484335501571c3b4879bd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/55ebba46d539f30b9484335501571c3b4879bd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0055ebba46d539f30b9484335501571c3b4879bd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0202 blob 0055eef24d855e9cd3a62620a70cad7c2008ea88" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0202_0055eef24d855e9cd3a62620a70cad7c2008ea88.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/55eef24d855e9cd3a62620a70cad7c2008ea88",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0055eef24d855e9cd3a62620a70cad7c2008ea88",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0203 blob 005674d8c18d43c61c69ee64a134883d2391fcdf" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0203_005674d8c18d43c61c69ee64a134883d2391fcdf.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5674d8c18d43c61c69ee64a134883d2391fcdf",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005674d8c18d43c61c69ee64a134883d2391fcdf",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0204 blob 0057392f988fdbaebc55628585b5d519e93307ed" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0204_0057392f988fdbaebc55628585b5d519e93307ed.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/57392f988fdbaebc55628585b5d519e93307ed",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0057392f988fdbaebc55628585b5d519e93307ed",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0205 blob 0057f865886753afb9493a2e82b11fe14aa91529" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0205_0057f865886753afb9493a2e82b11fe14aa91529.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/57f865886753afb9493a2e82b11fe14aa91529",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0057f865886753afb9493a2e82b11fe14aa91529",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0206 blob 0058619ca6742ae29b4f50d7188b0fc19d87f45b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0206_0058619ca6742ae29b4f50d7188b0fc19d87f45b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/58619ca6742ae29b4f50d7188b0fc19d87f45b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0058619ca6742ae29b4f50d7188b0fc19d87f45b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0207 blob 0058bd42aac473e157b4a2a7c22187249f457934" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0207_0058bd42aac473e157b4a2a7c22187249f457934.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/58bd42aac473e157b4a2a7c22187249f457934",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0058bd42aac473e157b4a2a7c22187249f457934",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0208 blob 0058fa5b4365d290ccdb0ed64f6a23eb6f195527" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0208_0058fa5b4365d290ccdb0ed64f6a23eb6f195527.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/58fa5b4365d290ccdb0ed64f6a23eb6f195527",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0058fa5b4365d290ccdb0ed64f6a23eb6f195527",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0209 blob 00590b1c3c2cceda7a75537c8680a96cd2ef84d4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0209_00590b1c3c2cceda7a75537c8680a96cd2ef84d4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/590b1c3c2cceda7a75537c8680a96cd2ef84d4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00590b1c3c2cceda7a75537c8680a96cd2ef84d4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0210 blob 0059a1f837882c504e717135c9c92bc5b1d7f62c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0210_0059a1f837882c504e717135c9c92bc5b1d7f62c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/59a1f837882c504e717135c9c92bc5b1d7f62c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0059a1f837882c504e717135c9c92bc5b1d7f62c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0211 blob 005adbebea80a83a8d0dbb1de744cb50bf689de6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0211_005adbebea80a83a8d0dbb1de744cb50bf689de6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5adbebea80a83a8d0dbb1de744cb50bf689de6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005adbebea80a83a8d0dbb1de744cb50bf689de6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0212 blob 005c5a51c08b046ed62034deeef0ea42967b1c1a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0212_005c5a51c08b046ed62034deeef0ea42967b1c1a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5c5a51c08b046ed62034deeef0ea42967b1c1a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005c5a51c08b046ed62034deeef0ea42967b1c1a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0213 blob 005c820aa42e1f3c98bd2c1a376bd3a52bfc32a2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0213_005c820aa42e1f3c98bd2c1a376bd3a52bfc32a2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5c820aa42e1f3c98bd2c1a376bd3a52bfc32a2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005c820aa42e1f3c98bd2c1a376bd3a52bfc32a2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0214 blob 005ca670b4b495887e6b591208e0c88229a40af6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0214_005ca670b4b495887e6b591208e0c88229a40af6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5ca670b4b495887e6b591208e0c88229a40af6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005ca670b4b495887e6b591208e0c88229a40af6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0215 blob 005caf61646ec74a448000564ca75038bb342142" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0215_005caf61646ec74a448000564ca75038bb342142.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5caf61646ec74a448000564ca75038bb342142",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005caf61646ec74a448000564ca75038bb342142",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0216 blob 005d66dbef6c361363752b37087bbbc6a3098833" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0216_005d66dbef6c361363752b37087bbbc6a3098833.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5d66dbef6c361363752b37087bbbc6a3098833",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005d66dbef6c361363752b37087bbbc6a3098833",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0217 blob 005e2b1756d1f04bfc6fcb68d9b336d089cdbf92" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0217_005e2b1756d1f04bfc6fcb68d9b336d089cdbf92.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5e2b1756d1f04bfc6fcb68d9b336d089cdbf92",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005e2b1756d1f04bfc6fcb68d9b336d089cdbf92",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0218 blob 005f415d368d7bd9202a9b06fcf0ebcdd6199635" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0218_005f415d368d7bd9202a9b06fcf0ebcdd6199635.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5f415d368d7bd9202a9b06fcf0ebcdd6199635",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005f415d368d7bd9202a9b06fcf0ebcdd6199635",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0219 blob 005f55aaa257fc34f81517650223a3c195c03178" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0219_005f55aaa257fc34f81517650223a3c195c03178.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5f55aaa257fc34f81517650223a3c195c03178",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005f55aaa257fc34f81517650223a3c195c03178",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0220 blob 005f74481625e88a4f36bd5f17d339c1924778c4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0220_005f74481625e88a4f36bd5f17d339c1924778c4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5f74481625e88a4f36bd5f17d339c1924778c4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005f74481625e88a4f36bd5f17d339c1924778c4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0221 blob 006016267e2cca3302770be3c923ef996254da01" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0221_006016267e2cca3302770be3c923ef996254da01.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6016267e2cca3302770be3c923ef996254da01",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006016267e2cca3302770be3c923ef996254da01",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0222 blob 00611107d20293b06157019dd6ff214a6dd0f286" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0222_00611107d20293b06157019dd6ff214a6dd0f286.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/611107d20293b06157019dd6ff214a6dd0f286",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00611107d20293b06157019dd6ff214a6dd0f286",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0223 blob 006134043a472edd54720d6d4237e9484476d3a3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0223_006134043a472edd54720d6d4237e9484476d3a3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6134043a472edd54720d6d4237e9484476d3a3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006134043a472edd54720d6d4237e9484476d3a3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0224 blob 0062341dbf156e022288045662db3825a71acc04" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0224_0062341dbf156e022288045662db3825a71acc04.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/62341dbf156e022288045662db3825a71acc04",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0062341dbf156e022288045662db3825a71acc04",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0225 blob 006321e009b321db6cf4f7bf35d8385017a7076a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0225_006321e009b321db6cf4f7bf35d8385017a7076a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6321e009b321db6cf4f7bf35d8385017a7076a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006321e009b321db6cf4f7bf35d8385017a7076a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0226 blob 0063559aab6e233abd0a69aef6cead9d01e39948" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0226_0063559aab6e233abd0a69aef6cead9d01e39948.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/63559aab6e233abd0a69aef6cead9d01e39948",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0063559aab6e233abd0a69aef6cead9d01e39948",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0227 blob 00635816156ba35feea882b48bfc79d93ff9338a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0227_00635816156ba35feea882b48bfc79d93ff9338a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/635816156ba35feea882b48bfc79d93ff9338a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00635816156ba35feea882b48bfc79d93ff9338a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0228 blob 0063606b55e5a3757810647447b523af665eff3a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0228_0063606b55e5a3757810647447b523af665eff3a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/63606b55e5a3757810647447b523af665eff3a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0063606b55e5a3757810647447b523af665eff3a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0229 blob 0064299c0e0cbe3e133d4464f2ab65d89324a0ab" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0229_0064299c0e0cbe3e133d4464f2ab65d89324a0ab.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/64299c0e0cbe3e133d4464f2ab65d89324a0ab",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0064299c0e0cbe3e133d4464f2ab65d89324a0ab",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0230 blob 0064788b252cadb98b71eec4d3517f92c88bba86" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0230_0064788b252cadb98b71eec4d3517f92c88bba86.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/64788b252cadb98b71eec4d3517f92c88bba86",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0064788b252cadb98b71eec4d3517f92c88bba86",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0231 blob 0064eb64f546a6349a8694ce251bd352febda6fe" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0231_0064eb64f546a6349a8694ce251bd352febda6fe.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/64eb64f546a6349a8694ce251bd352febda6fe",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0064eb64f546a6349a8694ce251bd352febda6fe",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0232 blob 00651c25cb4089a4d7334ad00f6ebc8e51bafb0f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0232_00651c25cb4089a4d7334ad00f6ebc8e51bafb0f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/651c25cb4089a4d7334ad00f6ebc8e51bafb0f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00651c25cb4089a4d7334ad00f6ebc8e51bafb0f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0233 blob 0065843d17aa8ba509c59b2f94bb8a7f864b3517" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0233_0065843d17aa8ba509c59b2f94bb8a7f864b3517.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/65843d17aa8ba509c59b2f94bb8a7f864b3517",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0065843d17aa8ba509c59b2f94bb8a7f864b3517",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0234 blob 00663f6a3003976aaa33f08ae7309fc190ea4748" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0234_00663f6a3003976aaa33f08ae7309fc190ea4748.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/663f6a3003976aaa33f08ae7309fc190ea4748",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00663f6a3003976aaa33f08ae7309fc190ea4748",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0235 blob 0066594fa6310b37903972e150c7cd1d7e232c38" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0235_0066594fa6310b37903972e150c7cd1d7e232c38.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/66594fa6310b37903972e150c7cd1d7e232c38",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0066594fa6310b37903972e150c7cd1d7e232c38",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0236 blob 006709a645aea2ddbc914673710e66fa2343d569" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0236_006709a645aea2ddbc914673710e66fa2343d569.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6709a645aea2ddbc914673710e66fa2343d569",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006709a645aea2ddbc914673710e66fa2343d569",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0237 blob 00679262625f273c18b9444281e1b607598e063d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0237_00679262625f273c18b9444281e1b607598e063d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/679262625f273c18b9444281e1b607598e063d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00679262625f273c18b9444281e1b607598e063d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0238 blob 00682e638d7294b6584e4ed2f0ed7c8d2c151d6b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0238_00682e638d7294b6584e4ed2f0ed7c8d2c151d6b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/682e638d7294b6584e4ed2f0ed7c8d2c151d6b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00682e638d7294b6584e4ed2f0ed7c8d2c151d6b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0239 blob 00691fcd82f13a55d06b3413a3fa2757a4c58269" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0239_00691fcd82f13a55d06b3413a3fa2757a4c58269.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/691fcd82f13a55d06b3413a3fa2757a4c58269",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00691fcd82f13a55d06b3413a3fa2757a4c58269",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0240 blob 006972a1f20fc334b88a32d6aa61687fe4a1c4e3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0240_006972a1f20fc334b88a32d6aa61687fe4a1c4e3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6972a1f20fc334b88a32d6aa61687fe4a1c4e3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006972a1f20fc334b88a32d6aa61687fe4a1c4e3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0241 blob 006a50b5481b552278931f5aec33883d79891a80" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0241_006a50b5481b552278931f5aec33883d79891a80.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6a50b5481b552278931f5aec33883d79891a80",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006a50b5481b552278931f5aec33883d79891a80",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0242 blob 006a968d14825346201b759caf114ee1c43cd9df" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0242_006a968d14825346201b759caf114ee1c43cd9df.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6a968d14825346201b759caf114ee1c43cd9df",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006a968d14825346201b759caf114ee1c43cd9df",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0243 blob 006b212057055d1437e62f1caa7bec513c7392fb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0243_006b212057055d1437e62f1caa7bec513c7392fb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6b212057055d1437e62f1caa7bec513c7392fb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006b212057055d1437e62f1caa7bec513c7392fb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0244 blob 006b94baf2991d5c81dcc02f86da66473e949626" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0244_006b94baf2991d5c81dcc02f86da66473e949626.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6b94baf2991d5c81dcc02f86da66473e949626",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006b94baf2991d5c81dcc02f86da66473e949626",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0245 blob 006bedafb7aa3f72f0261ef77a7c162eb22b1059" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0245_006bedafb7aa3f72f0261ef77a7c162eb22b1059.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6bedafb7aa3f72f0261ef77a7c162eb22b1059",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006bedafb7aa3f72f0261ef77a7c162eb22b1059",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0246 blob 006c1f4ba541cb3fa6679604326934d7e486bb9f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0246_006c1f4ba541cb3fa6679604326934d7e486bb9f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6c1f4ba541cb3fa6679604326934d7e486bb9f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006c1f4ba541cb3fa6679604326934d7e486bb9f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0247 blob 006d2a8152dc499f3588b130470285703b60dc92" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0247_006d2a8152dc499f3588b130470285703b60dc92.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6d2a8152dc499f3588b130470285703b60dc92",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006d2a8152dc499f3588b130470285703b60dc92",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0248 blob 006d759962ac61a927d2a08bfa831d1692cc63c4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0248_006d759962ac61a927d2a08bfa831d1692cc63c4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6d759962ac61a927d2a08bfa831d1692cc63c4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006d759962ac61a927d2a08bfa831d1692cc63c4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0249 blob 006e76672631f679097d50f8db71f58cd7e677d6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0249_006e76672631f679097d50f8db71f58cd7e677d6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6e76672631f679097d50f8db71f58cd7e677d6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006e76672631f679097d50f8db71f58cd7e677d6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0250 blob 006edf6b1945de1962cf17185cb7639fe41ad494" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0250_006edf6b1945de1962cf17185cb7639fe41ad494.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6edf6b1945de1962cf17185cb7639fe41ad494",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006edf6b1945de1962cf17185cb7639fe41ad494",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0251 blob 006fd08769dcf01c20b0c23dd7cf6c4aae931c68" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0251_006fd08769dcf01c20b0c23dd7cf6c4aae931c68.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6fd08769dcf01c20b0c23dd7cf6c4aae931c68",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006fd08769dcf01c20b0c23dd7cf6c4aae931c68",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0252 blob 006feb7ec149561e8f99069ab5153912dbd53661" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0252_006feb7ec149561e8f99069ab5153912dbd53661.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6feb7ec149561e8f99069ab5153912dbd53661",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006feb7ec149561e8f99069ab5153912dbd53661",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0253 blob 006fecbe38ae6ea4c0933807e9a87d79e61b3d57" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0253_006fecbe38ae6ea4c0933807e9a87d79e61b3d57.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6fecbe38ae6ea4c0933807e9a87d79e61b3d57",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006fecbe38ae6ea4c0933807e9a87d79e61b3d57",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0254 blob 006ffdc9c550d75a034960635f13d87b33dc57cc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0254_006ffdc9c550d75a034960635f13d87b33dc57cc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6ffdc9c550d75a034960635f13d87b33dc57cc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006ffdc9c550d75a034960635f13d87b33dc57cc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0255 blob 0070bf255612ea9d4826720df7a77dd8ccb762e8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0255_0070bf255612ea9d4826720df7a77dd8ccb762e8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/70bf255612ea9d4826720df7a77dd8ccb762e8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0070bf255612ea9d4826720df7a77dd8ccb762e8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0256 blob 00710b97812b033db91c1e76c8b441936d92a7d1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0256_00710b97812b033db91c1e76c8b441936d92a7d1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/710b97812b033db91c1e76c8b441936d92a7d1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00710b97812b033db91c1e76c8b441936d92a7d1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0257 blob 00721600184e50466f31d236001c20577e60db7a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0257_00721600184e50466f31d236001c20577e60db7a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/721600184e50466f31d236001c20577e60db7a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00721600184e50466f31d236001c20577e60db7a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0258 blob 007278cc119fded9f97832d87ffe5d6b95a5ce41" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0258_007278cc119fded9f97832d87ffe5d6b95a5ce41.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7278cc119fded9f97832d87ffe5d6b95a5ce41",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007278cc119fded9f97832d87ffe5d6b95a5ce41",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0259 blob 0072d5598926ebc4dbe35f71dc805c465e8575af" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0259_0072d5598926ebc4dbe35f71dc805c465e8575af.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/72d5598926ebc4dbe35f71dc805c465e8575af",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0072d5598926ebc4dbe35f71dc805c465e8575af",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0260 blob 0073e9df5f0e39738107f07919a6f12eafa5ae65" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0260_0073e9df5f0e39738107f07919a6f12eafa5ae65.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/73e9df5f0e39738107f07919a6f12eafa5ae65",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0073e9df5f0e39738107f07919a6f12eafa5ae65",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0261 blob 00740bd6796785cedd8d6baf730016f93a379cd8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0261_00740bd6796785cedd8d6baf730016f93a379cd8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/740bd6796785cedd8d6baf730016f93a379cd8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00740bd6796785cedd8d6baf730016f93a379cd8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0262 blob 0074bc9b8948693d0dcd7957e1f9511bc50e43bf" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0262_0074bc9b8948693d0dcd7957e1f9511bc50e43bf.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/74bc9b8948693d0dcd7957e1f9511bc50e43bf",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0074bc9b8948693d0dcd7957e1f9511bc50e43bf",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0263 blob 0074d6bc43dd2e97065d522a592709cec1e06196" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0263_0074d6bc43dd2e97065d522a592709cec1e06196.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/74d6bc43dd2e97065d522a592709cec1e06196",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0074d6bc43dd2e97065d522a592709cec1e06196",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0264 blob 0074ed311c8b6c26770f62a668f51abda316ec46" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0264_0074ed311c8b6c26770f62a668f51abda316ec46.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/74ed311c8b6c26770f62a668f51abda316ec46",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0074ed311c8b6c26770f62a668f51abda316ec46",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0265 blob 0075ac5c2a8745513e1e8c496ca6e276158c8d2b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0265_0075ac5c2a8745513e1e8c496ca6e276158c8d2b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/75ac5c2a8745513e1e8c496ca6e276158c8d2b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0075ac5c2a8745513e1e8c496ca6e276158c8d2b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0266 blob 00760ecc6532825c97eb22381edc88e7fb01432d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0266_00760ecc6532825c97eb22381edc88e7fb01432d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/760ecc6532825c97eb22381edc88e7fb01432d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00760ecc6532825c97eb22381edc88e7fb01432d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0267 blob 00761e408015ddf60e1ce2cd5ab18032f79e3c68" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0267_00761e408015ddf60e1ce2cd5ab18032f79e3c68.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/761e408015ddf60e1ce2cd5ab18032f79e3c68",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00761e408015ddf60e1ce2cd5ab18032f79e3c68",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0268 blob 0076fc5b20a71b4d32add42b8dcb76a22eea4ef6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0268_0076fc5b20a71b4d32add42b8dcb76a22eea4ef6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/76fc5b20a71b4d32add42b8dcb76a22eea4ef6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0076fc5b20a71b4d32add42b8dcb76a22eea4ef6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0269 blob 0077dbd50b516c9614573b5c6197fc627802527e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0269_0077dbd50b516c9614573b5c6197fc627802527e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/77dbd50b516c9614573b5c6197fc627802527e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0077dbd50b516c9614573b5c6197fc627802527e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0270 blob 00786606117feea4b33b7e632b8ff8a3c26de4e4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0270_00786606117feea4b33b7e632b8ff8a3c26de4e4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/786606117feea4b33b7e632b8ff8a3c26de4e4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00786606117feea4b33b7e632b8ff8a3c26de4e4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0271 blob 00787e306db4c010ae68845f27ed69966fb9e250" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0271_00787e306db4c010ae68845f27ed69966fb9e250.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/787e306db4c010ae68845f27ed69966fb9e250",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00787e306db4c010ae68845f27ed69966fb9e250",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0272 blob 007899bb4e4aeca84d125639d6f466a48b67d329" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0272_007899bb4e4aeca84d125639d6f466a48b67d329.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7899bb4e4aeca84d125639d6f466a48b67d329",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007899bb4e4aeca84d125639d6f466a48b67d329",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0273 blob 0078faf117e112e60244517f451ed6cbc3cf2f39" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0273_0078faf117e112e60244517f451ed6cbc3cf2f39.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/78faf117e112e60244517f451ed6cbc3cf2f39",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0078faf117e112e60244517f451ed6cbc3cf2f39",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0274 blob 007909a82fe77325e46c54799d00dc78493a47f9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0274_007909a82fe77325e46c54799d00dc78493a47f9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7909a82fe77325e46c54799d00dc78493a47f9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007909a82fe77325e46c54799d00dc78493a47f9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0275 blob 0079cb31ff277c26c5395b1c7ce4377c4a06815c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0275_0079cb31ff277c26c5395b1c7ce4377c4a06815c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/79cb31ff277c26c5395b1c7ce4377c4a06815c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0079cb31ff277c26c5395b1c7ce4377c4a06815c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0276 blob 007a0554d4b252e83e98f5578758d51ec0c6e120" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0276_007a0554d4b252e83e98f5578758d51ec0c6e120.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7a0554d4b252e83e98f5578758d51ec0c6e120",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007a0554d4b252e83e98f5578758d51ec0c6e120",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0277 blob 007a1bfdf37d231470f69d9d0cffa46e80127f34" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0277_007a1bfdf37d231470f69d9d0cffa46e80127f34.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7a1bfdf37d231470f69d9d0cffa46e80127f34",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007a1bfdf37d231470f69d9d0cffa46e80127f34",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0278 blob 007a392cf906c7a69fdafc883deb8cc8ff386d49" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0278_007a392cf906c7a69fdafc883deb8cc8ff386d49.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7a392cf906c7a69fdafc883deb8cc8ff386d49",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007a392cf906c7a69fdafc883deb8cc8ff386d49",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0279 blob 007a806994fd606984f9b28c51a61eee16bc9140" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0279_007a806994fd606984f9b28c51a61eee16bc9140.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7a806994fd606984f9b28c51a61eee16bc9140",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007a806994fd606984f9b28c51a61eee16bc9140",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0280 blob 007b136fe64b1afb6b398dd3a2790aeabc2bd127" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0280_007b136fe64b1afb6b398dd3a2790aeabc2bd127.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7b136fe64b1afb6b398dd3a2790aeabc2bd127",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007b136fe64b1afb6b398dd3a2790aeabc2bd127",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0281 blob 007b29b8bb4cf27b619467d69a88ef5c79db282d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0281_007b29b8bb4cf27b619467d69a88ef5c79db282d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7b29b8bb4cf27b619467d69a88ef5c79db282d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007b29b8bb4cf27b619467d69a88ef5c79db282d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0282 blob 007b540f4e825830275fcea889652f2917d7e5be" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0282_007b540f4e825830275fcea889652f2917d7e5be.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7b540f4e825830275fcea889652f2917d7e5be",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007b540f4e825830275fcea889652f2917d7e5be",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0283 blob 007b78eb248b5eab61f7f39942ad6d798a0c8cfa" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0283_007b78eb248b5eab61f7f39942ad6d798a0c8cfa.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7b78eb248b5eab61f7f39942ad6d798a0c8cfa",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007b78eb248b5eab61f7f39942ad6d798a0c8cfa",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0284 blob 007bba67950ab45f3310410ebc16081b5307e7b4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0284_007bba67950ab45f3310410ebc16081b5307e7b4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7bba67950ab45f3310410ebc16081b5307e7b4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007bba67950ab45f3310410ebc16081b5307e7b4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0285 blob 007bc065dd88d6fbbde553c550c58b363fc29c40" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0285_007bc065dd88d6fbbde553c550c58b363fc29c40.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7bc065dd88d6fbbde553c550c58b363fc29c40",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007bc065dd88d6fbbde553c550c58b363fc29c40",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0286 blob 007cc66a036429d602cf7afe19c163fcf6d06395" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0286_007cc66a036429d602cf7afe19c163fcf6d06395.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7cc66a036429d602cf7afe19c163fcf6d06395",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007cc66a036429d602cf7afe19c163fcf6d06395",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0287 blob 007d42b0383f3c8dbc9dba703260b9d1e785fac7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0287_007d42b0383f3c8dbc9dba703260b9d1e785fac7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7d42b0383f3c8dbc9dba703260b9d1e785fac7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007d42b0383f3c8dbc9dba703260b9d1e785fac7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0288 blob 007d7b20d8fe1be0f69e76215d51632c7df17205" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0288_007d7b20d8fe1be0f69e76215d51632c7df17205.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7d7b20d8fe1be0f69e76215d51632c7df17205",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007d7b20d8fe1be0f69e76215d51632c7df17205",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0289 blob 007dabf62f2574fc9214d6fb2a961619ad305a6b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0289_007dabf62f2574fc9214d6fb2a961619ad305a6b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7dabf62f2574fc9214d6fb2a961619ad305a6b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007dabf62f2574fc9214d6fb2a961619ad305a6b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0290 blob 007dd3e4d38ff657a29a06e559173b796f193763" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0290_007dd3e4d38ff657a29a06e559173b796f193763.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7dd3e4d38ff657a29a06e559173b796f193763",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007dd3e4d38ff657a29a06e559173b796f193763",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0291 blob 007e29a2edd64c4f103397bd62b5c33f98ff8382" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0291_007e29a2edd64c4f103397bd62b5c33f98ff8382.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7e29a2edd64c4f103397bd62b5c33f98ff8382",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007e29a2edd64c4f103397bd62b5c33f98ff8382",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0292 blob 007e2c6ee12db18152884c5ac9aa26eff224e36e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0292_007e2c6ee12db18152884c5ac9aa26eff224e36e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7e2c6ee12db18152884c5ac9aa26eff224e36e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007e2c6ee12db18152884c5ac9aa26eff224e36e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0293 blob 007e5af5f469664c89d2006fdc55a5fa85946582" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0293_007e5af5f469664c89d2006fdc55a5fa85946582.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7e5af5f469664c89d2006fdc55a5fa85946582",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007e5af5f469664c89d2006fdc55a5fa85946582",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0294 blob 007ec0d8eac529579cc00b14f9baaddb7ac68487" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0294_007ec0d8eac529579cc00b14f9baaddb7ac68487.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7ec0d8eac529579cc00b14f9baaddb7ac68487",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007ec0d8eac529579cc00b14f9baaddb7ac68487",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0295 blob 007f1a29954b590c5c3f046006e40d88b731aaa4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0295_007f1a29954b590c5c3f046006e40d88b731aaa4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7f1a29954b590c5c3f046006e40d88b731aaa4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007f1a29954b590c5c3f046006e40d88b731aaa4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0296 blob 007f2d78ea5b035a3c07b38b6fd5df5dee005273" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0296_007f2d78ea5b035a3c07b38b6fd5df5dee005273.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7f2d78ea5b035a3c07b38b6fd5df5dee005273",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007f2d78ea5b035a3c07b38b6fd5df5dee005273",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0297 blob 007f39d5e1dca6eff7e01969282c4cf2dc1bb57a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0297_007f39d5e1dca6eff7e01969282c4cf2dc1bb57a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7f39d5e1dca6eff7e01969282c4cf2dc1bb57a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007f39d5e1dca6eff7e01969282c4cf2dc1bb57a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0298 blob 00808500165068247826895c063aebce8e9901f7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0298_00808500165068247826895c063aebce8e9901f7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/808500165068247826895c063aebce8e9901f7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00808500165068247826895c063aebce8e9901f7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0299 blob 0081b96f2a92ca3768e2763dc97c379f2ffc5d7e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0299_0081b96f2a92ca3768e2763dc97c379f2ffc5d7e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/81b96f2a92ca3768e2763dc97c379f2ffc5d7e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0081b96f2a92ca3768e2763dc97c379f2ffc5d7e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0300 blob 00826778fc3d760a9b001423cd9c26e7972c126f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0300_00826778fc3d760a9b001423cd9c26e7972c126f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/826778fc3d760a9b001423cd9c26e7972c126f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00826778fc3d760a9b001423cd9c26e7972c126f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0301 blob 0082dadb73fb0767dd1e69001e485a2cbca6bf13" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0301_0082dadb73fb0767dd1e69001e485a2cbca6bf13.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/82dadb73fb0767dd1e69001e485a2cbca6bf13",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0082dadb73fb0767dd1e69001e485a2cbca6bf13",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0302 blob 008325f2a8f9d33723a10244d6fd13806914a6dc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0302_008325f2a8f9d33723a10244d6fd13806914a6dc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8325f2a8f9d33723a10244d6fd13806914a6dc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008325f2a8f9d33723a10244d6fd13806914a6dc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0303 blob 0083d92438916a8188656df140ba70d6acc8c6f6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0303_0083d92438916a8188656df140ba70d6acc8c6f6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/83d92438916a8188656df140ba70d6acc8c6f6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0083d92438916a8188656df140ba70d6acc8c6f6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0304 blob 00842678bd212236544e55f13661fd47aae2467f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0304_00842678bd212236544e55f13661fd47aae2467f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/842678bd212236544e55f13661fd47aae2467f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00842678bd212236544e55f13661fd47aae2467f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0305 blob 008456b675b6e5c8a5a07e0b8628a41e3acc733a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0305_008456b675b6e5c8a5a07e0b8628a41e3acc733a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8456b675b6e5c8a5a07e0b8628a41e3acc733a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008456b675b6e5c8a5a07e0b8628a41e3acc733a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0306 blob 0084709c8cd8c65c022879f8053413ff8c485cfd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0306_0084709c8cd8c65c022879f8053413ff8c485cfd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/84709c8cd8c65c022879f8053413ff8c485cfd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0084709c8cd8c65c022879f8053413ff8c485cfd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0307 blob 0084cf7400bd46ba7d8b72a908a67c3536abc907" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0307_0084cf7400bd46ba7d8b72a908a67c3536abc907.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/84cf7400bd46ba7d8b72a908a67c3536abc907",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0084cf7400bd46ba7d8b72a908a67c3536abc907",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0308 blob 00850864371e16d1fa572b0d0e5832b8a88d8666" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0308_00850864371e16d1fa572b0d0e5832b8a88d8666.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/850864371e16d1fa572b0d0e5832b8a88d8666",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00850864371e16d1fa572b0d0e5832b8a88d8666",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0309 blob 008513c2f135b5a77d1642ff88e272a7e2f9f9d5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0309_008513c2f135b5a77d1642ff88e272a7e2f9f9d5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8513c2f135b5a77d1642ff88e272a7e2f9f9d5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008513c2f135b5a77d1642ff88e272a7e2f9f9d5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0310 blob 0085fbb903291a836c67b3d8daaa5f8b2f54fd86" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0310_0085fbb903291a836c67b3d8daaa5f8b2f54fd86.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/85fbb903291a836c67b3d8daaa5f8b2f54fd86",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0085fbb903291a836c67b3d8daaa5f8b2f54fd86",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0311 blob 00862bc28ee7d94d0ca6218078e65faa1a1bdfad" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0311_00862bc28ee7d94d0ca6218078e65faa1a1bdfad.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/862bc28ee7d94d0ca6218078e65faa1a1bdfad",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00862bc28ee7d94d0ca6218078e65faa1a1bdfad",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0312 blob 0086bf18644d81ddb7b161142cc31a30dad1711e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0312_0086bf18644d81ddb7b161142cc31a30dad1711e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/86bf18644d81ddb7b161142cc31a30dad1711e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0086bf18644d81ddb7b161142cc31a30dad1711e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0313 blob 008822d67ccedd367fe010a261563adcca99227f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0313_008822d67ccedd367fe010a261563adcca99227f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8822d67ccedd367fe010a261563adcca99227f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008822d67ccedd367fe010a261563adcca99227f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0314 blob 0088eaa0c918aa4afd91d590f19f840e9a58661d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0314_0088eaa0c918aa4afd91d590f19f840e9a58661d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/88eaa0c918aa4afd91d590f19f840e9a58661d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0088eaa0c918aa4afd91d590f19f840e9a58661d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0315 blob 0089581e1dd55800302799a7381d4a7ad01bd79d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0315_0089581e1dd55800302799a7381d4a7ad01bd79d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/89581e1dd55800302799a7381d4a7ad01bd79d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0089581e1dd55800302799a7381d4a7ad01bd79d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0316 blob 008966cae4d6a08694d46f2534e0e0e2967a53fc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0316_008966cae4d6a08694d46f2534e0e0e2967a53fc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8966cae4d6a08694d46f2534e0e0e2967a53fc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008966cae4d6a08694d46f2534e0e0e2967a53fc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0317 blob 0089dd6702f7a09ba6e091a302a146bc16884989" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0317_0089dd6702f7a09ba6e091a302a146bc16884989.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/89dd6702f7a09ba6e091a302a146bc16884989",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0089dd6702f7a09ba6e091a302a146bc16884989",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0318 blob 0089e0cfb80df9a283b220ba4187e38f5612557d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0318_0089e0cfb80df9a283b220ba4187e38f5612557d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/89e0cfb80df9a283b220ba4187e38f5612557d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0089e0cfb80df9a283b220ba4187e38f5612557d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0319 blob 0089e52d9dff41bece11056e92625b923515c462" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0319_0089e52d9dff41bece11056e92625b923515c462.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/89e52d9dff41bece11056e92625b923515c462",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0089e52d9dff41bece11056e92625b923515c462",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0320 blob 008a0fa4a01d06c0e191e5988823ff630931d30d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0320_008a0fa4a01d06c0e191e5988823ff630931d30d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8a0fa4a01d06c0e191e5988823ff630931d30d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008a0fa4a01d06c0e191e5988823ff630931d30d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0321 blob 008a60c09dde780580c8eee7d2b08400a8c42b4d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0321_008a60c09dde780580c8eee7d2b08400a8c42b4d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8a60c09dde780580c8eee7d2b08400a8c42b4d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008a60c09dde780580c8eee7d2b08400a8c42b4d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0322 blob 008abfe0922f6d1662aebcfbf63ba9f47de4ae65" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0322_008abfe0922f6d1662aebcfbf63ba9f47de4ae65.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8abfe0922f6d1662aebcfbf63ba9f47de4ae65",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008abfe0922f6d1662aebcfbf63ba9f47de4ae65",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0323 blob 008ad72ae599b1b937e2956e2621d40c325ff632" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0323_008ad72ae599b1b937e2956e2621d40c325ff632.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8ad72ae599b1b937e2956e2621d40c325ff632",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008ad72ae599b1b937e2956e2621d40c325ff632",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0324 blob 008b25d3db08726b0fc1569f88fba76694bbcc12" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0324_008b25d3db08726b0fc1569f88fba76694bbcc12.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8b25d3db08726b0fc1569f88fba76694bbcc12",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008b25d3db08726b0fc1569f88fba76694bbcc12",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0325 blob 008c04fe2f6e0a8b39bc02005f0a576d92784bae" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0325_008c04fe2f6e0a8b39bc02005f0a576d92784bae.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8c04fe2f6e0a8b39bc02005f0a576d92784bae",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008c04fe2f6e0a8b39bc02005f0a576d92784bae",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0326 blob 008c0f32cfb3a72fbfb2218fe9ad97d0530b11b6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0326_008c0f32cfb3a72fbfb2218fe9ad97d0530b11b6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8c0f32cfb3a72fbfb2218fe9ad97d0530b11b6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008c0f32cfb3a72fbfb2218fe9ad97d0530b11b6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0327 blob 008c1ec8380af17de62452dbf580c0c81912bf8e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0327_008c1ec8380af17de62452dbf580c0c81912bf8e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8c1ec8380af17de62452dbf580c0c81912bf8e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008c1ec8380af17de62452dbf580c0c81912bf8e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0328 blob 008cf10a0cc37e18714578fd777c0b734f87d9f4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0328_008cf10a0cc37e18714578fd777c0b734f87d9f4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8cf10a0cc37e18714578fd777c0b734f87d9f4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008cf10a0cc37e18714578fd777c0b734f87d9f4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0329 blob 008d5711b818a315136290c141c830cdf5af80a0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0329_008d5711b818a315136290c141c830cdf5af80a0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8d5711b818a315136290c141c830cdf5af80a0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008d5711b818a315136290c141c830cdf5af80a0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0330 blob 008eeb44607cfb96aacc0823214c912ea74324d7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0330_008eeb44607cfb96aacc0823214c912ea74324d7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8eeb44607cfb96aacc0823214c912ea74324d7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008eeb44607cfb96aacc0823214c912ea74324d7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0331 blob 008fba7c8963889cdb7262509c2eddbdb63ca9c3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0331_008fba7c8963889cdb7262509c2eddbdb63ca9c3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8fba7c8963889cdb7262509c2eddbdb63ca9c3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008fba7c8963889cdb7262509c2eddbdb63ca9c3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0332 blob 0090571adf09ef79bff63f2f0be0d02237c4e5b4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0332_0090571adf09ef79bff63f2f0be0d02237c4e5b4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/90571adf09ef79bff63f2f0be0d02237c4e5b4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0090571adf09ef79bff63f2f0be0d02237c4e5b4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0333 blob 00906e7a2de218085eaec3c8488365cb2da0a0a8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0333_00906e7a2de218085eaec3c8488365cb2da0a0a8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/906e7a2de218085eaec3c8488365cb2da0a0a8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00906e7a2de218085eaec3c8488365cb2da0a0a8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0334 blob 0090ac00bba4b46eff46c4f57117829531b597eb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0334_0090ac00bba4b46eff46c4f57117829531b597eb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/90ac00bba4b46eff46c4f57117829531b597eb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0090ac00bba4b46eff46c4f57117829531b597eb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0335 blob 0090e68f4a7c035644a53dabe48754f78d80c8ae" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0335_0090e68f4a7c035644a53dabe48754f78d80c8ae.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/90e68f4a7c035644a53dabe48754f78d80c8ae",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0090e68f4a7c035644a53dabe48754f78d80c8ae",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0336 blob 009119299529d5c93f02d5f8dc2363f6e29f0f9c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0336_009119299529d5c93f02d5f8dc2363f6e29f0f9c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9119299529d5c93f02d5f8dc2363f6e29f0f9c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009119299529d5c93f02d5f8dc2363f6e29f0f9c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0337 blob 0092cbf3540e2fdfd2e882461ba39ba2a833b672" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0337_0092cbf3540e2fdfd2e882461ba39ba2a833b672.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/92cbf3540e2fdfd2e882461ba39ba2a833b672",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0092cbf3540e2fdfd2e882461ba39ba2a833b672",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0338 blob 0092d67b8a474367239f8f196a517c288de47dab" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0338_0092d67b8a474367239f8f196a517c288de47dab.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/92d67b8a474367239f8f196a517c288de47dab",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0092d67b8a474367239f8f196a517c288de47dab",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0339 blob 0093b2d8d8de561512efffe7cc416b1cdfe225dd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0339_0093b2d8d8de561512efffe7cc416b1cdfe225dd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/93b2d8d8de561512efffe7cc416b1cdfe225dd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0093b2d8d8de561512efffe7cc416b1cdfe225dd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0340 blob 0093c647bf64bc5a42d32b948e2d342c0ce61a49" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0340_0093c647bf64bc5a42d32b948e2d342c0ce61a49.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/93c647bf64bc5a42d32b948e2d342c0ce61a49",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0093c647bf64bc5a42d32b948e2d342c0ce61a49",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0341 blob 009437a5f3168fa9e36c5eb30291fcddfc431fdc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0341_009437a5f3168fa9e36c5eb30291fcddfc431fdc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9437a5f3168fa9e36c5eb30291fcddfc431fdc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009437a5f3168fa9e36c5eb30291fcddfc431fdc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0342 blob 0094ec1c9278332f736d2814c847b272788a7dd3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0342_0094ec1c9278332f736d2814c847b272788a7dd3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/94ec1c9278332f736d2814c847b272788a7dd3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0094ec1c9278332f736d2814c847b272788a7dd3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0343 blob 0096ace080b8f7d934c522a4daac8b4dd889242c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0343_0096ace080b8f7d934c522a4daac8b4dd889242c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/96ace080b8f7d934c522a4daac8b4dd889242c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0096ace080b8f7d934c522a4daac8b4dd889242c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0344 blob 0096f4913aa03bada1cfde879478926c5fe9ec06" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0344_0096f4913aa03bada1cfde879478926c5fe9ec06.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/96f4913aa03bada1cfde879478926c5fe9ec06",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0096f4913aa03bada1cfde879478926c5fe9ec06",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0345 blob 0096f57b7e09f33108d7177405d02eec05811c03" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0345_0096f57b7e09f33108d7177405d02eec05811c03.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/96f57b7e09f33108d7177405d02eec05811c03",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0096f57b7e09f33108d7177405d02eec05811c03",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0346 blob 00991b7c12ab7d9b74efbb67ee407b5788b79984" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0346_00991b7c12ab7d9b74efbb67ee407b5788b79984.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/991b7c12ab7d9b74efbb67ee407b5788b79984",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00991b7c12ab7d9b74efbb67ee407b5788b79984",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0347 blob 009a1de0a3d3f69e05a802d7d2356935018b0f81" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0347_009a1de0a3d3f69e05a802d7d2356935018b0f81.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9a1de0a3d3f69e05a802d7d2356935018b0f81",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009a1de0a3d3f69e05a802d7d2356935018b0f81",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0348 blob 009b113e5bb5d04bdfb116897cc17dc5f5a2fa9c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0348_009b113e5bb5d04bdfb116897cc17dc5f5a2fa9c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9b113e5bb5d04bdfb116897cc17dc5f5a2fa9c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009b113e5bb5d04bdfb116897cc17dc5f5a2fa9c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0349 blob 009b365370f0815e4493f4775f96ebda3cfa6e80" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0349_009b365370f0815e4493f4775f96ebda3cfa6e80.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9b365370f0815e4493f4775f96ebda3cfa6e80",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009b365370f0815e4493f4775f96ebda3cfa6e80",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0350 blob 009b7138ac72c5845225ce1f801be908ede4e3b4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0350_009b7138ac72c5845225ce1f801be908ede4e3b4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9b7138ac72c5845225ce1f801be908ede4e3b4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009b7138ac72c5845225ce1f801be908ede4e3b4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0351 blob 009c0db9bc3c92607d942f5fe858eeee0603b039" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0351_009c0db9bc3c92607d942f5fe858eeee0603b039.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9c0db9bc3c92607d942f5fe858eeee0603b039",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009c0db9bc3c92607d942f5fe858eeee0603b039",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0352 blob 009c954c73461366434ce7ab51d03fe0dd15f505" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0352_009c954c73461366434ce7ab51d03fe0dd15f505.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9c954c73461366434ce7ab51d03fe0dd15f505",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009c954c73461366434ce7ab51d03fe0dd15f505",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0353 blob 009c989ef88ea96c938d9f6715564812cf86e319" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0353_009c989ef88ea96c938d9f6715564812cf86e319.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9c989ef88ea96c938d9f6715564812cf86e319",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009c989ef88ea96c938d9f6715564812cf86e319",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0354 blob 009caf804b43fdd644ff08991d55d0e417fd34d8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0354_009caf804b43fdd644ff08991d55d0e417fd34d8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9caf804b43fdd644ff08991d55d0e417fd34d8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009caf804b43fdd644ff08991d55d0e417fd34d8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0355 blob 009cd863e5b0aa50af365dc027d89baf9c44e953" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0355_009cd863e5b0aa50af365dc027d89baf9c44e953.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9cd863e5b0aa50af365dc027d89baf9c44e953",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009cd863e5b0aa50af365dc027d89baf9c44e953",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0356 blob 009d403300d3d20d5a5736037df30d050807b571" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0356_009d403300d3d20d5a5736037df30d050807b571.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9d403300d3d20d5a5736037df30d050807b571",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009d403300d3d20d5a5736037df30d050807b571",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0357 blob 009d45a1dd47491d1fb1e1b09e279d335a162f9f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0357_009d45a1dd47491d1fb1e1b09e279d335a162f9f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9d45a1dd47491d1fb1e1b09e279d335a162f9f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009d45a1dd47491d1fb1e1b09e279d335a162f9f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0358 blob 009d8f0e27fec18b98d11d1fed6dab81cfd1d6f4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0358_009d8f0e27fec18b98d11d1fed6dab81cfd1d6f4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9d8f0e27fec18b98d11d1fed6dab81cfd1d6f4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009d8f0e27fec18b98d11d1fed6dab81cfd1d6f4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0359 blob 009e339dbcd5f4826246f08ce00f0cf528c6ec13" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0359_009e339dbcd5f4826246f08ce00f0cf528c6ec13.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9e339dbcd5f4826246f08ce00f0cf528c6ec13",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009e339dbcd5f4826246f08ce00f0cf528c6ec13",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0360 blob 009e69494b007fc7bfe590029c144d9ce41aa6b5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0360_009e69494b007fc7bfe590029c144d9ce41aa6b5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9e69494b007fc7bfe590029c144d9ce41aa6b5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009e69494b007fc7bfe590029c144d9ce41aa6b5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0361 blob 009e8b3b150eaab7c5c3705c0d466773743dbe0f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0361_009e8b3b150eaab7c5c3705c0d466773743dbe0f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9e8b3b150eaab7c5c3705c0d466773743dbe0f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009e8b3b150eaab7c5c3705c0d466773743dbe0f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0362 blob 009ec5ab374ef36426d9db32ef31b028a403ed6a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0362_009ec5ab374ef36426d9db32ef31b028a403ed6a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9ec5ab374ef36426d9db32ef31b028a403ed6a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009ec5ab374ef36426d9db32ef31b028a403ed6a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0363 blob 009ee80deec8c16d5336dd52c751f3b6cd7cfa3e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0363_009ee80deec8c16d5336dd52c751f3b6cd7cfa3e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9ee80deec8c16d5336dd52c751f3b6cd7cfa3e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009ee80deec8c16d5336dd52c751f3b6cd7cfa3e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0364 blob 009fa8ae3a29b7e9eda17fc39934be33d296840a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0364_009fa8ae3a29b7e9eda17fc39934be33d296840a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9fa8ae3a29b7e9eda17fc39934be33d296840a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009fa8ae3a29b7e9eda17fc39934be33d296840a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0365 blob 009faab4aefc34f55daf6fd7e6e63ec0f0ee108a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0365_009faab4aefc34f55daf6fd7e6e63ec0f0ee108a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9faab4aefc34f55daf6fd7e6e63ec0f0ee108a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009faab4aefc34f55daf6fd7e6e63ec0f0ee108a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0366 blob 00a01f07c3e56f96230bf5e382f2ad3cb976bb96" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0366_00a01f07c3e56f96230bf5e382f2ad3cb976bb96.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a01f07c3e56f96230bf5e382f2ad3cb976bb96",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a01f07c3e56f96230bf5e382f2ad3cb976bb96",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0367 blob 00a060df0b5e81cc1c47758240a7c790384b758e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0367_00a060df0b5e81cc1c47758240a7c790384b758e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a060df0b5e81cc1c47758240a7c790384b758e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a060df0b5e81cc1c47758240a7c790384b758e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0368 blob 00a0679a2866facb44d16f819ace2d0f115a899a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0368_00a0679a2866facb44d16f819ace2d0f115a899a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a0679a2866facb44d16f819ace2d0f115a899a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a0679a2866facb44d16f819ace2d0f115a899a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0369 blob 00a0f6f96f3f5ebc54bbfb841921c5ceff88c1c3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0369_00a0f6f96f3f5ebc54bbfb841921c5ceff88c1c3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a0f6f96f3f5ebc54bbfb841921c5ceff88c1c3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a0f6f96f3f5ebc54bbfb841921c5ceff88c1c3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0370 blob 00a1b684830c0201361b9ec84d874aaa40b2a9e0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0370_00a1b684830c0201361b9ec84d874aaa40b2a9e0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a1b684830c0201361b9ec84d874aaa40b2a9e0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a1b684830c0201361b9ec84d874aaa40b2a9e0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0371 blob 00a1e2ad22a9d77daa4c221bd5d21105e85c2ed7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0371_00a1e2ad22a9d77daa4c221bd5d21105e85c2ed7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a1e2ad22a9d77daa4c221bd5d21105e85c2ed7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a1e2ad22a9d77daa4c221bd5d21105e85c2ed7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0372 blob 00a22152a22b1d877f8bd75ee5063a0b6d28cbf0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0372_00a22152a22b1d877f8bd75ee5063a0b6d28cbf0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a22152a22b1d877f8bd75ee5063a0b6d28cbf0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a22152a22b1d877f8bd75ee5063a0b6d28cbf0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0373 blob 00a23e6edf454bce0a30783e57195f251c1e1e11" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0373_00a23e6edf454bce0a30783e57195f251c1e1e11.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a23e6edf454bce0a30783e57195f251c1e1e11",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a23e6edf454bce0a30783e57195f251c1e1e11",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0374 blob 00a341c595ebb6ac6965001cce84d3d4e65f60c3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0374_00a341c595ebb6ac6965001cce84d3d4e65f60c3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a341c595ebb6ac6965001cce84d3d4e65f60c3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a341c595ebb6ac6965001cce84d3d4e65f60c3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0375 blob 00a4ce602cc3f6784bb51784766c9ef2f655f0e9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0375_00a4ce602cc3f6784bb51784766c9ef2f655f0e9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a4ce602cc3f6784bb51784766c9ef2f655f0e9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a4ce602cc3f6784bb51784766c9ef2f655f0e9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0376 blob 00a53b36479a25a51734fa359ebf2f649795437b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0376_00a53b36479a25a51734fa359ebf2f649795437b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a53b36479a25a51734fa359ebf2f649795437b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a53b36479a25a51734fa359ebf2f649795437b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0377 blob 00a5ec206d63fff04b4691c5656dd2c5fdee62cb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0377_00a5ec206d63fff04b4691c5656dd2c5fdee62cb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a5ec206d63fff04b4691c5656dd2c5fdee62cb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a5ec206d63fff04b4691c5656dd2c5fdee62cb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0378 blob 00a5f6e0ec575af5a172f9771df52877eeaf664c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0378_00a5f6e0ec575af5a172f9771df52877eeaf664c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a5f6e0ec575af5a172f9771df52877eeaf664c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a5f6e0ec575af5a172f9771df52877eeaf664c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0379 blob 00a62e0c4276fb8889a0b158c9e71a22e3be092c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0379_00a62e0c4276fb8889a0b158c9e71a22e3be092c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a62e0c4276fb8889a0b158c9e71a22e3be092c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a62e0c4276fb8889a0b158c9e71a22e3be092c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0380 blob 00a64622e664a5aeb4d16bb785a334c7b9ca0f10" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0380_00a64622e664a5aeb4d16bb785a334c7b9ca0f10.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a64622e664a5aeb4d16bb785a334c7b9ca0f10",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a64622e664a5aeb4d16bb785a334c7b9ca0f10",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0381 blob 00a6e71568b5985c0b344bfebbe92d1e0bff1294" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0381_00a6e71568b5985c0b344bfebbe92d1e0bff1294.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a6e71568b5985c0b344bfebbe92d1e0bff1294",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a6e71568b5985c0b344bfebbe92d1e0bff1294",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0382 blob 00a74ee7384e4b824c9faf9e6d7891e4f28c775a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0382_00a74ee7384e4b824c9faf9e6d7891e4f28c775a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a74ee7384e4b824c9faf9e6d7891e4f28c775a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a74ee7384e4b824c9faf9e6d7891e4f28c775a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0383 blob 00a7d762ce6867d4f14d8157ddee4daec3dea0f6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0383_00a7d762ce6867d4f14d8157ddee4daec3dea0f6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a7d762ce6867d4f14d8157ddee4daec3dea0f6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a7d762ce6867d4f14d8157ddee4daec3dea0f6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0384 blob 00a850d61166aae6caaa61385b826cba73519b90" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0384_00a850d61166aae6caaa61385b826cba73519b90.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a850d61166aae6caaa61385b826cba73519b90",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a850d61166aae6caaa61385b826cba73519b90",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0385 blob 00a8553fcc10af2c37520d4a0eaae9e50f8e504c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0385_00a8553fcc10af2c37520d4a0eaae9e50f8e504c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a8553fcc10af2c37520d4a0eaae9e50f8e504c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a8553fcc10af2c37520d4a0eaae9e50f8e504c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0386 blob 00a8d210476089257be3d09ac8a16d1f8e1dd8dc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0386_00a8d210476089257be3d09ac8a16d1f8e1dd8dc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a8d210476089257be3d09ac8a16d1f8e1dd8dc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a8d210476089257be3d09ac8a16d1f8e1dd8dc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0387 blob 00a8eefde9aeb96592f5ed6455dbf5d3b16747c4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0387_00a8eefde9aeb96592f5ed6455dbf5d3b16747c4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a8eefde9aeb96592f5ed6455dbf5d3b16747c4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a8eefde9aeb96592f5ed6455dbf5d3b16747c4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0388 blob 00a9453a391726228867397fe45dcd2c3faa8918" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0388_00a9453a391726228867397fe45dcd2c3faa8918.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a9453a391726228867397fe45dcd2c3faa8918",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a9453a391726228867397fe45dcd2c3faa8918",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0389 blob 00a95e249fe82f2eb3d53dcc541559dceb3e8709" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0389_00a95e249fe82f2eb3d53dcc541559dceb3e8709.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a95e249fe82f2eb3d53dcc541559dceb3e8709",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a95e249fe82f2eb3d53dcc541559dceb3e8709",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0390 blob 00a994be120edaa1024733cb94e3f1fe4e494039" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0390_00a994be120edaa1024733cb94e3f1fe4e494039.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/a994be120edaa1024733cb94e3f1fe4e494039",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00a994be120edaa1024733cb94e3f1fe4e494039",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0391 blob 00ab9d7978f905c1949f3db35e051e2a20c69257" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0391_00ab9d7978f905c1949f3db35e051e2a20c69257.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/ab9d7978f905c1949f3db35e051e2a20c69257",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00ab9d7978f905c1949f3db35e051e2a20c69257",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0392 blob 00abde081739436236aa077412c3b5b686144f42" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0392_00abde081739436236aa077412c3b5b686144f42.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/abde081739436236aa077412c3b5b686144f42",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00abde081739436236aa077412c3b5b686144f42",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0393 blob 00abeb55afdd68089676d2007fbfd248b5a45e79" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0393_00abeb55afdd68089676d2007fbfd248b5a45e79.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/abeb55afdd68089676d2007fbfd248b5a45e79",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00abeb55afdd68089676d2007fbfd248b5a45e79",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0394 blob 00ad37986efdcebb440c95629acd16213028c239" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0394_00ad37986efdcebb440c95629acd16213028c239.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/ad37986efdcebb440c95629acd16213028c239",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00ad37986efdcebb440c95629acd16213028c239",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0395 blob 00ad649ae397f3c5d0f1200ec3860188133c5223" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0395_00ad649ae397f3c5d0f1200ec3860188133c5223.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/ad649ae397f3c5d0f1200ec3860188133c5223",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00ad649ae397f3c5d0f1200ec3860188133c5223",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0396 blob 00ada05f46c80c959253b418bc25a40478721654" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0396_00ada05f46c80c959253b418bc25a40478721654.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/ada05f46c80c959253b418bc25a40478721654",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00ada05f46c80c959253b418bc25a40478721654",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0397 blob 00ada7a938f7a971a54b2b398e4e53eea59eb4ae" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0397_00ada7a938f7a971a54b2b398e4e53eea59eb4ae.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/ada7a938f7a971a54b2b398e4e53eea59eb4ae",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00ada7a938f7a971a54b2b398e4e53eea59eb4ae",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0398 blob 00ae4e8d3208e09f2cf7a38202a126f728cadb48" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0398_00ae4e8d3208e09f2cf7a38202a126f728cadb48.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/ae4e8d3208e09f2cf7a38202a126f728cadb48",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00ae4e8d3208e09f2cf7a38202a126f728cadb48",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0399 blob 00aea3aa304f2731da070c447f694591b3021bc9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0399_00aea3aa304f2731da070c447f694591b3021bc9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/aea3aa304f2731da070c447f694591b3021bc9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00aea3aa304f2731da070c447f694591b3021bc9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0400 blob 00aedd9c579f9acc2c94dc8632f2c2b9fa2c96bc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0400_00aedd9c579f9acc2c94dc8632f2c2b9fa2c96bc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/aedd9c579f9acc2c94dc8632f2c2b9fa2c96bc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00aedd9c579f9acc2c94dc8632f2c2b9fa2c96bc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0401 blob 00aeee36d8a048d56ab686b136cc68bc111f9929" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0401_00aeee36d8a048d56ab686b136cc68bc111f9929.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/aeee36d8a048d56ab686b136cc68bc111f9929",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00aeee36d8a048d56ab686b136cc68bc111f9929",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0402 blob 00af9addd90d9b44f9134d50708548896deb0e2f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0402_00af9addd90d9b44f9134d50708548896deb0e2f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/af9addd90d9b44f9134d50708548896deb0e2f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00af9addd90d9b44f9134d50708548896deb0e2f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0403 blob 00afd7ef76ee8c1284f46cf9f6b67299c85dc760" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0403_00afd7ef76ee8c1284f46cf9f6b67299c85dc760.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/afd7ef76ee8c1284f46cf9f6b67299c85dc760",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00afd7ef76ee8c1284f46cf9f6b67299c85dc760",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0404 blob 00afe8931768b96ec3f8baf72ab9221a4c2426b6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0404_00afe8931768b96ec3f8baf72ab9221a4c2426b6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/afe8931768b96ec3f8baf72ab9221a4c2426b6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00afe8931768b96ec3f8baf72ab9221a4c2426b6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0405 blob 00b0c240fcd788edc3d33cd60f48cb49f963ff7f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0405_00b0c240fcd788edc3d33cd60f48cb49f963ff7f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b0c240fcd788edc3d33cd60f48cb49f963ff7f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b0c240fcd788edc3d33cd60f48cb49f963ff7f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0406 blob 00b1044d3adf7d9e0def6c12888a6abff8a3cd0d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0406_00b1044d3adf7d9e0def6c12888a6abff8a3cd0d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b1044d3adf7d9e0def6c12888a6abff8a3cd0d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b1044d3adf7d9e0def6c12888a6abff8a3cd0d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0407 blob 00b10ac877d31895ccdf3b2ae74137845cdffde7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0407_00b10ac877d31895ccdf3b2ae74137845cdffde7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b10ac877d31895ccdf3b2ae74137845cdffde7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b10ac877d31895ccdf3b2ae74137845cdffde7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0408 blob 00b116d797c844cd7320542a9829e94ee1e0311c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0408_00b116d797c844cd7320542a9829e94ee1e0311c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b116d797c844cd7320542a9829e94ee1e0311c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b116d797c844cd7320542a9829e94ee1e0311c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0409 blob 00b1fa4dcbccf2d083aa1b83ba5353eb06658867" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0409_00b1fa4dcbccf2d083aa1b83ba5353eb06658867.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b1fa4dcbccf2d083aa1b83ba5353eb06658867",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b1fa4dcbccf2d083aa1b83ba5353eb06658867",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0410 blob 00b2aabefca49b634f49143523ee31556baa7777" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0410_00b2aabefca49b634f49143523ee31556baa7777.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b2aabefca49b634f49143523ee31556baa7777",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b2aabefca49b634f49143523ee31556baa7777",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0411 blob 00b3a908cdba4822b4bb2aa42d3e69a0a8dd8dda" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0411_00b3a908cdba4822b4bb2aa42d3e69a0a8dd8dda.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b3a908cdba4822b4bb2aa42d3e69a0a8dd8dda",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b3a908cdba4822b4bb2aa42d3e69a0a8dd8dda",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0412 blob 00b3cf0e1872f6dabe6428b3283540b63b7ef939" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0412_00b3cf0e1872f6dabe6428b3283540b63b7ef939.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b3cf0e1872f6dabe6428b3283540b63b7ef939",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b3cf0e1872f6dabe6428b3283540b63b7ef939",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0413 blob 00b49033668160574c35555293c0c755cbafaeaa" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0413_00b49033668160574c35555293c0c755cbafaeaa.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b49033668160574c35555293c0c755cbafaeaa",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b49033668160574c35555293c0c755cbafaeaa",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0414 blob 00b607824dda2dab1c1ffb8bfdbd0972baa44ec5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0414_00b607824dda2dab1c1ffb8bfdbd0972baa44ec5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b607824dda2dab1c1ffb8bfdbd0972baa44ec5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b607824dda2dab1c1ffb8bfdbd0972baa44ec5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0415 blob 00b699fef71b45c78e298fa48609b553a32fd175" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0415_00b699fef71b45c78e298fa48609b553a32fd175.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b699fef71b45c78e298fa48609b553a32fd175",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b699fef71b45c78e298fa48609b553a32fd175",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0416 blob 00b6cdf28126d6462f3eebec930a265ef7e9722b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0416_00b6cdf28126d6462f3eebec930a265ef7e9722b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b6cdf28126d6462f3eebec930a265ef7e9722b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b6cdf28126d6462f3eebec930a265ef7e9722b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0417 blob 00b70137053dfcb7351f9a5f8e16b0cadb07f51c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0417_00b70137053dfcb7351f9a5f8e16b0cadb07f51c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b70137053dfcb7351f9a5f8e16b0cadb07f51c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b70137053dfcb7351f9a5f8e16b0cadb07f51c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0418 blob 00b71bc46233f30de7bc99c10c6358589970e417" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0418_00b71bc46233f30de7bc99c10c6358589970e417.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b71bc46233f30de7bc99c10c6358589970e417",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b71bc46233f30de7bc99c10c6358589970e417",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0419 blob 00b75bc10b53b0c64b14fc1d9111d5f4e1db3af5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0419_00b75bc10b53b0c64b14fc1d9111d5f4e1db3af5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b75bc10b53b0c64b14fc1d9111d5f4e1db3af5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b75bc10b53b0c64b14fc1d9111d5f4e1db3af5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0420 blob 00b7d58c33e38b2a48e4e2ab557239b1ed0c759d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0420_00b7d58c33e38b2a48e4e2ab557239b1ed0c759d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b7d58c33e38b2a48e4e2ab557239b1ed0c759d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b7d58c33e38b2a48e4e2ab557239b1ed0c759d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0421 blob 00b8403225de981e7180b93feb508dae75035640" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0421_00b8403225de981e7180b93feb508dae75035640.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b8403225de981e7180b93feb508dae75035640",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b8403225de981e7180b93feb508dae75035640",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0422 blob 00b84ecba660a1efb25d60fa82365f617d842387" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0422_00b84ecba660a1efb25d60fa82365f617d842387.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b84ecba660a1efb25d60fa82365f617d842387",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b84ecba660a1efb25d60fa82365f617d842387",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0423 blob 00b8804da8f74b6ea23e348adaeb8322f9b00c92" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0423_00b8804da8f74b6ea23e348adaeb8322f9b00c92.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b8804da8f74b6ea23e348adaeb8322f9b00c92",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b8804da8f74b6ea23e348adaeb8322f9b00c92",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0424 blob 00b97c18986091c50140dd644c9dc2405162c600" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0424_00b97c18986091c50140dd644c9dc2405162c600.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/b97c18986091c50140dd644c9dc2405162c600",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00b97c18986091c50140dd644c9dc2405162c600",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0425 blob 00ba1e2813b2c2fff74300e3b2036a04f9e28065" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0425_00ba1e2813b2c2fff74300e3b2036a04f9e28065.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/ba1e2813b2c2fff74300e3b2036a04f9e28065",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00ba1e2813b2c2fff74300e3b2036a04f9e28065",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0426 blob 00ba6bf08eaf0b6f3dbbea709922a6cfce49c86d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0426_00ba6bf08eaf0b6f3dbbea709922a6cfce49c86d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/ba6bf08eaf0b6f3dbbea709922a6cfce49c86d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00ba6bf08eaf0b6f3dbbea709922a6cfce49c86d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0427 blob 00bc3de22eb670c07e78087d96d9a3cff1d0fd67" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0427_00bc3de22eb670c07e78087d96d9a3cff1d0fd67.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/bc3de22eb670c07e78087d96d9a3cff1d0fd67",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00bc3de22eb670c07e78087d96d9a3cff1d0fd67",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0428 blob 00bc727865031620752771af4a9030c7de1b73df" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0428_00bc727865031620752771af4a9030c7de1b73df.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/bc727865031620752771af4a9030c7de1b73df",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00bc727865031620752771af4a9030c7de1b73df",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0429 blob 00bd8b15c625f3f95aefa771abded1a985342c23" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0429_00bd8b15c625f3f95aefa771abded1a985342c23.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/bd8b15c625f3f95aefa771abded1a985342c23",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00bd8b15c625f3f95aefa771abded1a985342c23",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0430 blob 00bdf9b1251a1df819545f3da758c51cc25d7bfa" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0430_00bdf9b1251a1df819545f3da758c51cc25d7bfa.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/bdf9b1251a1df819545f3da758c51cc25d7bfa",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00bdf9b1251a1df819545f3da758c51cc25d7bfa",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0431 blob 00beaaa4e6edc7d644f43a6503aa895eb6d934c4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0431_00beaaa4e6edc7d644f43a6503aa895eb6d934c4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/beaaa4e6edc7d644f43a6503aa895eb6d934c4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00beaaa4e6edc7d644f43a6503aa895eb6d934c4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0432 blob 00bf665aa09bf353dd2c81220d2c83a31086e5b7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0432_00bf665aa09bf353dd2c81220d2c83a31086e5b7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/bf665aa09bf353dd2c81220d2c83a31086e5b7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00bf665aa09bf353dd2c81220d2c83a31086e5b7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0433 blob 00bfc815b62f1593dc7121a81bd83ea76921ed42" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0433_00bfc815b62f1593dc7121a81bd83ea76921ed42.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/bfc815b62f1593dc7121a81bd83ea76921ed42",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00bfc815b62f1593dc7121a81bd83ea76921ed42",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0434 blob 00bfcd1afa05adf3db40c26771dd1b8ec98c0e28" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0434_00bfcd1afa05adf3db40c26771dd1b8ec98c0e28.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/bfcd1afa05adf3db40c26771dd1b8ec98c0e28",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00bfcd1afa05adf3db40c26771dd1b8ec98c0e28",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0435 blob 00c1b45b7963ea38c87dca95a94e8ccfc273f7b1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0435_00c1b45b7963ea38c87dca95a94e8ccfc273f7b1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c1b45b7963ea38c87dca95a94e8ccfc273f7b1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c1b45b7963ea38c87dca95a94e8ccfc273f7b1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0436 blob 00c1d44a56105822f7de7849c44ed593f7d1a8a4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0436_00c1d44a56105822f7de7849c44ed593f7d1a8a4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c1d44a56105822f7de7849c44ed593f7d1a8a4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c1d44a56105822f7de7849c44ed593f7d1a8a4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0437 blob 00c1f1aab1304c127a5dccdaeff62d7213b7a9e5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0437_00c1f1aab1304c127a5dccdaeff62d7213b7a9e5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c1f1aab1304c127a5dccdaeff62d7213b7a9e5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c1f1aab1304c127a5dccdaeff62d7213b7a9e5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0438 blob 00c332a1407a86096cbaf06ef5d8ec613a412190" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0438_00c332a1407a86096cbaf06ef5d8ec613a412190.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c332a1407a86096cbaf06ef5d8ec613a412190",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c332a1407a86096cbaf06ef5d8ec613a412190",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0439 blob 00c447c74c7d5df85b0521f2fc90b12470a5950f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0439_00c447c74c7d5df85b0521f2fc90b12470a5950f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c447c74c7d5df85b0521f2fc90b12470a5950f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c447c74c7d5df85b0521f2fc90b12470a5950f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0440 blob 00c50bf49f9b50b5d48be011eb08accc9de4752a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0440_00c50bf49f9b50b5d48be011eb08accc9de4752a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c50bf49f9b50b5d48be011eb08accc9de4752a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c50bf49f9b50b5d48be011eb08accc9de4752a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0441 blob 00c597e97c8fd5a97105d2c68315cef414175669" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0441_00c597e97c8fd5a97105d2c68315cef414175669.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c597e97c8fd5a97105d2c68315cef414175669",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c597e97c8fd5a97105d2c68315cef414175669",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0442 blob 00c622d5dcf622f66820a97c0ca6af1a5ce68280" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0442_00c622d5dcf622f66820a97c0ca6af1a5ce68280.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c622d5dcf622f66820a97c0ca6af1a5ce68280",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c622d5dcf622f66820a97c0ca6af1a5ce68280",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0443 blob 00c63a5622da8545f46fb6b170951b224679bc73" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0443_00c63a5622da8545f46fb6b170951b224679bc73.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c63a5622da8545f46fb6b170951b224679bc73",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c63a5622da8545f46fb6b170951b224679bc73",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0444 blob 00c649b140e516f6eb67c65b532308ff8af372e3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0444_00c649b140e516f6eb67c65b532308ff8af372e3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c649b140e516f6eb67c65b532308ff8af372e3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c649b140e516f6eb67c65b532308ff8af372e3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0445 blob 00c6a76ef803005698e14d7f31eb4acd22b35649" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0445_00c6a76ef803005698e14d7f31eb4acd22b35649.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c6a76ef803005698e14d7f31eb4acd22b35649",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c6a76ef803005698e14d7f31eb4acd22b35649",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0446 blob 00c6c5110065fa32dd73c64eec1c586685c28dd4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0446_00c6c5110065fa32dd73c64eec1c586685c28dd4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c6c5110065fa32dd73c64eec1c586685c28dd4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c6c5110065fa32dd73c64eec1c586685c28dd4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0447 blob 00c6d3d9b11a7966c04f42cdb06e9cff258814fb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0447_00c6d3d9b11a7966c04f42cdb06e9cff258814fb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c6d3d9b11a7966c04f42cdb06e9cff258814fb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c6d3d9b11a7966c04f42cdb06e9cff258814fb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0448 blob 00c756df5d4b61950760594e575a7d35dec3dbc6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0448_00c756df5d4b61950760594e575a7d35dec3dbc6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c756df5d4b61950760594e575a7d35dec3dbc6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c756df5d4b61950760594e575a7d35dec3dbc6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0449 blob 00c84be33ca950012af99d61878919974401c4a0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0449_00c84be33ca950012af99d61878919974401c4a0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c84be33ca950012af99d61878919974401c4a0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c84be33ca950012af99d61878919974401c4a0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0450 blob 00c8baace0f9bf73c8f809639babce775310237b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0450_00c8baace0f9bf73c8f809639babce775310237b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c8baace0f9bf73c8f809639babce775310237b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c8baace0f9bf73c8f809639babce775310237b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0451 blob 00c99c7272badc2d5a8f16c29db7d4040f5eb4d3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0451_00c99c7272badc2d5a8f16c29db7d4040f5eb4d3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c99c7272badc2d5a8f16c29db7d4040f5eb4d3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c99c7272badc2d5a8f16c29db7d4040f5eb4d3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0452 blob 00ca5571a1ab77e8a1b2d505d59e6ff59d629dd9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0452_00ca5571a1ab77e8a1b2d505d59e6ff59d629dd9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/ca5571a1ab77e8a1b2d505d59e6ff59d629dd9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00ca5571a1ab77e8a1b2d505d59e6ff59d629dd9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0453 blob 00ca7b99fef35e21d24af844e6dbaa92cab5834f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0453_00ca7b99fef35e21d24af844e6dbaa92cab5834f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/ca7b99fef35e21d24af844e6dbaa92cab5834f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00ca7b99fef35e21d24af844e6dbaa92cab5834f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0454 blob 00cae7433859ad8bc025b8c425b70f78c328a2f3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0454_00cae7433859ad8bc025b8c425b70f78c328a2f3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/cae7433859ad8bc025b8c425b70f78c328a2f3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00cae7433859ad8bc025b8c425b70f78c328a2f3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0455 blob 00cbd90bf68bc729d9b4d1bdb2fcaa92954010f1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0455_00cbd90bf68bc729d9b4d1bdb2fcaa92954010f1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/cbd90bf68bc729d9b4d1bdb2fcaa92954010f1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00cbd90bf68bc729d9b4d1bdb2fcaa92954010f1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0456 tree 000079a2eaef17b7eae70e1f0f635557ea67b644" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0456_000079a2eaef17b7eae70e1f0f635557ea67b644.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0079a2eaef17b7eae70e1f0f635557ea67b644",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000079a2eaef17b7eae70e1f0f635557ea67b644",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0457 tree 0000930674a61658209b20b9ff34a8a2649dc213" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0457_0000930674a61658209b20b9ff34a8a2649dc213.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/00930674a61658209b20b9ff34a8a2649dc213",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0000930674a61658209b20b9ff34a8a2649dc213",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0458 tree 0000a420a30cea4448b2da8954ec3dce797dfcdf" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0458_0000a420a30cea4448b2da8954ec3dce797dfcdf.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/00a420a30cea4448b2da8954ec3dce797dfcdf",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0000a420a30cea4448b2da8954ec3dce797dfcdf",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0459 tree 0000a455d676d833890594c69849aa6187382c67" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0459_0000a455d676d833890594c69849aa6187382c67.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/00a455d676d833890594c69849aa6187382c67",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0000a455d676d833890594c69849aa6187382c67",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0460 tree 0001140536704ecf3f0f86686fb6586cbc185ece" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0460_0001140536704ecf3f0f86686fb6586cbc185ece.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/01140536704ecf3f0f86686fb6586cbc185ece",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0001140536704ecf3f0f86686fb6586cbc185ece",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0461 tree 0001cb05252fa0c6211a63a437f23f70406973d3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0461_0001cb05252fa0c6211a63a437f23f70406973d3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/01cb05252fa0c6211a63a437f23f70406973d3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0001cb05252fa0c6211a63a437f23f70406973d3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0462 tree 00026cf8d8f9e753c8dad349955d65b71c210e36" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0462_00026cf8d8f9e753c8dad349955d65b71c210e36.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/026cf8d8f9e753c8dad349955d65b71c210e36",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00026cf8d8f9e753c8dad349955d65b71c210e36",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0463 tree 0002786a0d6007ae215b678c4a88726648a6fb9e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0463_0002786a0d6007ae215b678c4a88726648a6fb9e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/02786a0d6007ae215b678c4a88726648a6fb9e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0002786a0d6007ae215b678c4a88726648a6fb9e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0464 tree 0002f867146d1c2ebe9d1ef2949ef90e3fdcc1d3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0464_0002f867146d1c2ebe9d1ef2949ef90e3fdcc1d3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/02f867146d1c2ebe9d1ef2949ef90e3fdcc1d3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0002f867146d1c2ebe9d1ef2949ef90e3fdcc1d3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0465 tree 0003225d8e58ad22ce7f23beb9d5c98df4518369" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0465_0003225d8e58ad22ce7f23beb9d5c98df4518369.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/03225d8e58ad22ce7f23beb9d5c98df4518369",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0003225d8e58ad22ce7f23beb9d5c98df4518369",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0466 tree 0003ac6a7642fbf9d25ebf3c1ef22a0dcfe73836" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0466_0003ac6a7642fbf9d25ebf3c1ef22a0dcfe73836.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/03ac6a7642fbf9d25ebf3c1ef22a0dcfe73836",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0003ac6a7642fbf9d25ebf3c1ef22a0dcfe73836",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0467 tree 0003ba0b9fac54ba3a3d4b3bbae8ba315e8dfa01" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0467_0003ba0b9fac54ba3a3d4b3bbae8ba315e8dfa01.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/03ba0b9fac54ba3a3d4b3bbae8ba315e8dfa01",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0003ba0b9fac54ba3a3d4b3bbae8ba315e8dfa01",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0468 tree 0003dcdfd969f6100cfccaaf659c26a06888aa54" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0468_0003dcdfd969f6100cfccaaf659c26a06888aa54.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/03dcdfd969f6100cfccaaf659c26a06888aa54",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0003dcdfd969f6100cfccaaf659c26a06888aa54",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0469 tree 000409568e6b224b951e57c339f22ebd2671091d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0469_000409568e6b224b951e57c339f22ebd2671091d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0409568e6b224b951e57c339f22ebd2671091d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000409568e6b224b951e57c339f22ebd2671091d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0470 tree 00047a51a93eb38f34c680efb7d5ab93d0ff4ea5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0470_00047a51a93eb38f34c680efb7d5ab93d0ff4ea5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/047a51a93eb38f34c680efb7d5ab93d0ff4ea5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00047a51a93eb38f34c680efb7d5ab93d0ff4ea5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0471 tree 0004f21e1f485869fe42fcc5296b3cee0d603bcb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0471_0004f21e1f485869fe42fcc5296b3cee0d603bcb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/04f21e1f485869fe42fcc5296b3cee0d603bcb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0004f21e1f485869fe42fcc5296b3cee0d603bcb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0472 tree 0005ab605f87948b33d37487a54e8f911e3d4faa" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0472_0005ab605f87948b33d37487a54e8f911e3d4faa.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/05ab605f87948b33d37487a54e8f911e3d4faa",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0005ab605f87948b33d37487a54e8f911e3d4faa",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0473 tree 000621aea74de3db79ee2c0ee4bdd821ab2b06b0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0473_000621aea74de3db79ee2c0ee4bdd821ab2b06b0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0621aea74de3db79ee2c0ee4bdd821ab2b06b0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000621aea74de3db79ee2c0ee4bdd821ab2b06b0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0474 tree 00072e2b7d88051ec8d6d4e955743736529dd899" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0474_00072e2b7d88051ec8d6d4e955743736529dd899.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/072e2b7d88051ec8d6d4e955743736529dd899",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00072e2b7d88051ec8d6d4e955743736529dd899",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0475 tree 00073a748a8551bd27f733648c834dca1281e3c5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0475_00073a748a8551bd27f733648c834dca1281e3c5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/073a748a8551bd27f733648c834dca1281e3c5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00073a748a8551bd27f733648c834dca1281e3c5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0476 tree 0007a5feb040e1ff704f3ad636619ddca3e7382b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0476_0007a5feb040e1ff704f3ad636619ddca3e7382b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/07a5feb040e1ff704f3ad636619ddca3e7382b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0007a5feb040e1ff704f3ad636619ddca3e7382b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0477 tree 00084fe2cf48a3e4281c65ddf56881fa76cb1b31" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0477_00084fe2cf48a3e4281c65ddf56881fa76cb1b31.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/084fe2cf48a3e4281c65ddf56881fa76cb1b31",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00084fe2cf48a3e4281c65ddf56881fa76cb1b31",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0478 tree 00085821c84825ac7c47d974a9c8e3780282c236" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0478_00085821c84825ac7c47d974a9c8e3780282c236.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/085821c84825ac7c47d974a9c8e3780282c236",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00085821c84825ac7c47d974a9c8e3780282c236",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0479 tree 0008a1e9925c7fcb65a34aee9e210ec11654b773" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0479_0008a1e9925c7fcb65a34aee9e210ec11654b773.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/08a1e9925c7fcb65a34aee9e210ec11654b773",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0008a1e9925c7fcb65a34aee9e210ec11654b773",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0480 tree 0008c61b099c0a96f3ebcfd24ac4b95faf67115e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0480_0008c61b099c0a96f3ebcfd24ac4b95faf67115e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/08c61b099c0a96f3ebcfd24ac4b95faf67115e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0008c61b099c0a96f3ebcfd24ac4b95faf67115e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0481 tree 0009d5604c1c79d098303adfe580bdbe7f4a3b41" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0481_0009d5604c1c79d098303adfe580bdbe7f4a3b41.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/09d5604c1c79d098303adfe580bdbe7f4a3b41",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0009d5604c1c79d098303adfe580bdbe7f4a3b41",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0482 tree 0009e29800fdea42f03573ab231c4b91f0e84bc4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0482_0009e29800fdea42f03573ab231c4b91f0e84bc4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/09e29800fdea42f03573ab231c4b91f0e84bc4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0009e29800fdea42f03573ab231c4b91f0e84bc4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0483 tree 000a0382e736b024de1581ca3781b561a2ab1942" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0483_000a0382e736b024de1581ca3781b561a2ab1942.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0a0382e736b024de1581ca3781b561a2ab1942",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000a0382e736b024de1581ca3781b561a2ab1942",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0484 tree 000a2ec501e10ba5cae1bb3bd494f6109ea0f9ba" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0484_000a2ec501e10ba5cae1bb3bd494f6109ea0f9ba.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0a2ec501e10ba5cae1bb3bd494f6109ea0f9ba",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000a2ec501e10ba5cae1bb3bd494f6109ea0f9ba",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0485 tree 000a34fd8ca7712effc7de694eaca264f3681822" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0485_000a34fd8ca7712effc7de694eaca264f3681822.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0a34fd8ca7712effc7de694eaca264f3681822",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000a34fd8ca7712effc7de694eaca264f3681822",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0486 tree 000abc062797858c7c8da50ed6d23445c2b1f89c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0486_000abc062797858c7c8da50ed6d23445c2b1f89c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0abc062797858c7c8da50ed6d23445c2b1f89c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000abc062797858c7c8da50ed6d23445c2b1f89c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0487 tree 000be1d69bef6c7129bdc97568d441e6b8e6615a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0487_000be1d69bef6c7129bdc97568d441e6b8e6615a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0be1d69bef6c7129bdc97568d441e6b8e6615a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000be1d69bef6c7129bdc97568d441e6b8e6615a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0488 tree 000d00071b43dd78a4b74602ea84eb8c0d50362f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0488_000d00071b43dd78a4b74602ea84eb8c0d50362f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0d00071b43dd78a4b74602ea84eb8c0d50362f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000d00071b43dd78a4b74602ea84eb8c0d50362f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0489 tree 000d14cedf2bf4b38fb58e6dc0bb924898326b24" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0489_000d14cedf2bf4b38fb58e6dc0bb924898326b24.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0d14cedf2bf4b38fb58e6dc0bb924898326b24",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000d14cedf2bf4b38fb58e6dc0bb924898326b24",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0490 tree 000d37f24664df4f2765af156cdfc2f62d013967" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0490_000d37f24664df4f2765af156cdfc2f62d013967.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0d37f24664df4f2765af156cdfc2f62d013967",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000d37f24664df4f2765af156cdfc2f62d013967",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0491 tree 000e2239bd6b2e9d4c16408b75fe63183494bfbf" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0491_000e2239bd6b2e9d4c16408b75fe63183494bfbf.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0e2239bd6b2e9d4c16408b75fe63183494bfbf",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000e2239bd6b2e9d4c16408b75fe63183494bfbf",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0492 tree 000e84870c61ffe78d68106d16b483fbd7f2a250" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0492_000e84870c61ffe78d68106d16b483fbd7f2a250.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0e84870c61ffe78d68106d16b483fbd7f2a250",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000e84870c61ffe78d68106d16b483fbd7f2a250",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0493 tree 000ee20daccee5b594fd3f935e24d32ec5f10e33" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0493_000ee20daccee5b594fd3f935e24d32ec5f10e33.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0ee20daccee5b594fd3f935e24d32ec5f10e33",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000ee20daccee5b594fd3f935e24d32ec5f10e33",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0494 tree 000feb2ea490ecd13fe073ca4d92a1507ce246e2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0494_000feb2ea490ecd13fe073ca4d92a1507ce246e2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0feb2ea490ecd13fe073ca4d92a1507ce246e2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000feb2ea490ecd13fe073ca4d92a1507ce246e2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0495 tree 0010a59a311b2586b7409dd16dc78d141e348749" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0495_0010a59a311b2586b7409dd16dc78d141e348749.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/10a59a311b2586b7409dd16dc78d141e348749",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0010a59a311b2586b7409dd16dc78d141e348749",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0496 tree 0010c4ca615ef993f173cb4ce8d933b13dc6e135" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0496_0010c4ca615ef993f173cb4ce8d933b13dc6e135.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/10c4ca615ef993f173cb4ce8d933b13dc6e135",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0010c4ca615ef993f173cb4ce8d933b13dc6e135",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0497 tree 001177f82a93de8fa831e7134c4ddcfbeb030a24" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0497_001177f82a93de8fa831e7134c4ddcfbeb030a24.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1177f82a93de8fa831e7134c4ddcfbeb030a24",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001177f82a93de8fa831e7134c4ddcfbeb030a24",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0498 tree 0012929e62af8eee6a24e0795f46333d38a6d72f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0498_0012929e62af8eee6a24e0795f46333d38a6d72f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/12929e62af8eee6a24e0795f46333d38a6d72f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0012929e62af8eee6a24e0795f46333d38a6d72f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0499 tree 0013e189f06b7c8932323d00323ada6b50237776" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0499_0013e189f06b7c8932323d00323ada6b50237776.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/13e189f06b7c8932323d00323ada6b50237776",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0013e189f06b7c8932323d00323ada6b50237776",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0500 tree 0014851bdc71780993faa39e54897e6b1f8e25ce" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0500_0014851bdc71780993faa39e54897e6b1f8e25ce.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/14851bdc71780993faa39e54897e6b1f8e25ce",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0014851bdc71780993faa39e54897e6b1f8e25ce",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0501 tree 0014971e55ff2f95188c60f6c065ca47cdbbec1a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0501_0014971e55ff2f95188c60f6c065ca47cdbbec1a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/14971e55ff2f95188c60f6c065ca47cdbbec1a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0014971e55ff2f95188c60f6c065ca47cdbbec1a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0502 tree 0014a74c148ca303554167c1c16fed1bff944b05" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0502_0014a74c148ca303554167c1c16fed1bff944b05.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/14a74c148ca303554167c1c16fed1bff944b05",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0014a74c148ca303554167c1c16fed1bff944b05",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0503 tree 0014d7c2a5fcadce50f81277914173b426f72072" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0503_0014d7c2a5fcadce50f81277914173b426f72072.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/14d7c2a5fcadce50f81277914173b426f72072",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0014d7c2a5fcadce50f81277914173b426f72072",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0504 tree 001548acba7f76ea2c4303bc7f521ee8cc4b8eee" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0504_001548acba7f76ea2c4303bc7f521ee8cc4b8eee.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1548acba7f76ea2c4303bc7f521ee8cc4b8eee",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001548acba7f76ea2c4303bc7f521ee8cc4b8eee",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0505 tree 00156981952a89a6b7fb96cb08f2791a30c9a77d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0505_00156981952a89a6b7fb96cb08f2791a30c9a77d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/156981952a89a6b7fb96cb08f2791a30c9a77d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00156981952a89a6b7fb96cb08f2791a30c9a77d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0506 tree 00157ef1af98e9b7bcfa2e979010baeabb029613" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0506_00157ef1af98e9b7bcfa2e979010baeabb029613.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/157ef1af98e9b7bcfa2e979010baeabb029613",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00157ef1af98e9b7bcfa2e979010baeabb029613",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0507 tree 001616c2a8e96b6f8f3e845ada91d8c2c2ad735b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0507_001616c2a8e96b6f8f3e845ada91d8c2c2ad735b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1616c2a8e96b6f8f3e845ada91d8c2c2ad735b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001616c2a8e96b6f8f3e845ada91d8c2c2ad735b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0508 tree 00168240e7e31d2b1527f982c9b88b44c08c8593" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0508_00168240e7e31d2b1527f982c9b88b44c08c8593.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/168240e7e31d2b1527f982c9b88b44c08c8593",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00168240e7e31d2b1527f982c9b88b44c08c8593",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0509 tree 00171004dcfa80beadaf99dface42d22edbc94e1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0509_00171004dcfa80beadaf99dface42d22edbc94e1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/171004dcfa80beadaf99dface42d22edbc94e1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00171004dcfa80beadaf99dface42d22edbc94e1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0510 tree 0017320aba1e4abf0935b644e4512aae745b535e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0510_0017320aba1e4abf0935b644e4512aae745b535e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/17320aba1e4abf0935b644e4512aae745b535e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0017320aba1e4abf0935b644e4512aae745b535e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0511 tree 00176c786ea40bdb5746ab4aa1ba2ef72fa6c380" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0511_00176c786ea40bdb5746ab4aa1ba2ef72fa6c380.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/176c786ea40bdb5746ab4aa1ba2ef72fa6c380",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00176c786ea40bdb5746ab4aa1ba2ef72fa6c380",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0512 tree 001883bf5918588ed14f5dc903d96d2e622b831f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0512_001883bf5918588ed14f5dc903d96d2e622b831f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1883bf5918588ed14f5dc903d96d2e622b831f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001883bf5918588ed14f5dc903d96d2e622b831f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0513 tree 0018993299a23dc9a3924d655b3dc52f0df48841" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0513_0018993299a23dc9a3924d655b3dc52f0df48841.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/18993299a23dc9a3924d655b3dc52f0df48841",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0018993299a23dc9a3924d655b3dc52f0df48841",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0514 tree 0018f4f7ceef6f061e8c05fdb70e53ce6af2ec63" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0514_0018f4f7ceef6f061e8c05fdb70e53ce6af2ec63.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/18f4f7ceef6f061e8c05fdb70e53ce6af2ec63",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0018f4f7ceef6f061e8c05fdb70e53ce6af2ec63",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0515 tree 0019556cb9b7913de22a22e7b3081ea4abb425ac" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0515_0019556cb9b7913de22a22e7b3081ea4abb425ac.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/19556cb9b7913de22a22e7b3081ea4abb425ac",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0019556cb9b7913de22a22e7b3081ea4abb425ac",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0516 tree 001a64a115aa5614379ec4d328e71c88c8a51346" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0516_001a64a115aa5614379ec4d328e71c88c8a51346.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1a64a115aa5614379ec4d328e71c88c8a51346",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001a64a115aa5614379ec4d328e71c88c8a51346",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0517 tree 001ae72d0135871d4d3212aa880b988d8a011969" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0517_001ae72d0135871d4d3212aa880b988d8a011969.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1ae72d0135871d4d3212aa880b988d8a011969",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001ae72d0135871d4d3212aa880b988d8a011969",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0518 tree 001afe0a270e0b89cb7c9a08fae10b618dd89b0b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0518_001afe0a270e0b89cb7c9a08fae10b618dd89b0b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1afe0a270e0b89cb7c9a08fae10b618dd89b0b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001afe0a270e0b89cb7c9a08fae10b618dd89b0b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0519 tree 001b93a2cebe52fca97d0f310efb538151f0a6e8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0519_001b93a2cebe52fca97d0f310efb538151f0a6e8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1b93a2cebe52fca97d0f310efb538151f0a6e8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001b93a2cebe52fca97d0f310efb538151f0a6e8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0520 tree 001be6b42d68b64f46cd6bfee50270edce50815d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0520_001be6b42d68b64f46cd6bfee50270edce50815d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1be6b42d68b64f46cd6bfee50270edce50815d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001be6b42d68b64f46cd6bfee50270edce50815d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0521 tree 001c5f4eb5bd1f28d4aee5bd8814ba7f9c05f4aa" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0521_001c5f4eb5bd1f28d4aee5bd8814ba7f9c05f4aa.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1c5f4eb5bd1f28d4aee5bd8814ba7f9c05f4aa",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001c5f4eb5bd1f28d4aee5bd8814ba7f9c05f4aa",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0522 tree 001ce83dd43f03dcfc67f29d38922e4a9682aab0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0522_001ce83dd43f03dcfc67f29d38922e4a9682aab0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1ce83dd43f03dcfc67f29d38922e4a9682aab0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001ce83dd43f03dcfc67f29d38922e4a9682aab0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0523 tree 001d99652a7e824b1098880b7f2f4b3202b4d1ab" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0523_001d99652a7e824b1098880b7f2f4b3202b4d1ab.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1d99652a7e824b1098880b7f2f4b3202b4d1ab",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001d99652a7e824b1098880b7f2f4b3202b4d1ab",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0524 tree 001e1a72331f55d004a63f4cf10714f45a8907fe" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0524_001e1a72331f55d004a63f4cf10714f45a8907fe.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1e1a72331f55d004a63f4cf10714f45a8907fe",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001e1a72331f55d004a63f4cf10714f45a8907fe",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0525 tree 001e908a38f0bc19cb5a2762c899d0144e3f29ec" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0525_001e908a38f0bc19cb5a2762c899d0144e3f29ec.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1e908a38f0bc19cb5a2762c899d0144e3f29ec",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001e908a38f0bc19cb5a2762c899d0144e3f29ec",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0526 tree 001e9c710a3c7a4d340f45024665b962b8696814" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0526_001e9c710a3c7a4d340f45024665b962b8696814.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1e9c710a3c7a4d340f45024665b962b8696814",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001e9c710a3c7a4d340f45024665b962b8696814",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0527 tree 001ef8644b83dc2d1d55c6e8b8a0c6c3da315fdb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0527_001ef8644b83dc2d1d55c6e8b8a0c6c3da315fdb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1ef8644b83dc2d1d55c6e8b8a0c6c3da315fdb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001ef8644b83dc2d1d55c6e8b8a0c6c3da315fdb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0528 tree 001f5cf2e0f68410afeb84e7f91278fb90776bc9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0528_001f5cf2e0f68410afeb84e7f91278fb90776bc9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1f5cf2e0f68410afeb84e7f91278fb90776bc9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001f5cf2e0f68410afeb84e7f91278fb90776bc9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0529 tree 001f947be2c8b393bc34e314f3b27c6b7a3e5c28" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0529_001f947be2c8b393bc34e314f3b27c6b7a3e5c28.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1f947be2c8b393bc34e314f3b27c6b7a3e5c28",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001f947be2c8b393bc34e314f3b27c6b7a3e5c28",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0530 tree 001f9ccae307ef32eab9e60f426aa1e80342bd03" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0530_001f9ccae307ef32eab9e60f426aa1e80342bd03.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1f9ccae307ef32eab9e60f426aa1e80342bd03",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001f9ccae307ef32eab9e60f426aa1e80342bd03",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0531 tree 0020d08bd3b38f3bbe16ae2e11dc428da06f2f21" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0531_0020d08bd3b38f3bbe16ae2e11dc428da06f2f21.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/20d08bd3b38f3bbe16ae2e11dc428da06f2f21",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0020d08bd3b38f3bbe16ae2e11dc428da06f2f21",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0532 tree 0021a7b28c992ad322f85b5e2cfd7e4004b51fd2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0532_0021a7b28c992ad322f85b5e2cfd7e4004b51fd2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/21a7b28c992ad322f85b5e2cfd7e4004b51fd2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0021a7b28c992ad322f85b5e2cfd7e4004b51fd2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0533 tree 0021bcb9ff7cad4bb03e766507837ecc3d81932b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0533_0021bcb9ff7cad4bb03e766507837ecc3d81932b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/21bcb9ff7cad4bb03e766507837ecc3d81932b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0021bcb9ff7cad4bb03e766507837ecc3d81932b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0534 tree 0021e183d84e4359b66485a9d74c951a93ab9264" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0534_0021e183d84e4359b66485a9d74c951a93ab9264.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/21e183d84e4359b66485a9d74c951a93ab9264",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0021e183d84e4359b66485a9d74c951a93ab9264",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0535 tree 00223dd5484162494b966e7634a2fea156ff0703" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0535_00223dd5484162494b966e7634a2fea156ff0703.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/223dd5484162494b966e7634a2fea156ff0703",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00223dd5484162494b966e7634a2fea156ff0703",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0536 tree 00224aa1d8c3bb5cf7ca28da66915232db017f2b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0536_00224aa1d8c3bb5cf7ca28da66915232db017f2b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/224aa1d8c3bb5cf7ca28da66915232db017f2b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00224aa1d8c3bb5cf7ca28da66915232db017f2b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0537 tree 00225bf13e2481df2bfa8873304530afae0ea6ab" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0537_00225bf13e2481df2bfa8873304530afae0ea6ab.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/225bf13e2481df2bfa8873304530afae0ea6ab",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00225bf13e2481df2bfa8873304530afae0ea6ab",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0538 tree 0022d4d4dab76cdc5a321fb4220f8217cb79e136" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0538_0022d4d4dab76cdc5a321fb4220f8217cb79e136.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/22d4d4dab76cdc5a321fb4220f8217cb79e136",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0022d4d4dab76cdc5a321fb4220f8217cb79e136",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0539 tree 002351c9462943b5673cc49d51123e3787df8bc6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0539_002351c9462943b5673cc49d51123e3787df8bc6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2351c9462943b5673cc49d51123e3787df8bc6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002351c9462943b5673cc49d51123e3787df8bc6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0540 tree 0024523ca966cb12641c6dfd616b97628124298a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0540_0024523ca966cb12641c6dfd616b97628124298a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/24523ca966cb12641c6dfd616b97628124298a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0024523ca966cb12641c6dfd616b97628124298a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0541 tree 00246a64edde6a9cdfbcf72aff618f3cea47e627" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0541_00246a64edde6a9cdfbcf72aff618f3cea47e627.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/246a64edde6a9cdfbcf72aff618f3cea47e627",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00246a64edde6a9cdfbcf72aff618f3cea47e627",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0542 tree 0024f68fed38ec103d5ab6d3ca8a7313d66ac664" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0542_0024f68fed38ec103d5ab6d3ca8a7313d66ac664.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/24f68fed38ec103d5ab6d3ca8a7313d66ac664",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0024f68fed38ec103d5ab6d3ca8a7313d66ac664",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0543 tree 0024fb369d967587fd3d01bb06adffa4104d4e40" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0543_0024fb369d967587fd3d01bb06adffa4104d4e40.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/24fb369d967587fd3d01bb06adffa4104d4e40",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0024fb369d967587fd3d01bb06adffa4104d4e40",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0544 tree 00250527dbd3ed66219a1b07fcccc40dda50b33d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0544_00250527dbd3ed66219a1b07fcccc40dda50b33d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/250527dbd3ed66219a1b07fcccc40dda50b33d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00250527dbd3ed66219a1b07fcccc40dda50b33d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0545 tree 0025270b218499140b00d416e6ba804731023bc5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0545_0025270b218499140b00d416e6ba804731023bc5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/25270b218499140b00d416e6ba804731023bc5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0025270b218499140b00d416e6ba804731023bc5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0546 tree 00264af173b8d49d1c9ef2cc5ba80aa7c0ee49ce" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0546_00264af173b8d49d1c9ef2cc5ba80aa7c0ee49ce.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/264af173b8d49d1c9ef2cc5ba80aa7c0ee49ce",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00264af173b8d49d1c9ef2cc5ba80aa7c0ee49ce",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0547 tree 0026b67f47a039ada14312ec23decb7ceb265bd9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0547_0026b67f47a039ada14312ec23decb7ceb265bd9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/26b67f47a039ada14312ec23decb7ceb265bd9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0026b67f47a039ada14312ec23decb7ceb265bd9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0548 tree 0027a1009be48eb596edac022cf7f213e47a2577" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0548_0027a1009be48eb596edac022cf7f213e47a2577.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/27a1009be48eb596edac022cf7f213e47a2577",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0027a1009be48eb596edac022cf7f213e47a2577",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0549 tree 0028466bdab0b8c246d276b76a3ef0e433a87afb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0549_0028466bdab0b8c246d276b76a3ef0e433a87afb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/28466bdab0b8c246d276b76a3ef0e433a87afb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0028466bdab0b8c246d276b76a3ef0e433a87afb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0550 tree 0028ae1684fe3d1a967195a21c608b4726797647" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0550_0028ae1684fe3d1a967195a21c608b4726797647.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/28ae1684fe3d1a967195a21c608b4726797647",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0028ae1684fe3d1a967195a21c608b4726797647",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0551 tree 0028d3725ccd9869b34890f3e0a76a90dbfdd6b5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0551_0028d3725ccd9869b34890f3e0a76a90dbfdd6b5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/28d3725ccd9869b34890f3e0a76a90dbfdd6b5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0028d3725ccd9869b34890f3e0a76a90dbfdd6b5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0552 tree 0029190a909e5dbebc3b146b08884c299bc74f80" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0552_0029190a909e5dbebc3b146b08884c299bc74f80.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/29190a909e5dbebc3b146b08884c299bc74f80",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0029190a909e5dbebc3b146b08884c299bc74f80",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0553 tree 00292a2eec45efa23eb82c27471f0730dd78a85d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0553_00292a2eec45efa23eb82c27471f0730dd78a85d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/292a2eec45efa23eb82c27471f0730dd78a85d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00292a2eec45efa23eb82c27471f0730dd78a85d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0554 tree 00295cec9d8c7e81efcd8829e8bd00c1f5d4758d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0554_00295cec9d8c7e81efcd8829e8bd00c1f5d4758d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/295cec9d8c7e81efcd8829e8bd00c1f5d4758d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00295cec9d8c7e81efcd8829e8bd00c1f5d4758d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0555 tree 0029d079de66eaf739962e2230536e10fe508c98" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0555_0029d079de66eaf739962e2230536e10fe508c98.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/29d079de66eaf739962e2230536e10fe508c98",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0029d079de66eaf739962e2230536e10fe508c98",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0556 tree 002aafcb67d5cb9b65889ad9c07593eb3ca5b019" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0556_002aafcb67d5cb9b65889ad9c07593eb3ca5b019.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2aafcb67d5cb9b65889ad9c07593eb3ca5b019",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002aafcb67d5cb9b65889ad9c07593eb3ca5b019",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0557 tree 002b558f9d2a643b41428eaa60d11f716ddb6573" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0557_002b558f9d2a643b41428eaa60d11f716ddb6573.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2b558f9d2a643b41428eaa60d11f716ddb6573",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002b558f9d2a643b41428eaa60d11f716ddb6573",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0558 tree 002c384df521e31c16f645e909dc4ca7991b36cd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0558_002c384df521e31c16f645e909dc4ca7991b36cd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2c384df521e31c16f645e909dc4ca7991b36cd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002c384df521e31c16f645e909dc4ca7991b36cd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0559 tree 002c9cb871122cfb7552b242572c16315c12af7e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0559_002c9cb871122cfb7552b242572c16315c12af7e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2c9cb871122cfb7552b242572c16315c12af7e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002c9cb871122cfb7552b242572c16315c12af7e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0560 tree 002ca0e16de54c4a252214a8bb221cee180f3c90" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0560_002ca0e16de54c4a252214a8bb221cee180f3c90.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2ca0e16de54c4a252214a8bb221cee180f3c90",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002ca0e16de54c4a252214a8bb221cee180f3c90",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0561 tree 002cf45613d54d8e548b051f38a8999cbcdd0fda" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0561_002cf45613d54d8e548b051f38a8999cbcdd0fda.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2cf45613d54d8e548b051f38a8999cbcdd0fda",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002cf45613d54d8e548b051f38a8999cbcdd0fda",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0562 tree 002d32aecf30b4e814c39dd5e309b645547d4df6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0562_002d32aecf30b4e814c39dd5e309b645547d4df6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2d32aecf30b4e814c39dd5e309b645547d4df6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002d32aecf30b4e814c39dd5e309b645547d4df6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0563 tree 002d4469dfa8c17792e1296988316d6db2d4d559" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0563_002d4469dfa8c17792e1296988316d6db2d4d559.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2d4469dfa8c17792e1296988316d6db2d4d559",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002d4469dfa8c17792e1296988316d6db2d4d559",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0564 tree 002d481db5b2de5530d0b69ae470a7ebe5f77892" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0564_002d481db5b2de5530d0b69ae470a7ebe5f77892.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2d481db5b2de5530d0b69ae470a7ebe5f77892",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002d481db5b2de5530d0b69ae470a7ebe5f77892",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0565 tree 002d5e1bd591e098359d2b3b3c226342045468d0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0565_002d5e1bd591e098359d2b3b3c226342045468d0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2d5e1bd591e098359d2b3b3c226342045468d0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002d5e1bd591e098359d2b3b3c226342045468d0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0566 tree 002db882ece2ab6a240e495a169c6e06422289c8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0566_002db882ece2ab6a240e495a169c6e06422289c8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2db882ece2ab6a240e495a169c6e06422289c8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002db882ece2ab6a240e495a169c6e06422289c8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0567 tree 002dfa6084fb4a4288ceb3e0820d46667a052557" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0567_002dfa6084fb4a4288ceb3e0820d46667a052557.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2dfa6084fb4a4288ceb3e0820d46667a052557",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002dfa6084fb4a4288ceb3e0820d46667a052557",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0568 tree 002dfd4a6a6e8fd8a681302010cba425cb49255e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0568_002dfd4a6a6e8fd8a681302010cba425cb49255e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2dfd4a6a6e8fd8a681302010cba425cb49255e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002dfd4a6a6e8fd8a681302010cba425cb49255e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0569 tree 002e09d756c13f24baa319807bc1e5730fd21cd7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0569_002e09d756c13f24baa319807bc1e5730fd21cd7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2e09d756c13f24baa319807bc1e5730fd21cd7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002e09d756c13f24baa319807bc1e5730fd21cd7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0570 tree 002f2a0828a8fb39cf2aa94d0d29c8145ff3ca5c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0570_002f2a0828a8fb39cf2aa94d0d29c8145ff3ca5c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2f2a0828a8fb39cf2aa94d0d29c8145ff3ca5c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002f2a0828a8fb39cf2aa94d0d29c8145ff3ca5c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0571 tree 002f9ee6fb1a4262c9940e37830669da6fed9d70" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0571_002f9ee6fb1a4262c9940e37830669da6fed9d70.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2f9ee6fb1a4262c9940e37830669da6fed9d70",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002f9ee6fb1a4262c9940e37830669da6fed9d70",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0572 tree 003001d968b351c95fbc6528179dc80d27f72186" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0572_003001d968b351c95fbc6528179dc80d27f72186.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3001d968b351c95fbc6528179dc80d27f72186",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003001d968b351c95fbc6528179dc80d27f72186",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0573 tree 003083cd0f42101fa722fb26b7e3ed0651bb4115" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0573_003083cd0f42101fa722fb26b7e3ed0651bb4115.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3083cd0f42101fa722fb26b7e3ed0651bb4115",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003083cd0f42101fa722fb26b7e3ed0651bb4115",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0574 tree 00310cf107369aef0e5e57a35b5e58bc0f93e018" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0574_00310cf107369aef0e5e57a35b5e58bc0f93e018.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/310cf107369aef0e5e57a35b5e58bc0f93e018",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00310cf107369aef0e5e57a35b5e58bc0f93e018",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0575 tree 0031dc21d3ea2bad5754d1b48eafe64f4c5ca491" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0575_0031dc21d3ea2bad5754d1b48eafe64f4c5ca491.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/31dc21d3ea2bad5754d1b48eafe64f4c5ca491",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0031dc21d3ea2bad5754d1b48eafe64f4c5ca491",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0576 tree 003272b2af7b09237311f2c40e10883d0e3a6520" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0576_003272b2af7b09237311f2c40e10883d0e3a6520.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3272b2af7b09237311f2c40e10883d0e3a6520",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003272b2af7b09237311f2c40e10883d0e3a6520",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0577 tree 0032a185683f95393e112feb827ecf163d4c9897" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0577_0032a185683f95393e112feb827ecf163d4c9897.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/32a185683f95393e112feb827ecf163d4c9897",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0032a185683f95393e112feb827ecf163d4c9897",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0578 tree 003354ea236e5b5c9ca70bc035c5d7bb2d4d9458" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0578_003354ea236e5b5c9ca70bc035c5d7bb2d4d9458.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3354ea236e5b5c9ca70bc035c5d7bb2d4d9458",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003354ea236e5b5c9ca70bc035c5d7bb2d4d9458",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0579 tree 0033940e60d3f55f90d351e7d29b133aa26c2bad" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0579_0033940e60d3f55f90d351e7d29b133aa26c2bad.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/33940e60d3f55f90d351e7d29b133aa26c2bad",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0033940e60d3f55f90d351e7d29b133aa26c2bad",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0580 tree 0034e53144b06603d0a14d7bad514c3d37de4bbe" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0580_0034e53144b06603d0a14d7bad514c3d37de4bbe.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/34e53144b06603d0a14d7bad514c3d37de4bbe",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0034e53144b06603d0a14d7bad514c3d37de4bbe",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0581 tree 00358494dd944420a46a66396739fa3e6c7c7ae8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0581_00358494dd944420a46a66396739fa3e6c7c7ae8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/358494dd944420a46a66396739fa3e6c7c7ae8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00358494dd944420a46a66396739fa3e6c7c7ae8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0582 tree 0035be6c371c7a8b306ae7fded6efe0f8d3c7da7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0582_0035be6c371c7a8b306ae7fded6efe0f8d3c7da7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/35be6c371c7a8b306ae7fded6efe0f8d3c7da7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0035be6c371c7a8b306ae7fded6efe0f8d3c7da7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0583 tree 0035d368a857b7c7614b498c645ac1aa7a059fd0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0583_0035d368a857b7c7614b498c645ac1aa7a059fd0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/35d368a857b7c7614b498c645ac1aa7a059fd0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0035d368a857b7c7614b498c645ac1aa7a059fd0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0584 tree 003629b9873324ec09a786d2c2b2ea90e6e0f58a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0584_003629b9873324ec09a786d2c2b2ea90e6e0f58a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3629b9873324ec09a786d2c2b2ea90e6e0f58a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003629b9873324ec09a786d2c2b2ea90e6e0f58a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0585 tree 00364e1f41c1c72ad5465deaf91f2c843e26e954" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0585_00364e1f41c1c72ad5465deaf91f2c843e26e954.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/364e1f41c1c72ad5465deaf91f2c843e26e954",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00364e1f41c1c72ad5465deaf91f2c843e26e954",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0586 tree 0036bd03a8db762e1be604a18e80de8c78f93ad0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0586_0036bd03a8db762e1be604a18e80de8c78f93ad0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/36bd03a8db762e1be604a18e80de8c78f93ad0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0036bd03a8db762e1be604a18e80de8c78f93ad0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0587 tree 0036cd868abd43d64a7bf13fda39aec1a1e79d55" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0587_0036cd868abd43d64a7bf13fda39aec1a1e79d55.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/36cd868abd43d64a7bf13fda39aec1a1e79d55",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0036cd868abd43d64a7bf13fda39aec1a1e79d55",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0588 tree 00386687e18c7c4e9fb52ffb9834d3870e5b6cb8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0588_00386687e18c7c4e9fb52ffb9834d3870e5b6cb8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/386687e18c7c4e9fb52ffb9834d3870e5b6cb8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00386687e18c7c4e9fb52ffb9834d3870e5b6cb8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0589 tree 00387aa12446964804aa3a6cd72167b1084baaae" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0589_00387aa12446964804aa3a6cd72167b1084baaae.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/387aa12446964804aa3a6cd72167b1084baaae",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00387aa12446964804aa3a6cd72167b1084baaae",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0590 tree 0039671e6d2d25f69425e4e0c6ff820adf0aac4d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0590_0039671e6d2d25f69425e4e0c6ff820adf0aac4d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/39671e6d2d25f69425e4e0c6ff820adf0aac4d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0039671e6d2d25f69425e4e0c6ff820adf0aac4d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0591 tree 003a47bd55cc900624402cee450d0922a446aec4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0591_003a47bd55cc900624402cee450d0922a446aec4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3a47bd55cc900624402cee450d0922a446aec4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003a47bd55cc900624402cee450d0922a446aec4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0592 tree 003aa9057ced725f8654038013c1ee7c97b71716" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0592_003aa9057ced725f8654038013c1ee7c97b71716.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3aa9057ced725f8654038013c1ee7c97b71716",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003aa9057ced725f8654038013c1ee7c97b71716",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0593 tree 003ae874ace62bfe01945a8a866f19728ede4974" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0593_003ae874ace62bfe01945a8a866f19728ede4974.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3ae874ace62bfe01945a8a866f19728ede4974",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003ae874ace62bfe01945a8a866f19728ede4974",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0594 tree 003c4231419d07820d589aad0c2400711a5f0ad2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0594_003c4231419d07820d589aad0c2400711a5f0ad2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3c4231419d07820d589aad0c2400711a5f0ad2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003c4231419d07820d589aad0c2400711a5f0ad2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0595 tree 003c6bec059d113cd3363b541a9cf0cc7ebdd33a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0595_003c6bec059d113cd3363b541a9cf0cc7ebdd33a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3c6bec059d113cd3363b541a9cf0cc7ebdd33a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003c6bec059d113cd3363b541a9cf0cc7ebdd33a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0596 tree 003cf1e61da5c5fe13ed574ae3630c1ee8b56cae" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0596_003cf1e61da5c5fe13ed574ae3630c1ee8b56cae.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3cf1e61da5c5fe13ed574ae3630c1ee8b56cae",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003cf1e61da5c5fe13ed574ae3630c1ee8b56cae",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0597 tree 003d04d09175737a1a8e9ab1f76be0a602011f53" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0597_003d04d09175737a1a8e9ab1f76be0a602011f53.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3d04d09175737a1a8e9ab1f76be0a602011f53",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003d04d09175737a1a8e9ab1f76be0a602011f53",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0598 tree 003d6020e014d51269a9b299f5a829b70194227e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0598_003d6020e014d51269a9b299f5a829b70194227e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3d6020e014d51269a9b299f5a829b70194227e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003d6020e014d51269a9b299f5a829b70194227e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0599 tree 003d7e949aa3af9b4d1a230873c379b4cdec8d81" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0599_003d7e949aa3af9b4d1a230873c379b4cdec8d81.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3d7e949aa3af9b4d1a230873c379b4cdec8d81",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003d7e949aa3af9b4d1a230873c379b4cdec8d81",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0600 tree 003e2eba20df2e7110dd02083fa6b9b40f4edb7b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0600_003e2eba20df2e7110dd02083fa6b9b40f4edb7b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3e2eba20df2e7110dd02083fa6b9b40f4edb7b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003e2eba20df2e7110dd02083fa6b9b40f4edb7b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0601 tree 003eed89aa8e422b7a604d02542cc929d50852d1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0601_003eed89aa8e422b7a604d02542cc929d50852d1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3eed89aa8e422b7a604d02542cc929d50852d1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003eed89aa8e422b7a604d02542cc929d50852d1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0602 tree 003f082c15b11ebc24f7c8bf95d5bfbb719a7cda" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0602_003f082c15b11ebc24f7c8bf95d5bfbb719a7cda.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3f082c15b11ebc24f7c8bf95d5bfbb719a7cda",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003f082c15b11ebc24f7c8bf95d5bfbb719a7cda",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0603 tree 003f73860c8b780387a16986e645f7e2aafa300d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0603_003f73860c8b780387a16986e645f7e2aafa300d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3f73860c8b780387a16986e645f7e2aafa300d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003f73860c8b780387a16986e645f7e2aafa300d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0604 tree 003f73b5c9cf4bb14b617c935d9c50a0c917a758" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0604_003f73b5c9cf4bb14b617c935d9c50a0c917a758.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3f73b5c9cf4bb14b617c935d9c50a0c917a758",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003f73b5c9cf4bb14b617c935d9c50a0c917a758",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0605 tree 003fd7ad62a75c46abf40aa1c3f25affefbdf327" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0605_003fd7ad62a75c46abf40aa1c3f25affefbdf327.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3fd7ad62a75c46abf40aa1c3f25affefbdf327",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003fd7ad62a75c46abf40aa1c3f25affefbdf327",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0606 tree 0040b5935a3b0df9bf0c0cbef6b4a3e93f32751c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0606_0040b5935a3b0df9bf0c0cbef6b4a3e93f32751c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/40b5935a3b0df9bf0c0cbef6b4a3e93f32751c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0040b5935a3b0df9bf0c0cbef6b4a3e93f32751c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0607 tree 0040f086246c6dc88c88479bd087baf436a7c8b3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0607_0040f086246c6dc88c88479bd087baf436a7c8b3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/40f086246c6dc88c88479bd087baf436a7c8b3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0040f086246c6dc88c88479bd087baf436a7c8b3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0608 tree 00410bbbd9c04128fa54a1bed01c536e81bb56fb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0608_00410bbbd9c04128fa54a1bed01c536e81bb56fb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/410bbbd9c04128fa54a1bed01c536e81bb56fb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00410bbbd9c04128fa54a1bed01c536e81bb56fb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0609 tree 00417eacc5e390a46cf87cf368d39d0495b40479" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0609_00417eacc5e390a46cf87cf368d39d0495b40479.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/417eacc5e390a46cf87cf368d39d0495b40479",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00417eacc5e390a46cf87cf368d39d0495b40479",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0610 tree 0042255821ff32d2ed4fdbf776cad4326ec24be7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0610_0042255821ff32d2ed4fdbf776cad4326ec24be7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/42255821ff32d2ed4fdbf776cad4326ec24be7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0042255821ff32d2ed4fdbf776cad4326ec24be7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0611 tree 00423e31a71bd01d15cd723826bd9e1d8340f3c1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0611_00423e31a71bd01d15cd723826bd9e1d8340f3c1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/423e31a71bd01d15cd723826bd9e1d8340f3c1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00423e31a71bd01d15cd723826bd9e1d8340f3c1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0612 tree 0042a6a266598a7d5001f3e4a04e1fea62c9df75" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0612_0042a6a266598a7d5001f3e4a04e1fea62c9df75.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/42a6a266598a7d5001f3e4a04e1fea62c9df75",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0042a6a266598a7d5001f3e4a04e1fea62c9df75",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0613 tree 004322ee57196e10e308a8d50bbdb03a2cb87ce6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0613_004322ee57196e10e308a8d50bbdb03a2cb87ce6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4322ee57196e10e308a8d50bbdb03a2cb87ce6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004322ee57196e10e308a8d50bbdb03a2cb87ce6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0614 tree 0043651653e62cd21bd1b3c9b6a6e6e17f38b29f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0614_0043651653e62cd21bd1b3c9b6a6e6e17f38b29f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/43651653e62cd21bd1b3c9b6a6e6e17f38b29f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0043651653e62cd21bd1b3c9b6a6e6e17f38b29f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0615 tree 00437e0123b00c13dae529d15029f652f4dd0a51" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0615_00437e0123b00c13dae529d15029f652f4dd0a51.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/437e0123b00c13dae529d15029f652f4dd0a51",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00437e0123b00c13dae529d15029f652f4dd0a51",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0616 tree 004451970eaf52760d143e7788e9f5f11517113c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0616_004451970eaf52760d143e7788e9f5f11517113c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4451970eaf52760d143e7788e9f5f11517113c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004451970eaf52760d143e7788e9f5f11517113c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0617 tree 0044c6f61e515585132625d5cebc9b48a5ade8f2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0617_0044c6f61e515585132625d5cebc9b48a5ade8f2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/44c6f61e515585132625d5cebc9b48a5ade8f2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0044c6f61e515585132625d5cebc9b48a5ade8f2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0618 tree 00454ac41711e1e39ba909f006ff689704db5c29" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0618_00454ac41711e1e39ba909f006ff689704db5c29.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/454ac41711e1e39ba909f006ff689704db5c29",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00454ac41711e1e39ba909f006ff689704db5c29",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0619 tree 00454e539f6f1942aba0e0ce89199cf83499bd71" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0619_00454e539f6f1942aba0e0ce89199cf83499bd71.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/454e539f6f1942aba0e0ce89199cf83499bd71",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00454e539f6f1942aba0e0ce89199cf83499bd71",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0620 tree 0045810462c348517e2885818aa8e7d4d1c1af45" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0620_0045810462c348517e2885818aa8e7d4d1c1af45.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/45810462c348517e2885818aa8e7d4d1c1af45",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0045810462c348517e2885818aa8e7d4d1c1af45",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0621 tree 00461313b09ef04e07561521f5fb307187e7f053" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0621_00461313b09ef04e07561521f5fb307187e7f053.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/461313b09ef04e07561521f5fb307187e7f053",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00461313b09ef04e07561521f5fb307187e7f053",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0622 tree 00465fcad702d8300676fa1043e10600f5ef5d42" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0622_00465fcad702d8300676fa1043e10600f5ef5d42.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/465fcad702d8300676fa1043e10600f5ef5d42",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00465fcad702d8300676fa1043e10600f5ef5d42",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0623 tree 0046ed4ab07df6e933ed356e7f8ace1cd4b71638" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0623_0046ed4ab07df6e933ed356e7f8ace1cd4b71638.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/46ed4ab07df6e933ed356e7f8ace1cd4b71638",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0046ed4ab07df6e933ed356e7f8ace1cd4b71638",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0624 tree 004759bd8125a5e637254a8b498fee10c42d199f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0624_004759bd8125a5e637254a8b498fee10c42d199f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4759bd8125a5e637254a8b498fee10c42d199f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004759bd8125a5e637254a8b498fee10c42d199f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0625 tree 0047653dada0d9bd3b82cb0b0ab84063db715d5f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0625_0047653dada0d9bd3b82cb0b0ab84063db715d5f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/47653dada0d9bd3b82cb0b0ab84063db715d5f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0047653dada0d9bd3b82cb0b0ab84063db715d5f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0626 tree 004792f1217a75e9b45e472617bfc4ca3957f085" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0626_004792f1217a75e9b45e472617bfc4ca3957f085.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4792f1217a75e9b45e472617bfc4ca3957f085",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004792f1217a75e9b45e472617bfc4ca3957f085",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0627 tree 00483a03935fd0201f359948af64b16f5aea7437" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0627_00483a03935fd0201f359948af64b16f5aea7437.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/483a03935fd0201f359948af64b16f5aea7437",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00483a03935fd0201f359948af64b16f5aea7437",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0628 tree 0049288495683008d89911a9969da9327eb0d80e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0628_0049288495683008d89911a9969da9327eb0d80e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/49288495683008d89911a9969da9327eb0d80e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0049288495683008d89911a9969da9327eb0d80e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0629 tree 004935cfde776d78f8e1ee17d8e79cce0d55282a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0629_004935cfde776d78f8e1ee17d8e79cce0d55282a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4935cfde776d78f8e1ee17d8e79cce0d55282a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004935cfde776d78f8e1ee17d8e79cce0d55282a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0630 tree 004976181827e55ee150fe5a9eb8d0b7106db26c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0630_004976181827e55ee150fe5a9eb8d0b7106db26c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4976181827e55ee150fe5a9eb8d0b7106db26c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004976181827e55ee150fe5a9eb8d0b7106db26c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0631 tree 00499f7b08f8ecf28b2740da66e3180b44738224" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0631_00499f7b08f8ecf28b2740da66e3180b44738224.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/499f7b08f8ecf28b2740da66e3180b44738224",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00499f7b08f8ecf28b2740da66e3180b44738224",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0632 tree 0049c8c6537753b1418ca8b2b4bb9dc02d386fb7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0632_0049c8c6537753b1418ca8b2b4bb9dc02d386fb7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/49c8c6537753b1418ca8b2b4bb9dc02d386fb7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0049c8c6537753b1418ca8b2b4bb9dc02d386fb7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0633 tree 004a540f8add5e9a792060793853eafee4b53086" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0633_004a540f8add5e9a792060793853eafee4b53086.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4a540f8add5e9a792060793853eafee4b53086",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004a540f8add5e9a792060793853eafee4b53086",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0634 tree 004a96534ee6f26ab5c904827092a3afa0a97b8a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0634_004a96534ee6f26ab5c904827092a3afa0a97b8a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4a96534ee6f26ab5c904827092a3afa0a97b8a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004a96534ee6f26ab5c904827092a3afa0a97b8a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0635 tree 004ab1a5bcbe6593373c102431c3dd91bad44783" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0635_004ab1a5bcbe6593373c102431c3dd91bad44783.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4ab1a5bcbe6593373c102431c3dd91bad44783",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004ab1a5bcbe6593373c102431c3dd91bad44783",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0636 tree 004b18325fca198ffb5e15b827728c6abf9f9edc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0636_004b18325fca198ffb5e15b827728c6abf9f9edc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4b18325fca198ffb5e15b827728c6abf9f9edc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004b18325fca198ffb5e15b827728c6abf9f9edc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0637 tree 004b439c43f83336c011139f0ddff67a45b7d233" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0637_004b439c43f83336c011139f0ddff67a45b7d233.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4b439c43f83336c011139f0ddff67a45b7d233",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004b439c43f83336c011139f0ddff67a45b7d233",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0638 tree 004bbfc2c1e877e7a93b6cade545b6c1f9c8e883" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0638_004bbfc2c1e877e7a93b6cade545b6c1f9c8e883.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4bbfc2c1e877e7a93b6cade545b6c1f9c8e883",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004bbfc2c1e877e7a93b6cade545b6c1f9c8e883",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0639 tree 004ca814083135b984d9d5ebd9baa433589fd885" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0639_004ca814083135b984d9d5ebd9baa433589fd885.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4ca814083135b984d9d5ebd9baa433589fd885",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004ca814083135b984d9d5ebd9baa433589fd885",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0640 tree 004d05ed16ef33adf3385a94022ed4dfd0d2a918" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0640_004d05ed16ef33adf3385a94022ed4dfd0d2a918.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4d05ed16ef33adf3385a94022ed4dfd0d2a918",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004d05ed16ef33adf3385a94022ed4dfd0d2a918",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0641 tree 004d1a01c5be6f6422d928b3d8b5ceecf4e6b76d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0641_004d1a01c5be6f6422d928b3d8b5ceecf4e6b76d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4d1a01c5be6f6422d928b3d8b5ceecf4e6b76d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004d1a01c5be6f6422d928b3d8b5ceecf4e6b76d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0642 tree 004d2bc28b41b064858cf021770168a79b0c2fc2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0642_004d2bc28b41b064858cf021770168a79b0c2fc2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4d2bc28b41b064858cf021770168a79b0c2fc2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004d2bc28b41b064858cf021770168a79b0c2fc2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0643 tree 004d7ebcd753d22060530bbe149a15d7d5df6fc2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0643_004d7ebcd753d22060530bbe149a15d7d5df6fc2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4d7ebcd753d22060530bbe149a15d7d5df6fc2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004d7ebcd753d22060530bbe149a15d7d5df6fc2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0644 tree 004dba68cb73504f544402d2549aa15874a39a38" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0644_004dba68cb73504f544402d2549aa15874a39a38.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4dba68cb73504f544402d2549aa15874a39a38",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004dba68cb73504f544402d2549aa15874a39a38",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0645 tree 004ec26a4fd1a8617a42978545b39e6b193dfc1a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0645_004ec26a4fd1a8617a42978545b39e6b193dfc1a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4ec26a4fd1a8617a42978545b39e6b193dfc1a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004ec26a4fd1a8617a42978545b39e6b193dfc1a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0646 tree 004f6b721f9ce71025e93a93554fdf15c4095720" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0646_004f6b721f9ce71025e93a93554fdf15c4095720.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4f6b721f9ce71025e93a93554fdf15c4095720",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004f6b721f9ce71025e93a93554fdf15c4095720",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0647 tree 004f948b77d4705b4b3fcabdf386a73475a0f053" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0647_004f948b77d4705b4b3fcabdf386a73475a0f053.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4f948b77d4705b4b3fcabdf386a73475a0f053",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004f948b77d4705b4b3fcabdf386a73475a0f053",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0648 tree 004fe0ffaa644c708a55fc27549f1639a2871dee" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0648_004fe0ffaa644c708a55fc27549f1639a2871dee.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4fe0ffaa644c708a55fc27549f1639a2871dee",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004fe0ffaa644c708a55fc27549f1639a2871dee",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0649 tree 0050c389f8a446223c2904cffb7915000f3a2d62" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0649_0050c389f8a446223c2904cffb7915000f3a2d62.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/50c389f8a446223c2904cffb7915000f3a2d62",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0050c389f8a446223c2904cffb7915000f3a2d62",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0650 tree 0051911081eef1869a7c7e2a6ca54ede709db4db" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0650_0051911081eef1869a7c7e2a6ca54ede709db4db.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/51911081eef1869a7c7e2a6ca54ede709db4db",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0051911081eef1869a7c7e2a6ca54ede709db4db",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0651 tree 0051b6b57189cd6232de7a9863e0a8e1ae4b57e2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0651_0051b6b57189cd6232de7a9863e0a8e1ae4b57e2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/51b6b57189cd6232de7a9863e0a8e1ae4b57e2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0051b6b57189cd6232de7a9863e0a8e1ae4b57e2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0652 tree 0052b6cbadca2f1f1f6c0d2fbcb9e9aff4ff6f9f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0652_0052b6cbadca2f1f1f6c0d2fbcb9e9aff4ff6f9f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/52b6cbadca2f1f1f6c0d2fbcb9e9aff4ff6f9f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0052b6cbadca2f1f1f6c0d2fbcb9e9aff4ff6f9f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0653 tree 0052c6481e50dec5dc321a563c31a1db992a17ee" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0653_0052c6481e50dec5dc321a563c31a1db992a17ee.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/52c6481e50dec5dc321a563c31a1db992a17ee",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0052c6481e50dec5dc321a563c31a1db992a17ee",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0654 tree 0053d2e28444cc5082f8a898081f5dd6ad5ededa" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0654_0053d2e28444cc5082f8a898081f5dd6ad5ededa.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/53d2e28444cc5082f8a898081f5dd6ad5ededa",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0053d2e28444cc5082f8a898081f5dd6ad5ededa",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0655 tree 00541928cf20740ff0b7c586640e2729ee88d7fa" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0655_00541928cf20740ff0b7c586640e2729ee88d7fa.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/541928cf20740ff0b7c586640e2729ee88d7fa",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00541928cf20740ff0b7c586640e2729ee88d7fa",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0656 tree 00541bc3a301954bca37cb15c522e737202b010a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0656_00541bc3a301954bca37cb15c522e737202b010a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/541bc3a301954bca37cb15c522e737202b010a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00541bc3a301954bca37cb15c522e737202b010a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0657 tree 005453438112cc9658477c85c8fae9e8d100ea96" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0657_005453438112cc9658477c85c8fae9e8d100ea96.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5453438112cc9658477c85c8fae9e8d100ea96",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005453438112cc9658477c85c8fae9e8d100ea96",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0658 tree 0054a5f96acedacfdc0bbf6676b45db759c17707" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0658_0054a5f96acedacfdc0bbf6676b45db759c17707.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/54a5f96acedacfdc0bbf6676b45db759c17707",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0054a5f96acedacfdc0bbf6676b45db759c17707",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0659 tree 0054ee0024aed5009df1eea6b045cc2975716804" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0659_0054ee0024aed5009df1eea6b045cc2975716804.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/54ee0024aed5009df1eea6b045cc2975716804",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0054ee0024aed5009df1eea6b045cc2975716804",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0660 tree 0054fb58243a1ede631e0d12a0482d37c3476a25" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0660_0054fb58243a1ede631e0d12a0482d37c3476a25.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/54fb58243a1ede631e0d12a0482d37c3476a25",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0054fb58243a1ede631e0d12a0482d37c3476a25",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0661 tree 0054fd0673b74df7400c6f2e6d7e3141bd679ec4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0661_0054fd0673b74df7400c6f2e6d7e3141bd679ec4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/54fd0673b74df7400c6f2e6d7e3141bd679ec4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0054fd0673b74df7400c6f2e6d7e3141bd679ec4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0662 tree 00551a814864ba0565e1a943524b8cbe92c218ef" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0662_00551a814864ba0565e1a943524b8cbe92c218ef.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/551a814864ba0565e1a943524b8cbe92c218ef",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00551a814864ba0565e1a943524b8cbe92c218ef",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0663 tree 0055d6e3b6666fe950e6ec7ea122ff7cd1c612a3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0663_0055d6e3b6666fe950e6ec7ea122ff7cd1c612a3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/55d6e3b6666fe950e6ec7ea122ff7cd1c612a3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0055d6e3b6666fe950e6ec7ea122ff7cd1c612a3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0664 tree 0055f397e4f7f8b511f689d3cd788fd37c5c9495" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0664_0055f397e4f7f8b511f689d3cd788fd37c5c9495.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/55f397e4f7f8b511f689d3cd788fd37c5c9495",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0055f397e4f7f8b511f689d3cd788fd37c5c9495",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0665 tree 005689a0e5105ea6cb99ad76c06069f5b93bd90a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0665_005689a0e5105ea6cb99ad76c06069f5b93bd90a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5689a0e5105ea6cb99ad76c06069f5b93bd90a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005689a0e5105ea6cb99ad76c06069f5b93bd90a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0666 tree 0056afccc219981e9bf4f0366759e2fa65c24117" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0666_0056afccc219981e9bf4f0366759e2fa65c24117.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/56afccc219981e9bf4f0366759e2fa65c24117",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0056afccc219981e9bf4f0366759e2fa65c24117",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0667 tree 00572e24287e1f6771e5da7b97f10026c7856484" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0667_00572e24287e1f6771e5da7b97f10026c7856484.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/572e24287e1f6771e5da7b97f10026c7856484",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00572e24287e1f6771e5da7b97f10026c7856484",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0668 tree 0057ca4dbce31bc0efb2b1494e9bc5f9845d0293" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0668_0057ca4dbce31bc0efb2b1494e9bc5f9845d0293.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/57ca4dbce31bc0efb2b1494e9bc5f9845d0293",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0057ca4dbce31bc0efb2b1494e9bc5f9845d0293",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0669 tree 0058258c0925976b8f913f3ff4b3f7b0a9faae9d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0669_0058258c0925976b8f913f3ff4b3f7b0a9faae9d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/58258c0925976b8f913f3ff4b3f7b0a9faae9d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0058258c0925976b8f913f3ff4b3f7b0a9faae9d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0670 tree 005886766e9afe0391dc2cecf3c099955d3f7a64" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0670_005886766e9afe0391dc2cecf3c099955d3f7a64.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5886766e9afe0391dc2cecf3c099955d3f7a64",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005886766e9afe0391dc2cecf3c099955d3f7a64",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0671 tree 0058afb5bf08740c6a6c0c655ae63a105b64ede2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0671_0058afb5bf08740c6a6c0c655ae63a105b64ede2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/58afb5bf08740c6a6c0c655ae63a105b64ede2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0058afb5bf08740c6a6c0c655ae63a105b64ede2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0672 tree 0058e8aeaaee45ab4759c2f3fe2aba312c3e8f0a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0672_0058e8aeaaee45ab4759c2f3fe2aba312c3e8f0a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/58e8aeaaee45ab4759c2f3fe2aba312c3e8f0a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0058e8aeaaee45ab4759c2f3fe2aba312c3e8f0a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0673 tree 005904711b318e07b7797d8c96cd1aa86f350419" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0673_005904711b318e07b7797d8c96cd1aa86f350419.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5904711b318e07b7797d8c96cd1aa86f350419",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005904711b318e07b7797d8c96cd1aa86f350419",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0674 tree 005953b09dfb2baa3a056895597076d347a29801" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0674_005953b09dfb2baa3a056895597076d347a29801.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5953b09dfb2baa3a056895597076d347a29801",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005953b09dfb2baa3a056895597076d347a29801",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0675 tree 005a504ece6de3693f6f92839c75109d7efd2f65" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0675_005a504ece6de3693f6f92839c75109d7efd2f65.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5a504ece6de3693f6f92839c75109d7efd2f65",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005a504ece6de3693f6f92839c75109d7efd2f65",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0676 tree 005a6e86ca2eec0b0f3d158ef9884a512730fdb8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0676_005a6e86ca2eec0b0f3d158ef9884a512730fdb8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5a6e86ca2eec0b0f3d158ef9884a512730fdb8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005a6e86ca2eec0b0f3d158ef9884a512730fdb8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0677 tree 005a7c7364303f6203dde4902c9c89412e43d53a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0677_005a7c7364303f6203dde4902c9c89412e43d53a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5a7c7364303f6203dde4902c9c89412e43d53a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005a7c7364303f6203dde4902c9c89412e43d53a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0678 tree 005a97440b8a5c0cc35851d1f76793db5da96b46" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0678_005a97440b8a5c0cc35851d1f76793db5da96b46.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5a97440b8a5c0cc35851d1f76793db5da96b46",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005a97440b8a5c0cc35851d1f76793db5da96b46",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0679 tree 005ab8506bf03b378044430d699be8b409f97be5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0679_005ab8506bf03b378044430d699be8b409f97be5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5ab8506bf03b378044430d699be8b409f97be5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005ab8506bf03b378044430d699be8b409f97be5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0680 tree 005acfab804147c48dedfdf7ae39bf2e765820d3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0680_005acfab804147c48dedfdf7ae39bf2e765820d3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5acfab804147c48dedfdf7ae39bf2e765820d3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005acfab804147c48dedfdf7ae39bf2e765820d3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0681 tree 005b10770005c0d15a7cb6272425031e9510356a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0681_005b10770005c0d15a7cb6272425031e9510356a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5b10770005c0d15a7cb6272425031e9510356a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005b10770005c0d15a7cb6272425031e9510356a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0682 tree 005b2ee1fe09ceec3668852fa81c7618ae5a1a26" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0682_005b2ee1fe09ceec3668852fa81c7618ae5a1a26.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5b2ee1fe09ceec3668852fa81c7618ae5a1a26",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005b2ee1fe09ceec3668852fa81c7618ae5a1a26",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0683 tree 005bb1458105c06ae7fa2067a4d25c81e6399d25" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0683_005bb1458105c06ae7fa2067a4d25c81e6399d25.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5bb1458105c06ae7fa2067a4d25c81e6399d25",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005bb1458105c06ae7fa2067a4d25c81e6399d25",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0684 tree 005bceff51b5502d752dfa612211591ad1a619a4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0684_005bceff51b5502d752dfa612211591ad1a619a4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5bceff51b5502d752dfa612211591ad1a619a4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005bceff51b5502d752dfa612211591ad1a619a4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0685 tree 005c400fe384d494b3d87843d5cf0235ea7939a1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0685_005c400fe384d494b3d87843d5cf0235ea7939a1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5c400fe384d494b3d87843d5cf0235ea7939a1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005c400fe384d494b3d87843d5cf0235ea7939a1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0686 tree 005c79a7488a4e6f9f31ed81305d43e3734032ac" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0686_005c79a7488a4e6f9f31ed81305d43e3734032ac.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5c79a7488a4e6f9f31ed81305d43e3734032ac",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005c79a7488a4e6f9f31ed81305d43e3734032ac",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0687 tree 005e0095e82d6ac36b1d60a693666a3253cf46dc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0687_005e0095e82d6ac36b1d60a693666a3253cf46dc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5e0095e82d6ac36b1d60a693666a3253cf46dc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005e0095e82d6ac36b1d60a693666a3253cf46dc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0688 tree 005ee01d7e4813930c25854277d704d2f11bccb3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0688_005ee01d7e4813930c25854277d704d2f11bccb3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5ee01d7e4813930c25854277d704d2f11bccb3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005ee01d7e4813930c25854277d704d2f11bccb3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0689 tree 005f1372f5e79147bbe23f3be13e25db87cb2815" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0689_005f1372f5e79147bbe23f3be13e25db87cb2815.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5f1372f5e79147bbe23f3be13e25db87cb2815",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005f1372f5e79147bbe23f3be13e25db87cb2815",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0690 tree 005f524db57eeacc030e3a0322b8b180ea00302b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0690_005f524db57eeacc030e3a0322b8b180ea00302b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5f524db57eeacc030e3a0322b8b180ea00302b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005f524db57eeacc030e3a0322b8b180ea00302b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0691 tree 00608775b4a01ec4bc65627c08f5ead07237c44d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0691_00608775b4a01ec4bc65627c08f5ead07237c44d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/608775b4a01ec4bc65627c08f5ead07237c44d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00608775b4a01ec4bc65627c08f5ead07237c44d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0692 tree 00608898fc3cc37980eedfd695fa22a9c2b0fd0e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0692_00608898fc3cc37980eedfd695fa22a9c2b0fd0e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/608898fc3cc37980eedfd695fa22a9c2b0fd0e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00608898fc3cc37980eedfd695fa22a9c2b0fd0e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0693 tree 0060e7ffa0172f2c33f08c7e12355f46648db65a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0693_0060e7ffa0172f2c33f08c7e12355f46648db65a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/60e7ffa0172f2c33f08c7e12355f46648db65a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0060e7ffa0172f2c33f08c7e12355f46648db65a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0694 tree 00618ea091d7450a06026bbb7e9ecac601ae0a46" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0694_00618ea091d7450a06026bbb7e9ecac601ae0a46.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/618ea091d7450a06026bbb7e9ecac601ae0a46",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00618ea091d7450a06026bbb7e9ecac601ae0a46",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0695 tree 006190a6d181255fe6afdf80295cc5afe08e72f8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0695_006190a6d181255fe6afdf80295cc5afe08e72f8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6190a6d181255fe6afdf80295cc5afe08e72f8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006190a6d181255fe6afdf80295cc5afe08e72f8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0696 tree 00622179a2fa407e4611fab78b173e5c622fb61c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0696_00622179a2fa407e4611fab78b173e5c622fb61c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/622179a2fa407e4611fab78b173e5c622fb61c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00622179a2fa407e4611fab78b173e5c622fb61c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0697 tree 006284a4a35c5deebaa1ded7198c91d3c3bc25df" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0697_006284a4a35c5deebaa1ded7198c91d3c3bc25df.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6284a4a35c5deebaa1ded7198c91d3c3bc25df",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006284a4a35c5deebaa1ded7198c91d3c3bc25df",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0698 tree 006325d34fbe11f3ff7c11a1e20a912470ffc899" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0698_006325d34fbe11f3ff7c11a1e20a912470ffc899.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6325d34fbe11f3ff7c11a1e20a912470ffc899",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006325d34fbe11f3ff7c11a1e20a912470ffc899",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0699 tree 0063896a0043013e3b2ce8d3834586da5120d9d9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0699_0063896a0043013e3b2ce8d3834586da5120d9d9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/63896a0043013e3b2ce8d3834586da5120d9d9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0063896a0043013e3b2ce8d3834586da5120d9d9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0700 tree 00640f959691911904b3d6a21b32935bf934d7aa" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0700_00640f959691911904b3d6a21b32935bf934d7aa.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/640f959691911904b3d6a21b32935bf934d7aa",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00640f959691911904b3d6a21b32935bf934d7aa",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0701 tree 0064ef40a7bcbbc4358a09862cfebd11b1d54dea" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0701_0064ef40a7bcbbc4358a09862cfebd11b1d54dea.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/64ef40a7bcbbc4358a09862cfebd11b1d54dea",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0064ef40a7bcbbc4358a09862cfebd11b1d54dea",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0702 tree 0065bcff47507267c5cfbc0a313e1958dec5498d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0702_0065bcff47507267c5cfbc0a313e1958dec5498d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/65bcff47507267c5cfbc0a313e1958dec5498d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0065bcff47507267c5cfbc0a313e1958dec5498d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0703 tree 006668b9f1b9a8e8233001278e00a18208342578" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0703_006668b9f1b9a8e8233001278e00a18208342578.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6668b9f1b9a8e8233001278e00a18208342578",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006668b9f1b9a8e8233001278e00a18208342578",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0704 tree 00677ca8806fc02a7e2b6adf1418ffddc645f827" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0704_00677ca8806fc02a7e2b6adf1418ffddc645f827.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/677ca8806fc02a7e2b6adf1418ffddc645f827",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00677ca8806fc02a7e2b6adf1418ffddc645f827",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0705 tree 0067be6bc5fc30af702c7436d4c16dde0a246afc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0705_0067be6bc5fc30af702c7436d4c16dde0a246afc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/67be6bc5fc30af702c7436d4c16dde0a246afc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0067be6bc5fc30af702c7436d4c16dde0a246afc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0706 tree 00681e6f57e3f1d86d84a5962c4e2bbd511e63d7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0706_00681e6f57e3f1d86d84a5962c4e2bbd511e63d7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/681e6f57e3f1d86d84a5962c4e2bbd511e63d7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00681e6f57e3f1d86d84a5962c4e2bbd511e63d7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0707 tree 0068eeea70265e53372786874d04375b332a45c3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0707_0068eeea70265e53372786874d04375b332a45c3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/68eeea70265e53372786874d04375b332a45c3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0068eeea70265e53372786874d04375b332a45c3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0708 tree 0068fb09ecdb92495d3529d918759e16a943dc3c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0708_0068fb09ecdb92495d3529d918759e16a943dc3c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/68fb09ecdb92495d3529d918759e16a943dc3c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0068fb09ecdb92495d3529d918759e16a943dc3c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0709 tree 0069444ff1accf86b73731e7db0cb3eb7e60f263" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0709_0069444ff1accf86b73731e7db0cb3eb7e60f263.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/69444ff1accf86b73731e7db0cb3eb7e60f263",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0069444ff1accf86b73731e7db0cb3eb7e60f263",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0710 tree 006a43e6a413dff418ef13581a8a2116e0ebf7fb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0710_006a43e6a413dff418ef13581a8a2116e0ebf7fb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6a43e6a413dff418ef13581a8a2116e0ebf7fb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006a43e6a413dff418ef13581a8a2116e0ebf7fb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0711 tree 006b875202c979427616145a4259958b937cefe9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0711_006b875202c979427616145a4259958b937cefe9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6b875202c979427616145a4259958b937cefe9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006b875202c979427616145a4259958b937cefe9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0712 tree 006ba5c9799ef415c5531bfd122f0899823b351a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0712_006ba5c9799ef415c5531bfd122f0899823b351a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6ba5c9799ef415c5531bfd122f0899823b351a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006ba5c9799ef415c5531bfd122f0899823b351a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0713 tree 006cda997082311a47f8dfc2d2e43c4907de1b53" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0713_006cda997082311a47f8dfc2d2e43c4907de1b53.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6cda997082311a47f8dfc2d2e43c4907de1b53",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006cda997082311a47f8dfc2d2e43c4907de1b53",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0714 tree 006cff6a346a28bf0c63231bde445490de8ab5fe" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0714_006cff6a346a28bf0c63231bde445490de8ab5fe.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6cff6a346a28bf0c63231bde445490de8ab5fe",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006cff6a346a28bf0c63231bde445490de8ab5fe",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0715 tree 006d08f7d407fa411b9f683c50e5902bc7582fe9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0715_006d08f7d407fa411b9f683c50e5902bc7582fe9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6d08f7d407fa411b9f683c50e5902bc7582fe9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006d08f7d407fa411b9f683c50e5902bc7582fe9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0716 tree 006e58dc4da399f6e2458025b401acf0406946fd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0716_006e58dc4da399f6e2458025b401acf0406946fd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6e58dc4da399f6e2458025b401acf0406946fd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006e58dc4da399f6e2458025b401acf0406946fd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0717 tree 006f050d93b3c4d3e5a9e4aa72f983331b38e9db" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0717_006f050d93b3c4d3e5a9e4aa72f983331b38e9db.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6f050d93b3c4d3e5a9e4aa72f983331b38e9db",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006f050d93b3c4d3e5a9e4aa72f983331b38e9db",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0718 tree 00705c658734dc6efba8c00869be5f4736b3d7ae" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0718_00705c658734dc6efba8c00869be5f4736b3d7ae.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/705c658734dc6efba8c00869be5f4736b3d7ae",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00705c658734dc6efba8c00869be5f4736b3d7ae",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0719 tree 0070a92e774fb78aaa589a26f04b74df68c124aa" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0719_0070a92e774fb78aaa589a26f04b74df68c124aa.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/70a92e774fb78aaa589a26f04b74df68c124aa",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0070a92e774fb78aaa589a26f04b74df68c124aa",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0720 tree 0070e225b1c4ad4cfddace9c0db946aeeb93f4f2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0720_0070e225b1c4ad4cfddace9c0db946aeeb93f4f2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/70e225b1c4ad4cfddace9c0db946aeeb93f4f2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0070e225b1c4ad4cfddace9c0db946aeeb93f4f2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0721 tree 00714e06465e6ba1a864bd89a5ee6fe2c41653fb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0721_00714e06465e6ba1a864bd89a5ee6fe2c41653fb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/714e06465e6ba1a864bd89a5ee6fe2c41653fb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00714e06465e6ba1a864bd89a5ee6fe2c41653fb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0722 tree 007185907961e10104835b6fbf5f69af6199c7b3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0722_007185907961e10104835b6fbf5f69af6199c7b3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7185907961e10104835b6fbf5f69af6199c7b3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007185907961e10104835b6fbf5f69af6199c7b3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0723 tree 0071c8c188695db5bdffaeb0390383bc5c218e52" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0723_0071c8c188695db5bdffaeb0390383bc5c218e52.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/71c8c188695db5bdffaeb0390383bc5c218e52",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0071c8c188695db5bdffaeb0390383bc5c218e52",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0724 tree 00723ad466f8cb77e2595c319359dfd625b13576" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0724_00723ad466f8cb77e2595c319359dfd625b13576.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/723ad466f8cb77e2595c319359dfd625b13576",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00723ad466f8cb77e2595c319359dfd625b13576",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0725 tree 007296fa3e0be74ed6e53231eed0edc789c0cf2c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0725_007296fa3e0be74ed6e53231eed0edc789c0cf2c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7296fa3e0be74ed6e53231eed0edc789c0cf2c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007296fa3e0be74ed6e53231eed0edc789c0cf2c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0726 tree 0072decca072386b72b01239d7a8d3abd5364823" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0726_0072decca072386b72b01239d7a8d3abd5364823.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/72decca072386b72b01239d7a8d3abd5364823",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0072decca072386b72b01239d7a8d3abd5364823",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0727 tree 0072f315d261bf4c4792ddcba45445facab1e0d1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0727_0072f315d261bf4c4792ddcba45445facab1e0d1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/72f315d261bf4c4792ddcba45445facab1e0d1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0072f315d261bf4c4792ddcba45445facab1e0d1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0728 tree 007314447bdd55a4232ee8ef43084c6ec0a26f62" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0728_007314447bdd55a4232ee8ef43084c6ec0a26f62.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7314447bdd55a4232ee8ef43084c6ec0a26f62",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007314447bdd55a4232ee8ef43084c6ec0a26f62",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0729 tree 00737a3bbd3d8ce995070e1c0b783144e2cf9b02" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0729_00737a3bbd3d8ce995070e1c0b783144e2cf9b02.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/737a3bbd3d8ce995070e1c0b783144e2cf9b02",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00737a3bbd3d8ce995070e1c0b783144e2cf9b02",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0730 tree 007449bce27863f7871c9d70a413aaf9b187a86c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0730_007449bce27863f7871c9d70a413aaf9b187a86c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7449bce27863f7871c9d70a413aaf9b187a86c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007449bce27863f7871c9d70a413aaf9b187a86c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0731 tree 00745108c321debc1e03ae62d8adb9140bfb3984" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0731_00745108c321debc1e03ae62d8adb9140bfb3984.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/745108c321debc1e03ae62d8adb9140bfb3984",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00745108c321debc1e03ae62d8adb9140bfb3984",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0732 tree 00745e177be38864825967528bf654226a1c0e70" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0732_00745e177be38864825967528bf654226a1c0e70.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/745e177be38864825967528bf654226a1c0e70",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00745e177be38864825967528bf654226a1c0e70",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0733 tree 007480faae11ba668f4ea1a4d51e2acb079b0b12" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0733_007480faae11ba668f4ea1a4d51e2acb079b0b12.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7480faae11ba668f4ea1a4d51e2acb079b0b12",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007480faae11ba668f4ea1a4d51e2acb079b0b12",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0734 tree 0074b08d20ca4c33694a7c2711d31d12e99cad16" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0734_0074b08d20ca4c33694a7c2711d31d12e99cad16.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/74b08d20ca4c33694a7c2711d31d12e99cad16",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0074b08d20ca4c33694a7c2711d31d12e99cad16",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0735 tree 00753eeb98e5e9e57d53cc031ec3c3846aa38de1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0735_00753eeb98e5e9e57d53cc031ec3c3846aa38de1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/753eeb98e5e9e57d53cc031ec3c3846aa38de1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00753eeb98e5e9e57d53cc031ec3c3846aa38de1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0736 tree 0075962892ce720ce7b2521f81c0605acdbbd9dc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0736_0075962892ce720ce7b2521f81c0605acdbbd9dc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/75962892ce720ce7b2521f81c0605acdbbd9dc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0075962892ce720ce7b2521f81c0605acdbbd9dc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0737 tree 00761c50a255cd8ae8778566e25a1e5dd9b8acfd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0737_00761c50a255cd8ae8778566e25a1e5dd9b8acfd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/761c50a255cd8ae8778566e25a1e5dd9b8acfd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00761c50a255cd8ae8778566e25a1e5dd9b8acfd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0738 tree 007705f30625a7b2f45edd2400bd3d44b0d624cf" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0738_007705f30625a7b2f45edd2400bd3d44b0d624cf.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7705f30625a7b2f45edd2400bd3d44b0d624cf",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007705f30625a7b2f45edd2400bd3d44b0d624cf",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0739 tree 007725bca1f345c85340cefa242ba28b4325e680" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0739_007725bca1f345c85340cefa242ba28b4325e680.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7725bca1f345c85340cefa242ba28b4325e680",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007725bca1f345c85340cefa242ba28b4325e680",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0740 tree 007728a4e0c2572196e5b118761bf69fdea5bfd8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0740_007728a4e0c2572196e5b118761bf69fdea5bfd8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7728a4e0c2572196e5b118761bf69fdea5bfd8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007728a4e0c2572196e5b118761bf69fdea5bfd8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0741 tree 0077523338ba174c44548a20cf07d04b7c4836f6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0741_0077523338ba174c44548a20cf07d04b7c4836f6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/77523338ba174c44548a20cf07d04b7c4836f6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0077523338ba174c44548a20cf07d04b7c4836f6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0742 tree 0077a4dc5762677513734b8c0cc03c7e46014e25" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0742_0077a4dc5762677513734b8c0cc03c7e46014e25.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/77a4dc5762677513734b8c0cc03c7e46014e25",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0077a4dc5762677513734b8c0cc03c7e46014e25",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0743 tree 0078a01358ccd32d785a7b18057efe9c358f812e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0743_0078a01358ccd32d785a7b18057efe9c358f812e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/78a01358ccd32d785a7b18057efe9c358f812e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0078a01358ccd32d785a7b18057efe9c358f812e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0744 tree 0078b93d0e7e3d4f33e92274ef908af52512ec6d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0744_0078b93d0e7e3d4f33e92274ef908af52512ec6d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/78b93d0e7e3d4f33e92274ef908af52512ec6d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0078b93d0e7e3d4f33e92274ef908af52512ec6d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0745 tree 0079357ef462d229af4457be324627bde1619054" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0745_0079357ef462d229af4457be324627bde1619054.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/79357ef462d229af4457be324627bde1619054",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0079357ef462d229af4457be324627bde1619054",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0746 tree 00796cb78afd8a6d21b8aafd200576d1c7ffeb86" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0746_00796cb78afd8a6d21b8aafd200576d1c7ffeb86.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/796cb78afd8a6d21b8aafd200576d1c7ffeb86",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00796cb78afd8a6d21b8aafd200576d1c7ffeb86",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0747 tree 0079db76d1554afd3807a59f6247259e7e2ec686" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0747_0079db76d1554afd3807a59f6247259e7e2ec686.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/79db76d1554afd3807a59f6247259e7e2ec686",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0079db76d1554afd3807a59f6247259e7e2ec686",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0748 tree 007a1bfb0d16e237af92d23d8a1872da2aaae854" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0748_007a1bfb0d16e237af92d23d8a1872da2aaae854.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7a1bfb0d16e237af92d23d8a1872da2aaae854",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007a1bfb0d16e237af92d23d8a1872da2aaae854",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0749 tree 007a4e32e846c77a93b3e75ee5bb1c30b512dc5c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0749_007a4e32e846c77a93b3e75ee5bb1c30b512dc5c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7a4e32e846c77a93b3e75ee5bb1c30b512dc5c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007a4e32e846c77a93b3e75ee5bb1c30b512dc5c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0750 tree 007ad9dc7e763049aeeefc1918ae85d57e5f2b7e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0750_007ad9dc7e763049aeeefc1918ae85d57e5f2b7e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7ad9dc7e763049aeeefc1918ae85d57e5f2b7e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007ad9dc7e763049aeeefc1918ae85d57e5f2b7e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0751 tree 007c70b6455b25b1b640262f9fdb53fbb8f81db5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0751_007c70b6455b25b1b640262f9fdb53fbb8f81db5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7c70b6455b25b1b640262f9fdb53fbb8f81db5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007c70b6455b25b1b640262f9fdb53fbb8f81db5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0752 tree 007c79ec00d1558a4473a49911b18d44c0f446d1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0752_007c79ec00d1558a4473a49911b18d44c0f446d1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7c79ec00d1558a4473a49911b18d44c0f446d1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007c79ec00d1558a4473a49911b18d44c0f446d1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0753 tree 007cff4b3b5b0156c80aa47cc5f92ac2c7293068" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0753_007cff4b3b5b0156c80aa47cc5f92ac2c7293068.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7cff4b3b5b0156c80aa47cc5f92ac2c7293068",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007cff4b3b5b0156c80aa47cc5f92ac2c7293068",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0754 tree 007d5c9ef1f3b4c40955967ecb7d7fc12683bab1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0754_007d5c9ef1f3b4c40955967ecb7d7fc12683bab1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7d5c9ef1f3b4c40955967ecb7d7fc12683bab1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007d5c9ef1f3b4c40955967ecb7d7fc12683bab1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0755 tree 007d5ef2fc99a223bf9245a3f78b062bc68d9930" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0755_007d5ef2fc99a223bf9245a3f78b062bc68d9930.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7d5ef2fc99a223bf9245a3f78b062bc68d9930",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007d5ef2fc99a223bf9245a3f78b062bc68d9930",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0756 commit 000023961a0c02d6e21dc51ea3484ff71abf1c74" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0756_000023961a0c02d6e21dc51ea3484ff71abf1c74.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0023961a0c02d6e21dc51ea3484ff71abf1c74",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000023961a0c02d6e21dc51ea3484ff71abf1c74",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0757 commit 0000d6543f1c2ceea017161a2807167cdfbf8c0b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0757_0000d6543f1c2ceea017161a2807167cdfbf8c0b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/00d6543f1c2ceea017161a2807167cdfbf8c0b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0000d6543f1c2ceea017161a2807167cdfbf8c0b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0758 commit 0000e81811bcbdc44339d03ae772650b98c26ed9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0758_0000e81811bcbdc44339d03ae772650b98c26ed9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/00e81811bcbdc44339d03ae772650b98c26ed9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0000e81811bcbdc44339d03ae772650b98c26ed9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0759 commit 000182eacf99cde27d5916aa415921924b82972c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0759_000182eacf99cde27d5916aa415921924b82972c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0182eacf99cde27d5916aa415921924b82972c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000182eacf99cde27d5916aa415921924b82972c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0760 commit 0003692409f153dd725b3455dfc2e128276cfbe2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0760_0003692409f153dd725b3455dfc2e128276cfbe2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/03692409f153dd725b3455dfc2e128276cfbe2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0003692409f153dd725b3455dfc2e128276cfbe2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0761 commit 0004d97099b78987ad143a5e797cc972621cdbe0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0761_0004d97099b78987ad143a5e797cc972621cdbe0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/04d97099b78987ad143a5e797cc972621cdbe0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0004d97099b78987ad143a5e797cc972621cdbe0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0762 commit 00057bf14c9269cb26a6b8ba7e8bc9ecd634d22c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0762_00057bf14c9269cb26a6b8ba7e8bc9ecd634d22c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/057bf14c9269cb26a6b8ba7e8bc9ecd634d22c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00057bf14c9269cb26a6b8ba7e8bc9ecd634d22c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0763 commit 0006d85c3a2fcbd803ed46cf283fab4e4fae3a7f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0763_0006d85c3a2fcbd803ed46cf283fab4e4fae3a7f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/06d85c3a2fcbd803ed46cf283fab4e4fae3a7f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0006d85c3a2fcbd803ed46cf283fab4e4fae3a7f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0764 commit 0006e2e3f1de6a3a5351da298ee52b5d936addfd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0764_0006e2e3f1de6a3a5351da298ee52b5d936addfd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/06e2e3f1de6a3a5351da298ee52b5d936addfd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0006e2e3f1de6a3a5351da298ee52b5d936addfd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0765 commit 0007618107627eb5bd616427132424e3bf9642bb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0765_0007618107627eb5bd616427132424e3bf9642bb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/07618107627eb5bd616427132424e3bf9642bb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0007618107627eb5bd616427132424e3bf9642bb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0766 commit 000792830b8ca96e6d973545192cba8d5df48279" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0766_000792830b8ca96e6d973545192cba8d5df48279.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0792830b8ca96e6d973545192cba8d5df48279",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000792830b8ca96e6d973545192cba8d5df48279",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0767 commit 000866909a5d9233c89d8fcc33a8125cc84f24d6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0767_000866909a5d9233c89d8fcc33a8125cc84f24d6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0866909a5d9233c89d8fcc33a8125cc84f24d6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000866909a5d9233c89d8fcc33a8125cc84f24d6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0768 commit 0008d12284ef916b53341c2aadccdc017ff07c7a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0768_0008d12284ef916b53341c2aadccdc017ff07c7a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/08d12284ef916b53341c2aadccdc017ff07c7a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0008d12284ef916b53341c2aadccdc017ff07c7a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0769 commit 0009426d6721a0356d41811aa34b4ac7f278a76e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0769_0009426d6721a0356d41811aa34b4ac7f278a76e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/09426d6721a0356d41811aa34b4ac7f278a76e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0009426d6721a0356d41811aa34b4ac7f278a76e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0770 commit 0009542cabb808f558605f0faa8c57d3b97ed055" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0770_0009542cabb808f558605f0faa8c57d3b97ed055.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/09542cabb808f558605f0faa8c57d3b97ed055",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0009542cabb808f558605f0faa8c57d3b97ed055",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0771 commit 0009d3501b87bd02f6c6faba93cf991d701fa5a5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0771_0009d3501b87bd02f6c6faba93cf991d701fa5a5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/09d3501b87bd02f6c6faba93cf991d701fa5a5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0009d3501b87bd02f6c6faba93cf991d701fa5a5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0772 commit 000a10696c0bc1e428bbd22af9e19b27795e72dd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0772_000a10696c0bc1e428bbd22af9e19b27795e72dd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0a10696c0bc1e428bbd22af9e19b27795e72dd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000a10696c0bc1e428bbd22af9e19b27795e72dd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0773 commit 000bce0ee4d0ef719b84fb643c45fe68fa4bb773" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0773_000bce0ee4d0ef719b84fb643c45fe68fa4bb773.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0bce0ee4d0ef719b84fb643c45fe68fa4bb773",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000bce0ee4d0ef719b84fb643c45fe68fa4bb773",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0774 commit 000c4ceca794645eb4744f9c9afb6247232c0646" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0774_000c4ceca794645eb4744f9c9afb6247232c0646.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0c4ceca794645eb4744f9c9afb6247232c0646",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000c4ceca794645eb4744f9c9afb6247232c0646",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0775 commit 000d2c07ef65b19bd9cf30ef44a3018b8f110b2c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0775_000d2c07ef65b19bd9cf30ef44a3018b8f110b2c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0d2c07ef65b19bd9cf30ef44a3018b8f110b2c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000d2c07ef65b19bd9cf30ef44a3018b8f110b2c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0776 commit 000dd595e40b3240f4bca910932c6049e9790b06" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0776_000dd595e40b3240f4bca910932c6049e9790b06.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0dd595e40b3240f4bca910932c6049e9790b06",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000dd595e40b3240f4bca910932c6049e9790b06",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0777 commit 000dfd3f6e3f61e15ccfd4cecb3a51624adfbf38" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0777_000dfd3f6e3f61e15ccfd4cecb3a51624adfbf38.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0dfd3f6e3f61e15ccfd4cecb3a51624adfbf38",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000dfd3f6e3f61e15ccfd4cecb3a51624adfbf38",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0778 commit 000f0da57aca00d6ff960f0763dee73c34cd7677" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0778_000f0da57aca00d6ff960f0763dee73c34cd7677.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0f0da57aca00d6ff960f0763dee73c34cd7677",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000f0da57aca00d6ff960f0763dee73c34cd7677",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0779 commit 000f97bd11e94fa8ede7fcdb43f5633997fed672" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0779_000f97bd11e94fa8ede7fcdb43f5633997fed672.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/0f97bd11e94fa8ede7fcdb43f5633997fed672",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="000f97bd11e94fa8ede7fcdb43f5633997fed672",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0780 commit 0011f94a4f05d5311a4f3223da8caf3bfbb9e293" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0780_0011f94a4f05d5311a4f3223da8caf3bfbb9e293.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/11f94a4f05d5311a4f3223da8caf3bfbb9e293",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0011f94a4f05d5311a4f3223da8caf3bfbb9e293",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0781 commit 0012a3873b5df4476b5b9142d0b5748a101c1ba8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0781_0012a3873b5df4476b5b9142d0b5748a101c1ba8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/12a3873b5df4476b5b9142d0b5748a101c1ba8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0012a3873b5df4476b5b9142d0b5748a101c1ba8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0782 commit 0012ba2108aa42947dedf19f3db2de73a67cc4f5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0782_0012ba2108aa42947dedf19f3db2de73a67cc4f5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/12ba2108aa42947dedf19f3db2de73a67cc4f5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0012ba2108aa42947dedf19f3db2de73a67cc4f5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0783 commit 0013251fe217b882bc4fd5a40b732baebfad02fb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0783_0013251fe217b882bc4fd5a40b732baebfad02fb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/13251fe217b882bc4fd5a40b732baebfad02fb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0013251fe217b882bc4fd5a40b732baebfad02fb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0784 commit 0015f897e54f760a2f422e2896b1984afc41a62c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0784_0015f897e54f760a2f422e2896b1984afc41a62c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/15f897e54f760a2f422e2896b1984afc41a62c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0015f897e54f760a2f422e2896b1984afc41a62c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0785 commit 00160242770aea137ec7154a8e8406feef733926" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0785_00160242770aea137ec7154a8e8406feef733926.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/160242770aea137ec7154a8e8406feef733926",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00160242770aea137ec7154a8e8406feef733926",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0786 commit 0016043bf46f4b85054c61f9000ccc58d0ef4ad7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0786_0016043bf46f4b85054c61f9000ccc58d0ef4ad7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/16043bf46f4b85054c61f9000ccc58d0ef4ad7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0016043bf46f4b85054c61f9000ccc58d0ef4ad7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0787 commit 0016a48251abefed11efc919703d980a21c95f2c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0787_0016a48251abefed11efc919703d980a21c95f2c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/16a48251abefed11efc919703d980a21c95f2c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0016a48251abefed11efc919703d980a21c95f2c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0788 commit 0016b618182f642771dc589cf0090289f9fe1b4f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0788_0016b618182f642771dc589cf0090289f9fe1b4f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/16b618182f642771dc589cf0090289f9fe1b4f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0016b618182f642771dc589cf0090289f9fe1b4f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0789 commit 00183cbb3d0f60852d7286e766c9b631c0c1f952" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0789_00183cbb3d0f60852d7286e766c9b631c0c1f952.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/183cbb3d0f60852d7286e766c9b631c0c1f952",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00183cbb3d0f60852d7286e766c9b631c0c1f952",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0790 commit 0018da1088e3d7e282998d80db3c719fa7a18ce3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0790_0018da1088e3d7e282998d80db3c719fa7a18ce3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/18da1088e3d7e282998d80db3c719fa7a18ce3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0018da1088e3d7e282998d80db3c719fa7a18ce3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0791 commit 001b0976afe6f41bff46aa3eaad0285b641a50ea" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0791_001b0976afe6f41bff46aa3eaad0285b641a50ea.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1b0976afe6f41bff46aa3eaad0285b641a50ea",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001b0976afe6f41bff46aa3eaad0285b641a50ea",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0792 commit 001d1160541a6dcfceb82a0a900478e315a129eb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0792_001d1160541a6dcfceb82a0a900478e315a129eb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1d1160541a6dcfceb82a0a900478e315a129eb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001d1160541a6dcfceb82a0a900478e315a129eb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0793 commit 001d4a27dbfaaa59c25dc35dafc69bd9b9bc21d3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0793_001d4a27dbfaaa59c25dc35dafc69bd9b9bc21d3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1d4a27dbfaaa59c25dc35dafc69bd9b9bc21d3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001d4a27dbfaaa59c25dc35dafc69bd9b9bc21d3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0794 commit 001fd7a90b5851f62e700510729a5e09706f9b63" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0794_001fd7a90b5851f62e700510729a5e09706f9b63.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/1fd7a90b5851f62e700510729a5e09706f9b63",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="001fd7a90b5851f62e700510729a5e09706f9b63",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0795 commit 00200e9ea090cbf68c33e8d00c2976ee49972fdd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0795_00200e9ea090cbf68c33e8d00c2976ee49972fdd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/200e9ea090cbf68c33e8d00c2976ee49972fdd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00200e9ea090cbf68c33e8d00c2976ee49972fdd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0796 commit 0024a54923a12f8c05ce4290f5ebefab0cce4336" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0796_0024a54923a12f8c05ce4290f5ebefab0cce4336.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/24a54923a12f8c05ce4290f5ebefab0cce4336",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0024a54923a12f8c05ce4290f5ebefab0cce4336",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0797 commit 0025dde775ea20c64dfedff17da15bbef047a1c9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0797_0025dde775ea20c64dfedff17da15bbef047a1c9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/25dde775ea20c64dfedff17da15bbef047a1c9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0025dde775ea20c64dfedff17da15bbef047a1c9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0798 commit 0026d5484158ee093da5ab302ee794ec1931303f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0798_0026d5484158ee093da5ab302ee794ec1931303f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/26d5484158ee093da5ab302ee794ec1931303f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0026d5484158ee093da5ab302ee794ec1931303f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0799 commit 00271485d4acefda7ff054a1db5d5a39735e28b9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0799_00271485d4acefda7ff054a1db5d5a39735e28b9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/271485d4acefda7ff054a1db5d5a39735e28b9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00271485d4acefda7ff054a1db5d5a39735e28b9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0800 commit 00271bb3001fd8732d8afc746f2188f807192e87" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0800_00271bb3001fd8732d8afc746f2188f807192e87.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/271bb3001fd8732d8afc746f2188f807192e87",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00271bb3001fd8732d8afc746f2188f807192e87",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0801 commit 00272a6339fa65dd6cb9d16e2eb3a0193e4574e6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0801_00272a6339fa65dd6cb9d16e2eb3a0193e4574e6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/272a6339fa65dd6cb9d16e2eb3a0193e4574e6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00272a6339fa65dd6cb9d16e2eb3a0193e4574e6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0802 commit 002933f3fe2b016022ebbbbb359f6aeba58309a4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0802_002933f3fe2b016022ebbbbb359f6aeba58309a4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2933f3fe2b016022ebbbbb359f6aeba58309a4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002933f3fe2b016022ebbbbb359f6aeba58309a4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0803 commit 002a6dfc7c4642524d1e82f8cf994fc9ea5786f9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0803_002a6dfc7c4642524d1e82f8cf994fc9ea5786f9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2a6dfc7c4642524d1e82f8cf994fc9ea5786f9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002a6dfc7c4642524d1e82f8cf994fc9ea5786f9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0804 commit 002a8a9d3697866aec32cc9293e4d9b436bb028f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0804_002a8a9d3697866aec32cc9293e4d9b436bb028f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2a8a9d3697866aec32cc9293e4d9b436bb028f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002a8a9d3697866aec32cc9293e4d9b436bb028f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0805 commit 002a9ec005cd3d4273e3c6b7dbe7a2fb9e70c1bc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0805_002a9ec005cd3d4273e3c6b7dbe7a2fb9e70c1bc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2a9ec005cd3d4273e3c6b7dbe7a2fb9e70c1bc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002a9ec005cd3d4273e3c6b7dbe7a2fb9e70c1bc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0806 commit 002b726a400a1dea16c0b59ae61527a1e55799fb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0806_002b726a400a1dea16c0b59ae61527a1e55799fb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2b726a400a1dea16c0b59ae61527a1e55799fb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002b726a400a1dea16c0b59ae61527a1e55799fb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0807 commit 002ba0376b0836ff36f3ba1d079258ca94e66aca" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0807_002ba0376b0836ff36f3ba1d079258ca94e66aca.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2ba0376b0836ff36f3ba1d079258ca94e66aca",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002ba0376b0836ff36f3ba1d079258ca94e66aca",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0808 commit 002d4ce8aa40644698721d59691d38f1df702f4b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0808_002d4ce8aa40644698721d59691d38f1df702f4b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2d4ce8aa40644698721d59691d38f1df702f4b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002d4ce8aa40644698721d59691d38f1df702f4b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0809 commit 002dd773b0b2ff2e28a335fb879a321056c0f6e2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0809_002dd773b0b2ff2e28a335fb879a321056c0f6e2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2dd773b0b2ff2e28a335fb879a321056c0f6e2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002dd773b0b2ff2e28a335fb879a321056c0f6e2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0810 commit 002e5e9ad163f30e1664a2bf37e45097c8ab6be5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0810_002e5e9ad163f30e1664a2bf37e45097c8ab6be5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2e5e9ad163f30e1664a2bf37e45097c8ab6be5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002e5e9ad163f30e1664a2bf37e45097c8ab6be5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0811 commit 002ee2fe68258e5a4c6dfa93b1c46cf3318b5342" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0811_002ee2fe68258e5a4c6dfa93b1c46cf3318b5342.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2ee2fe68258e5a4c6dfa93b1c46cf3318b5342",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002ee2fe68258e5a4c6dfa93b1c46cf3318b5342",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0812 commit 002f206faf09d39abee80f916cabaf3ab342b74f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0812_002f206faf09d39abee80f916cabaf3ab342b74f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/2f206faf09d39abee80f916cabaf3ab342b74f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="002f206faf09d39abee80f916cabaf3ab342b74f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0813 commit 0032d548db56eac9ea09b4ba05843365f6325b85" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0813_0032d548db56eac9ea09b4ba05843365f6325b85.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/32d548db56eac9ea09b4ba05843365f6325b85",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0032d548db56eac9ea09b4ba05843365f6325b85",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0814 commit 00332b8152c541fcb8887019bb04dd425739d038" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0814_00332b8152c541fcb8887019bb04dd425739d038.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/332b8152c541fcb8887019bb04dd425739d038",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00332b8152c541fcb8887019bb04dd425739d038",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0815 commit 00333ca35c5986e44d4cd4fd59433200d916f77e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0815_00333ca35c5986e44d4cd4fd59433200d916f77e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/333ca35c5986e44d4cd4fd59433200d916f77e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00333ca35c5986e44d4cd4fd59433200d916f77e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0816 commit 0033ab3f599c565c27ef5850a0d3c75c2c8b2024" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0816_0033ab3f599c565c27ef5850a0d3c75c2c8b2024.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/33ab3f599c565c27ef5850a0d3c75c2c8b2024",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0033ab3f599c565c27ef5850a0d3c75c2c8b2024",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0817 commit 0039ba7e5e630502be9ac601845b214abce93750" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0817_0039ba7e5e630502be9ac601845b214abce93750.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/39ba7e5e630502be9ac601845b214abce93750",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0039ba7e5e630502be9ac601845b214abce93750",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0818 commit 0039d60c3fdf0e01ad7e6fce59b2522764f2edc8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0818_0039d60c3fdf0e01ad7e6fce59b2522764f2edc8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/39d60c3fdf0e01ad7e6fce59b2522764f2edc8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0039d60c3fdf0e01ad7e6fce59b2522764f2edc8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0819 commit 003b19693bfcf08d1685a415f77963a93621b232" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0819_003b19693bfcf08d1685a415f77963a93621b232.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3b19693bfcf08d1685a415f77963a93621b232",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003b19693bfcf08d1685a415f77963a93621b232",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0820 commit 003b33a8ad686ee4a0d0b36635bfd6aba940b24a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0820_003b33a8ad686ee4a0d0b36635bfd6aba940b24a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3b33a8ad686ee4a0d0b36635bfd6aba940b24a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003b33a8ad686ee4a0d0b36635bfd6aba940b24a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0821 commit 003b93cfb3f588284b89dc4e4c89e1046913ff59" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0821_003b93cfb3f588284b89dc4e4c89e1046913ff59.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3b93cfb3f588284b89dc4e4c89e1046913ff59",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003b93cfb3f588284b89dc4e4c89e1046913ff59",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0822 commit 003c1f1171f12678fe7994b3e6b3f6b2f2b88de3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0822_003c1f1171f12678fe7994b3e6b3f6b2f2b88de3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3c1f1171f12678fe7994b3e6b3f6b2f2b88de3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003c1f1171f12678fe7994b3e6b3f6b2f2b88de3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0823 commit 003c6abdb27c367747847a76b0a7890d67c794be" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0823_003c6abdb27c367747847a76b0a7890d67c794be.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3c6abdb27c367747847a76b0a7890d67c794be",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003c6abdb27c367747847a76b0a7890d67c794be",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0824 commit 003c84f6d2b9e9c4d5bbf5262cae994bac7190cb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0824_003c84f6d2b9e9c4d5bbf5262cae994bac7190cb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3c84f6d2b9e9c4d5bbf5262cae994bac7190cb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003c84f6d2b9e9c4d5bbf5262cae994bac7190cb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0825 commit 003cdf8882fe9a57a056ab91d2dd9088624c01a2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0825_003cdf8882fe9a57a056ab91d2dd9088624c01a2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3cdf8882fe9a57a056ab91d2dd9088624c01a2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003cdf8882fe9a57a056ab91d2dd9088624c01a2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0826 commit 003d6ddaf41aa5614ac49693d199d1ad5f21fcbf" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0826_003d6ddaf41aa5614ac49693d199d1ad5f21fcbf.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3d6ddaf41aa5614ac49693d199d1ad5f21fcbf",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003d6ddaf41aa5614ac49693d199d1ad5f21fcbf",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0827 commit 003f69b282f9cc54da771e1b3e9378aa3f5178cd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0827_003f69b282f9cc54da771e1b3e9378aa3f5178cd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3f69b282f9cc54da771e1b3e9378aa3f5178cd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003f69b282f9cc54da771e1b3e9378aa3f5178cd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0828 commit 003f815dd9f42b1bb893338b32d9cce33a8926c1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0828_003f815dd9f42b1bb893338b32d9cce33a8926c1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/3f815dd9f42b1bb893338b32d9cce33a8926c1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="003f815dd9f42b1bb893338b32d9cce33a8926c1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0829 commit 00408adeac13f6c16f93a3856961f7b327485c6b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0829_00408adeac13f6c16f93a3856961f7b327485c6b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/408adeac13f6c16f93a3856961f7b327485c6b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00408adeac13f6c16f93a3856961f7b327485c6b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0830 commit 0040d6eb23001531a6defc7f0fc15a2a7eb23baf" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0830_0040d6eb23001531a6defc7f0fc15a2a7eb23baf.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/40d6eb23001531a6defc7f0fc15a2a7eb23baf",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0040d6eb23001531a6defc7f0fc15a2a7eb23baf",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0831 commit 0041797449da61f4131bb1673fa5d4c3af48240d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0831_0041797449da61f4131bb1673fa5d4c3af48240d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/41797449da61f4131bb1673fa5d4c3af48240d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0041797449da61f4131bb1673fa5d4c3af48240d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0832 commit 0041bf6544b9b46022b6362eae834a36505d7baa" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0832_0041bf6544b9b46022b6362eae834a36505d7baa.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/41bf6544b9b46022b6362eae834a36505d7baa",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0041bf6544b9b46022b6362eae834a36505d7baa",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0833 commit 0041f09de6e62efc31c860487f04e8b08bce68c8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0833_0041f09de6e62efc31c860487f04e8b08bce68c8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/41f09de6e62efc31c860487f04e8b08bce68c8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0041f09de6e62efc31c860487f04e8b08bce68c8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0834 commit 00432a36e20f86338774e5daf8c7fb2eff0beda8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0834_00432a36e20f86338774e5daf8c7fb2eff0beda8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/432a36e20f86338774e5daf8c7fb2eff0beda8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00432a36e20f86338774e5daf8c7fb2eff0beda8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0835 commit 00436bf1b1c2a8fe6cf5d2c2457d419d683042f4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0835_00436bf1b1c2a8fe6cf5d2c2457d419d683042f4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/436bf1b1c2a8fe6cf5d2c2457d419d683042f4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00436bf1b1c2a8fe6cf5d2c2457d419d683042f4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0836 commit 00449f992b629f7f7884fb2cf46ff411a2a4f381" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0836_00449f992b629f7f7884fb2cf46ff411a2a4f381.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/449f992b629f7f7884fb2cf46ff411a2a4f381",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00449f992b629f7f7884fb2cf46ff411a2a4f381",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0837 commit 0044f7700fdbfdb04b8f88c385ca6fd545e1e1bb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0837_0044f7700fdbfdb04b8f88c385ca6fd545e1e1bb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/44f7700fdbfdb04b8f88c385ca6fd545e1e1bb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0044f7700fdbfdb04b8f88c385ca6fd545e1e1bb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0838 commit 00458dc5f191f52ef965ca7185b739e8c800b7cb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0838_00458dc5f191f52ef965ca7185b739e8c800b7cb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/458dc5f191f52ef965ca7185b739e8c800b7cb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00458dc5f191f52ef965ca7185b739e8c800b7cb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0839 commit 00466c162082c4c5f2ea96384a9f51147e1c874b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0839_00466c162082c4c5f2ea96384a9f51147e1c874b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/466c162082c4c5f2ea96384a9f51147e1c874b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00466c162082c4c5f2ea96384a9f51147e1c874b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0840 commit 00473fd1968ee887093dc66c616112f9dd2891ab" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0840_00473fd1968ee887093dc66c616112f9dd2891ab.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/473fd1968ee887093dc66c616112f9dd2891ab",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00473fd1968ee887093dc66c616112f9dd2891ab",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0841 commit 0047dd2fd1fc1980913901c5fa098357482c2842" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0841_0047dd2fd1fc1980913901c5fa098357482c2842.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/47dd2fd1fc1980913901c5fa098357482c2842",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0047dd2fd1fc1980913901c5fa098357482c2842",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0842 commit 00480a1e9ccd44f257c09c45c185c9c8825a3078" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0842_00480a1e9ccd44f257c09c45c185c9c8825a3078.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/480a1e9ccd44f257c09c45c185c9c8825a3078",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00480a1e9ccd44f257c09c45c185c9c8825a3078",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0843 commit 004825d314db4ba3f34ef499e3522ef72792d896" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0843_004825d314db4ba3f34ef499e3522ef72792d896.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4825d314db4ba3f34ef499e3522ef72792d896",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004825d314db4ba3f34ef499e3522ef72792d896",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0844 commit 004a3830918a2b20e53ad817a68e75f46c3fe41a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0844_004a3830918a2b20e53ad817a68e75f46c3fe41a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4a3830918a2b20e53ad817a68e75f46c3fe41a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004a3830918a2b20e53ad817a68e75f46c3fe41a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0845 commit 004ae6cbd01fce6968baa99ecac775e9f4153bca" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0845_004ae6cbd01fce6968baa99ecac775e9f4153bca.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4ae6cbd01fce6968baa99ecac775e9f4153bca",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004ae6cbd01fce6968baa99ecac775e9f4153bca",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0846 commit 004c0be766f57ffbf5538aeb3edfd3c650f6ceae" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0846_004c0be766f57ffbf5538aeb3edfd3c650f6ceae.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4c0be766f57ffbf5538aeb3edfd3c650f6ceae",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004c0be766f57ffbf5538aeb3edfd3c650f6ceae",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0847 commit 004c9432f7e4c9f1f3b915b0785d0f175dc664fe" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0847_004c9432f7e4c9f1f3b915b0785d0f175dc664fe.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4c9432f7e4c9f1f3b915b0785d0f175dc664fe",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004c9432f7e4c9f1f3b915b0785d0f175dc664fe",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0848 commit 004e0f790f947c9c511a9ac4f905021c7dbfa9e1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0848_004e0f790f947c9c511a9ac4f905021c7dbfa9e1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4e0f790f947c9c511a9ac4f905021c7dbfa9e1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004e0f790f947c9c511a9ac4f905021c7dbfa9e1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0849 commit 004fefa754a4aa3a99a5954da9fb805dbba8dbeb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0849_004fefa754a4aa3a99a5954da9fb805dbba8dbeb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/4fefa754a4aa3a99a5954da9fb805dbba8dbeb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="004fefa754a4aa3a99a5954da9fb805dbba8dbeb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0850 commit 00504aeac9133c7a100ed66fa2a0ed30aa13e5e4" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0850_00504aeac9133c7a100ed66fa2a0ed30aa13e5e4.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/504aeac9133c7a100ed66fa2a0ed30aa13e5e4",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00504aeac9133c7a100ed66fa2a0ed30aa13e5e4",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0851 commit 0050f8e401a70b1eda9e7358b04e6d6ef3d64ab1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0851_0050f8e401a70b1eda9e7358b04e6d6ef3d64ab1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/50f8e401a70b1eda9e7358b04e6d6ef3d64ab1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0050f8e401a70b1eda9e7358b04e6d6ef3d64ab1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0852 commit 0051b441b38ee2312499f46d78c6c9b29ee09234" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0852_0051b441b38ee2312499f46d78c6c9b29ee09234.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/51b441b38ee2312499f46d78c6c9b29ee09234",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0051b441b38ee2312499f46d78c6c9b29ee09234",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0853 commit 00530834fb17f0ec070018270d0fb3e97e5dba07" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0853_00530834fb17f0ec070018270d0fb3e97e5dba07.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/530834fb17f0ec070018270d0fb3e97e5dba07",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00530834fb17f0ec070018270d0fb3e97e5dba07",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0854 commit 00536761df113c8ad935c78bf407e427fce2f040" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0854_00536761df113c8ad935c78bf407e427fce2f040.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/536761df113c8ad935c78bf407e427fce2f040",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00536761df113c8ad935c78bf407e427fce2f040",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0855 commit 00539cef390dc860d9eda399dc99d14f6f258a5b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0855_00539cef390dc860d9eda399dc99d14f6f258a5b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/539cef390dc860d9eda399dc99d14f6f258a5b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00539cef390dc860d9eda399dc99d14f6f258a5b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0856 commit 0053e902b4f777ba454b62263d3695e5292b1559" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0856_0053e902b4f777ba454b62263d3695e5292b1559.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/53e902b4f777ba454b62263d3695e5292b1559",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0053e902b4f777ba454b62263d3695e5292b1559",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0857 commit 00540458a82ff2454ae1cc63e38a9ce4a1eea878" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0857_00540458a82ff2454ae1cc63e38a9ce4a1eea878.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/540458a82ff2454ae1cc63e38a9ce4a1eea878",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00540458a82ff2454ae1cc63e38a9ce4a1eea878",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0858 commit 0055b56e10f77b1b5f5521b8ba3614f962a09288" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0858_0055b56e10f77b1b5f5521b8ba3614f962a09288.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/55b56e10f77b1b5f5521b8ba3614f962a09288",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0055b56e10f77b1b5f5521b8ba3614f962a09288",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0859 commit 0057847208f5ccec05a0ea62b239e65f3def3a8c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0859_0057847208f5ccec05a0ea62b239e65f3def3a8c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/57847208f5ccec05a0ea62b239e65f3def3a8c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0057847208f5ccec05a0ea62b239e65f3def3a8c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0860 commit 0057c0917d35f9f21e01f2122e7f2b9f169a8b02" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0860_0057c0917d35f9f21e01f2122e7f2b9f169a8b02.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/57c0917d35f9f21e01f2122e7f2b9f169a8b02",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0057c0917d35f9f21e01f2122e7f2b9f169a8b02",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0861 commit 00588bb5cd4a7ff5e2b1ded97d4459bfe6aad6eb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0861_00588bb5cd4a7ff5e2b1ded97d4459bfe6aad6eb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/588bb5cd4a7ff5e2b1ded97d4459bfe6aad6eb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00588bb5cd4a7ff5e2b1ded97d4459bfe6aad6eb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0862 commit 0058a33a8eb5a8bfcfc5f5e769a2517cff4b73f1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0862_0058a33a8eb5a8bfcfc5f5e769a2517cff4b73f1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/58a33a8eb5a8bfcfc5f5e769a2517cff4b73f1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0058a33a8eb5a8bfcfc5f5e769a2517cff4b73f1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0863 commit 0058b3d5eedcf5777712e872e01f74bf8d933be7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0863_0058b3d5eedcf5777712e872e01f74bf8d933be7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/58b3d5eedcf5777712e872e01f74bf8d933be7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0058b3d5eedcf5777712e872e01f74bf8d933be7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0864 commit 005a1de380733477382c50e2e44ed8042c401fed" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0864_005a1de380733477382c50e2e44ed8042c401fed.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5a1de380733477382c50e2e44ed8042c401fed",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005a1de380733477382c50e2e44ed8042c401fed",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0865 commit 005a2f4e6df7060561817828d4fa4245f87ccadf" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0865_005a2f4e6df7060561817828d4fa4245f87ccadf.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5a2f4e6df7060561817828d4fa4245f87ccadf",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005a2f4e6df7060561817828d4fa4245f87ccadf",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0866 commit 005af339c9ad292f9ae2fe3555d8d362a225ca45" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0866_005af339c9ad292f9ae2fe3555d8d362a225ca45.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5af339c9ad292f9ae2fe3555d8d362a225ca45",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005af339c9ad292f9ae2fe3555d8d362a225ca45",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0867 commit 005c62fe4639117a355d933288d74fcee49fbc45" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0867_005c62fe4639117a355d933288d74fcee49fbc45.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5c62fe4639117a355d933288d74fcee49fbc45",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005c62fe4639117a355d933288d74fcee49fbc45",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0868 commit 005e2dfdf299a7d869fa9ec819171fba574f42eb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0868_005e2dfdf299a7d869fa9ec819171fba574f42eb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5e2dfdf299a7d869fa9ec819171fba574f42eb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005e2dfdf299a7d869fa9ec819171fba574f42eb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0869 commit 005f85d9ae95c44d8c6ecf61364642fbcaf49dd2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0869_005f85d9ae95c44d8c6ecf61364642fbcaf49dd2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/5f85d9ae95c44d8c6ecf61364642fbcaf49dd2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="005f85d9ae95c44d8c6ecf61364642fbcaf49dd2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0870 commit 0060041df1b0873b36aacfae8e579999bcc27f39" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0870_0060041df1b0873b36aacfae8e579999bcc27f39.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/60041df1b0873b36aacfae8e579999bcc27f39",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0060041df1b0873b36aacfae8e579999bcc27f39",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0871 commit 00609463979c3a2549c0c917a206345f51975b5d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0871_00609463979c3a2549c0c917a206345f51975b5d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/609463979c3a2549c0c917a206345f51975b5d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00609463979c3a2549c0c917a206345f51975b5d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0872 commit 0060fd1511b94c918928fa3708f69a3f33895a4a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0872_0060fd1511b94c918928fa3708f69a3f33895a4a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/60fd1511b94c918928fa3708f69a3f33895a4a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0060fd1511b94c918928fa3708f69a3f33895a4a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0873 commit 00611d8440ecb64f2c252def017e90c87e55526a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0873_00611d8440ecb64f2c252def017e90c87e55526a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/611d8440ecb64f2c252def017e90c87e55526a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00611d8440ecb64f2c252def017e90c87e55526a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0874 commit 00624d608cc69bd62801c93e74d1ea7a7ddd6598" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0874_00624d608cc69bd62801c93e74d1ea7a7ddd6598.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/624d608cc69bd62801c93e74d1ea7a7ddd6598",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00624d608cc69bd62801c93e74d1ea7a7ddd6598",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0875 commit 0064053bd76ba385e1b5d51b6175bc17bc507804" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0875_0064053bd76ba385e1b5d51b6175bc17bc507804.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/64053bd76ba385e1b5d51b6175bc17bc507804",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0064053bd76ba385e1b5d51b6175bc17bc507804",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0876 commit 00648ba0505bbe1999bb6ae2f1d02a0ef923b191" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0876_00648ba0505bbe1999bb6ae2f1d02a0ef923b191.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/648ba0505bbe1999bb6ae2f1d02a0ef923b191",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00648ba0505bbe1999bb6ae2f1d02a0ef923b191",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0877 commit 00652369ff285f84e440f5d41d708283e30825d7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0877_00652369ff285f84e440f5d41d708283e30825d7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/652369ff285f84e440f5d41d708283e30825d7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00652369ff285f84e440f5d41d708283e30825d7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0878 commit 00653435488f5ed86c5d6dc411fa14fa56f5e3bc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0878_00653435488f5ed86c5d6dc411fa14fa56f5e3bc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/653435488f5ed86c5d6dc411fa14fa56f5e3bc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00653435488f5ed86c5d6dc411fa14fa56f5e3bc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0879 commit 0067272999bcf3ac3929a77114ec0e095910e03d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0879_0067272999bcf3ac3929a77114ec0e095910e03d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/67272999bcf3ac3929a77114ec0e095910e03d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0067272999bcf3ac3929a77114ec0e095910e03d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0880 commit 0067ecc82b2dbef64d3768484eb6a1b4ca2c27d2" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0880_0067ecc82b2dbef64d3768484eb6a1b4ca2c27d2.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/67ecc82b2dbef64d3768484eb6a1b4ca2c27d2",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0067ecc82b2dbef64d3768484eb6a1b4ca2c27d2",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0881 commit 0068aa794696188d3c9bea62804780d44bee824f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0881_0068aa794696188d3c9bea62804780d44bee824f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/68aa794696188d3c9bea62804780d44bee824f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0068aa794696188d3c9bea62804780d44bee824f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0882 commit 0068c82a13d321b567cade0309eff8421bb2358d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0882_0068c82a13d321b567cade0309eff8421bb2358d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/68c82a13d321b567cade0309eff8421bb2358d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0068c82a13d321b567cade0309eff8421bb2358d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0883 commit 0068cede4a753cec0ec5f290bacb1fb22a8f9e58" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0883_0068cede4a753cec0ec5f290bacb1fb22a8f9e58.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/68cede4a753cec0ec5f290bacb1fb22a8f9e58",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0068cede4a753cec0ec5f290bacb1fb22a8f9e58",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0884 commit 0068f2116e67fac511941442cbbf7b0109adf57a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0884_0068f2116e67fac511941442cbbf7b0109adf57a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/68f2116e67fac511941442cbbf7b0109adf57a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0068f2116e67fac511941442cbbf7b0109adf57a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0885 commit 006a0744998804d43a02034bf44b97a163027bb5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0885_006a0744998804d43a02034bf44b97a163027bb5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6a0744998804d43a02034bf44b97a163027bb5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006a0744998804d43a02034bf44b97a163027bb5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0886 commit 006a86646434e5212defdea59092059fe41387b0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0886_006a86646434e5212defdea59092059fe41387b0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6a86646434e5212defdea59092059fe41387b0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006a86646434e5212defdea59092059fe41387b0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0887 commit 006c5f79be55c029d6f68ea0d5a33cb41d1b5e80" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0887_006c5f79be55c029d6f68ea0d5a33cb41d1b5e80.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6c5f79be55c029d6f68ea0d5a33cb41d1b5e80",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006c5f79be55c029d6f68ea0d5a33cb41d1b5e80",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0888 commit 006ede5e860717ff1ec68125393bcd4e74507e5b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0888_006ede5e860717ff1ec68125393bcd4e74507e5b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6ede5e860717ff1ec68125393bcd4e74507e5b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006ede5e860717ff1ec68125393bcd4e74507e5b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0889 commit 006f31d77f3dd5f813557c2839b39b2aaa22b925" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0889_006f31d77f3dd5f813557c2839b39b2aaa22b925.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6f31d77f3dd5f813557c2839b39b2aaa22b925",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006f31d77f3dd5f813557c2839b39b2aaa22b925",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0890 commit 006f3f28af2afb8c567ef3ddf4f0a9110c6be437" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0890_006f3f28af2afb8c567ef3ddf4f0a9110c6be437.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6f3f28af2afb8c567ef3ddf4f0a9110c6be437",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006f3f28af2afb8c567ef3ddf4f0a9110c6be437",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0891 commit 006f424b2d014b8a7c4887b7ddbb57256dd6b8c7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0891_006f424b2d014b8a7c4887b7ddbb57256dd6b8c7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6f424b2d014b8a7c4887b7ddbb57256dd6b8c7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006f424b2d014b8a7c4887b7ddbb57256dd6b8c7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0892 commit 006f546bc30bd42de6ba569ab70ec80441f54430" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0892_006f546bc30bd42de6ba569ab70ec80441f54430.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6f546bc30bd42de6ba569ab70ec80441f54430",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006f546bc30bd42de6ba569ab70ec80441f54430",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0893 commit 006f678780e816a2540628e5473b0eea199d0b61" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0893_006f678780e816a2540628e5473b0eea199d0b61.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6f678780e816a2540628e5473b0eea199d0b61",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006f678780e816a2540628e5473b0eea199d0b61",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0894 commit 006fd83e0389a42b766cb1acd8796c15f69b02b5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0894_006fd83e0389a42b766cb1acd8796c15f69b02b5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/6fd83e0389a42b766cb1acd8796c15f69b02b5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="006fd83e0389a42b766cb1acd8796c15f69b02b5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0895 commit 00703e6d6822f81e7b22d079b7e6d9d044f46cf0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0895_00703e6d6822f81e7b22d079b7e6d9d044f46cf0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/703e6d6822f81e7b22d079b7e6d9d044f46cf0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00703e6d6822f81e7b22d079b7e6d9d044f46cf0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0896 commit 00704e4ba527c7e6a36db9b37d59c719310d878c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0896_00704e4ba527c7e6a36db9b37d59c719310d878c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/704e4ba527c7e6a36db9b37d59c719310d878c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00704e4ba527c7e6a36db9b37d59c719310d878c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0897 commit 00723b02912cc9dae1ee5601ab4b942fdd42ff52" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0897_00723b02912cc9dae1ee5601ab4b942fdd42ff52.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/723b02912cc9dae1ee5601ab4b942fdd42ff52",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00723b02912cc9dae1ee5601ab4b942fdd42ff52",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0898 commit 00727249ec8404c68391ec58e9c9f0d8a88d5ca0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0898_00727249ec8404c68391ec58e9c9f0d8a88d5ca0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/727249ec8404c68391ec58e9c9f0d8a88d5ca0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00727249ec8404c68391ec58e9c9f0d8a88d5ca0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0899 commit 0074aba1c0d3b073c635fdc1d5754dc6a6b6b7b9" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0899_0074aba1c0d3b073c635fdc1d5754dc6a6b6b7b9.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/74aba1c0d3b073c635fdc1d5754dc6a6b6b7b9",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0074aba1c0d3b073c635fdc1d5754dc6a6b6b7b9",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0900 commit 0074c9110db6b8cddc9950f94f69d143379b25ed" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0900_0074c9110db6b8cddc9950f94f69d143379b25ed.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/74c9110db6b8cddc9950f94f69d143379b25ed",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0074c9110db6b8cddc9950f94f69d143379b25ed",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0901 commit 0074cc299493ff4567641e9af5492eb4799ca0ef" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0901_0074cc299493ff4567641e9af5492eb4799ca0ef.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/74cc299493ff4567641e9af5492eb4799ca0ef",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0074cc299493ff4567641e9af5492eb4799ca0ef",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0902 commit 0074d18dc0d816f9842d3e0e1cd0b26341715b37" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0902_0074d18dc0d816f9842d3e0e1cd0b26341715b37.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/74d18dc0d816f9842d3e0e1cd0b26341715b37",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0074d18dc0d816f9842d3e0e1cd0b26341715b37",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0903 commit 007512152e1c8cf64dbb12d8bbc86f5a2514b78d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0903_007512152e1c8cf64dbb12d8bbc86f5a2514b78d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7512152e1c8cf64dbb12d8bbc86f5a2514b78d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007512152e1c8cf64dbb12d8bbc86f5a2514b78d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0904 commit 00754b20f931e0e85fe12e59111cf250d51d288b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0904_00754b20f931e0e85fe12e59111cf250d51d288b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/754b20f931e0e85fe12e59111cf250d51d288b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00754b20f931e0e85fe12e59111cf250d51d288b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0905 commit 00764ca10e0b55b21853fe3f41d688254cfaec08" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0905_00764ca10e0b55b21853fe3f41d688254cfaec08.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/764ca10e0b55b21853fe3f41d688254cfaec08",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00764ca10e0b55b21853fe3f41d688254cfaec08",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0906 commit 0077138cd9d4f94636184553afd8b33b98d320a1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0906_0077138cd9d4f94636184553afd8b33b98d320a1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/77138cd9d4f94636184553afd8b33b98d320a1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0077138cd9d4f94636184553afd8b33b98d320a1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0907 commit 00781ecea10bd10e00a508169c3f935b71420ffd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0907_00781ecea10bd10e00a508169c3f935b71420ffd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/781ecea10bd10e00a508169c3f935b71420ffd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00781ecea10bd10e00a508169c3f935b71420ffd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0908 commit 00787ed55adbc2350efa911bf0bdebf6ca08c095" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0908_00787ed55adbc2350efa911bf0bdebf6ca08c095.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/787ed55adbc2350efa911bf0bdebf6ca08c095",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00787ed55adbc2350efa911bf0bdebf6ca08c095",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0909 commit 0078a7598518a66c085311a11a0f25203b9ecce6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0909_0078a7598518a66c085311a11a0f25203b9ecce6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/78a7598518a66c085311a11a0f25203b9ecce6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0078a7598518a66c085311a11a0f25203b9ecce6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0910 commit 0078a7fa05b3d671739aefba5265da809ea32e55" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0910_0078a7fa05b3d671739aefba5265da809ea32e55.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/78a7fa05b3d671739aefba5265da809ea32e55",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0078a7fa05b3d671739aefba5265da809ea32e55",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0911 commit 0079732e960dc20ab2a68043d5593de358f1377f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0911_0079732e960dc20ab2a68043d5593de358f1377f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/79732e960dc20ab2a68043d5593de358f1377f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0079732e960dc20ab2a68043d5593de358f1377f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0912 commit 0079d6ebd76f4e3fa261b367b0ec2679c47a479a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0912_0079d6ebd76f4e3fa261b367b0ec2679c47a479a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/79d6ebd76f4e3fa261b367b0ec2679c47a479a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0079d6ebd76f4e3fa261b367b0ec2679c47a479a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0913 commit 007aa8d8344f97e9e547c128728cd87095f0f0ac" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0913_007aa8d8344f97e9e547c128728cd87095f0f0ac.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7aa8d8344f97e9e547c128728cd87095f0f0ac",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007aa8d8344f97e9e547c128728cd87095f0f0ac",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0914 commit 007ac544011213045e3905983b4350ffec8f41f7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0914_007ac544011213045e3905983b4350ffec8f41f7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7ac544011213045e3905983b4350ffec8f41f7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007ac544011213045e3905983b4350ffec8f41f7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0915 commit 007b8994d4fc49f4a68ee414db9e814736a3fc04" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0915_007b8994d4fc49f4a68ee414db9e814736a3fc04.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7b8994d4fc49f4a68ee414db9e814736a3fc04",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007b8994d4fc49f4a68ee414db9e814736a3fc04",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0916 commit 007cb03102c5e596bfce0f8e4d86d23eb41ff003" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0916_007cb03102c5e596bfce0f8e4d86d23eb41ff003.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7cb03102c5e596bfce0f8e4d86d23eb41ff003",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007cb03102c5e596bfce0f8e4d86d23eb41ff003",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0917 commit 007d06aa57e673c95da583d2afa30bb14fb69e28" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0917_007d06aa57e673c95da583d2afa30bb14fb69e28.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7d06aa57e673c95da583d2afa30bb14fb69e28",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007d06aa57e673c95da583d2afa30bb14fb69e28",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0918 commit 007e2ba65902b484fc65a313e54594a009841740" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0918_007e2ba65902b484fc65a313e54594a009841740.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7e2ba65902b484fc65a313e54594a009841740",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007e2ba65902b484fc65a313e54594a009841740",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0919 commit 007f7f6e544b89a7efc0dcb5f11a4d5bf5180c3f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0919_007f7f6e544b89a7efc0dcb5f11a4d5bf5180c3f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/7f7f6e544b89a7efc0dcb5f11a4d5bf5180c3f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="007f7f6e544b89a7efc0dcb5f11a4d5bf5180c3f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0920 commit 008028a910b1bb820ad14b976665acf0f5cd4015" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0920_008028a910b1bb820ad14b976665acf0f5cd4015.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8028a910b1bb820ad14b976665acf0f5cd4015",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008028a910b1bb820ad14b976665acf0f5cd4015",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0921 commit 0080f50eb333192617739c9954a30611cc0adeaa" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0921_0080f50eb333192617739c9954a30611cc0adeaa.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/80f50eb333192617739c9954a30611cc0adeaa",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0080f50eb333192617739c9954a30611cc0adeaa",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0922 commit 0081e36c9dc3c201e22f12ebebadfff88fa32b91" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0922_0081e36c9dc3c201e22f12ebebadfff88fa32b91.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/81e36c9dc3c201e22f12ebebadfff88fa32b91",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0081e36c9dc3c201e22f12ebebadfff88fa32b91",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0923 commit 008217cb4a11b1bd9d25eda2d412d813cfeacd9f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0923_008217cb4a11b1bd9d25eda2d412d813cfeacd9f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8217cb4a11b1bd9d25eda2d412d813cfeacd9f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008217cb4a11b1bd9d25eda2d412d813cfeacd9f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0924 commit 00829b5def72f36269796727c9589316a214dc85" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0924_00829b5def72f36269796727c9589316a214dc85.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/829b5def72f36269796727c9589316a214dc85",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00829b5def72f36269796727c9589316a214dc85",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0925 commit 0082d82183b42c19fe7db1531279ff6d3f86c3fe" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0925_0082d82183b42c19fe7db1531279ff6d3f86c3fe.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/82d82183b42c19fe7db1531279ff6d3f86c3fe",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0082d82183b42c19fe7db1531279ff6d3f86c3fe",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0926 commit 0083f1d43a7280aefa23656eaac7266139484b24" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0926_0083f1d43a7280aefa23656eaac7266139484b24.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/83f1d43a7280aefa23656eaac7266139484b24",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0083f1d43a7280aefa23656eaac7266139484b24",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0927 commit 008442f5e798e511cc0cd5d9443552b0d107d558" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0927_008442f5e798e511cc0cd5d9443552b0d107d558.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8442f5e798e511cc0cd5d9443552b0d107d558",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008442f5e798e511cc0cd5d9443552b0d107d558",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0928 commit 0084a813e725aaab79848773e390465283101287" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0928_0084a813e725aaab79848773e390465283101287.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/84a813e725aaab79848773e390465283101287",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0084a813e725aaab79848773e390465283101287",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0929 commit 00855b656bf883c607a4adcd5bc7a76711e4b3a3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0929_00855b656bf883c607a4adcd5bc7a76711e4b3a3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/855b656bf883c607a4adcd5bc7a76711e4b3a3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00855b656bf883c607a4adcd5bc7a76711e4b3a3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0930 commit 008566e0f8ef9751c43197f40ac08d3bdfce78a7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0930_008566e0f8ef9751c43197f40ac08d3bdfce78a7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8566e0f8ef9751c43197f40ac08d3bdfce78a7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008566e0f8ef9751c43197f40ac08d3bdfce78a7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0931 commit 0086e2c854e3af3209915e4ec2f933bcef400050" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0931_0086e2c854e3af3209915e4ec2f933bcef400050.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/86e2c854e3af3209915e4ec2f933bcef400050",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0086e2c854e3af3209915e4ec2f933bcef400050",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0932 commit 0087a87ba8fc69b27dde0183ec24ade367a4aa5b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0932_0087a87ba8fc69b27dde0183ec24ade367a4aa5b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/87a87ba8fc69b27dde0183ec24ade367a4aa5b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0087a87ba8fc69b27dde0183ec24ade367a4aa5b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0933 commit 0087d7dfbebf10f23394f32db3c283eb7ab03129" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0933_0087d7dfbebf10f23394f32db3c283eb7ab03129.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/87d7dfbebf10f23394f32db3c283eb7ab03129",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0087d7dfbebf10f23394f32db3c283eb7ab03129",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0934 commit 00880a17dd1ccad44150c425d5709b767c9326bc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0934_00880a17dd1ccad44150c425d5709b767c9326bc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/880a17dd1ccad44150c425d5709b767c9326bc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00880a17dd1ccad44150c425d5709b767c9326bc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0935 commit 008849689e04e774aa7b194cd690405761e2383a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0935_008849689e04e774aa7b194cd690405761e2383a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8849689e04e774aa7b194cd690405761e2383a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008849689e04e774aa7b194cd690405761e2383a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0936 commit 00889c8ca7017d7b9d07d47843e3a3e245a1de26" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0936_00889c8ca7017d7b9d07d47843e3a3e245a1de26.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/889c8ca7017d7b9d07d47843e3a3e245a1de26",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00889c8ca7017d7b9d07d47843e3a3e245a1de26",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0937 commit 00892786b83936ec53d7d38df9bfc4e180fc2e19" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0937_00892786b83936ec53d7d38df9bfc4e180fc2e19.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/892786b83936ec53d7d38df9bfc4e180fc2e19",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00892786b83936ec53d7d38df9bfc4e180fc2e19",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0938 commit 0089521cacd99db8018b7a31e205dad0bf0738c7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0938_0089521cacd99db8018b7a31e205dad0bf0738c7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/89521cacd99db8018b7a31e205dad0bf0738c7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0089521cacd99db8018b7a31e205dad0bf0738c7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0939 commit 008a5d481ef1636efab82a72fd0b542b3d750e60" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0939_008a5d481ef1636efab82a72fd0b542b3d750e60.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8a5d481ef1636efab82a72fd0b542b3d750e60",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008a5d481ef1636efab82a72fd0b542b3d750e60",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0940 commit 008adee2087e8e78f767bbfdfd49d1d1eabf9469" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0940_008adee2087e8e78f767bbfdfd49d1d1eabf9469.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8adee2087e8e78f767bbfdfd49d1d1eabf9469",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008adee2087e8e78f767bbfdfd49d1d1eabf9469",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0941 commit 008bb6ea695e14740bfd14bec805cde6219b336e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0941_008bb6ea695e14740bfd14bec805cde6219b336e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8bb6ea695e14740bfd14bec805cde6219b336e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008bb6ea695e14740bfd14bec805cde6219b336e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0942 commit 008c208c2c54f7bb97bfb7bc5dc606a4eb0d6837" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0942_008c208c2c54f7bb97bfb7bc5dc606a4eb0d6837.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8c208c2c54f7bb97bfb7bc5dc606a4eb0d6837",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008c208c2c54f7bb97bfb7bc5dc606a4eb0d6837",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0943 commit 008d5d005d862d9b0309af94dfc266e3b06bdf6d" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0943_008d5d005d862d9b0309af94dfc266e3b06bdf6d.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8d5d005d862d9b0309af94dfc266e3b06bdf6d",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008d5d005d862d9b0309af94dfc266e3b06bdf6d",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0944 commit 008d896df5deaa967d4d86306b408333e8ef34c3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0944_008d896df5deaa967d4d86306b408333e8ef34c3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8d896df5deaa967d4d86306b408333e8ef34c3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008d896df5deaa967d4d86306b408333e8ef34c3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0945 commit 008e3cc5d781273053c79d1ccf8cc3bf36086a07" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0945_008e3cc5d781273053c79d1ccf8cc3bf36086a07.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8e3cc5d781273053c79d1ccf8cc3bf36086a07",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008e3cc5d781273053c79d1ccf8cc3bf36086a07",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0946 commit 008ed7df93082103c8c74d045e573e19868b2c6b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0946_008ed7df93082103c8c74d045e573e19868b2c6b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8ed7df93082103c8c74d045e573e19868b2c6b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008ed7df93082103c8c74d045e573e19868b2c6b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0947 commit 008f59d2d6b3be1017d8d321985b89d85659df04" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0947_008f59d2d6b3be1017d8d321985b89d85659df04.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8f59d2d6b3be1017d8d321985b89d85659df04",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008f59d2d6b3be1017d8d321985b89d85659df04",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0948 commit 008feced5acbbd64e924b80dd144178f20691f23" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0948_008feced5acbbd64e924b80dd144178f20691f23.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/8feced5acbbd64e924b80dd144178f20691f23",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="008feced5acbbd64e924b80dd144178f20691f23",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0949 commit 009055f3ecd8d9b4eb140429cb5ce5d2088174c7" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0949_009055f3ecd8d9b4eb140429cb5ce5d2088174c7.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9055f3ecd8d9b4eb140429cb5ce5d2088174c7",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009055f3ecd8d9b4eb140429cb5ce5d2088174c7",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0950 commit 00906d6f227b259ac7c8cebd07bbea0ba4792185" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0950_00906d6f227b259ac7c8cebd07bbea0ba4792185.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/906d6f227b259ac7c8cebd07bbea0ba4792185",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00906d6f227b259ac7c8cebd07bbea0ba4792185",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0951 commit 0090a6185af18a199d5bc12781adf411177f1e1a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0951_0090a6185af18a199d5bc12781adf411177f1e1a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/90a6185af18a199d5bc12781adf411177f1e1a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0090a6185af18a199d5bc12781adf411177f1e1a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0952 commit 009315499e789d241998fcc5add1f109af8ba0e6" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0952_009315499e789d241998fcc5add1f109af8ba0e6.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9315499e789d241998fcc5add1f109af8ba0e6",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009315499e789d241998fcc5add1f109af8ba0e6",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0953 commit 009318b1f1db24588d93bc658ea6c6a5324c9c3c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0953_009318b1f1db24588d93bc658ea6c6a5324c9c3c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9318b1f1db24588d93bc658ea6c6a5324c9c3c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009318b1f1db24588d93bc658ea6c6a5324c9c3c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0954 commit 0093abc286fe3f195f702de28c6d9af009dda8e0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0954_0093abc286fe3f195f702de28c6d9af009dda8e0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/93abc286fe3f195f702de28c6d9af009dda8e0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0093abc286fe3f195f702de28c6d9af009dda8e0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0955 commit 009409fe72e53ce5a3c7cf6802d7e068632e68e8" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0955_009409fe72e53ce5a3c7cf6802d7e068632e68e8.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9409fe72e53ce5a3c7cf6802d7e068632e68e8",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009409fe72e53ce5a3c7cf6802d7e068632e68e8",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0956 tag 009b88644c36209e5ed2de067d5cdce9a1ff0dc0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0956_009b88644c36209e5ed2de067d5cdce9a1ff0dc0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/9b88644c36209e5ed2de067d5cdce9a1ff0dc0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="009b88644c36209e5ed2de067d5cdce9a1ff0dc0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0957 tag 00c2e1f092f5fc428e3f5b74bdbb618c227b2f54" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0957_00c2e1f092f5fc428e3f5b74bdbb618c227b2f54.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/c2e1f092f5fc428e3f5b74bdbb618c227b2f54",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00c2e1f092f5fc428e3f5b74bdbb618c227b2f54",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0958 tag 00e6af904e4ec9e908d5797975fd4a36f1d322dd" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0958_00e6af904e4ec9e908d5797975fd4a36f1d322dd.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/00/e6af904e4ec9e908d5797975fd4a36f1d322dd",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="00e6af904e4ec9e908d5797975fd4a36f1d322dd",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0959 tag 01a825578e79203a87b832731ed1fc7c23a3e77f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0959_01a825578e79203a87b832731ed1fc7c23a3e77f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/01/a825578e79203a87b832731ed1fc7c23a3e77f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="01a825578e79203a87b832731ed1fc7c23a3e77f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0960 tag 01cde9d884eb7e88c8a79d68804395a89b0013be" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0960_01cde9d884eb7e88c8a79d68804395a89b0013be.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/01/cde9d884eb7e88c8a79d68804395a89b0013be",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="01cde9d884eb7e88c8a79d68804395a89b0013be",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0961 tag 01dcc68948db4bd63135e7bdcddea06d038c0231" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0961_01dcc68948db4bd63135e7bdcddea06d038c0231.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/01/dcc68948db4bd63135e7bdcddea06d038c0231",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="01dcc68948db4bd63135e7bdcddea06d038c0231",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0962 tag 01e6515feb062a18cea84571e8779f4ad851e2ae" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0962_01e6515feb062a18cea84571e8779f4ad851e2ae.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/01/e6515feb062a18cea84571e8779f4ad851e2ae",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="01e6515feb062a18cea84571e8779f4ad851e2ae",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0963 tag 02164beebd5292478f585ca84f0129b17b6318f1" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0963_02164beebd5292478f585ca84f0129b17b6318f1.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/02/164beebd5292478f585ca84f0129b17b6318f1",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="02164beebd5292478f585ca84f0129b17b6318f1",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0964 tag 0229fbdd7a9fb39d6e3701865c1c4b4a5dcb8b9b" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0964_0229fbdd7a9fb39d6e3701865c1c4b4a5dcb8b9b.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/02/29fbdd7a9fb39d6e3701865c1c4b4a5dcb8b9b",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0229fbdd7a9fb39d6e3701865c1c4b4a5dcb8b9b",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0965 tag 02a5ab81c43d0aeea569974b286a9098c458cc92" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0965_02a5ab81c43d0aeea569974b286a9098c458cc92.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/02/a5ab81c43d0aeea569974b286a9098c458cc92",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="02a5ab81c43d0aeea569974b286a9098c458cc92",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0966 tag 02abbc9dd6f78b96976c9219b9507a2cc59c7d94" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0966_02abbc9dd6f78b96976c9219b9507a2cc59c7d94.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/02/abbc9dd6f78b96976c9219b9507a2cc59c7d94",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="02abbc9dd6f78b96976c9219b9507a2cc59c7d94",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0967 tag 02b2acff8bafb6d73c6513469cdda0c6c18c4138" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0967_02b2acff8bafb6d73c6513469cdda0c6c18c4138.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/02/b2acff8bafb6d73c6513469cdda0c6c18c4138",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="02b2acff8bafb6d73c6513469cdda0c6c18c4138",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0968 tag 031e0b808433c2b8bbad6de5007c5857b4e6e7fb" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0968_031e0b808433c2b8bbad6de5007c5857b4e6e7fb.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/03/1e0b808433c2b8bbad6de5007c5857b4e6e7fb",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="031e0b808433c2b8bbad6de5007c5857b4e6e7fb",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0969 tag 034ee24912da0a700ba27109825710fd84d64591" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0969_034ee24912da0a700ba27109825710fd84d64591.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/03/4ee24912da0a700ba27109825710fd84d64591",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="034ee24912da0a700ba27109825710fd84d64591",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0970 tag 03c5bd5315930d8d88d0c6b521e998041a13bb26" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0970_03c5bd5315930d8d88d0c6b521e998041a13bb26.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/03/c5bd5315930d8d88d0c6b521e998041a13bb26",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="03c5bd5315930d8d88d0c6b521e998041a13bb26",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0971 tag 04043f4d1ae42bddee67d354a2e6fd2464592a1e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0971_04043f4d1ae42bddee67d354a2e6fd2464592a1e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/04/043f4d1ae42bddee67d354a2e6fd2464592a1e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="04043f4d1ae42bddee67d354a2e6fd2464592a1e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0972 tag 041ed88c7369c3e45077502b74664d8101f99ab3" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0972_041ed88c7369c3e45077502b74664d8101f99ab3.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/04/1ed88c7369c3e45077502b74664d8101f99ab3",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="041ed88c7369c3e45077502b74664d8101f99ab3",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0973 tag 046968b18ac0839c68773a104fc377078775615c" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0973_046968b18ac0839c68773a104fc377078775615c.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/04/6968b18ac0839c68773a104fc377078775615c",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="046968b18ac0839c68773a104fc377078775615c",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0974 tag 04cab0c6c9fa523b0cdf89d714fc937addb23936" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0974_04cab0c6c9fa523b0cdf89d714fc937addb23936.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/04/cab0c6c9fa523b0cdf89d714fc937addb23936",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="04cab0c6c9fa523b0cdf89d714fc937addb23936",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0975 tag 04d14fa25c7a481a6141248e3cbd04d76ab15df0" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0975_04d14fa25c7a481a6141248e3cbd04d76ab15df0.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/04/d14fa25c7a481a6141248e3cbd04d76ab15df0",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="04d14fa25c7a481a6141248e3cbd04d76ab15df0",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0976 tag 04f013dc38d7512eadb915eba22efc414f18b869" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0976_04f013dc38d7512eadb915eba22efc414f18b869.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/04/f013dc38d7512eadb915eba22efc414f18b869",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="04f013dc38d7512eadb915eba22efc414f18b869",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0977 tag 055e4ae3ae6eb344cbabf2a5256a49ea66040131" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0977_055e4ae3ae6eb344cbabf2a5256a49ea66040131.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/05/5e4ae3ae6eb344cbabf2a5256a49ea66040131",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="055e4ae3ae6eb344cbabf2a5256a49ea66040131",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0978 tag 058196d2e39dbe1ef6a4413680df37349fa2d4cf" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0978_058196d2e39dbe1ef6a4413680df37349fa2d4cf.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/05/8196d2e39dbe1ef6a4413680df37349fa2d4cf",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="058196d2e39dbe1ef6a4413680df37349fa2d4cf",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0979 tag 0586476e09a02303693fed1b03f8153df97e5001" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0979_0586476e09a02303693fed1b03f8153df97e5001.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/05/86476e09a02303693fed1b03f8153df97e5001",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0586476e09a02303693fed1b03f8153df97e5001",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0980 tag 05ed6224f705b71044e62069c28536f3d7aa817f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0980_05ed6224f705b71044e62069c28536f3d7aa817f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/05/ed6224f705b71044e62069c28536f3d7aa817f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="05ed6224f705b71044e62069c28536f3d7aa817f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0981 tag 0675c6702155753b8e354e83c45d9c980bbccdff" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0981_0675c6702155753b8e354e83c45d9c980bbccdff.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/06/75c6702155753b8e354e83c45d9c980bbccdff",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0675c6702155753b8e354e83c45d9c980bbccdff",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0982 tag 06f20e9d0f1bcbf887ddd4f47883a8bf9e1c73cc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0982_06f20e9d0f1bcbf887ddd4f47883a8bf9e1c73cc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/06/f20e9d0f1bcbf887ddd4f47883a8bf9e1c73cc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="06f20e9d0f1bcbf887ddd4f47883a8bf9e1c73cc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0983 tag 06fa2b7c2b65eedca6f31d62ae59e6f551db5495" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0983_06fa2b7c2b65eedca6f31d62ae59e6f551db5495.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/06/fa2b7c2b65eedca6f31d62ae59e6f551db5495",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="06fa2b7c2b65eedca6f31d62ae59e6f551db5495",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0984 tag 0719925f2364525036803722735c5591d7fdc134" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0984_0719925f2364525036803722735c5591d7fdc134.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/07/19925f2364525036803722735c5591d7fdc134",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0719925f2364525036803722735c5591d7fdc134",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0985 tag 072c71817c179b9e45d8639ca5326c5c5f66a91e" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0985_072c71817c179b9e45d8639ca5326c5c5f66a91e.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/07/2c71817c179b9e45d8639ca5326c5c5f66a91e",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="072c71817c179b9e45d8639ca5326c5c5f66a91e",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0986 tag 074ffb61b4b507b3bde7dcf6006e5660a0430860" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0986_074ffb61b4b507b3bde7dcf6006e5660a0430860.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/07/4ffb61b4b507b3bde7dcf6006e5660a0430860",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="074ffb61b4b507b3bde7dcf6006e5660a0430860",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0987 tag 0798abe9c2bec5749a57b671c97e96e81de4bd5f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0987_0798abe9c2bec5749a57b671c97e96e81de4bd5f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/07/98abe9c2bec5749a57b671c97e96e81de4bd5f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="0798abe9c2bec5749a57b671c97e96e81de4bd5f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0988 tag 07cca3b30ee2b5d060e44e5b18d7c22929c63d1a" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0988_07cca3b30ee2b5d060e44e5b18d7c22929c63d1a.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/07/cca3b30ee2b5d060e44e5b18d7c22929c63d1a",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="07cca3b30ee2b5d060e44e5b18d7c22929c63d1a",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0989 tag 07e38db6a5a03690034d27104401f6c8ea40f1fc" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0989_07e38db6a5a03690034d27104401f6c8ea40f1fc.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/07/e38db6a5a03690034d27104401f6c8ea40f1fc",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="07e38db6a5a03690034d27104401f6c8ea40f1fc",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0990 tag 07ef072f51d64a1945a34db5465adc560b6bcf23" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0990_07ef072f51d64a1945a34db5465adc560b6bcf23.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/07/ef072f51d64a1945a34db5465adc560b6bcf23",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="07ef072f51d64a1945a34db5465adc560b6bcf23",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0991 tag 08110d785b496c9214d4b779a98ccebbbe318579" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0991_08110d785b496c9214d4b779a98ccebbbe318579.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/08/110d785b496c9214d4b779a98ccebbbe318579",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="08110d785b496c9214d4b779a98ccebbbe318579",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0992 tag 081c686fea3ad65ddcfe7cc1fe5c9787c5f3cf9f" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0992_081c686fea3ad65ddcfe7cc1fe5c9787c5f3cf9f.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/08/1c686fea3ad65ddcfe7cc1fe5c9787c5f3cf9f",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="081c686fea3ad65ddcfe7cc1fe5c9787c5f3cf9f",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0993 tag 085b01231ab913efe780ee553991ea8681b12fe5" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0993_085b01231ab913efe780ee553991ea8681b12fe5.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/08/5b01231ab913efe780ee553991ea8681b12fe5",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="085b01231ab913efe780ee553991ea8681b12fe5",
  )
  assert_eq(obj.to_json(), expected)
}

///|
async test "git object 0994 tag 088f4810d88a751eb016fe8bdff8c5b999b0acae" {
  let expected = load_expected_json(
    "fixtures_priv_test/expected/test_0994_088f4810d88a751eb016fe8bdff8c5b999b0acae.json",
  )
  let payload = load_object_bytes(
    "fixtures_priv_test/objects/08/8f4810d88a751eb016fe8bdff8c5b999b0acae",
  )
  let obj = parse_object_bytes(
    payload,
    expected_oid="088f4810d88a751eb016fe8bdff8c5b999b0acae",
  )
  assert_eq(obj.to_json(), expected)
}
