///|
test "invalid/array/double-comma-01" {
  let toml_text =
    #|double-comma-01 = [1,,2]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/double-comma-02" {
  let toml_text =
    #|double-comma-02 = [1,2,,]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/missing-separator-01" {
  let toml_text =
    #|arrr = [true false]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/missing-separator-02" {
  let toml_text =
    #|wrong = [ 1 2 3 ]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/no-close-01" {
  let toml_text =
    #|no-close-01 = [ 1, 2, 3
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/no-close-02" {
  let toml_text =
    #|no-close-02 = [1,
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/no-close-03" {
  let toml_text =
    #|no-close-03 = [42 #]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/no-close-04" {
  let toml_text =
    #|no-close-04 = [{ key = 42
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/no-close-05" {
  let toml_text =
    #|no-close-05 = [{ key = 42}
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/no-close-06" {
  let toml_text =
    #|no-close-06 = [{ key = 42 #}]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/no-close-07" {
  let toml_text =
    #|no-close-07 = [{ key = 42} #]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/no-close-08" {
  let toml_text =
    #|no-close-08 = [
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/no-comma-01" {
  let toml_text =
    #|no-comma-01 = [true false]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/no-comma-02" {
  let toml_text =
    #|no-comma-02 = [ 1 2 3 ]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/no-comma-03" {
  let toml_text =
    #|no-comma-03 = [ 1 #,]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/only-comma-01" {
  let toml_text =
    #|only-comma-01 = [,]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/array/only-comma-02" {
  let toml_text =
    #|only-comma-02 = [,,]
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/almost-false-with-extra" {
  let toml_text =
    #|almost-false-with-extra = falsify
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/almost-false" {
  let toml_text =
    #|almost-false            = fals
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/almost-true-with-extra" {
  let toml_text =
    #|almost-true-with-extra  = truthy
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/almost-true" {
  let toml_text =
    #|almost-true             = tru
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/capitalized-false" {
  let toml_text =
    #|capitalized-false        = False
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/capitalized-true" {
  let toml_text =
    #|capitalized-true         = True
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/just-f" {
  let toml_text =
    #|just-f                  = f
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/just-t" {
  let toml_text =
    #|just-t                  = t
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/mixed-case-false" {
  let toml_text =
    #|mixed-case-false        = falsE
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/mixed-case-true" {
  let toml_text =
    #|mixed-case-true         = trUe
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/mixed-case" {
  let toml_text =
    #|mixed-case              = valid   = False
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/starting-same-false" {
  let toml_text =
    #|starting-same-false     = falsey
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/starting-same-true" {
  let toml_text =
    #|starting-same-true      = truer
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/wrong-case-false" {
  let toml_text =
    #|wrong-case-false        = FALSE
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/bool/wrong-case-true" {
  let toml_text =
    #|wrong-case-true         = TRUE
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/bare-cr" {
  let toml_text = "# The following line contains a single carriage return control character\r\n\r"
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/bare-formfeed" {
  let toml_text =
    #|bare-formfeed     = 
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/bare-null" {
  let toml_text =
    #|bare-null         = "some value"  
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/bare-vertical-tab" {
  let toml_text =
    #|bare-vertical-tab = 
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/comment-cr" {
  let toml_text = "comment-cr   = \"Carriage return in comment\" # \ra=1\n"
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/comment-del" {
  let toml_text =
    #|comment-del  = "0x7f"   # 
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/comment-ff" {
  let toml_text =
    #|comment-ff   = "0x7f"   # 
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/comment-lf" {
  let toml_text =
    #|comment-lf   = "ctrl-P" # 
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/comment-null" {
  let toml_text =
    #|comment-null = "null"   #  
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/comment-us" {
  let toml_text =
    #|comment-us   = "ctrl-_" # 
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/only-ff" {
  let toml_text =
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/only-null" {
  let toml_text =
    #| 
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/only-vt" {
  let toml_text =
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/string-bs" {
  let toml_text =
    #|string-bs   = "backspace"
    #|
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control/string-cr" {
  let toml_text = "string-cr   = \"null\r\"\n"
  match @toml.parse(toml_text) {
    Ok(toml) => {
      let test_json = toml.to_test_json()
      fail(
        "Expected parsing to fail for invalid TOML, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "valid/array/bool" {
  let toml_text =
    #|a = [true, false]
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "a": [
      { "type": "bool", "value": "true" },
      { "type": "bool", "value": "false" },
    ],
  })
}

///|
test "valid/array/empty" {
  let toml_text =
    #|thevoid = [[[[[]]]]]
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={ "thevoid": [[[[[]]]]] })
}

///|
test "valid/array/nospaces" {
  let toml_text =
    #|ints = [1,2,3]
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "ints": [
      { "type": "integer", "value": "1" },
      { "type": "integer", "value": "2" },
      { "type": "integer", "value": "3" },
    ],
  })
}

///|
test "valid/array/string-quote-comma-01" {
  let toml_text =
    #|title = [
    #|"Client: \"XXXX\", Job: XXXX",
    #|"Code: XXXX"
    #|]
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "title": [
      { "type": "string", "value": "Client: \"XXXX\", Job: XXXX" },
      { "type": "string", "value": "Code: XXXX" },
    ],
  })
}

