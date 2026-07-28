///|
test "invalid/unclosed-section" {
  let ini_text =
    #|[section
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for unclosed section, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/empty-section-name" {
  let ini_text =
    #|[]
    #|key=value
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      fail(
        "Expected parsing to fail for empty section name, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "valid/simple-key-value" {
  let ini_text =
    #|key=value
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
test "valid/multiple-keys" {
  let ini_text =
    #|name=John
    #|age=30
    #|city=NYC
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "name": "John", "age": "30", "city": "NYC" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/simple-section" {
  let ini_text =
    #|[database]
    #|host=localhost
    #|port=5432
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "database": { "host": "localhost", "port": "5432" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/multiple-sections" {
  let ini_text =
    #|[database]
    #|host=localhost
    #|port=5432
    #|
    #|[server]
    #|port=8080
    #|debug=true
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "database": { "host": "localhost", "port": "5432" },
        "server": { "port": "8080", "debug": "true" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/global-and-sections" {
  let ini_text =
    #|global_key=global_value
    #|
    #|[section1]
    #|key1=value1
    #|
    #|[section2]
    #|key2=value2
    #|
  match @ini.parse(ini_text) {
    Ok(ini) => {
      let test_json = ini.to_test_json()
      json_inspect(test_json, content={
        "": { "global_key": "global_value" },
        "section1": { "key1": "value1" },
        "section2": { "key2": "value2" },
      })
    }
    Err(e) => fail("Expected valid INI, got error: " + e.to_string())
  }
}

///|
test "valid/comments-semicolon" {
  let ini_text =
    #|; This is a comment
    #|key=value ; inline comment
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
test "valid/comments-hash" {
  let ini_text =
    #|# This is a comment
    #|key=value # inline comment
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
test "valid/empty-value" {
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
