///|
test "invalid/no-equals-sign" {
  let ini_text =
    #|keyvalue
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for missing equals sign, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/empty-key" {
  let ini_text =
    #|=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for empty key, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/section-after-content" {
  let ini_text =
    #|[section key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for content after section, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/unclosed-quote" {
  let ini_text =
    #|key="unclosed value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for unclosed quote, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/mismatched-quotes-01" {
  let ini_text =
    #|value="starts with double'
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for mismatched quotes, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/mismatched-quotes-02" {
  let ini_text =
    #|value='starts with single"
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for mismatched quotes, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/section-no-open-bracket" {
  let ini_text =
    #|section]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for missing open bracket, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/multiple-equals-without-quotes" {
  let ini_text =
    #|key=value=extra
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for multiple equals without quotes, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/nested-sections-brackets" {
  let ini_text =
    #|[[nested]]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for double brackets, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/quote-in-section-name" {
  let ini_text =
    #|[section"name]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for quote in section name, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/multiline-without-backslash" {
  let ini_text =
    #|key=value
    #|continued
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for multiline without backslash, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/control-characters-in-key" {
  let ini_text =
    #|key\nname=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for control chars in key, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/section-in-value" {
  let ini_text =
    #|key=value [section]
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for section in value, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/nested-brackets-in-section" {
  let ini_text =
    #|[[section]]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for nested brackets, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/angle-brackets-section" {
  let ini_text =
    #|<section>
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for angle brackets, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/key-only-spaces" {
  let ini_text =
    #|   =value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for key with only spaces, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/section-only-spaces" {
  let ini_text =
    #|[   ]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for section with only spaces, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/backslash-continuation-no-newline" {
  let ini_text =
    #|key=value\
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for backslash at EOF, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "valid/spaces-around-equals" {
  let ini_text =
    #|key = value
    #|key2  =  value2
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "key": "value", "key2": "value2" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/quoted-values" {
  let ini_text =
    #|name="John Doe"
    #|path='C:\Program Files'
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "name": "John Doe", "path": "C:\\Program Files" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/special-characters-in-value" {
  let ini_text =
    #|url=http://example.com:8080/path?query=value&foo=bar
    #|email=user@example.com
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "url": "http://example.com:8080/path?query=value&foo=bar",
          "email": "user@example.com",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/empty-section" {
  let ini_text =
    #|[empty]
    #|[nonempty]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "empty": Json::empty_object(),
        "nonempty": { "key": "value" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/section-with-spaces" {
  let ini_text =
    #|[section name]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "section name": { "key": "value" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/blank-lines" {
  let ini_text =
    #|key1=value1
    #|
    #|
    #|key2=value2
    #|
    #|[section]
    #|
    #|key3=value3
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "key1": "value1", "key2": "value2" },
        "section": { "key3": "value3" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/unicode-content" {
  let ini_text =
    #|[データベース]
    #|名前=テスト
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "データベース": { "名前": "テスト" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/colon-separator" {
  let ini_text =
    #|key:value
    #|key2 : value2
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "key": "value", "key2": "value2" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/empty-ini" {
  let ini_text = ""
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content=Json::empty_object())
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/only-comments" {
  let ini_text =
    #|; comment 1
    #|# comment 2
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content=Json::empty_object())
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/duplicate-keys-last-wins" {
  let ini_text =
    #|key=value1
    #|key=value2
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "key": "value2" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/multiline-value-with-backslash" {
  let ini_text =
    #|key=line1\
    #|line2\
    #|line3
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "key": "line1line2line3" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/leading-whitespace" {
  let ini_text =
    #|  key=value
    #|  [section]
    #|  key2=value2
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "key": "value" },
        "section": { "key2": "value2" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/trailing-whitespace" {
  let ini_text =
    #|key=value  
    #|[section]  
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "key": "value" },
        "section": Json::empty_object(),
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/value-with-equals" {
  let ini_text =
    #|url=http://example.com?a=b&c=d
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "url": "http://example.com?a=b&c=d" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/numeric-section-name" {
  let ini_text =
    #|[123]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "123": { "key": "value" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/special-chars-in-section" {
  let ini_text =
    #|[section-name_with.special]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "section-name_with.special": { "key": "value" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/case-sensitivity" {
  let ini_text =
    #|Key=value1
    #|key=value2
    #|KEY=value3
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "Key": "value1", "key": "value2", "KEY": "value3" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/crlf-line-endings" {
  let ini_text = "[section]\r\nkey=value\r\n"
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "section": { "key": "value" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/boolean-like-values" {
  let ini_text =
    #|bool1=true
    #|bool2=false
    #|bool3=yes
    #|bool4=no
    #|bool5=on
    #|bool6=off
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "bool1": "true",
          "bool2": "false",
          "bool3": "yes",
          "bool4": "no",
          "bool5": "on",
          "bool6": "off",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/nested-section-appearance" {
  let ini_text =
    #|[section.subsection]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "section.subsection": { "key": "value" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/complex-multiline" {
  let ini_text =
    #|description=This is a \
    #|very long \
    #|description
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "description": "This is a very long description" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/quoted-with-semicolon" {
  let ini_text =
    #|value="contains ; semicolon"
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "value": "contains ; semicolon" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/quoted-with-hash" {
  let ini_text =
    #|value="contains # hash"
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "value": "contains # hash" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/quoted-with-newline" {
  let ini_text =
    #|value="line1
    #|line2"
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "value": "line1\nline2" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/escaped-quotes-in-value" {
  let ini_text =
    #|value="She said \"Hello\""
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "value": "She said \"Hello\"" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/array-like-syntax" {
  let ini_text =
    #|colors=red,green,blue
    #|numbers=1,2,3,4,5
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "colors": "red,green,blue", "numbers": "1,2,3,4,5" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/section-overwrite" {
  let ini_text =
    #|[section]
    #|key1=value1
    #|
    #|[section]
    #|key2=value2
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "section": { "key1": "value1", "key2": "value2" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/numbers-as-values" {
  let ini_text =
    #|integer=42
    #|negative=-17
    #|float=3.14
    #|scientific=1.23e-4
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "integer": "42",
          "negative": "-17",
          "float": "3.14",
          "scientific": "1.23e-4",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/empty-lines-between-sections" {
  let ini_text =
    #|[section1]
    #|key1=value1
    #|
    #|
    #|
    #|[section2]
    #|key2=value2
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "section1": { "key1": "value1" },
        "section2": { "key2": "value2" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/comment-only-lines" {
  let ini_text =
    #|; Header comment
    #|# Another header comment
    #|
    #|[section]
    #|; Section comment
    #|key=value
    #|# Another section comment
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "section": { "key": "value" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/very-long-key" {
  let ini_text =
    #|this_is_a_very_long_key_name_that_should_still_be_valid=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "this_is_a_very_long_key_name_that_should_still_be_valid": "value",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/very-long-section-name" {
  let ini_text =
    #|[this.is.a.very.long.section.name.that.should.still.be.valid]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "this.is.a.very.long.section.name.that.should.still.be.valid": {
          "key": "value",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/windows-path-value" {
  let ini_text =
    #|path=C:\Users\John\Documents\file.txt
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "path": "C:\\Users\\John\\Documents\\file.txt" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/value-with-brackets" {
  let ini_text =
    #|value=[not a section]
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "value": "[not a section]" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/whitespace-only-value" {
  let ini_text =
    #|key=   
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "key": "" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/mixed-comment-styles" {
  let ini_text =
    #|; Semicolon comment
    #|key1=value1
    #|# Hash comment
    #|key2=value2 ; inline semicolon
    #|key3=value3 # inline hash
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "key1": "value1", "key2": "value2", "key3": "value3" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/tab-separated" {
  let ini_text =
    #|key	=	value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "key": "value" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/many-sections" {
  let ini_text =
    #|[section1]
    #|a=1
    #|
    #|[section2]
    #|b=2
    #|
    #|[section3]
    #|c=3
    #|
    #|[section4]
    #|d=4
    #|
    #|[section5]
    #|e=5
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "section1": { "a": "1" },
        "section2": { "b": "2" },
        "section3": { "c": "3" },
        "section4": { "d": "4" },
        "section5": { "e": "5" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/mixed-separators" {
  let ini_text =
    #|key1=value1
    #|key2:value2
    #|key3 = value3
    #|key4 : value4
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "key1": "value1",
          "key2": "value2",
          "key3": "value3",
          "key4": "value4",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/real-world-database-config" {
  // Keep credential-shaped fixture values explicitly synthetic so repository
  // scanners do not mistake this parser input for deployable credentials.
  let ini_text =
    #|; Database configuration
    #|
    #|[database]
    #|driver=postgresql
    #|host=localhost
    #|port=5432
    #|account_name=example_user
    #|authentication=fixture_value
    #|database=myapp
    #|
    #|[connection]
    #|max_connections=100
    #|timeout=30
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "database": {
          "driver": "postgresql",
          "host": "localhost",
          "port": "5432",
          "account_name": "example_user",
          "authentication": "fixture_value",
          "database": "myapp",
        },
        "connection": { "max_connections": "100", "timeout": "30" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/real-world-app-config" {
  let ini_text =
    #|app_name=MyApplication
    #|version=1.2.3
    #|
    #|[server]
    #|host=0.0.0.0
    #|port=8080
    #|ssl=true
    #|
    #|[logging]
    #|level=debug
    #|file=/var/log/app.log
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "app_name": "MyApplication", "version": "1.2.3" },
        "server": { "host": "0.0.0.0", "port": "8080", "ssl": "true" },
        "logging": { "level": "debug", "file": "/var/log/app.log" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/special-section-chars" {
  let ini_text =
    #|[section_name-123]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "section_name-123": { "key": "value" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/value-starts-with-quote" {
  let ini_text =
    #|quote="value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "quote": "\"value" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/value-ends-with-backslash" {
  let ini_text =
    #|path=C:\Windows\
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "path": "C:\\Windows\\" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/escape-sequences" {
  let ini_text =
    #|newline=line1\nline2
    #|tab=col1\tcol2
    #|backslash=path\\to\\file
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "newline": "line1\nline2",
          "tab": "col1\tcol2",
          "backslash": "path\\to\\file",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/complex-quoted-strings" {
  let ini_text =
    #|single='single quoted'
    #|double="double quoted"
    #|mixed1="contains 'single' quotes"
    #|mixed2='contains "double" quotes'
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "single": "single quoted",
          "double": "double quoted",
          "mixed1": "contains 'single' quotes",
          "mixed2": "contains \"double\" quotes",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/whitespace-preservation-in-quotes" {
  let ini_text =
    #|value="  leading and trailing  "
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "value": "  leading and trailing  " },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/unicode-special-chars" {
  let ini_text =
    #|emoji=🚀🌟💻
    #|chinese=你好世界
    #|arabic=مرحبا
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "emoji": "🚀🌟💻",
          "chinese": "你好世界",
          "arabic": "مرحبا",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/complex-real-world-config" {
  // This exercises quoted values without embedding a password-like sample.
  let ini_text =
    #|; Application Configuration File
    #|; Generated on 2024-01-01
    #|
    #|app_name=MyApp
    #|version=2.1.0
    #|environment=production
    #|
    #|[database]
    #|; Primary database connection
    #|driver=mysql
    #|host=db.example.com
    #|port=3306
    #|database=production_db
    #|account_name=example_user
    #|authentication="fixture-only"
    #|charset=utf8mb4
    #|
    #|[cache]
    #|enabled=true
    #|driver=redis
    #|host=cache.example.com
    #|port=6379
    #|prefix=myapp:
    #|
    #|[logging]
    #|level=info
    #|file=/var/log/myapp/app.log
    #|max_size=10M
    #|rotate=daily
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "app_name": "MyApp",
          "version": "2.1.0",
          "environment": "production",
        },
        "database": {
          "driver": "mysql",
          "host": "db.example.com",
          "port": "3306",
          "database": "production_db",
          "account_name": "example_user",
          "authentication": "fixture-only",
          "charset": "utf8mb4",
        },
        "cache": {
          "enabled": "true",
          "driver": "redis",
          "host": "cache.example.com",
          "port": "6379",
          "prefix": "myapp:",
        },
        "logging": {
          "level": "info",
          "file": "/var/log/myapp/app.log",
          "max_size": "10M",
          "rotate": "daily",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/php-ini-style" {
  let ini_text =
    #|[PHP]
    #|engine = On
    #|short_open_tag = Off
    #|precision = 14
    #|output_buffering = 4096
    #|implicit_flush = Off
    #|serialize_precision = -1
    #|
    #|[Date]
    #|date.timezone = UTC
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "PHP": {
          "engine": "On",
          "short_open_tag": "Off",
          "precision": "14",
          "output_buffering": "4096",
          "implicit_flush": "Off",
          "serialize_precision": "-1",
        },
        "Date": { "date.timezone": "UTC" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/git-config-style" {
  let ini_text =
    #|[core]
    #|repositoryformatversion = 0
    #|filemode = true
    #|bare = false
    #|logallrefupdates = true
    #|
    #|[remote "origin"]
    #|url = https://github.com/user/repo.git
    #|fetch = +refs/heads/*:refs/remotes/origin/*
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "core": {
          "repositoryformatversion": "0",
          "filemode": "true",
          "bare": "false",
          "logallrefupdates": "true",
        },
        "remote \"origin\"": {
          "url": "https://github.com/user/repo.git",
          "fetch": "+refs/heads/*:refs/remotes/origin/*",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/systemd-unit-style" {
  let ini_text =
    #|[Unit]
    #|Description=My Service
    #|After=network.target
    #|
    #|[Service]
    #|Type=simple
    #|ExecStart=/usr/bin/myapp
    #|Restart=always
    #|
    #|[Install]
    #|WantedBy=multi-user.target
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "Unit": { "Description": "My Service", "After": "network.target" },
        "Service": {
          "Type": "simple",
          "ExecStart": "/usr/bin/myapp",
          "Restart": "always",
        },
        "Install": { "WantedBy": "multi-user.target" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/key-with-dots" {
  let ini_text =
    #|key.with.dots=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "key.with.dots": "value" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/key-with-dashes" {
  let ini_text =
    #|key-with-dashes=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "": { "key-with-dashes": "value" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/numeric-keys" {
  let ini_text =
    #|123=numeric key
    #|456.789=dotted numeric
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "123": "numeric key", "456.789": "dotted numeric" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/url-as-value" {
  let ini_text =
    #|url=https://example.com:8080/path?param1=value1&param2=value2#fragment
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "url": "https://example.com:8080/path?param1=value1&param2=value2#fragment",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/json-like-value" {
  let ini_text =
    #|json={"key":"value","array":[1,2,3]}
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "json": "{\"key\":\"value\",\"array\":[1,2,3]}" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/base64-like-value" {
  let ini_text =
    #|token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/section-with-unicode" {
  let ini_text =
    #|[セクション]
    #|キー=値
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "セクション": { "キー": "値" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/section-with-emoji" {
  let ini_text =
    #|[🚀 rocket]
    #|speed=fast
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "🚀 rocket": { "speed": "fast" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/long-multiline-value" {
  let ini_text =
    #|long_text=This is a very long line that \
    #|continues on the next line and \
    #|then continues again and \
    #|finally ends here
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": {
          "long_text": "This is a very long line that continues on the next line and then continues again and finally ends here",
        },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/key-value-no-space" {
  let ini_text =
    #|key=value
    #|key2:value2
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "key": "value", "key2": "value2" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/quoted-section-name" {
  let ini_text =
    #|["quoted section"]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "quoted section": { "key": "value" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/single-quoted-section-name" {
  let ini_text =
    #|['quoted section']
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={ "quoted section": { "key": "value" } })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/backslash-at-eol-without-continuation" {
  let ini_text =
    #|path=C:\Program Files\
    #|nextkey=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "path": "C:\\Program Files\\", "nextkey": "value" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/all-empty-values" {
  let ini_text =
    #|key1=
    #|key2=
    #|key3=
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "key1": "", "key2": "", "key3": "" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/mixed-quote-types-in-value" {
  let ini_text =
    #|value=It's a "test" value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "value": "It's a \"test\" value" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/preserve-internal-whitespace" {
  let ini_text =
    #|text=hello    world    with    spaces
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "text": "hello    world    with    spaces" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "edge/comment-char-in-quoted-value" {
  let ini_text =
    #|comment="#not a comment"
    #|semicolon=";also not a comment"
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "comment": "#not a comment", "semicolon": ";also not a comment" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}