///|
test "valid/array/string-quote-comma-02" {
  let toml_text =
    #|title = [ " \", ",]
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "title": [{ "type": "string", "value": " \", " }],
  })
}

///|
test "valid/array/string-with-comma-01" {
  let toml_text =
    #|title = [
    #|"Client: XXXX, Job: XXXX",
    #|"Code: XXXX"
    #|]
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "title": [
      { "type": "string", "value": "Client: XXXX, Job: XXXX" },
      { "type": "string", "value": "Code: XXXX" },
    ],
  })
}

///|
test "valid/array/string-with-comma-02" {
  let toml_text =
    #|title = [
    #|"""Client: XXXX,
    #|Job: XXXX""",
    #|"Code: XXXX"
    #|]
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "title": [
      { "type": "string", "value": "Client: XXXX,\nJob: XXXX" },
      { "type": "string", "value": "Code: XXXX" },
    ],
  })
}

///|
test "valid/array/strings" {
  let toml_text =
    #|string_array = [ "all", 'strings', """are the same""", '''type''']
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "string_array": [
      { "type": "string", "value": "all" },
      { "type": "string", "value": "strings" },
      { "type": "string", "value": "are the same" },
      { "type": "string", "value": "type" },
    ],
  })
}

///|
test "valid/bool/bool" {
  let toml_text =
    #|t = true
    #|f = false
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "f": { "type": "bool", "value": "false" },
    "t": { "type": "bool", "value": "true" },
  })
}

///|
test "valid/comment/after-literal-no-ws" {
  let toml_text =
    #|inf=inf#infinity
    #|nan=nan#not a number
    #|true=true#true
    #|false=false#false
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "false": { "type": "bool", "value": "false" },
    "inf": { "type": "float", "value": "inf" },
    "nan": { "type": "float", "value": "nan" },
    "true": { "type": "bool", "value": "true" },
  })
}

///|
test "valid/comment/at-eof2" {
  let toml_text =
    #|# This is a full-line comment
    #|key = "value" # This is a comment at the end of a line
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "key": { "type": "string", "value": "value" },
  })
}

///|
test "valid/comment/at-eof" {
  let toml_text =
    #|# This is a full-line comment
    #|key = "value" # This is a comment at the end of a line
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "key": { "type": "string", "value": "value" },
  })
}

///|
test "valid/comment/everywhere" {
  let toml_text =
    #|# Top comment.
    #|  # Top comment.
    #|# Top comment.
    #|
    #|# [no-extraneous-groups-please]
    #|
    #|[group] # Comment
    #|answer = 42 # Comment
    #|# no-extraneous-keys-please = 999
    #|# Inbetween comment.
    #|more = [ # Comment
    #|  # What about multiple # comments?
    #|  # Can you handle it?
    #|  #
    #|          # Evil.
    #|# Evil.
    #|  42, 42, # Comments within arrays are fun.
    #|  # What about multiple # comments?
    #|  # Can you handle it?
    #|  #
    #|          # Evil.
    #|# Evil.
    #|# ] Did I fool you?
    #|] # Hopefully not.
    #|
    #|# Make sure the space between the datetime and "#" isn't lexed.
    #|dt = 1979-05-27T07:32:12-07:00  # c
    #|d = 1979-05-27 # Comment
    #|
    #|[[aot]] # Comment
    #|k = 98 # Comment
    #|[[aot]]# Comment
    #|k = 99# Comment
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "aot": [
      { "k": { "type": "integer", "value": "98" } },
      { "k": { "type": "integer", "value": "99" } },
    ],
    "group": {
      "answer": { "type": "integer", "value": "42" },
      "d": { "type": "date-local", "value": "1979-05-27" },
      "dt": { "type": "datetime", "value": "1979-05-27T07:32:12-07:00" },
      "more": [
        { "type": "integer", "value": "42" },
        { "type": "integer", "value": "42" },
      ],
    },
  })
}

///|
test "valid/comment/noeol" {
  let toml_text =
    #|# single comment without any eol characters
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={})
}

///|
test "valid/comment/nonascii" {
  let toml_text =
    #|# ~  ÿ ퟿  ￿ 𐀀 􏿿
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={})
}

