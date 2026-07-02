///|
test "edge/line-endings/crlf-only" {
  let csv_text = "a,b\r\nc,d\r\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "b"], ["c", "d"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/line-endings/no-trailing-newline" {
  let csv_text = "a,b\nc,d"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "b"], ["c", "d"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/line-endings/mixed-endings" {
  let csv_text = "a,b\nc,d\r\ne,f\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a", "b"], ["c", "d"], ["e", "f"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/unicode/chinese" {
  let csv_text =
    #|中文,测试
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["中文", "测试"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/unicode/japanese" {
  let csv_text =
    #|日本語,テスト
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["日本語", "テスト"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/unicode/emoji" {
  let csv_text =
    #|😀,🎉
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["😀", "🎉"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/unicode/mixed-scripts" {
  let csv_text =
    #|Hello 世界,АБВ
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["Hello 世界", "АБВ"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/special/tab-in-field" {
  let csv_text = "a\tb,c\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a\tb", "c"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/special/quoted-tab" {
  let csv_text = "\"a\tb\",c\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a\tb", "c"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/special/leading-space" {
  let csv_text =
    #| a,b
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [[" a", "b"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/special/trailing-space" {
  let csv_text =
    #|a ,b
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a ", "b"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/multirow/many-rows" {
  let csv_text =
    #|a,b
    #|c,d
    #|e,f
    #|g,h
    #|i,j
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a", "b"], ["c", "d"], ["e", "f"], ["g", "h"], ["i", "j"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/multirow/single-row" {
  let csv_text =
    #|a,b,c,d,e
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "b", "c", "d", "e"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/fields/single-column" {
  let csv_text =
    #|a
    #|b
    #|c
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a"], ["b"], ["c"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/fields/many-columns" {
  let csv_text =
    #|a,b,c,d,e,f,g,h,i,j
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/real-world/address-data" {
  let csv_text =
    #|name,address,city
    #|"John Doe","123 Main St, Apt 4",Springfield
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["name", "address", "city"],
          ["John Doe", "123 Main St, Apt 4", "Springfield"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/real-world/description-with-newlines" {
  let csv_text =
    #|id,description
    #|1,"Line 1
    #|Line 2
    #|Line 3"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["id", "description"], ["1", "Line 1\nLine 2\nLine 3"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/real-world/numeric-data" {
  let csv_text =
    #|id,price,quantity
    #|1,19.99,100
    #|2,0.50,1000
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["id", "price", "quantity"],
          ["1", "19.99", "100"],
          ["2", "0.50", "1000"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/real-world/quoted-numbers" {
  let csv_text =
    #|"1","2","3"
    #|"4","5","6"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["1", "2", "3"], ["4", "5", "6"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/boundary/long-field" {
  let long_value = "a".repeat(1000)
  let csv_text = long_value + ",b\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      // Just verify it parses and has correct structure
      match test_json {
        { "records": [Array(row)], .. } =>
          match row {
            [String(first), String(second)] => {
              assert_eq(first.length(), 1000)
              assert_eq(second, "b")
            }
            _ => fail("Unexpected row structure")
          }
        _ => fail("Unexpected JSON structure")
      }
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/boundary/long-quoted-field" {
  let long_value = "a".repeat(1000)
  let csv_text = "\"" + long_value + "\",b\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      match test_json {
        { "records": [Array(row)], .. } =>
          match row {
            [String(first), String(second)] => {
              assert_eq(first.length(), 1000)
              assert_eq(second, "b")
            }
            _ => fail("Unexpected row structure")
          }
        _ => fail("Unexpected JSON structure")
      }
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "invalid/unclosed-quote" {
  let csv_text =
    #|"unclosed
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for unclosed quote, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "valid/simple-single-row" {
  let csv_text =
    #|a,b,c
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "b", "c"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "valid/simple-multiple-rows" {
  let csv_text =
    #|name,age,city
    #|Alice,30,NYC
    #|Bob,25,LA
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["name", "age", "city"],
          ["Alice", "30", "NYC"],
          ["Bob", "25", "LA"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "valid/quoted-fields" {
  let csv_text =
    #|a,"b,c",d
    #|1,"2,3",4
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a", "b,c", "d"], ["1", "2,3", "4"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "valid/escaped-quotes" {
  let csv_text =
    #|"a""b","c""d""e"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a\"b", "c\"d\"e"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "invalid/quote-in-unquoted-field" {
  let csv_text =
    #|a,b"c,d
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for quote in unquoted field, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/text-after-quoted-field" {
  let csv_text =
    #|"quoted"text,b
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for text after quoted field, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/inconsistent-field-count" {
  let csv_text =
    #|a,b,c
    #|1,2
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for inconsistent field count, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/mid/unclosed-quote-multiline" {
  let csv_text =
    #|a,"b
    #|c
    #|d,e
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for unclosed quote in multiline, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/mid/quote-in-middle-of-unquoted" {
  let csv_text =
    #|a,b"c"d,e
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for quote in middle of unquoted field, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/mid/mismatched-field-counts-complex" {
  let csv_text =
    #|a,b,c,d,e
    #|1,2,3
    #|4,5,6,7,8
    #|9,10
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for mismatched field counts, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/mid/improper-quote-escape" {
  let csv_text =
    #|a,"b\"c",d
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for improper quote escape, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/hard/quote-after-data" {
  let csv_text =
    #|a,b,c
    #|1,2"3,4
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for quote after data, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/hard/unescaped-quote-in-quoted-field" {
  let csv_text =
    #|a,b,c
    #|1,"2"3",4
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for unescaped quote in quoted field, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/hard/unclosed-quote-eof" {
  let csv_text =
    #|a,b,c
    #|1,"2
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for unclosed quote at EOF, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/hard/text-between-quoted-fields" {
  let csv_text =
    #|"a"x"b","c"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for text between quoted fields, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/hard/odd-number-of-quotes-in-field" {
  let csv_text =
    #|a,b,c
    #|1,"""2,3
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for odd number of quotes, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/hard/multiline-unquoted-field" {
  let csv_text =
    #|a,b,c
    #|1,2
    #|3,4
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for inconsistent columns, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/quote/single-quote-start" {
  // Starting with a quote but not properly quoted field
  let csv_text =
    #|"a,b
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for unclosed quote, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/quote/space-before-quote" {
  // Space before opening quote in field that looks quoted
  // " "hello"  - this might be ambiguous but typically invalid
  let csv_text =
    #|a, "b",c
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for space before opening quote, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/structure/extra-fields-mid-file" {
  // First row has 3 fields, second row has 5 fields
  let csv_text =
    #|a,b,c
    #|1,2,3,4,5
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for extra fields, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/quote/lone-quote-field" {
  // A single quote character as a field
  let csv_text =
    #|a,",c
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for lone quote, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "invalid/quote/triple-quote-odd" {
  // Triple quote without proper escaping
  let csv_text =
    #|a,""",c
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for triple quote, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "valid/empty-fields" {
  let csv_text =
    #|a,,c
    #|,b,
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a", "", "c"], ["", "b", ""]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "valid/newline-in-quoted-field" {
  let csv_text =
    #|a,"b
    #|c",d
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "b\nc", "d"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "valid/crlf-line-endings" {
  let csv_text = "a,b,c\r\n1,2,3\r\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a", "b", "c"], ["1", "2", "3"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "valid/empty-csv" {
  let csv_text = ""
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "valid/single-field" {
  let csv_text =
    #|hello
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["hello"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/whitespace-preservation" {
  let csv_text =
    #| a , b , c 
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [[" a ", " b ", " c "]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/quoted-empty-field" {
  let csv_text =
    #|a,"",c
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "", "c"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/only-commas" {
  let csv_text =
    #|,,,
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["", "", "", ""]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/unicode-content" {
  let csv_text =
    #|名前,年齢
    #|太郎,30
    #|花子,25
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["名前", "年齢"], ["太郎", "30"], ["花子", "25"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "valid/cr-line-endings" {
  let csv_text = "a,b,c\r1,2,3\r"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a", "b", "c"], ["1", "2", "3"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "valid/quoted-eof-no-newline" {
  let csv_text = "\"a\",\"b\""
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "b"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "mid/multi-line-multiple-fields" {
  let csv_text =
    #|name,address,notes
    #|John,"123 Main St
    #|Apt 4B
    #|New York, NY","Important
    #|customer"
    #|Jane,"456 Oak Ave
    #|Boston, MA",Regular
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["name", "address", "notes"],
          ["John", "123 Main St\nApt 4B\nNew York, NY", "Important\ncustomer"],
          ["Jane", "456 Oak Ave\nBoston, MA", "Regular"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "mid/complex-quote-escaping" {
  let csv_text =
    #|field1,field2,field3
    #|"He said ""Hello""","She replied ""Hi there""","They said ""Goodbye"""
    #|"""quoted""","middle""quote""here","""start and end"""
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["field1", "field2", "field3"],
          [
            "He said \"Hello\"", "She replied \"Hi there\"", "They said \"Goodbye\"",
          ],
          ["\"quoted\"", "middle\"quote\"here", "\"start and end\""],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "mid/mixed-quoted-unquoted" {
  let csv_text =
    #|id,"name",age,"email",city
    #|1,"Alice",30,alice@example.com,"New York"
    #|2,Bob,"25","bob@example.com",Boston
    #|3,"Charlie","35","charlie@example.com","San Francisco"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["id", "name", "age", "email", "city"],
          ["1", "Alice", "30", "alice@example.com", "New York"],
          ["2", "Bob", "25", "bob@example.com", "Boston"],
          ["3", "Charlie", "35", "charlie@example.com", "San Francisco"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "mid/many-columns" {
  let csv_text =
    #|col1,col2,col3,col4,col5,col6,col7,col8,col9,col10
    #|a,b,c,d,e,f,g,h,i,j
    #|1,2,3,4,5,6,7,8,9,10
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          [
            "col1", "col2", "col3", "col4", "col5", "col6", "col7", "col8", "col9",
            "col10",
          ],
          ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"],
          ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "mid/special-characters" {
  let csv_text =
    #|symbols,math,currency
    #|"@#$%","<>=≠","$€¥£"
    #|"&*()","±∞÷","¢₹₽₩"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["symbols", "math", "currency"],
          ["@#$%", "<>=≠", "$€¥£"],
          ["&*()", "±∞÷", "¢₹₽₩"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "mid/tab-characters" {
  let csv_text = "a\tb\tc\n1\t2\t3\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a\tb\tc"], ["1\t2\t3"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "mid/quoted-newlines-only" {
  let csv_text =
    #|a,"b
    #|
    #|c",d
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "b\n\nc", "d"]] })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "invalid/mid/empty-lines-between-records" {
  let csv_text =
    #|a,b,c
    #|1,2,3
    #|
    #|4,5,6
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for blank middle line with inconsistent field count, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "mid/trailing-comma" {
  let csv_text =
    #|a,b,c,
    #|1,2,3,
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a", "b", "c", ""], ["1", "2", "3", ""]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "invalid/mid/blank-line-first" {
  let csv_text = "\na,b,c\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      fail(
        "Expected parsing to fail for blank first line with inconsistent field count, got \{test_json.stringify(indent=2)}",
      )
    }
    Err(_) => ()
  }
}

///|
test "mid/semicolon-separator" {
  let csv_text = "a;b;c\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      // Semicolons should be part of the field since comma is the separator
      json_inspect(test_json, content={ "records": [["a;b;c"]] })
    }
    Err(e) =>
      fail("Expected valid CSV for semicolon, got error: " + e.to_string())
  }
}

///|
test "hard/deeply-nested-quotes" {
  let csv_text =
    #|field1,field2
    #|"He said ""She said """"Hello"""" to me""","A ""B ""C"" D"" E"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["field1", "field2"],
          ["He said \"She said \"\"Hello\"\" to me\"", "A \"B \"C\" D\" E"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "hard/many-empty-fields" {
  let csv_text =
    #|,,,,,,,,,
    #|,,,,,,,,,
    #|,,,,,,,,,
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["", "", "", "", "", "", "", "", "", ""],
          ["", "", "", "", "", "", "", "", "", ""],
          ["", "", "", "", "", "", "", "", "", ""],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "hard/alternating-quoted-unquoted" {
  let csv_text =
    #|"a",b,"c",d,"e",f,"g",h,"i",j
    #|1,"2",3,"4",5,"6",7,"8",9,"10"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"],
          ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "hard/complex-multiline-records" {
  let csv_text =
    #|id,description,metadata
    #|1,"Line 1
    #|Line 2
    #|Line 3","Meta 1
    #|Meta 2"
    #|2,"Single line","Multi
    #|line
    #|meta"
    #|3,"A ""quoted"" word
    #|on multiple
    #|lines","Simple"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["id", "description", "metadata"],
          ["1", "Line 1\nLine 2\nLine 3", "Meta 1\nMeta 2"],
          ["2", "Single line", "Multi\nline\nmeta"],
          ["3", "A \"quoted\" word\non multiple\nlines", "Simple"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "hard/consecutive-quotes-pattern" {
  let csv_text =
    #|a,b,c
    #|"""",""""""," """""
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a", "b", "c"], ["\"", "\"\"", " \"\""]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "hard/mixed-line-endings" {
  let csv_text = "a,b,c\r\n1,2,3\n4,5,6\r\n7,8,9\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["a", "b", "c"],
          ["1", "2", "3"],
          ["4", "5", "6"],
          ["7", "8", "9"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "hard/quoted-field-with-all-special-chars" {
  let csv_text =
    #|field
    #|"comma,quote""newline
    #|tab	space end"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["field"], ["comma,quote\"newline\ntab\tspace end"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "hard/rfc4180-example" {
  let csv_text =
    #|Year,Make,Model,Description,Price
    #|1997,Ford,E350,"ac, abs, moon",3000.00
    #|1999,Chevy,"Venture ""Extended Edition""","",4900.00
    #|1999,Chevy,"Venture ""Extended Edition, Very Large""",,5000.00
    #|1996,Jeep,Grand Cherokee,"MUST SELL!
    #|air, moon roof, loaded",4799.00
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["Year", "Make", "Model", "Description", "Price"],
          ["1997", "Ford", "E350", "ac, abs, moon", "3000.00"],
          ["1999", "Chevy", "Venture \"Extended Edition\"", "", "4900.00"],
          [
            "1999", "Chevy", "Venture \"Extended Edition, Very Large\"", "", "5000.00",
          ],
          [
            "1996", "Jeep", "Grand Cherokee", "MUST SELL!\nair, moon roof, loaded",
            "4799.00",
          ],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "hard/only-newlines-in-quoted-field" {
  let csv_text =
    #|a,b,c
    #|1,"
    #|
    #|
    #|",3
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a", "b", "c"], ["1", "\n\n\n", "3"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "hard/unicode-emoji-and-symbols" {
  let csv_text =
    #|emoji,symbols,text
    #|"😀😃😄","→←↑↓","Hello 世界"
    #|"🎉🎊🎈","★☆✓✗","Привет мир"
    #|"❤️💙💚","♠♣♥♦","مرحبا العالم"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["emoji", "symbols", "text"],
          ["😀😃😄", "→←↑↓", "Hello 世界"],
          ["🎉🎊🎈", "★☆✓✗", "Привет мир"],
          ["❤️💙💚", "♠♣♥♦", "مرحبا العالم"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "hard/single-column-many-rows" {
  let csv_text =
    #|value
    #|1
    #|2
    #|3
    #|4
    #|5
    #|6
    #|7
    #|8
    #|9
    #|10
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["value"],
          ["1"],
          ["2"],
          ["3"],
          ["4"],
          ["5"],
          ["6"],
          ["7"],
          ["8"],
          ["9"],
          ["10"],
        ],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "hard/quoted-commas-everywhere" {
  let csv_text =
    #|"a,b","c,d,e","f,g,h,i"
    #|"1,2","3,4,5","6,7,8,9"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a,b", "c,d,e", "f,g,h,i"], ["1,2", "3,4,5", "6,7,8,9"]],
      })
    }
    Err(e) => fail("Expected valid CSV, got error: " + e.to_string())
  }
}

///|
test "edge/implicit-close-quote" {
  let csv_text = "a,b,\"c\"\"\""
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "b", "c\""]] })
    }
    Err(e) =>
      fail("Expected valid CSV for implicit close, got error: " + e.to_string())
  }
}

///|
test "valid/unicode/rtl-text" {
  // Right-to-left text (Arabic, Hebrew)
  let csv_text =
    #|language,greeting,direction
    #|Arabic,"مرحبا بالعالم",RTL
    #|Hebrew,"שלום עולם",RTL
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["language", "greeting", "direction"],
          ["Arabic", "مرحبا بالعالم", "RTL"],
          ["Hebrew", "שלום עולם", "RTL"],
        ],
      })
    }
    Err(e) =>
      fail("Expected valid CSV for RTL text, got error: " + e.to_string())
  }
}

///|
test "valid/unicode/zero-width-characters" {
  // Zero-width characters (ZWJ, ZWNJ)
  let csv_text = "a,b\u200Bc,d\n" // Zero-width space
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "b\u200Bc", "d"]] })
    }
    Err(e) =>
      fail(
        "Expected valid CSV for zero-width chars, got error: " + e.to_string(),
      )
  }
}

///|
test "valid/unicode/combining-characters" {
  // Combining diacritical marks
  let csv_text =
    #|name,normalized
    #|"café","café"
    #|"naïve","naïve"
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["name", "normalized"],
          ["café", "cafe\u0301"],
          ["naïve", "nai\u0308ve"],
        ],
      })
    }
    Err(e) =>
      fail(
        "Expected valid CSV for combining chars, got error: " + e.to_string(),
      )
  }
}

///|
test "valid/edge/bom-at-start" {
  // UTF-8 BOM at the start of file
  let csv_text = "\u{FEFF}a,b,c\n1,2,3\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      // BOM may be included in first field or stripped
      // depending on implementation
      let records = test_json.stringify()
      // Just verify it parses successfully
      assert_true(records.length() > 0)
    }
    Err(e) => fail("Expected valid CSV with BOM, got error: " + e.to_string())
  }
}

///|
test "valid/edge/very-long-field" {
  // Field with many characters
  let long_value = "x".repeat(1000)
  let csv_text = "short,\"\{long_value}\",short\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      let json_str = test_json.stringify()
      assert_true(json_str.contains(long_value))
    }
    Err(e) =>
      fail("Expected valid CSV for long field, got error: " + e.to_string())
  }
}

///|
test "valid/edge/many-columns" {
  // Record with many columns
  let csv_text = "c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15,c16,c17,c18,c19,c20\nv1,v2,v3,v4,v5,v6,v7,v8,v9,v10,v11,v12,v13,v14,v15,v16,v17,v18,v19,v20\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          [
            "c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8", "c9", "c10", "c11", "c12",
            "c13", "c14", "c15", "c16", "c17", "c18", "c19", "c20",
          ],
          [
            "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12",
            "v13", "v14", "v15", "v16", "v17", "v18", "v19", "v20",
          ],
        ],
      })
    }
    Err(e) =>
      fail("Expected valid CSV for many columns, got error: " + e.to_string())
  }
}

///|
test "valid/edge/crlf-in-quoted-field" {
  // CRLF inside quoted field
  let csv_text = "a,\"b\r\nc\",d\n"
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={ "records": [["a", "b\r\nc", "d"]] })
    }
    Err(e) =>
      fail("Expected valid CSV for CRLF in field, got error: " + e.to_string())
  }
}

///|
test "valid/edge/tabs-in-field" {
  // Tab characters in fields (tabs are not delimiters in CSV)
  let csv_text =
    #|a,b	with	tabs,c
    #|1,2	also	tabs,3
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [["a", "b\twith\ttabs", "c"], ["1", "2\talso\ttabs", "3"]],
      })
    }
    Err(e) =>
      fail("Expected valid CSV for tabs in field, got error: " + e.to_string())
  }
}

///|
test "valid/edge/numeric-data" {
  // Various numeric formats (all treated as strings in CSV)
  let csv_text =
    #|int,float,scientific,negative
    #|123,3.14,1.23e10,-456
    #|0,0.0,1e-5,-0.001
    #|
  match @csv.parse(csv_text) {
    Ok(csv) => {
      let test_json = csv.to_test_json()
      json_inspect(test_json, content={
        "records": [
          ["int", "float", "scientific", "negative"],
          ["123", "3.14", "1.23e10", "-456"],
          ["0", "0.0", "1e-5", "-0.001"],
        ],
      })
    }
    Err(e) =>
      fail("Expected valid CSV for numeric data, got error: " + e.to_string())
  }
}
