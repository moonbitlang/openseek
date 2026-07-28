///|
test "raw/malformed/seed_0/case_0000" {
  let bytes : Bytes = bytes_concat([
    b"\xdd\xf1\xe9\xfc\x96\xda\xf9\x7c\x14\xf5\xcf\x59\x09\x76\xc4\xd6\x88\x10\x59\xb2\x19\x95\x58\x36\x57\x7e\x3f\x54\xe7\xc4\xba\xb3",
    b"\x8e\x6b\xe2\xe1\x7c\xdc\x3f\x61\x38\x25\x9e\xb1\x54\xda\x4e\x57\x0a\xa8\x65\x35\xc4\x4f\x41\xc5\x36\xc0\x08\xbe\x90\xda\xbc\xfb",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0001" {
  let bytes : Bytes = bytes_concat([
    b"\x18\x42\xe0\x78\x8a\x88\xf6\x08\xd5\x53\x53\xd1\x4f\x89\x96\xaf\x0b\x12\x47\xa6\x1a\x6e\x7a\x8a\x8b\x85\xa0\x11\x4e\xf0\x41\x9e",
    b"\x71\x90\x77\x0d\x87\xd2\x18\x4f\x10\x0c\xb0\xf7\xa6\x42\xa6\x29\x06\x9c\x42\x2c\x02\x1d\x65\xb4\x98\xe1\xdd\x1d\x37\x24\xbe\xeb",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0002" {
  let bytes : Bytes = bytes_concat([
    b"\x5d\x35\xe3\xf3\x0e\xf1\xa7\xc2\x4b\x8c\x8e\x22\x8f\x25\xe0\x06\xb9\x28\x54\x74\x6f\x7a\x81\x77\xb8\xa5\x5f\xc0\xc9\x7f\x16\x8f",
    b"\x1e\xa6\x8d\x67\x67\x7f\x7a\xad\x4f\xa5\x9e\xb9\xd5\xd4\xfd\x0c\x10\x99\xb5\x58\x3e\x75\xc8\xcb\x1c\xb6\x56\x2f\x3d\x84\xf1\x23",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0003" {
  let bytes : Bytes = bytes_concat([
    b"\xfe\x32\x9b\x9f\x69\xc7\xb1\x35\x71\x62\x94\xab\x53\x44\xf0\x83\xe1\xc4\x50\xe3\x9c\x61\x53\x3e\x95\xab\x28\x93\x19\xb4\xc2\xee",
    b"\x79\x15\x44\x87\xc2\xfc\x5f\x3b\xf9\x20\x51\x2f\x3e\x92\xbc\x3f\x44\xbc\xf5\x9b\x6c\x6a\xce\xaa\xc0\x94\x19\x8d\xc0\x42\xfd\x0e",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0004" {
  let bytes : Bytes = bytes_concat([
    b"\x4e\xc8\x50\x49\x2d\x7a\xa0\x2a\x57\x45\x04\x2c\x40\xa8\x03\x2d\x11\xde\xa7\xd3\x09\x51\x21\x96\x22\xea\xa4\x57\xbc\xff\xc0\x83",
    b"\x38\xf5\xbc\x0b\x91\x26\xcb\x05\x20\x0e\x5b\x92\xb3\xd3\x67\x23\xa4\x6b\x6a\xb8\xe9\x8d\xd9\x0b\x45\x8e\xb7\x7f\x24\x68\xe1\x39",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0005" {
  let bytes : Bytes = bytes_concat([
    b"\x5c\x88\x11\xa2\x77\x08\x57\x78\xaa\x33\xf7\x1f\x24\x68\x67\x77\x78\x1d\xcd\xed\xf4\xeb\xa0\xfa\xfb\xe7\x9d\x78\xfd\xb9\x3e\x8f",
    b"\x40\xc3\xc2\x2b\x87\x3c\xe5\xef\x41\xa4\x93\x91\xf8\x7b\x72\xeb\x11\x5b\xfd\x11\x0b\x75\xe1\x07\xcb\xd6\x14\xad\x53\x2f\x24\x23",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0006" {
  let bytes : Bytes = bytes_concat([
    b"\xf2\x7d\xff\xc2\x9e\xb7\x53\x6e\xcf\xf6\x1c\x90\xec\x4e\x44\xaa\x98\x67\x2a\x2e\x15\xf5\xc7\x89\xd7\xec\x63\x3a\xa2\x55\xf3\x04",
    b"\xac\x09\xff\xe1\xdb\x22\x6b\x12\x30\x4f\xe6\xbd\xf1\x9c\xc7\x81\xf7\xf7\x17\x86\x9d\xdb\x99\xfb\x1e\xcd\xd3\x19\xd6\x26\xb2\xf2",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0007" {
  let bytes : Bytes = bytes_concat([
    b"\xf8\xfa\x7a\x8f\xe3\xf9\xb5\xa7\x81\xb4\x1f\x8b\xce\xe4\x8b\xb2\x57\x10\x48\x8d\x03\xc1\x17\xd7\x37\x42\x89\x22\x81\x9f\x9b\xd2",
    b"\xa4\xae\x40\x25\x77\xf0\x1a\x9c\xaf\xd4\xff\x26\xe9\x8c\xb3\x7b\x2a\xaf\xc2\xb1\x50\x9b\xbf\x07\x57\xf5\xc4\x5a\x5a\xaf\x86\x99",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0008" {
  let bytes : Bytes = bytes_concat([
    b"\x78\x27\xad\xbf\xbe\x68\xe1\x69\x67\x13\xa4\x82\x17\xb2\x19\xb9\x24\x14\xda\xf5\x03\x19\xdb\x88\x03\xbe\x23\x39\x1b\xc0\x38\x5a",
    b"\xb1\xf9\xc4\xf1\x07\xf3\x10\x25\x76\x97\xaa\x70\x5d\x1a\xdc\xa5\xf0\x18\x96\x06\xce\x39\x17\x8d\x0a\x7d\x78\x10\x78\xf3\x16\x55",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0009" {
  let bytes : Bytes = bytes_concat([
    b"\x89\x96\x24\x8f\xc2\xda\x41\x1b\x9b\x30\x8c\xf0\xe5\xfa\x62\x62\x88\x0b\x05\x65\x7b\x76\x16\xe1\x02\x28\xf3\x34\x0f\x2c\xf2\x7b",
    b"\x8f\xda\x31\x12\xcc\x29\x06\x39\xae\x92\x9e\xd4\x87\xeb\x19\x22\x0c\x7d\x4c\x2f\x2c\xb1\xf4\xcf\xb8\x30\x25\x3e\xd7\x69\x21\x0d",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0010" {
  let bytes : Bytes = bytes_concat([
    b"\xf8\xf2\x1a\x69\xef\x84\x54\x50\xf1\x39\x71\x7c\x04\xe3\x26\x50\x6e\x49\xfc\x84\x5e\x69\x77\x28\xec\xaa\xba\x4a\xc2\x42\xc9\x22",
    b"\xa1\xe5\x1b\x8d\xc8\xca\x8d\x69\xf6\xa9\x98\x17\xb4\x8c\x77\x70\xd9\x17\xd5\x4a\x1c\x1f\xe1\x30\xfa\xb4\x89\x82\xcf\x1e\x3c\x5d",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0011" {
  let bytes : Bytes = bytes_concat([
    b"\x09\xfe\x10\x36\xa3\x22\xa9\x7c\x60\xcf\x35\xb7\x01\xa2\x2a\x39\xaf\xe5\x07\x0c\x0f\x44\x1e\x9d\x1d\xe6\x3d\x8e\x40\x30\x68\x45",
    b"\xd2\x8b\xfe\xda\x83\xb8\x09\x58\x16\x16\x85\x16\x79\x8c\xde\x1d\xa2\xd2\x62\x5b\xf5\xb7\xfc\x50\xf0\x5f\xb1\x8b\xf4\x9d\xe6\xaf",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0012" {
  let bytes : Bytes = bytes_concat([
    b"\x39\xbd\x38\xec\x34\x01\xc8\x91\x59\xd1\x53\xb4\x21\xeb\xa2\x03\x01\x1c\xae\xb2\x31\xb5\x99\x6e\x0d\x11\xee\x9b\xa5\x10\xee\x67",
    b"\xd6\xf0\xa0\xf6\x12\x0f\xd7\xdd\xc0\x8e\x4e\xdd\x8a\x47\xaf\x01\xfc\xe3\x58\x01\xa2\x46\x33\xb5\xf5\xb1\x95\xe7\xe6\xa5\x1d\xd2",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0013" {
  let bytes : Bytes = bytes_concat([
    b"\xdd\x5a\x0b\xe5\xb9\x6f\x16\xa5\x4a\x79\xb7\x6a\x80\x20\x69\xd4\x42\xcd\xe7\x66\x11\xb4\x22\x7f\x05\x4a\xfa\x67\x6c\x17\xf6\xc9",
    b"\x1f\x60\x44\xbc\x88\x53\xe3\x15\xb5\x98\xdb\x9a\xd6\xf5\x29\xa6\x19\xf2\x6f\x83\x68\x22\x4d\x42\xc0\x02\x5e\xc3\xc2\xf8\x20\x98",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0014" {
  let bytes : Bytes = bytes_concat([
    b"\x28\xdc\xe9\xdb\x9d\x10\xa7\x73\x3d\x7a\x72\x86\xd7\xf7\xc1\xb1\x89\xb3\x5e\xbc\x1b\x9f\x41\x79\x9f\x01\x3b\x73\x2d\x48\xdb\x71",
    b"\x90\xc2\x98\xe0\x86\xce\xb7\xac\xee\x40\x38\x6f\x91\xea\xe5\x79\x31\x61\x54\xa1\xd3\x94\xef\xa2\x30\x75\x0f\x4a\xbc\x58\x97\x26",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0015" {
  let bytes : Bytes = bytes_concat([
    b"\xc8\xd5\xb5\x85\xcd\x6d\x7b\x40\xc0\x5b\x30\xee\xda\xde\xbb\xd1\xbb\xdd\xf0\xa3\x60\xd2\x28\xa9\x28\xdd\xa1\x26\x60\x57\x55\x6e",
    b"\x52\x7d\x13\x3c\x0a\xc7\xff\x46\x88\x35\x4e\x75\xad\x8e\xb9\x49\x39\xd6\x77\x08\x16\xa7\xe8\xf8\x64\x6f\x0f\x24\x7d\x43\x69\x67",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0016" {
  let bytes : Bytes = bytes_concat([
    b"\x0d\xbe\x47\x78\xe4\xeb\xe0\x60\xd3\xa3\x81\xc6\xff\xdf\x7d\x2a\x67\x0f\xc2\x6e\x47\x2f\x55\x9b\x45\x11\x46\x88\x20\x92\x74\x45",
    b"\x34\x53\xe6\xab\x54\x2a\xbd\xee\x6f\x85\x02\x34\xc6\x16\xf8\xb1\x91\xd7\x45\xd6\x5e\x1b\x06\x2d\x83\xdf\xca\x21\xc1\x90\xa6\x27",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0017" {
  let bytes : Bytes = bytes_concat([
    b"\xef\xb8\xc4\xc8\x3b\x21\xa9\x8c\xb3\xe9\x36\x50\xea\xcd\xcb\x8a\x74\x60\xc5\x1e\xcb\x44\xb4\xab\x8d\x4f\x73\xa8\x28\x51\xac\xfc",
    b"\x62\x8b\xcc\xa6\x18\x43\x15\x0d\xae\xf7\xd2\x19\xcf\xfc\x1c\xb2\xe5\x48\x63\x35\x1d\xa9\x69\xc1\x87\x9b\x1c\x14\xd7\xe7\xc7\x37",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0018" {
  let bytes : Bytes = bytes_concat([
    b"\x36\xa3\xf6\x0b\x39\x1f\x31\xd9\x0a\x83\x51\x08\x4d\x84\x5d\x21\xfc\x5f\x49\x61\x66\x3d\xfd\x8b\x20\xfe\x67\x06\x2c\xfc\x9c\xa8",
    b"\x8e\x43\x0d\xcb\xe9\x27\x1a\x43\x38\xaf\x5a\xa4\x7a\x39\x19\xcd\x80\xcb\xd6\xb0\x6c\x62\x9f\x17\x78\x44\xbb\x40\x77\x12\xe1\x84",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0019" {
  let bytes : Bytes = bytes_concat([
    b"\xc8\xa2\x7b\xd6\xed\xfb\x32\x33\x14\xe3\x2f\xcd\xac\x09\xcd\x54\x1c\xd4\xc0\x0e\xc5\x7f\xb6\x80\x5a\xa5\x7c\xca\xb0\x6a\x95\x7e",
    b"\x0c\xbf\xe3\xd1\x57\xd3\xe1\x10\xe0\xed\x6f\x8d\x38\x50\xec\x19\xd4\x0c\x99\xb3\x4c\x46\xe1\x85\xad\x67\xf9\x5d\xe5\x05\x64\x7a",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0020" {
  let bytes : Bytes = bytes_concat([
    b"\xf8\x66\x4b\x88\x01\xa7\x5a\xd3\x43\x03\x75\xeb\xf6\x7b\x1b\xb4\xef\x43\x5a\xe0\xa9\x38\xdb\x22\xbb\x8a\xbd\x5f\xef\xf3\x1c\xaf",
    b"\xda\xd4\x77\xba\x23\x5f\xbf\x3b\x48\x35\x1c\x0b\x79\x6f\x8e\xcb\xed\x8d\x2c\x61\x20\x28\x1c\x4a\x10\xba\x7c\x11\x2c\xb2\x09\xe6",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0021" {
  let bytes : Bytes = bytes_concat([
    b"\x74\xb3\x79\xed\x5d\x25\xb5\xab\xee\x31\x21\xd2\xdf\x23\x8b\xd5\x60\x0a\x34\xf0\xfa\x73\xce\xde\x00\x58\xdb\x3d\x0a\x5f\xdf\xc6",
    b"\x6d\x4c\x6f\x00\xfc\xc6\xa0\x4d\xbc\xe4\x4c\xf3\xa0\x40\xd6\xdc\x45\xdf\x97\xcc\xd1\x41\x6e\x96\xed\x0d\xd2\xd5\x18\x06\xe2\x9b",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0022" {
  let bytes : Bytes = bytes_concat([
    b"\x5b\x54\x0f\xf5\x24\x62\xb3\x15\xcb\x83\x7e\xda\x04\x54\x5c\xd6\xae\xcc\xe8\x98\x3b\x4d\xec\x34\xd4\xa8\x33\x67\x5d\x46\xa1\x73",
    b"\xcc\x20\x33\x62\x0e\x49\x2e\x23\x87\x10\xab\x5a\xc7\x0d\x9d\xb2\x7d\x26\xda\x4f\xbb\x99\x76\x9b\x38\xa5\x23\x26\x09\xd7\x23\x34",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0023" {
  let bytes : Bytes = bytes_concat([
    b"\x11\xbf\xc9\xec\xc3\x4b\x0b\xd5\x31\xc6\xf9\xf6\x63\xdc\x63\xbd\x98\xab\xe5\x6a\xfd\x0b\xb1\x68\x0f\xfe\xfe\x38\x8a\xe2\x31\x25",
    b"\x97\xdc\x28\xe7\x3f\xac\x78\x85\x4e\x9d\xff\x2f\x6b\xb8\x12\xae\x4c\xf3\x06\x66\x9d\x06\xd6\xcc\xe1\xa8\x28\xec\x2b\x3e\x36\x99",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0024" {
  let bytes : Bytes = bytes_concat([
    b"\xf4\xcf\xd6\xf4\x85\x29\xc4\x30\x84\x83\xb3\x34\x51\x2f\x3b\x5c\x4f\xed\x25\xa0\x6d\xf4\x25\x0d\x22\x86\x54\xea\xd6\x34\xe0\x06",
    b"\xb3\x51\xec\x09\x61\x0e\x8f\x7d\x6d\xc1\x91\xdd\x0a\x48\x13\x13\xfb\x45\xa9\xd3\x6f\xa3\xff\x4d\x1f\x26\x9d\x3a\x9b\xc6\xfd\x73",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0025" {
  let bytes : Bytes = bytes_concat([
    b"\x88\xb1\x99\xa2\x0a\x78\xec\x3c\x50\xe0\x70\xaf\x51\xe8\x61\xec\x73\xe8\x79\xfa\x6f\x38\xcd\xf6\xe8\x7e\x11\xf9\x43\xb2\x06\x9d",
    b"\xc3\x3d\x2e\x48\xfe\x03\xd5\x8f\x02\xb4\x07\xd3\xab\x26\x87\x4d\xdb\x6d\xf6\x5e\x14\x2b\x99\xdc\x52\xa3\x1a\x02\xf7\x97\xa4\x27",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0026" {
  let bytes : Bytes = bytes_concat([
    b"\x58\x9c\xe0\x46\xab\x15\x4a\xa3\x75\x50\xce\x0a\x75\x1e\xd2\x55\x49\xc1\xfc\xff\x27\xfe\x99\x6c\xc1\x90\xa2\x36\x2d\x11\xc1\xe2",
    b"\x54\x96\x62\xb9\xa5\x67\x7a\x80\xa9\x5e\x34\x8e\xba\x4f\xe7\xe9\x66\x49\x11\x48\xb8\x7e\xc5\xc1\xbf\xb7\x86\xa2\xa5\xcb\xf8\x37",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0027" {
  let bytes : Bytes = bytes_concat([
    b"\x1b\xd4\xe4\x25\xa6\x29\x28\xc9\x67\x65\x73\x0a\x41\x2f\x1c\x3b\x25\xf8\x43\x59\x3c\x8c\xe3\x23\xa1\xe5\xfa\x80\x3d\xc9\x77\xaf",
    b"\x65\x94\x38\x7e\x1a\xbb\xe7\x17\xcd\x64\xcc\x1f\xa5\x86\xa1\xd7\x09\xed\x19\x19\x5f\xab\xce\x89\x8a\x6b\xe9\xc4\x52\x33\xbf\x20",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0028" {
  let bytes : Bytes = bytes_concat([
    b"\x38\x3c\xfa\x5f\xc8\xa5\xab\xae\x0f\x9f\x1f\xb0\xb7\x9b\xa7\x64\xa2\xbb\x17\xf9\x56\x18\x28\xcd\xcf\x0d\x37\x0c\xa7\x94\x10\x45",
    b"\x1b\xd4\xb5\x90\x30\x6c\xcf\x61\xd8\xc1\xde\x90\x89\xf4\x44\x18\x93\x7e\xfe\xe2\x8e\xb9\x76\x02\x8b\xda\x34\x94\x51\x2a\x43\x40",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0029" {
  let bytes : Bytes = bytes_concat([
    b"\xa5\xe6\x25\x46\x9d\x36\x06\x28\x28\xd7\x1b\xa4\x1b\x1c\x09\xa0\xac\x70\x34\xe9\x32\x16\x48\x8a\x06\x44\x62\x79\xd8\x03\xda\x74",
    b"\xdc\x81\x87\x39\xd2\xcf\x37\xda\x0b\x14\xf3\x9f\xa5\xaa\x51\xd2\x27\x46\xd1\x9d\x1a\x60\xed\x01\xcc\xd2\x09\xbf\x8a\xe2\x34\xcc",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0030" {
  let bytes : Bytes = bytes_concat([
    b"\x1a\xd0\x0e\x46\xac\xcd\x1b\x72\x21\x6d\x95\xfa\xce\x4c\x03\x57\x7e\x56\x29\x8c\x48\xfb\x31\x4a\x05\xb8\xa9\x90\x27\xd3\xd5\x79",
    b"\x89\xd7\x87\xc2\x32\x4e\xf9\x71\x65\x46\x8b\x4d\x35\x33\x97\x36\xe3\x1d\xbb\x5c\xc5\x8e\x14\x3e\x80\x26\xda\xdc\x2c\x86\xf5\xb3",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0031" {
  let bytes : Bytes = bytes_concat([
    b"\x28\x15\x81\x87\x92\xe2\x35\x21\xa6\x83\x7c\x2f\x53\x21\xf7\x93\x16\x2d\x97\x8e\x21\x72\xc0\xbf\xbf\xfb\xe2\x5c\x99\x1a\x4f\x50",
    b"\x29\x31\xa6\xf6\xd0\x42\xdf\x71\x8c\x2b\xdb\xc5\xcc\x90\xd6\x7e\xcf\xea\x61\xbb\xe3\x3f\x7c\x7f\xc9\x1f\x7e\xa6\x67\xbc\xa5\xfc",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0032" {
  let bytes : Bytes = bytes_concat([
    b"\xd5\x4c\x94\x39\x4a\x56\xb0\x32\xa6\x0d\x10\xc3\x16\x47\x61\x69\xd1\x23\xe9\x82\x4c\x39\x98\x44\x77\x44\xb2\x8b\xe3\xb4\xd8\x54",
    b"\x81\x5a\x6c\xd6\x0e\x47\x6b\xd8\xc1\xab\xae\x94\xeb\x8a\x31\xdc\x4a\x71\x54\x44\x22\x29\x12\xa5\x4c\xb4\xbb\x11\xfd\x57\x63\x27",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0033" {
  let bytes : Bytes = bytes_concat([
    b"\x8d\x5f\x20\x93\xff\xdb\xb4\xa7\xd4\xc5\x3b\xef\xa4\x77\x4b\x54\xef\xf5\x2a\x05\x8a\xaf\x94\xa3\x4b\x0b\x27\xe2\x51\xcc\xd2\xc0",
    b"\x13\x27\xa3\xaa\x8c\xfc\x68\xb8\xda\x8c\xb1\x19\x7b\xe4\x08\xf2\x6b\x6c\xa8\xa6\xbf\x10\x40\xb5\x50\x4c\xf7\xe7\x71\x84\xbd\x94",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0034" {
  let bytes : Bytes = bytes_concat([
    b"\x8d\x34\x4d\x66\xf8\x40\x44\x89\x25\x34\xe4\x99\x41\x02\xb9\xcb\x3c\xc5\xcf\x34\x35\x12\x6b\x3a\xc6\x1f\xcc\x2e\xe7\x85\x12\x02",
    b"\x76\xd0\xc4\x15\x8c\x8f\x90\x72\x51\x3e\x96\xed\x3e\x9e\x36\xa0\x6e\x29\x06\xe8\x9f\x83\x90\xd5\xff\xf1\x5e\xa0\x15\x60\x3a\x6d",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0035" {
  let bytes : Bytes = bytes_concat([
    b"\xa4\x84\xf5\xd8\x20\x2c\x70\xac\x56\x38\xb1\xb4\x62\x57\x8a\x62\x82\x10\x5a\xe2\xf1\xe4\x3d\x30\x64\xb1\x86\x0a\xed\x80\x99\x69",
    b"\xe5\x13\x84\x6c\x91\xe0\x40\xc0\xab\x5f\x2c\x35\x2d\xdf\xbc\x8c\x18\x58\x0c\xb0\x48\x5a\x3c\xe7\xa0\xe0\x43\xa4\x9d\x84\x43\xc8",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0036" {
  let bytes : Bytes = bytes_concat([
    b"\x0d\x60\xe9\xa7\x91\xd2\xa3\x3f\xa0\x61\x23\x88\x09\x37\xf6\xcb\x01\xd9\x3e\x27\xcc\x5f\x3d\xc1\x4f\x01\xf5\xeb\x53\x94\xea\xc5",
    b"\xe8\x10\xcf\xe5\x24\x0a\x39\xda\xc4\xa0\x8d\x37\x2c\xaf\xf1\x1d\x79\x2e\x76\xbd\x65\x11\xec\xe8\x49\x8b\x3a\x71\x09\xf1\x6a\x00",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0037" {
  let bytes : Bytes = bytes_concat([
    b"\x4f\x49\x55\xf9\xcb\xcb\x9d\x06\x57\x5a\x97\xa1\x16\xf7\xfa\xbd\x35\x40\x4f\x2d\x8b\xda\xb3\xbc\x64\xf0\xfc\x46\x2c\x39\x3d\xe1",
    b"\x78\x29\x61\x78\x1f\x6b\x1e\x49\x34\x4a\xc8\xe1\xf2\x08\x17\xc8\x5e\x35\x81\x2f\xf0\xff\x3e\xb4\xf3\x52\xc4\x0a\xa1\x19\xc5\x33",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0038" {
  let bytes : Bytes = bytes_concat([
    b"\x93\x15\xb5\x21\xbb\xb5\xc4\x7b\xbe\x5a\xde\x46\x4c\x54\xec\xfd\x4a\x7a\x53\x9d\xdd\x50\x72\x90\x71\x74\x18\xc9\x1a\x6d\x1b\x16",
    b"\xf1\x18\xb3\xd4\x70\xb8\x68\x6c\x53\x8b\x25\xe2\x36\x36\x19\x4e\x24\x31\xa5\x84\x90\xf4\x84\x36\xfb\x07\x07\x76\xa5\xb5\x1d\xc4",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0039" {
  let bytes : Bytes = bytes_concat([
    b"\x8d\xc8\x53\xa4\xbf\xcf\x2e\x42\xac\xba\xf7\xf7\x3f\xbf\xb0\x98\x91\x76\xb1\x51\xd3\x6b\xd8\x85\x72\xfa\x33\xb5\xe9\x09\x06\xfc",
    b"\xc4\x9e\xf0\x33\xa7\xc9\x36\x26\x86\x30\x99\x79\xa9\x55\x5c\x62\x64\x9c\x33\xca\xb4\x7a\x1a\xf3\x37\xe7\xa0\x6a\x37\xac\x22\x2c",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0040" {
  let bytes : Bytes = bytes_concat([
    b"\xc8\xaf\x67\x89\xdd\x38\x2d\x12\x74\xd8\xe3\x1a\x33\xcd\x5b\x0b\x2b\xf2\xa5\x9b\x43\xae\x1a\xae\x6e\xd5\xa3\x51\x69\xcb\xdf\x96",
    b"\x26\x30\x85\x23\x33\x18\xb3\xd1\xd1\xdc\xeb\xbf\x82\x0c\x6b\xc7\xf0\x9a\xe4\x1d\xb6\xbd\x8e\x55\xaa\xec\x20\x6f\x0f\xf2\xa8\x48",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0041" {
  let bytes : Bytes = bytes_concat([
    b"\xe6\x5f\x8b\xa6\x34\x77\x9d\x89\xff\xeb\x65\x35\x2a\xf6\xda\x1b\xb6\x79\xe9\xf8\x8a\xbf\x8f\x7f\xab\x1e\x49\xca\xd6\xe7\x98\x91",
    b"\xe9\x3d\x31\x57\x34\xef\xf0\x21\x62\x89\xde\xc0\x17\x67\x1b\x10\x7f\x8a\xe1\xb6\x57\xcd\x56\x2e\x21\x71\x2c\x9b\x8b\x97\x2c\x95",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0042" {
  let bytes : Bytes = bytes_concat([
    b"\xa0\x19\x98\x42\x8f\xe7\x52\xac\x59\x2b\xcf\x0a\x21\x7b\x82\x97\x64\x75\x3a\xb7\x07\x82\xae\x84\x60\xf3\x37\xce\x8c\x6d\x1f\xb1",
    b"\x78\x26\xad\xc8\x2d\xec\xf8\xdc\x9f\x44\x62\x4f\xa4\xb2\xea\xf0\x9d\x63\xb6\xec\x24\x56\x4b\x02\xed\xe0\x07\x39\x54\xb0\x38\x56",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0043" {
  let bytes : Bytes = bytes_concat([
    b"\x34\x6a\xc7\x88\xf2\xb8\x9f\x59\xb4\x66\x0d\x37\xb3\xb5\x08\xae\x90\x62\x30\xf4\xc4\xaa\x74\xd1\xca\xbc\x90\x3c\x98\x4e\x8e\x5b",
    b"\xd0\xd2\x72\x59\xc0\x76\x00\xb1\xbd\x3a\x06\x73\xec\x04\xdd\x63\x8b\x2e\xa0\xde\xd2\xe9\x9f\x55\xc1\x3d\xda\x14\xcf\x83\x2a\xc0",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0044" {
  let bytes : Bytes = bytes_concat([
    b"\x9d\x3e\x8c\x8a\x55\xda\x78\x53\xfb\x3b\xb9\xb2\x96\x61\x46\xc7\xf6\x64\xa9\x98\xe8\x50\x55\xd2\x74\xe8\x61\x5f\x82\xdb\xde\x96",
    b"\xca\xba\x71\x7d\x01\xf0\xf0\x0f\xe5\xc3\xb8\xf2\xcc\xcd\x22\x8b\x75\x52\x96\xdf\x62\x76\xf2\x55\x1b\xb5\x59\xbc\xd6\x99\x18\xb5",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0045" {
  let bytes : Bytes = bytes_concat([
    b"\x91\x5f\x3c\x62\xda\x47\x72\xc2\x84\xf1\x13\x34\xf0\xfe\xfa\xf5\xf8\xe3\xdd\x08\xd3\x80\xae\xf9\x53\x25\xb1\xb9\xad\x70\x53\x6c",
    b"\x72\x19\xb3\xfa\xc1\x87\x1d\x6c\xf7\xfd\x6e\xa7\x29\xdc\x8a\x1d\x00\x36\xb4\x94\x33\xf2\x72\xae\x3d\x6c\x13\x33\x05\xb8\xdc\x75",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0046" {
  let bytes : Bytes = bytes_concat([
    b"\xee\x11\x05\x67\x7a\x5f\x93\xd7\x1b\xd6\x96\xa9\x8e\x4a\x15\x77\x7b\x8c\x21\x60\x00\x80\x97\x13\xad\x1c\xe1\xe6\x8c\x7c\x6d\x6a",
    b"\x9b\xe7\xd9\xa4\x56\x47\xb9\xed\x8b\xb3\xec\x25\xad\xea\x6e\x9b\xa1\x8e\xf5\xfa\x8c\x00\xe7\xc9\x9e\xe2\xc1\xe2\x4e\xbe\xf5\xf5",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0047" {
  let bytes : Bytes = bytes_concat([
    b"\x2b\x1b\x30\xb3\x6c\x70\xff\xe7\x40\x32\x00\x4c\x0d\x09\x78\xd8\x39\xbf\x00\x1f\x69\x15\x69\x42\xd6\x53\x7f\x6c\x0d\x93\x0d\x15",
    b"\x03\xaf\xb0\x0c\xf9\xb5\xbd\x95\xd6\x6e\xe4\x6e\xf3\x75\x79\xc0\x1a\xb7\x65\x32\x69\x82\x6f\x76\x3b\x09\x74\x8d\x38\xd5\x34\x8e",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0048" {
  let bytes : Bytes = bytes_concat([
    b"\xe7\xbc\xa2\xce\xdd\x36\x58\xff\x36\xe4\x11\xbe\x3d\x42\x51\x5f\x76\xc2\x34\x07\xe3\xfe\xf8\x22\xea\x77\x53\xd0\x50\x38\x14\x8d",
    b"\x88\xe5\xec\x67\xac\x6c\x3d\x66\x3a\x99\x53\x18\x27\x28\x02\x45\x50\xcc\xf3\x5f\x9c\x39\x78\xe3\xcd\xad\x77\x75\xb0\x4b\x50\x26",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0049" {
  let bytes : Bytes = bytes_concat([
    b"\xc4\x7f\x2d\x38\x80\xa8\xff\xe7\x39\xca\x7a\xf2\x2d\xf6\xd2\x32\xbf\xec\x1a\x30\x04\x2a\x2a\xfe\xe7\xdf\x05\x56\xf3\x73\xec\x85",
    b"\x76\x33\x2e\xee\x00\xba\x6c\x03\x0f\x6e\x2a\xd4\x92\xd6\x8c\x6a\x23\xc7\x7c\x1d\x4e\x65\x32\x13\xe6\xb7\x95\xb2\x5b\x33\xfe\xf9",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0050" {
  let bytes : Bytes = bytes_concat([
    b"\xac\x77\x77\x3d\x4f\xe0\x33\x8f\x83\xa1\x03\x20\x80\x24\x1e\xeb\x6a\x4e\x55\xb9\xe3\x0d\x35\xdf\x39\xda\x4a\xdc\x1a\x9e\xab\xde",
    b"\x95\xee\xbc\x9d\xfa\xa1\xef\xa5\x77\x74\xf4\x2c\x9a\xd0\xa2\x0c\xdc\x8c\x6e\x4d\xfa\x7f\x25\xe3\xec\x33\x34\x37\xf9\xcb\x9d\xa1",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0051" {
  let bytes : Bytes = bytes_concat([
    b"\x41\x59\xf6\x0b\x85\x14\x1f\x49\x40\xc9\x2c\xb3\x51\x42\xbf\xe1\xe2\x88\xf2\xc1\xa7\xcb\x46\x72\x47\x4e\xab\x0a\x2f\xa0\x3c\x57",
    b"\x5f\x0d\x47\xf5\x45\x42\x15\xf3\xc3\xda\x94\x3b\xe2\x59\xb2\x74\x81\x9c\x9e\x86\x48\xd3\xdb\xc8\x02\xf0\x32\xac\xf5\x53\xdd\x58",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0052" {
  let bytes : Bytes = bytes_concat([
    b"\xbe\x3c\x5a\xa2\x7e\x9c\xae\xe4\x71\x46\xcc\x36\x4d\x7f\x15\x71\xcf\x22\x50\x74\xe3\x85\xfd\x8b\xac\x51\xa0\xf4\xe0\xdb\x16\x19",
    b"\x91\x1d\x5e\x48\x32\x53\x8a\x3a\x13\xd4\x3e\x17\x29\x89\xc8\x34\x4b\x84\x39\x8b\x09\x30\x31\x0d\x29\x10\xe7\x65\xbc\xfd\xe3\x88",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0053" {
  let bytes : Bytes = bytes_concat([
    b"\x06\xb2\xe2\x40\x06\x3e\x80\xbc\x9a\x20\xa2\x07\x9c\x13\x44\x48\x9a\x51\xa2\xb0\x11\x1b\x85\x57\x50\x93\xe7\xde\xd5\x27\x98\x10",
    b"\xf5\x24\xe6\xa0\xab\x0d\xfb\xea\x21\xb8\xb2\x29\xbf\x59\xc7\x37\xe3\x0c\xf4\x0b\x78\x9c\x16\x68\xe4\x5b\x2f\x5e\x5e\x23\x61\xd9",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0054" {
  let bytes : Bytes = bytes_concat([
    b"\x02\x47\x03\x28\x6e\x7d\x44\x96\xc8\x67\x35\xc7\xac\xda\x9b\xdf\x0b\xc0\x5d\x15\xd0\x45\x2b\x2e\xe4\xa8\xd8\x3b\xc3\x5a\x8b\x89",
    b"\x0b\x3f\x2b\xea\xfb\x58\xcd\x39\x94\xb7\x44\x68\xdc\x5e\x69\xea\xde\xdf\xc6\xcb\xe5\x4c\x1b\x63\x1b\x47\x6f\xf8\xcb\x59\x86\x01",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0055" {
  let bytes : Bytes = bytes_concat([
    b"\x0c\x83\x4e\x57\x75\xb3\x50\x8b\xe0\xea\x72\xdf\xf0\x79\x6b\xc2\x1c\xad\xa9\xda\x52\xf1\x8e\xd1\x14\xde\x94\x6d\x2a\xe0\xc2\x7d",
    b"\xc9\x09\x66\xd7\x81\xdc\x3c\x20\x76\xd3\xf8\xd2\x34\xaa\x02\xe0\x1d\x85\x52\x27\xa0\x5a\x7b\xb4\xd5\x2a\xf3\x05\xdd\x00\x22\x2d",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0056" {
  let bytes : Bytes = bytes_concat([
    b"\xb4\x25\x14\xa8\xe4\xea\x9f\x49\x32\x18\xd2\x06\x2a\x97\xa9\xe0\xf9\x08\xee\xde\x47\x0d\x10\x1a\xf6\x9b\x1a\x1f\x4e\x9e\xa1\x5d",
    b"\xa3\xc7\x55\x20\x14\xf8\x7c\x17\x5e\x88\xc8\xf0\x3e\x84\x40\xfb\x19\x44\x8a\xe0\x92\xc3\xf9\xd2\x57\x34\x1a\xa8\xdd\x55\xdb\xb4",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0057" {
  let bytes : Bytes = bytes_concat([
    b"\xc9\x97\x12\xb2\x58\x7e\x59\xb0\x7d\x8c\x4b\x40\xf3\xc8\xda\x9c\x11\xda\x19\x5a\x19\x00\xe0\xca\xa4\xbf\x25\x07\x80\x40\x00\x35",
    b"\x05\xdb\xd5\xd5\x58\xf9\x2a\xcb\xf6\x1b\xa4\xb9\xc3\xbb\x11\xfc\x1a\x62\x5d\x25\xc0\x54\x5d\x2e\x9b\xa8\x85\x52\xe2\x49\xa7\xc1",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0058" {
  let bytes : Bytes = bytes_concat([
    b"\x34\x68\xe5\xfd\x22\x8b\x07\x3e\xb2\xba\x59\x1a\x05\x0c\x2a\xa4\x1c\x7e\x13\xe4\xdc\x34\x7e\xb7\x86\xbe\x71\x0a\xc3\x72\x1a\xec",
    b"\xce\x22\x64\x0e\x58\x42\x35\xf1\x14\x0a\x24\x50\x29\x93\x84\xb9\x9b\xd7\x45\x67\xbb\xac\x8a\xa7\x6e\xb5\xf4\xf2\x77\x2a\x16\x55",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "raw/malformed/seed_0/case_0059" {
  let bytes : Bytes = bytes_concat([
    b"\x38\x08\x88\x5d\xb5\x6e\x51\x2a\x26\x55\x44\x1b\xa0\xf4\x35\x18\xa3\x75\x19\xf8\x0a\x40\x94\x5f\xbc\x7a\xe6\x99\x6f\xb6\x31\x24",
    b"\x53\x4d\x7b\x11\xb1\x76\x0e\x94\x6a\x58\x8c\x43\xd7\x26\xaa\xa6\x48\x0f\x24\xea\xce\xc8\x1c\x60\x71\x70\xdd\x24\x47\x04\x00\x7c",
  ])
  try @wasm.decode_module(bytes) catch {
    @wasm.DecodeError::InvalidMagicNumber => ()
    e => fail("expected DecodeError::InvalidMagicNumber, got " + e.to_string())
  } noraise {
    _ => fail("expected DecodeError, got Ok")
  }
}

///|
test "smith/valid/seed_0/case_0000" {
  let bytes : Bytes = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x01\x00"
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "validation/start-function-index-out-of-bounds" {
  // The start section is well-formed binary syntax, but function 0 does not
  // exist. Decoding and validation must remain separate phases.
  let bytes = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x08\x01\x00"
  let decoded = @wasm.decode_module(bytes)
  try @wasm.validate_module(decoded) catch {
    @wasm.ValidationError::InvalidModule(_) => ()
  } noraise {
    _ => fail("expected validation failure")
  }
}

///|
test "smith/valid/seed_0/case_0001" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x8c\x01\x01\x4e\x13\x5e\x78\x01\x50\x00\x5e\x7d\x01\x60\x01\x72\x01\x7f\x5e\x7d\x00\x5e\x78",
    b"\x00\x50\x00\x60\x02\x7c\x72\x01\x7c\x50\x00\x5e\x77\x01\x5e\x77\x00\x5f\x14\x77\x00\x77\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78",
    b"\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x50\x01\x01\x5e\x7d",
    b"\x01\x50\x01\x01\x5e\x7d\x01\x50\x01\x01\x5e\x7d\x01\x50\x01\x01\x5e\x7d\x01\x50\x01\x01\x5e\x7d\x01\x50\x01\x01\x5e\x7d\x01\x50",
    b"\x01\x01\x5e\x7d\x01\x50\x01\x01\x5e\x7d\x01\x50\x01\x01\x5e\x7d\x01\x50\x01\x01\x5e\x7d\x01",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (rec
      #|    (type (;0;) (array (mut i8)))
      #|    (type (;1;) (sub (array (mut f32))))
      #|    (type (;2;) (func (param nullexternref) (result i32)))
      #|    (type (;3;) (array f32))
      #|    (type (;4;) (array i8))
      #|    (type (;5;) (sub (func (param f64 nullexternref) (result f64))))
      #|    (type (;6;) (sub (array (mut i16))))
      #|    (type (;7;) (array i16))
      #|    (type (;8;) (struct (field i16) (field i16) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8)))
      #|    (type (;9;) (sub 1 (array (mut f32))))
      #|    (type (;10;) (sub 1 (array (mut f32))))
      #|    (type (;11;) (sub 1 (array (mut f32))))
      #|    (type (;12;) (sub 1 (array (mut f32))))
      #|    (type (;13;) (sub 1 (array (mut f32))))
      #|    (type (;14;) (sub 1 (array (mut f32))))
      #|    (type (;15;) (sub 1 (array (mut f32))))
      #|    (type (;16;) (sub 1 (array (mut f32))))
      #|    (type (;17;) (sub 1 (array (mut f32))))
      #|    (type (;18;) (sub 1 (array (mut f32))))
      #|  )
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0002" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\xb9\x02\x01\x4e\x28\x60\x00\x00\x50\x00\x60\x02\x7b\x7e\x01\x7e\x5e\x78\x00\x5e\x7c\x00\x60",
    b"\x00\x01\x7b\x50\x00\x5e\x78\x01\x50\x00\x5e\x7d\x00\x50\x00\x5e\x78\x00\x50\x00\x5f\x01\x77\x01\x5e\x77\x01\x50\x00\x5f\x00\x50",
    b"\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b",
    b"\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01",
    b"\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e",
    b"\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01",
    b"\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01",
    b"\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60",
    b"\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e",
    b"\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02\x7b\x7e\x01\x7e\x50\x01\x01\x60\x02",
    b"\x7b\x7e\x01\x7e",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (rec
      #|    (type (;0;) (func))
      #|    (type (;1;) (sub (func (param v128 i64) (result i64))))
      #|    (type (;2;) (array i8))
      #|    (type (;3;) (array f64))
      #|    (type (;4;) (func (result v128)))
      #|    (type (;5;) (sub (array (mut i8))))
      #|    (type (;6;) (sub (array f32)))
      #|    (type (;7;) (sub (array i8)))
      #|    (type (;8;) (sub (struct (field (mut i16)))))
      #|    (type (;9;) (array (mut i16)))
      #|    (type (;10;) (sub (struct)))
      #|    (type (;11;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;12;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;13;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;14;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;15;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;16;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;17;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;18;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;19;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;20;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;21;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;22;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;23;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;24;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;25;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;26;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;27;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;28;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;29;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;30;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;31;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;32;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;33;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;34;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;35;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;36;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;37;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;38;) (sub 1 (func (param v128 i64) (result i64))))
      #|    (type (;39;) (sub 1 (func (param v128 i64) (result i64))))
      #|  )
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0003" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x01\x00\x02\x18\x03\x00\x01\x69\x01\x6d\x00\xee\x02\x01\x44\x00\x03\x7f\x00\x00\x03\x77\x2a",
    b"\x3b\x02\x04\xb1\x60\x06\x16\x02\x7f\x01\x41\xfe\xfd\xaf\x9c\x06\x0b\x7c\x01\x44\x0b\xae\xf3\x7e\x30\xdd\x44\x8b\x0b\x09\x07\x02",
    b"\x05\x6d\x00\x05\x70\x00",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (import "" "i" (table (;0;) 366 eqref))
      #|  (import "D" "" (global (;0;) i32))
      #|  (import "" "w*;" (memory (;0;) i64 12337))
      #|  (global (;1;) (mut i32) i32.const 1670119166)
      #|  (global (;2;) (mut f64) f64.const -0x1.4dd307ef3ae0bp-843 (;=-0.000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022232673428045548;))
      #|  (elem (;0;) eqref)
      #|  (elem (;1;) funcref)
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0004" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x01\x00\x02\x01\x00\x04\x07\x01\x69\x05\x02\xca\xe1\x22\x06\x0d\x01\x7c\x00\x44\x92\xa0\x62",
    b"\xb1\x59\x7b\x08\x74\x0b\x07\x08\x02\x00\x01\x00\x01\x2f\x01\x00\x0c\x01\x02\x0b\x05\x02\x01\x00\x01\x00",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (table (;0;) i64 2 569546 exnref)
      #|  (global (;0;) f64 f64.const 0x1.87b59b162a092p+833 (;=87641623470456410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;))
      #|  (export "" (table 0))
      #|  (export "/" (table 0))
      #|  (data (;0;) "")
      #|  (data (;1;) "")
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0005" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x02\x01\x00\x04\x04\x01\x6d\x04\x00\x05\x0b\x01\x05\x82\x34\xa3\xef\xf9\xe6\xcd\xbe\x36\x07\x04",
    b"\x01\x00\x01\x00\x09\x0a\x02\x05\x6c\x00\x05\x72\x01\xd0\x72\x0b",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (table (;0;) i64 0 eqref)
      #|  (memory (;0;) i64 6658 239645700814755)
      #|  (export "" (table 0))
      #|  (elem (;0;) i31ref)
      #|  (elem (;1;) nullexternref (ref.null noextern))
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0006" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\xd0\x0d\x01\x4e\x35\x50\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00",
    b"\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x00\x5f\x0b\x78\x00\x77\x00\x77\x01\x77\x00\x77\x01\x6b\x00\x78\x00",
    b"\x78\x00\x78\x00\x78\x00\x78\x00\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77",
    b"\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01",
    b"\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73",
    b"\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00",
    b"\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b",
    b"\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00",
    b"\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77",
    b"\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01",
    b"\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77",
    b"\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00",
    b"\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77",
    b"\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01",
    b"\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78",
    b"\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00",
    b"\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b",
    b"\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00",
    b"\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e",
    b"\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01",
    b"\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78",
    b"\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e",
    b"\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f",
    b"\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00",
    b"\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01",
    b"\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50",
    b"\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01",
    b"\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78",
    b"\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00",
    b"\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77",
    b"\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01",
    b"\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e",
    b"\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01",
    b"\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77",
    b"\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01",
    b"\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77",
    b"\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01",
    b"\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73",
    b"\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00",
    b"\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b",
    b"\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00",
    b"\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77",
    b"\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01",
    b"\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77",
    b"\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77\x00",
    b"\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01\x77",
    b"\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78\x01",
    b"\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00\x78",
    b"\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b\x00",
    b"\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00\x7b",
    b"\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e\x00",
    b"\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01\x7e",
    b"\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78\x01",
    b"\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01\x50\x01\x00\x5f\x0e\x78",
    b"\x01\x7e\x00\x7b\x00\x78\x01\x77\x00\x77\x01\x77\x00\x7b\x00\x73\x01\x77\x01\x77\x01\x6e\x01\x77\x00\x78\x01",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (rec
      #|    (type (;0;) (sub (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;1;) (sub (struct (field i8) (field i16) (field (mut i16)) (field i16) (field (mut i16)) (field structref) (field i8) (field i8) (field i8) (field i8) (field i8))))
      #|    (type (;2;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;3;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;4;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;5;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;6;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;7;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;8;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;9;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;10;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;11;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;12;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;13;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;14;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;15;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;16;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;17;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;18;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;19;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;20;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;21;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;22;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;23;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;24;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;25;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;26;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;27;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;28;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;29;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;30;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;31;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;32;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;33;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;34;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;35;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;36;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;37;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;38;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;39;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;40;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;41;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;42;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;43;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;44;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;45;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;46;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;47;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;48;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;49;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;50;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;51;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|    (type (;52;) (sub 0 (struct (field (mut i8)) (field i64) (field v128) (field (mut i8)) (field i16) (field (mut i16)) (field i16) (field v128) (field (mut nullfuncref)) (field (mut i16)) (field (mut i16)) (field (mut anyref)) (field i16) (field (mut i8)))))
      #|  )
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0007" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\xb3\x02\x01\x4e\x25\x5f\x0d\x78\x00\x7e\x00\x6f\x00\x77\x01\x7c\x01\x77\x00\x77\x00\x7c\x01",
    b"\x7d\x01\x78\x01\x78\x00\x77\x00\x78\x00\x50\x00\x60\x01\x7d\x00\x50\x00\x60\x02\x7f\x7b\x00\x5f\x0f\x78\x01\x7d\x01\x77\x00\x78",
    b"\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01",
    b"\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d",
    b"\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01",
    b"\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00",
    b"\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60",
    b"\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50",
    b"\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01",
    b"\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00\x50\x01\x01\x60\x01\x7d\x00",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (rec
      #|    (type (;0;) (struct (field i8) (field i64) (field externref) (field (mut i16)) (field (mut f64)) (field i16) (field i16) (field (mut f64)) (field (mut f32)) (field (mut i8)) (field i8) (field i16) (field i8)))
      #|    (type (;1;) (sub (func (param f32))))
      #|    (type (;2;) (sub (func (param i32 v128))))
      #|    (type (;3;) (struct (field (mut i8)) (field (mut f32)) (field i16) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8)))
      #|    (type (;4;) (sub 1 (func (param f32))))
      #|    (type (;5;) (sub 1 (func (param f32))))
      #|    (type (;6;) (sub 1 (func (param f32))))
      #|    (type (;7;) (sub 1 (func (param f32))))
      #|    (type (;8;) (sub 1 (func (param f32))))
      #|    (type (;9;) (sub 1 (func (param f32))))
      #|    (type (;10;) (sub 1 (func (param f32))))
      #|    (type (;11;) (sub 1 (func (param f32))))
      #|    (type (;12;) (sub 1 (func (param f32))))
      #|    (type (;13;) (sub 1 (func (param f32))))
      #|    (type (;14;) (sub 1 (func (param f32))))
      #|    (type (;15;) (sub 1 (func (param f32))))
      #|    (type (;16;) (sub 1 (func (param f32))))
      #|    (type (;17;) (sub 1 (func (param f32))))
      #|    (type (;18;) (sub 1 (func (param f32))))
      #|    (type (;19;) (sub 1 (func (param f32))))
      #|    (type (;20;) (sub 1 (func (param f32))))
      #|    (type (;21;) (sub 1 (func (param f32))))
      #|    (type (;22;) (sub 1 (func (param f32))))
      #|    (type (;23;) (sub 1 (func (param f32))))
      #|    (type (;24;) (sub 1 (func (param f32))))
      #|    (type (;25;) (sub 1 (func (param f32))))
      #|    (type (;26;) (sub 1 (func (param f32))))
      #|    (type (;27;) (sub 1 (func (param f32))))
      #|    (type (;28;) (sub 1 (func (param f32))))
      #|    (type (;29;) (sub 1 (func (param f32))))
      #|    (type (;30;) (sub 1 (func (param f32))))
      #|    (type (;31;) (sub 1 (func (param f32))))
      #|    (type (;32;) (sub 1 (func (param f32))))
      #|    (type (;33;) (sub 1 (func (param f32))))
      #|    (type (;34;) (sub 1 (func (param f32))))
      #|    (type (;35;) (sub 1 (func (param f32))))
      #|    (type (;36;) (sub 1 (func (param f32))))
      #|  )
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0008" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x19\x01\x4e\x04\x50\x00\x5e\x78\x01\x60\x00\x01\x7f\x50\x00\x5f\x02\x78\x00\x7c\x00\x50\x00",
    b"\x5e\x7e\x00\x02\x01\x00\x03\x02\x01\x01\x05\x03\x01\x04\x00\x06\x1a\x02\x7c\x00\x44\x73\xce\x0f\x0d\xad\x26\x8b\x1a\x0b\x7e\x00",
    b"\x42\xc7\xc6\xfe\xb2\xfc\xff\x98\xf7\x00\x0b\x0a\x05\x01\x03\x00\x00\x0b",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (rec
      #|    (type (;0;) (sub (array (mut i8))))
      #|    (type (;1;) (func (result i32)))
      #|    (type (;2;) (sub (struct (field i8) (field f64))))
      #|    (type (;3;) (sub (array i64)))
      #|  )
      #|  (memory (;0;) i64 0)
      #|  (global (;0;) f64 f64.const 0x1.b26ad0d0fce73p-599 (;=0.000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000817899029367008;))
      #|  (global (;1;) i64 i64.const 67100994653102919)
      #|  (func (;0;) (type 1) (result i32)
      #|    unreachable
      #|  )
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0009" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x02\x06\x01\x00\x00\x03\x7c\x01\x05\x07\x01\x01\xbe\x45\xfb\xe2\x01\x06\x38\x03\x7f\x00\x41\xd0",
    b"\x81\xc9\xb7\x7b\x0b\x7b\x00\xfd\x0c\x55\xce\x81\x0e\x1f\xba\xd2\x0c\x4e\x7d\x46\x50\x58\x21\x28\xb9\x0b\x7e\x00\x42\x00\x42\x00",
    b"\x42\xac\xcb\x03\x7c\x7c\x42\xe5\xb0\xb6\xd3\x9c\xb4\xa7\xc3\xf8\x00\x7c\x0b",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (import "" "" (global (;0;) (mut f64)))
      #|  (memory (;0;) 8894 29051)
      #|  (global (;1;) i32 i32.const -1225637680)
      #|  (global (;2;) v128 v128.const i32x4 0x0e81ce55 0x0cd2ba1f 0x50467d4e 0xb9282158)
      #|  (global (;3;) i64 i64.const 0 i64.const 0 i64.const 58796 i64.add i64.add i64.const 8684802249642055781 i64.add)
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0010" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x02\x0e\x02\x00\x03\x5d\xd6\xad\x03\x7e\x00\x00\x00\x03\x7b\x01\x06\x06\x01\x6a\x00\xd0\x6a\x0b",
    b"\x07\x04\x01\x00\x03\x01\x09\x04\x01\x07\x6f\x00\x0c\x01\x01\x0b\x04\x01\x01\x01\x2f",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (import "" "]\u{5ad}" (global (;0;) i64))
      #|  (import "" "" (global (;1;) (mut v128)))
      #|  (global (;2;) arrayref ref.null array)
      #|  (export "" (global 1))
      #|  (elem (;0;) declare externref)
      #|  (data (;0;) "/")
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0011" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x02\x0b\x02\x00\x00\x03\x6f\x01\x00\x00\x03\x7e\x01\x04\x0d\x01\x40\x00\x6a\x01\xdd\x01\xa1\xf5",
    b"\x02\xd0\x6a\x0b\x05\x0b\x01\x07\xd1\x2b\xb5\x9b\x89\xd1\x9c\xcd\x19\x06\x01\x00\x09\x13\x03\x05\x71\x00\x06\x00\x41\x00\x0b\x71",
    b"\x00\x06\x00\x41\xd4\x00\x0b\x6a\x00",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (import "" "" (global (;0;) (mut externref)))
      #|  (import "" "" (global (;1;) (mut i64)))
      #|  (table (;0;) 221 47777 arrayref ref.null array)
      #|  (memory (;0;) i64 5585 112604548844981 shared)
      #|  (elem (;0;) nullref)
      #|  (elem (;1;) (table 0) (i32.const 0) nullref)
      #|  (elem (;2;) (table 0) (i32.const 84) arrayref)
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0012" {
  let bytes : Bytes = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x02\x01\x00\x09\x0d\x01\x07\x6c\x03\xd0\x71\x0b\xd0\x6c\x0b\xd0\x6c\x0b"
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (elem (;0;) declare i31ref (ref.null none) (ref.null i31) (ref.null i31))
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0013" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x02\x19\x03\x00\x00\x03\x7e\x00\x01\x04\x00\x02\x05\x8a\x03\xad\xbe\xde\xcb\xcf\xdd\x38\x00\x00",
    b"\x03\x6d\x00\x06\x06\x01\x7e\x00\x23\x00\x0b\x0c\x01\x03\x0b\x14\x03\x01\x05\x21\x08\x57\xe4\xf3\x00\x23\x00\x0b\x02\x8a\x94\x00",
    b"\x42\x00\x0b\x00",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (import "" "" (global (;0;) i64))
      #|  (import "\u{4}" "" (memory (;0;) i64 394 249507425525549))
      #|  (import "" "" (global (;1;) eqref))
      #|  (global (;2;) i64 global.get 0)
      #|  (data (;0;) "!\08W\e4\f3")
      #|  (data (;1;) (global.get 0) "\8a\94")
      #|  (data (;2;) (i64.const 0) "")
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0014" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\xca\x01\x01\x4e\x1b\x50\x00\x5e\x7d\x01\x5e\x7d\x00\x50\x00\x5f\x06\x77\x01\x6b\x00\x78\x00",
    b"\x78\x00\x77\x00\x7c\x00\x50\x00\x60\x00\x01\x71\x5e\x78\x01\x50\x00\x5f\x12\x78\x00\x78\x00\x78\x01\x7d\x01\x7e\x01\x77\x00\x78",
    b"\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x78\x00\x50\x01\x00\x5e\x7d\x01\x50\x01\x00",
    b"\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d",
    b"\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50",
    b"\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00",
    b"\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01\x50\x01\x00\x5e\x7d\x01",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (rec
      #|    (type (;0;) (sub (array (mut f32))))
      #|    (type (;1;) (array f32))
      #|    (type (;2;) (sub (struct (field (mut i16)) (field structref) (field i8) (field i8) (field i16) (field f64))))
      #|    (type (;3;) (sub (func (result nullref))))
      #|    (type (;4;) (array (mut i8)))
      #|    (type (;5;) (sub (struct (field i8) (field i8) (field (mut i8)) (field (mut f32)) (field (mut i64)) (field i16) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8) (field i8))))
      #|    (type (;6;) (sub 0 (array (mut f32))))
      #|    (type (;7;) (sub 0 (array (mut f32))))
      #|    (type (;8;) (sub 0 (array (mut f32))))
      #|    (type (;9;) (sub 0 (array (mut f32))))
      #|    (type (;10;) (sub 0 (array (mut f32))))
      #|    (type (;11;) (sub 0 (array (mut f32))))
      #|    (type (;12;) (sub 0 (array (mut f32))))
      #|    (type (;13;) (sub 0 (array (mut f32))))
      #|    (type (;14;) (sub 0 (array (mut f32))))
      #|    (type (;15;) (sub 0 (array (mut f32))))
      #|    (type (;16;) (sub 0 (array (mut f32))))
      #|    (type (;17;) (sub 0 (array (mut f32))))
      #|    (type (;18;) (sub 0 (array (mut f32))))
      #|    (type (;19;) (sub 0 (array (mut f32))))
      #|    (type (;20;) (sub 0 (array (mut f32))))
      #|    (type (;21;) (sub 0 (array (mut f32))))
      #|    (type (;22;) (sub 0 (array (mut f32))))
      #|    (type (;23;) (sub 0 (array (mut f32))))
      #|    (type (;24;) (sub 0 (array (mut f32))))
      #|    (type (;25;) (sub 0 (array (mut f32))))
      #|    (type (;26;) (sub 0 (array (mut f32))))
      #|  )
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0015" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x01\x00\x02\x1e\x04\x00\x00\x02\x00\x12\x00\x00\x03\x7f\x00\x01\x4f\x00\x03\x7e\x00\x03\x32",
    b"\x57\x6c\x00\x01\x70\x05\xab\x01\x8c\xc8\x2b\x06\x01\x00\x07\x04\x01\x00\x02\x00\x0c\x01\x02\x0b\x0c\x02\x00\x23\x00\x0b\x01\x52",
    b"\x00\x41\x00\x0b\x00",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (import "" "" (memory (;0;) 18))
      #|  (import "" "" (global (;0;) i32))
      #|  (import "O" "" (global (;1;) i64))
      #|  (import "2Wl" "" (table (;0;) i64 171 713740 funcref))
      #|  (export "" (memory 0))
      #|  (data (;0;) (global.get 0) "R")
      #|  (data (;1;) (i32.const 0) "")
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0016" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\xcc\x07\x01\x4e\x1f\x50\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01",
    b"\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x5e\x78\x00\x50\x00\x60\x03\x7e\x7f\x7c\x02\x7c\x7b\x50\x01\x00\x5f\x0e",
    b"\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f",
    b"\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00",
    b"\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01",
    b"\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50",
    b"\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00",
    b"\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77",
    b"\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00",
    b"\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78",
    b"\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01",
    b"\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b",
    b"\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01",
    b"\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c",
    b"\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00",
    b"\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f",
    b"\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01",
    b"\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77",
    b"\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01",
    b"\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78",
    b"\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78\x01",
    b"\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01\x78",
    b"\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77\x01",
    b"\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00\x77",
    b"\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f\x00",
    b"\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01\x7f",
    b"\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c\x01",
    b"\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00\x6c",
    b"\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78\x00",
    b"\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00\x50\x01\x00\x5f\x0e\x7e\x01\x78\x00\x78",
    b"\x00\x6c\x01\x7f\x00\x77\x01\x78\x01\x78\x01\x77\x01\x6f\x00\x7c\x01\x7b\x01\x78\x00\x77\x00",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (rec
      #|    (type (;0;) (sub (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;1;) (array i8))
      #|    (type (;2;) (sub (func (param i64 i32 f64) (result f64 v128))))
      #|    (type (;3;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;4;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;5;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;6;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;7;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;8;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;9;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;10;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;11;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;12;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;13;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;14;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;15;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;16;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;17;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;18;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;19;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;20;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;21;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;22;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;23;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;24;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;25;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;26;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;27;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;28;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;29;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|    (type (;30;) (sub 0 (struct (field (mut i64)) (field i8) (field i8) (field (mut i31ref)) (field i32) (field (mut i16)) (field (mut i8)) (field (mut i8)) (field (mut i16)) (field externref) (field (mut f64)) (field (mut v128)) (field i8) (field i16))))
      #|  )
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0017" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\xc9\x06\x01\x4e\x5d\x60\x00\x01\x7b\x5f\x01\x7d\x00\x50\x00\x60\x02\x7b\x6d\x01\x7d\x50\x00",
    b"\x5f\x09\x7e\x01\x77\x01\x71\x01\x77\x01\x7c\x01\x7e\x01\x77\x00\x78\x01\x77\x00\x5f\x03\x7b\x00\x78\x00\x77\x00\x50\x01\x02\x60",
    b"\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d",
    b"\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02",
    b"\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50",
    b"\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b",
    b"\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01",
    b"\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d",
    b"\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02",
    b"\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01",
    b"\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60",
    b"\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d",
    b"\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02",
    b"\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50",
    b"\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b",
    b"\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01",
    b"\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d",
    b"\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02",
    b"\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01",
    b"\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60",
    b"\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d",
    b"\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02",
    b"\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50",
    b"\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b",
    b"\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01",
    b"\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d",
    b"\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d\x50\x01\x02\x60\x02\x7b\x6d\x01\x7d",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (rec
      #|    (type (;0;) (func (result v128)))
      #|    (type (;1;) (struct (field f32)))
      #|    (type (;2;) (sub (func (param v128 eqref) (result f32))))
      #|    (type (;3;) (sub (struct (field (mut i64)) (field (mut i16)) (field (mut nullref)) (field (mut i16)) (field (mut f64)) (field (mut i64)) (field i16) (field (mut i8)) (field i16))))
      #|    (type (;4;) (struct (field v128) (field i8) (field i16)))
      #|    (type (;5;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;6;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;7;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;8;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;9;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;10;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;11;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;12;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;13;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;14;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;15;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;16;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;17;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;18;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;19;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;20;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;21;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;22;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;23;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;24;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;25;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;26;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;27;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;28;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;29;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;30;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;31;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;32;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;33;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;34;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;35;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;36;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;37;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;38;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;39;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;40;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;41;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;42;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;43;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;44;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;45;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;46;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;47;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;48;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;49;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;50;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;51;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;52;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;53;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;54;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;55;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;56;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;57;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;58;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;59;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;60;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;61;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;62;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;63;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;64;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;65;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;66;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;67;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;68;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;69;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;70;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;71;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;72;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;73;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;74;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;75;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;76;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;77;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;78;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;79;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;80;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;81;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;82;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;83;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;84;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;85;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;86;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;87;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;88;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;89;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;90;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;91;) (sub 2 (func (param v128 eqref) (result f32))))
      #|    (type (;92;) (sub 2 (func (param v128 eqref) (result f32))))
      #|  )
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0018" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\xe7\x09\x01\x4e\x56\x5f\x01\x78\x00\x5e\x78\x00\x50\x00\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d",
    b"\x01\x77\x00\x5f\x0a\x78\x01\x78\x01\x7c\x01\x77\x00\x7d\x01\x7d\x01\x78\x01\x78\x00\x78\x00\x73\x00\x60\x01\x7d\x00\x50\x00\x5e",
    b"\x78\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00",
    b"\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01",
    b"\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f",
    b"\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78",
    b"\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77",
    b"\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c",
    b"\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d",
    b"\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77",
    b"\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50",
    b"\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02",
    b"\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05",
    b"\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01",
    b"\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00",
    b"\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00",
    b"\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01",
    b"\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00",
    b"\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01",
    b"\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f",
    b"\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78",
    b"\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77",
    b"\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c",
    b"\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d",
    b"\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77",
    b"\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50",
    b"\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02",
    b"\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05",
    b"\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01",
    b"\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00",
    b"\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00",
    b"\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01",
    b"\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00",
    b"\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01",
    b"\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f",
    b"\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78",
    b"\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77",
    b"\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c",
    b"\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d",
    b"\x01\x77\x00\x50\x01\x02\x5f\x05\x78\x01\x77\x00\x7c\x00\x7d\x01\x77\x00",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (rec
      #|    (type (;0;) (struct (field i8)))
      #|    (type (;1;) (array i8))
      #|    (type (;2;) (sub (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;3;) (struct (field (mut i8)) (field (mut i8)) (field (mut f64)) (field i16) (field (mut f32)) (field (mut f32)) (field (mut i8)) (field i8) (field i8) (field nullfuncref)))
      #|    (type (;4;) (func (param f32)))
      #|    (type (;5;) (sub (array i8)))
      #|    (type (;6;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;7;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;8;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;9;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;10;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;11;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;12;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;13;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;14;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;15;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;16;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;17;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;18;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;19;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;20;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;21;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;22;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;23;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;24;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;25;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;26;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;27;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;28;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;29;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;30;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;31;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;32;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;33;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;34;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;35;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;36;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;37;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;38;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;39;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;40;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;41;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;42;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;43;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;44;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;45;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;46;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;47;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;48;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;49;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;50;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;51;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;52;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;53;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;54;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;55;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;56;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;57;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;58;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;59;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;60;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;61;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;62;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;63;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;64;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;65;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;66;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;67;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;68;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;69;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;70;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;71;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;72;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;73;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;74;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;75;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;76;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;77;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;78;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;79;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;80;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;81;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;82;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;83;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;84;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|    (type (;85;) (sub 2 (struct (field (mut i8)) (field i16) (field f64) (field (mut f32)) (field i16))))
      #|  )
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}

///|
test "smith/valid/seed_0/case_0019" {
  let bytes : Bytes = bytes_concat([
    b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\xe2\x01\x01\x4e\x20\x50\x00\x60\x00\x00\x60\x00\x00\x60\x00\x00\x50\x00\x5f\x14\x77\x00\x78",
    b"\x01\x77\x00\x6b\x00\x77\x00\x78\x01\x7b\x00\x77\x00\x77\x01\x77\x00\x78\x00\x78\x01\x77\x01\x78\x01\x7b\x00\x77\x01\x77\x01\x77",
    b"\x00\x7e\x00\x78\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00",
    b"\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00",
    b"\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50",
    b"\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00",
    b"\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00",
    b"\x00\x50\x01\x00\x60\x00\x00\x50\x01\x00\x60\x00\x00",
  ])
  let m = @wasm.decode_module(bytes)
  inspect(
    m.print(),
    content=(
      #|(module
      #|  (rec
      #|    (type (;0;) (sub (func)))
      #|    (type (;1;) (func))
      #|    (type (;2;) (func))
      #|    (type (;3;) (sub (struct (field i16) (field (mut i8)) (field i16) (field structref) (field i16) (field (mut i8)) (field v128) (field i16) (field (mut i16)) (field i16) (field i8) (field (mut i8)) (field (mut i16)) (field (mut i8)) (field v128) (field (mut i16)) (field (mut i16)) (field i16) (field i64) (field i8))))
      #|    (type (;4;) (sub 0 (func)))
      #|    (type (;5;) (sub 0 (func)))
      #|    (type (;6;) (sub 0 (func)))
      #|    (type (;7;) (sub 0 (func)))
      #|    (type (;8;) (sub 0 (func)))
      #|    (type (;9;) (sub 0 (func)))
      #|    (type (;10;) (sub 0 (func)))
      #|    (type (;11;) (sub 0 (func)))
      #|    (type (;12;) (sub 0 (func)))
      #|    (type (;13;) (sub 0 (func)))
      #|    (type (;14;) (sub 0 (func)))
      #|    (type (;15;) (sub 0 (func)))
      #|    (type (;16;) (sub 0 (func)))
      #|    (type (;17;) (sub 0 (func)))
      #|    (type (;18;) (sub 0 (func)))
      #|    (type (;19;) (sub 0 (func)))
      #|    (type (;20;) (sub 0 (func)))
      #|    (type (;21;) (sub 0 (func)))
      #|    (type (;22;) (sub 0 (func)))
      #|    (type (;23;) (sub 0 (func)))
      #|    (type (;24;) (sub 0 (func)))
      #|    (type (;25;) (sub 0 (func)))
      #|    (type (;26;) (sub 0 (func)))
      #|    (type (;27;) (sub 0 (func)))
      #|    (type (;28;) (sub 0 (func)))
      #|    (type (;29;) (sub 0 (func)))
      #|    (type (;30;) (sub 0 (func)))
      #|    (type (;31;) (sub 0 (func)))
      #|  )
      #|)
      #|
    ),
  )
  @wasm.validate_module(m)
}