///|
test "valid/comment/tricky" {
  let toml_text =
    #|[section]#attached comment
    #|#[notsection]
    #|one = "11"#cmt
    #|two = "22#"
    #|three = '#'
    #|
    #|four = """# no comment
    #|# nor this
    #|#also not comment"""#is_comment
    #|
    #|five = 5.5#66
    #|six = 6#7
    #|8 = "eight"
    #|#nine = 99
    #|ten = 10e2#1
    #|eleven = 1.11e1#23
    #|
    #|["hash#tag"]
    #|"#!" = "hash bang"
    #|arr3 = [ "#", '#', """###""" ]
    #|arr4 = [ 1,# 9, 9,
    #|2#,9
    #|,#9
    #|3#]
    #|,4]
    #|arr5 = [[[[#["#"],
    #|["#"]]]]#]
    #|]
    #|tbl1 = { "#" = '}#'}#}}
    #|
    #|
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "hash#tag": {
      "#!": { "type": "string", "value": "hash bang" },
      "arr3": [
        { "type": "string", "value": "#" },
        { "type": "string", "value": "#" },
        { "type": "string", "value": "###" },
      ],
      "arr4": [
        { "type": "integer", "value": "1" },
        { "type": "integer", "value": "2" },
        { "type": "integer", "value": "3" },
        { "type": "integer", "value": "4" },
      ],
      "arr5": [[[[[{ "type": "string", "value": "#" }]]]]],
      "tbl1": { "#": { "type": "string", "value": "}#" } },
    },
    "section": {
      "8": { "type": "string", "value": "eight" },
      "eleven": { "type": "float", "value": "11.1" },
      "five": { "type": "float", "value": "5.5" },
      "four": {
        "type": "string",
        "value": "# no comment\n# nor this\n#also not comment",
      },
      "one": { "type": "string", "value": "11" },
      "six": { "type": "integer", "value": "6" },
      "ten": { "type": "float", "value": "1000.0" },
      "three": { "type": "string", "value": "#" },
      "two": { "type": "string", "value": "22#" },
    },
  })
}

///|
test "valid/empty-crlf" {
  let toml_text = "\r\n"
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={})
}

///|
test "valid/empty-lf" {
  let toml_text =
    #|
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={})
}

///|
test "valid/empty-nothing" {
  let toml_text =
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={})
}

///|
test "valid/empty-space" {
  let toml_text =
    #| 
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={})
}

///|
test "valid/empty-tab" {
  let toml_text =
    #|	
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={})
}

///|
test "valid/example" {
  let toml_text =
    #|best-day-ever = 1987-07-05T17:45:00Z
    #|
    #|[numtheory]
    #|boring = false
    #|perfection = [6, 28, 496]
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "best-day-ever": { "type": "datetime", "value": "1987-07-05T17:45:00Z" },
    "numtheory": {
      "boring": { "type": "bool", "value": "false" },
      "perfection": [
        { "type": "integer", "value": "6" },
        { "type": "integer", "value": "28" },
        { "type": "integer", "value": "496" },
      ],
    },
  })
}

///|
test "valid/float/exponent" {
  let toml_text =
    #|lower = 3e2
    #|upper = 3E2
    #|neg = 3e-2
    #|pos = 3E+2
    #|zero = 3e0
    #|pointlower = 3.1e2
    #|pointupper = 3.1E2
    #|minustenth = -1E-1
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "lower": { "type": "float", "value": "300.0" },
    "minustenth": { "type": "float", "value": "-0.1" },
    "neg": { "type": "float", "value": "0.03" },
    "pointlower": { "type": "float", "value": "310.0" },
    "pointupper": { "type": "float", "value": "310.0" },
    "pos": { "type": "float", "value": "300.0" },
    "upper": { "type": "float", "value": "300.0" },
    "zero": { "type": "float", "value": "3.0" },
  })
}

///|
test "valid/float/float" {
  let toml_text =
    #|pi = 3.14
    #|pospi = +3.14
    #|negpi = -3.14
    #|zero-intpart = 0.123
    #|leading-zero-fractional = 0.0123
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "leading-zero-fractional": { "type": "float", "value": "0.0123" },
    "negpi": { "type": "float", "value": "-3.14" },
    "pi": { "type": "float", "value": "3.14" },
    "pospi": { "type": "float", "value": "3.14" },
    "zero-intpart": { "type": "float", "value": "0.123" },
  })
}

///|
test "valid/float/zero" {
  let toml_text =
    #|zero = 0.0
    #|signed-pos = +0.0
    #|signed-neg = -0.0
    #|exponent = 0e0
    #|exponent-two-0 = 0e00
    #|exponent-signed-pos = +0e0
    #|exponent-signed-neg = -0e0
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "exponent": { "type": "float", "value": "0" },
    "exponent-signed-neg": { "type": "float", "value": "-0" },
    "exponent-signed-pos": { "type": "float", "value": "0" },
    "exponent-two-0": { "type": "float", "value": "0" },
    "signed-neg": { "type": "float", "value": "-0" },
    "signed-pos": { "type": "float", "value": "0" },
    "zero": { "type": "float", "value": "0" },
  })
}

///|
test "valid/integer/float64-max" {
  let toml_text =
    #|# Maximum and minimum safe float64 natural numbers. Mainly here for
    #|# -int-as-float.
    #|max_int =  9_007_199_254_740_991
    #|min_int = -9_007_199_254_740_991
    #|
  let toml = match @toml.parse(toml_text) {
    Ok(toml) => toml
    Err(error) => fail("Failed to parse TOML" + error.to_string())
  }
  json_inspect(toml.to_test_json(), content={
    "max_int": { "type": "integer", "value": "9007199254740991" },
    "min_int": { "type": "integer", "value": "-9007199254740991" },
  })
}
