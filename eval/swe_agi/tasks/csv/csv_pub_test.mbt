///|
test "edge/quotes/double-quote-escape" {
  let csv_text =
    #|"a""b",c
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a\"b", "c"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/quotes/multiple-escapes" {
  let csv_text =
    #|"a""b""c",d
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a\"b\"c", "d"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/quotes/only-quotes" {
  let csv_text =
    #|"""",a
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["\"", "a"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/quotes/quoted-comma" {
  let csv_text =
    #|"a,b",c
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a,b", "c"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/quotes/quoted-newline" {
  let csv_text =
    #|"a
    #|b",c
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a\nb", "c"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/quotes/quoted-crlf" {
  let csv_text = "\"a\r\nb\",c\r\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a\r\nb", "c"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/empty/all-empty-fields" {
  let csv_text =
    #|,,
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["", "", ""]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/empty/single-empty-field" {
  let csv_text = "\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [[""]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/empty/quoted-empty" {
  let csv_text =
    #|"","",""
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["", "", ""]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/line-endings/lf-only" {
  let csv_text = "a,b\nc,d\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "b"], ["c", "d"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}
