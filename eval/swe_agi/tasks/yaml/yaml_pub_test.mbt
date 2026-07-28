///|
test "229Q" {
  let in_yaml =
    #|-
    #|  name: Mark McGwire
    #|  hr:   65
    #|  avg:  0.278
    #|-
    #|  name: Sammy Sosa
    #|  hr:   63
    #|  avg:  0.288
    #|
  let in_json : Json = [
    { "name": "Mark McGwire", "hr": 65, "avg": 0.278 },
    { "name": "Sammy Sosa", "hr": 63, "avg": 0.288 },
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "236B" {
  let in_yaml =
    #|foo:
    #|  bar
    #|invalid
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "26DV" {
  let in_yaml =
    #|"top1" : 
    #|  "key1" : &alias1 scalar1
    #|'top2' : 
    #|  'key2' : &alias2 scalar2
    #|top3: &node3 
    #|  *alias1 : scalar3
    #|top4: 
    #|  *alias2 : scalar4
    #|top5   :    
    #|  scalar5
    #|top6: 
    #|  &anchor6 'key6' : scalar6
    #|
  let in_json : Json = {
    "top1": { "key1": "scalar1" },
    "top2": { "key2": "scalar2" },
    "top3": { "scalar1": "scalar3" },
    "top4": { "scalar2": "scalar4" },
    "top5": "scalar5",
    "top6": { "key6": "scalar6" },
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "27NA" {
  let in_yaml =
    #|%YAML 1.2
    #|--- text
    #|
  let in_json : Json = "text"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "2AUY" {
  let in_yaml =
    #| - !!str a
    #| - b
    #| - !!int 42
    #| - d
    #|
  let in_json : Json = ["a", "b", 42, "d"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "2CMS" {
  let in_yaml =
    #|this
    #| is
    #|  invalid: x
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "2EBW" {
  let in_yaml =
    #|a!"#$%&'()*+,-./09:;<=>?@AZ[\]^_`az{|}~: safe
    #|?foo: safe question mark
    #|:foo: safe colon
    #|-foo: safe dash
    #|this is#not: a comment
    #|
  let in_json : Json = {
    "a!\"#$%&'()*+,-./09:;<=>?@AZ[\\]^_`az{|}~": "safe",
    "?foo": "safe question mark",
    ":foo": "safe colon",
    "-foo": "safe dash",
    "this is#not": "a comment",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "2LFX" {
  let in_yaml =
    #|%FOO  bar baz # Should be ignored
    #|              # with a warning.
    #|---
    #|"foo"
    #|
  let in_json : Json = "foo"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "2SXE" {
  let in_yaml =
    #|&a: key: &a value
    #|foo:
    #|  *a:
    #|
  let in_json : Json = { "key": "value", "foo": "key" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "2XXW" {
  let in_yaml =
    #|# Sets are represented as a
    #|# Mapping where each key is
    #|# associated with a null value
    #|--- !!set
    #|? Mark McGwire
    #|? Sammy Sosa
    #|? Ken Griff
    #|
  let in_json : Json = {
    "Mark McGwire": null,
    "Sammy Sosa": null,
    "Ken Griff": null,
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "33X3" {
  let in_yaml =
    #|---
    #|- !!int 1
    #|- !!int -2
    #|- !!int 33
    #|
  let in_json : Json = [1, -2, 33]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "35KP" {
  let in_yaml =
    #|--- !!map
    #|? a
    #|: b
    #|--- !!seq
    #|- !!str c
    #|--- !!str
    #|d
    #|e
    #|
  let in_json : Json = { "a": "b" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "36F6" {
  let in_yaml =
    #|---
    #|plain: a
    #| b
    #|
    #| c
    #|
  let in_json : Json = { "plain": "a b\nc" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "3ALJ" {
  let in_yaml =
    #|- - s1_i1
    #|  - s1_i2
    #|- s2
    #|
  let in_json : Json = [["s1_i1", "s1_i2"], "s2"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "3GZX" {
  let in_yaml =
    #|First occurrence: &anchor Foo
    #|Second occurrence: *anchor
    #|Override anchor: &anchor Bar
    #|Reuse anchor: *anchor
    #|
  let in_json : Json = {
    "First occurrence": "Foo",
    "Second occurrence": "Foo",
    "Override anchor": "Bar",
    "Reuse anchor": "Bar",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "3HFZ" {
  let in_yaml =
    #|---
    #|key: value
    #|... invalid
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "3MYT" {
  let in_yaml =
    #|---
    #|k:#foo
    #| &a !t s
    #|
  let in_json : Json = "k:#foo &a !t s"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "3R3P" {
  let in_yaml =
    #|&sequence
    #|- a
    #|
  let in_json : Json = ["a"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "3UYS" {
  let in_yaml =
    #|escaped slash: "a\/b"
    #|
  let in_json : Json = { "escaped slash": "a/b" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "4CQQ" {
  let in_yaml =
    #|plain:
    #|  This unquoted scalar
    #|  spans many lines.
    #|
    #|quoted: "So does this
    #|  quoted scalar.\n"
    #|
  let in_json : Json = {
    "plain": "This unquoted scalar spans many lines.",
    "quoted": "So does this quoted scalar.\n",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "4EJS" {
  let in_yaml =
    #|---
    #|a:
    #|	b:
    #|		c: value
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "4GC6" {
  let in_yaml =
    #|'here''s to "quotes"'
    #|
  let in_json : Json = "here's to \"quotes\""
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "4H7K" {
  let in_yaml =
    #|---
    #|[ a, b, c ] ]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "4HVU" {
  let in_yaml =
    #|key:
    #|   - ok
    #|   - also ok
    #|  - wrong
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "4JVG" {
  let in_yaml =
    #|top1: &node1
    #|  &k1 key1: val1
    #|top2: &node2
    #|  &v2 val2
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "4Q9F" {
  let in_yaml =
    #|--- >
    #| ab
    #| cd
    #| 
    #| ef
    #|
    #|
    #| gh
    #|
  let in_json : Json = "ab cd\nef\n\ngh\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "4QFQ" {
  let in_yaml =
    #|- |
    #| detected
    #|- >
    #| 
    #|  
    #|  # detected
    #|- |1
    #|  explicit
    #|- >
    #| detected
    #|
  let in_json : Json = [
    "detected\n", "\n\n# detected\n", " explicit\n", "detected\n",
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "4RWC" {
  let in_yaml =
    #|  [1, 2, 3]  
    #|  
    #|
  let in_json : Json = [1, 2, 3]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "4UYU" {
  let in_yaml =
    #|"foo: bar\": baz"
    #|
  let in_json : Json = "foo: bar\": baz"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "4V8U" {
  let in_yaml =
    #|---
    #|plain\value\with\backslashes
    #|
  let in_json : Json = "plain\\value\\with\\backslashes"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "invalid yaml returns error" {
  let in_yaml =
    #|a: [1, 2
    #|
  match @yaml.parse(in_yaml) {
    Ok(yaml) =>
      fail("Expected parse error, got: " + yaml.to_json().stringify(indent=2))
    Err(error) =>
      if error.to_string() == "" {
        fail("Expected non-empty error message")
      }
  }
}

///|
test "invalid flow map trailing tokens" {
  let in_yaml =
    #|---
    #|x: { y: z }in: valid
    #|
  match @yaml.parse(in_yaml) {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "impl01 mapping duplicates should error" {
  let in_yaml =
    #|a: foo
    #|a: bar
    #|
  match @yaml.parse(in_yaml) {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "impl01 invalid trailing content after double quoted string" {
  let in_yaml =
    #|"foo" l"
    #|
  match @yaml.parse(in_yaml) {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "detect invalid indentation" {
  let in_yaml =
    #|a:
    #|  b: 1
    #| c: 2
    #|
  match @yaml.parse(in_yaml) {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "parse scalar" {
  let in_yaml =
    #|hello
    #|
  let in_json : Json = "hello"
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "parse mapping" {
  let in_yaml =
    #|a: 1
    #|b: two
    #|
  let in_json : Json = { "a": 1, "b": "two" }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "parse ignores comments" {
  let in_yaml =
    #|a: 1 # comment
    #|b: two
    #|
  let in_json : Json = { "a": 1, "b": "two" }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "parse null scalar" {
  let in_yaml =
    #|~
    #|
  let in_json : Json = null
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}
