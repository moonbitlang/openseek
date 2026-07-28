///|
test "4WA9" {
  let in_yaml =
    #|- aaa: |2
    #|    xxx
    #|  bbb: |
    #|    xxx
    #|
  let in_json : Json = [{ "aaa": "xxx\n", "bbb": "xxx\n" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "4ZYM" {
  let in_yaml =
    #|plain: text
    #|  lines
    #|quoted: "text
    #|  	lines"
    #|block: |
    #|  text
    #|   	lines
    #|
  let in_json : Json = {
    "plain": "text lines",
    "quoted": "text lines",
    "block": "text\n \tlines\n",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "52DL" {
  let in_yaml =
    #|---
    #|! a
    #|
  let in_json : Json = "a"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "54T7" {
  let in_yaml =
    #|{foo: you, bar: far}
    #|
  let in_json : Json = { "foo": "you", "bar": "far" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "55WF" {
  let in_yaml =
    #|---
    #|"\."
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "565N" {
  let in_yaml =
    #|canonical: !!binary "\
    #| R0lGODlhDAAMAIQAAP//9/X17unp5WZmZgAAAOfn515eXvPz7Y6OjuDg4J+fn5\
    #| OTk6enp56enmlpaWNjY6Ojo4SEhP/++f/++f/++f/++f/++f/++f/++f/++f/+\
    #| +f/++f/++f/++f/++f/++SH+Dk1hZGUgd2l0aCBHSU1QACwAAAAADAAMAAAFLC\
    #| AgjoEwnuNAFOhpEMTRiggcz4BNJHrv/zCFcLiwMWYNG84BwwEeECcgggoBADs="
    #|generic: !!binary |
    #| R0lGODlhDAAMAIQAAP//9/X17unp5WZmZgAAAOfn515eXvPz7Y6OjuDg4J+fn5
    #| OTk6enp56enmlpaWNjY6Ojo4SEhP/++f/++f/++f/++f/++f/++f/++f/++f/+
    #| +f/++f/++f/++f/++f/++SH+Dk1hZGUgd2l0aCBHSU1QACwAAAAADAAMAAAFLC
    #| AgjoEwnuNAFOhpEMTRiggcz4BNJHrv/zCFcLiwMWYNG84BwwEeECcgggoBADs=
    #|description:
    #| The binary value above is a tiny arrow encoded as a gif image.
    #|
  let in_json : Json = {
    "canonical": "R0lGODlhDAAMAIQAAP//9/X17unp5WZmZgAAAOfn515eXvPz7Y6OjuDg4J+fn5OTk6enp56enmlpaWNjY6Ojo4SEhP/++f/++f/++f/++f/++f/++f/++f/++f/++f/++f/++f/++f/++f/++SH+Dk1hZGUgd2l0aCBHSU1QACwAAAAADAAMAAAFLCAgjoEwnuNAFOhpEMTRiggcz4BNJHrv/zCFcLiwMWYNG84BwwEeECcgggoBADs=",
    "generic": "R0lGODlhDAAMAIQAAP//9/X17unp5WZmZgAAAOfn515eXvPz7Y6OjuDg4J+fn5\nOTk6enp56enmlpaWNjY6Ojo4SEhP/++f/++f/++f/++f/++f/++f/++f/++f/+\n+f/++f/++f/++f/++f/++SH+Dk1hZGUgd2l0aCBHSU1QACwAAAAADAAMAAAFLC\nAgjoEwnuNAFOhpEMTRiggcz4BNJHrv/zCFcLiwMWYNG84BwwEeECcgggoBADs=\n",
    "description": "The binary value above is a tiny arrow encoded as a gif image.",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "57H4" {
  let in_yaml =
    #|sequence: !!seq
    #|- entry
    #|- !!seq
    #| - nested
    #|mapping: !!map
    #| foo: bar
    #|
  let in_json : Json = {
    "sequence": ["entry", ["nested"]],
    "mapping": { "foo": "bar" },
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "58MP" {
  let in_yaml =
    #|{x: :x}
    #|
  let in_json : Json = { "x": ":x" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "5BVJ" {
  let in_yaml =
    #|literal: |
    #|  some
    #|  text
    #|folded: >
    #|  some
    #|  text
    #|
  let in_json : Json = { "literal": "some\ntext\n", "folded": "some text\n" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "5C5M" {
  let in_yaml =
    #|- { one : two , three: four , }
    #|- {five: six,seven : eight}
    #|
  let in_json : Json = [
    { "one": "two", "three": "four" },
    { "five": "six", "seven": "eight" },
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "5GBF" {
  let in_yaml =
    #|Folding:
    #|  "Empty line
    #|   	
    #|  as a line feed"
    #|Chomping: |
    #|  Clipped empty lines
    #| 
    #|
    #|
  let in_json : Json = {
    "Folding": "Empty line\nas a line feed",
    "Chomping": "Clipped empty lines\n",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "5KJE" {
  let in_yaml =
    #|- [ one, two, ]
    #|- [three ,four]
    #|
  let in_json : Json = [["one", "two"], ["three", "four"]]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "5LLU" {
  let in_yaml =
    #|block scalar: >
    #| 
    #|  
    #|   
    #| invalid
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "5MUD" {
  let in_yaml =
    #|---
    #|{ "foo"
    #|  :bar }
    #|
  let in_json : Json = { "foo": "bar" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "5NYZ" {
  let in_yaml =
    #|key:    # Comment
    #|  value
    #|
  let in_json : Json = { "key": "value" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "5T43" {
  let in_yaml =
    #|- { "key":value }
    #|- { "key"::value }
    #|
  let in_json : Json = [{ "key": "value" }, { "key": ":value" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "5TRB" {
  let in_yaml =
    #|---
    #|"
    #|---
    #|"
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "5TYM" {
  let in_yaml =
    #|%TAG !m! !my-
    #|--- # Bulb here
    #|!m!light fluorescent
    #|...
    #|%TAG !m! !my-
    #|--- # Color here
    #|!m!light green
    #|
  let in_json : Json = "fluorescent"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "5U3A" {
  let in_yaml =
    #|key: - a
    #|     - b
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "5WE3" {
  let in_yaml =
    #|? explicit key # Empty value
    #|? |
    #|  block key
    #|: - one # Explicit compact
    #|  - two # block value
    #|
  let in_json : Json = { "explicit key": null, "block key\n": ["one", "two"] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "62EZ" {
  let in_yaml =
    #|---
    #|x: { y: z }in: valid
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "652Z" {
  let in_yaml =
    #|{ ?foo: bar,
    #|bar: 42
    #|}
    #|
  let in_json : Json = { "?foo": "bar", "bar": 42 }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "65WH" {
  let in_yaml =
    #|- foo
    #|
  let in_json : Json = ["foo"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6BCT" {
  let in_yaml =
    #|- foo:	 bar
    #|- - baz
    #|  -	baz
    #|
  let in_json : Json = [{ "foo": "bar" }, ["baz", "baz"]]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6CA3" {
  let in_yaml =
    #|	[
    #|	]
    #|
  let in_json : Json = []
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6CK3" {
  let in_yaml =
    #|%TAG !e! tag:example.com,2000:app/
    #|---
    #|- !local foo
    #|- !!str bar
    #|- !e!tag%21 baz
    #|
  let in_json : Json = ["foo", "bar", "baz"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6FWR" {
  let in_yaml =
    #|--- |+
    #| ab
    #| 
    #|  
    #|...
    #|
  let in_json : Json = "ab\n\n \n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6H3V" {
  let in_yaml =
    #|'foo: bar\': baz'
    #|
  let in_json : Json = { "foo: bar\\": "baz'" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6HB6" {
  let in_yaml =
    #|  # Leading comment line spaces are
    #|   # neither content nor indentation.
    #|    
    #|Not indented:
    #| By one space: |
    #|    By four
    #|      spaces
    #| Flow style: [    # Leading spaces
    #|   By two,        # in flow style
    #|  Also by two,    # are neither
    #|  	Still by two   # content nor
    #|    ]             # indentation.
    #|
  let in_json : Json = {
    "Not indented": {
      "By one space": "By four\n  spaces\n",
      "Flow style": ["By two", "Also by two", "Still by two"],
    },
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6JQW" {
  let in_yaml =
    #|# ASCII Art
    #|--- |
    #|  \//||\/||
    #|  // ||  ||__
    #|
  let in_json : Json = "\\//||\\/||\n// ||  ||__\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6JTT" {
  let in_yaml =
    #|---
    #|[ [ a, b, c ]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "6JWB" {
  let in_yaml =
    #|foo: !!seq
    #|  - !!str a
    #|  - !!map
    #|    key: !!str value
    #|
  let in_json : Json = { "foo": ["a", { "key": "value" }] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6KGN" {
  let in_yaml =
    #|---
    #|a: &anchor
    #|b: *anchor
    #|
  let in_json : Json = { "a": null, "b": null }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6LVF" {
  let in_yaml =
    #|%FOO  bar baz # Should be ignored
    #|              # with a warning.
    #|--- "foo"
    #|
  let in_json : Json = "foo"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6S55" {
  let in_yaml =
    #|key:
    #| - bar
    #| - baz
    #| invalid
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "6SLA" {
  let in_yaml =
    #|"foo\nbar:baz\tx \\$%^&*()x": 23
    #|'x\ny:z\tx $%^&*()x': 24
    #|
  let in_json : Json = {
    "foo\nbar:baz\tx \\$%^&*()x": 23,
    "x\\ny:z\\tx $%^&*()x": 24,
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6VJK" {
  let in_yaml =
    #|>
    #| Sammy Sosa completed another
    #| fine season with great stats.
    #|
    #|   63 Home Runs
    #|   0.288 Batting Average
    #|
    #| What a year!
    #|
  let in_json : Json = "Sammy Sosa completed another fine season with great stats.\n\n  63 Home Runs\n  0.288 Batting Average\n\nWhat a year!\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6WLZ" {
  let in_yaml =
    #|# Private
    #|---
    #|!foo "bar"
    #|...
    #|# Global
    #|%TAG ! tag:example.com,2000:app/
    #|---
    #|!foo "bar"
    #|
  let in_json : Json = "bar"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6WPF" {
  let in_yaml =
    #|---
    #|"
    #|  foo 
    #| 
    #|    bar
    #|
    #|  baz
    #|"
    #|
  let in_json : Json = " foo\nbar\nbaz "
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6XDY" {
  let in_yaml =
    #|---
    #|---
    #|
  let in_json : Json = null
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "6ZKB" {
  let in_yaml =
    #|Document
    #|---
    #|# Empty
    #|...
    #|%YAML 1.2
    #|---
    #|matches %: 20
    #|
  let in_json : Json = "Document"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "735Y" {
  let in_yaml =
    #|-
    #|  "flow in block"
    #|- >
    #| Block scalar
    #|- !!map # Block collection
    #|  foo : bar
    #|
  let in_json : Json = ["flow in block", "Block scalar\n", { "foo": "bar" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "74H7" {
  let in_yaml =
    #|!!str a: b
    #|c: !!int 42
    #|e: !!str f
    #|g: h
    #|!!str 23: !!bool false
    #|
  let in_json : Json = { "a": "b", "c": 42, "e": "f", "g": "h", "23": false }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "753E" {
  let in_yaml =
    #|--- |-
    #| ab
    #| 
    #| 
    #|...
    #|
  let in_json : Json = "ab"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "7A4E" {
  let in_yaml =
    #|" 1st non-empty
    #|
    #| 2nd non-empty 
    #|	3rd non-empty "
    #|
  let in_json : Json = " 1st non-empty\n2nd non-empty 3rd non-empty "
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "7BMT" {
  let in_yaml =
    #|---
    #|top1: &node1
    #|  &k1 key1: one
    #|top2: &node2 # comment
    #|  key2: two
    #|top3:
    #|  &k3 key3: three
    #|top4: &node4
    #|  &k4 key4: four
    #|top5: &node5
    #|  key5: five
    #|top6: &val6
    #|  six
    #|top7:
    #|  &val7 seven
    #|
  let in_json : Json = {
    "top1": { "key1": "one" },
    "top2": { "key2": "two" },
    "top3": { "key3": "three" },
    "top4": { "key4": "four" },
    "top5": { "key5": "five" },
    "top6": "six",
    "top7": "seven",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "7BUB" {
  let in_yaml =
    #|---
    #|hr:
    #|  - Mark McGwire
    #|  # Following node labeled SS
    #|  - &SS Sammy Sosa
    #|rbi:
    #|  - *SS # Subsequent occurrence
    #|  - Ken Griffey
    #|
  let in_json : Json = {
    "hr": ["Mark McGwire", "Sammy Sosa"],
    "rbi": ["Sammy Sosa", "Ken Griffey"],
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "7FWL" {
  let in_yaml =
    #|!<tag:yaml.org,2002:str> foo :
    #|  !<!bar> baz
    #|
  let in_json : Json = { "foo": "baz" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "7LBH" {
  let in_yaml =
    #|"a\nb": 1
    #|"c
    #| d": 1
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "7MNF" {
  let in_yaml =
    #|top1:
    #|  key1: val1
    #|top2
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "7T8X" {
  let in_yaml =
    #|>
    #|
    #| folded
    #| line
    #|
    #| next
    #| line
    #|   * bullet
    #|
    #|   * list
    #|   * lines
    #|
    #| last
    #| line
    #|
    #|# Comment
    #|
  let in_json : Json = "\nfolded line\nnext line\n  * bullet\n\n  * list\n  * lines\n\nlast line\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "7TMG" {
  let in_yaml =
    #|---
    #|[ word1
    #|# comment
    #|, word2]
    #|
  let in_json : Json = ["word1", "word2"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "7W2P" {
  let in_yaml =
    #|? a
    #|? b
    #|c:
    #|
  let in_json : Json = { "a": null, "b": null, "c": null }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "7Z25" {
  let in_yaml =
    #|---
    #|scalar1
    #|...
    #|key: value
    #|
  let in_json : Json = "scalar1"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "7ZZ5" {
  let in_yaml =
    #|---
    #|nested sequences:
    #|- - - []
    #|- - - {}
    #|key1: []
    #|key2: {}
    #|
  let in_json : Json = {
    "nested sequences": [[[[]]], [[Json::empty_object()]]],
    "key1": [],
    "key2": Json::empty_object(),
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "82AN" {
  let in_yaml =
    #|---word1
    #|word2
    #|
  let in_json : Json = "---word1 word2"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "87E4" {
  let in_yaml =
    #|'implicit block key' : [
    #|  'implicit flow key' : value,
    #| ]
    #|
  let in_json : Json = {
    "implicit block key": [{ "implicit flow key": "value" }],
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "8CWC" {
  let in_yaml =
    #|---
    #|key ends with two colons::: value
    #|
  let in_json : Json = { "key ends with two colons::": "value" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "8KB6" {
  let in_yaml =
    #|---
    #|- { single line, a: b}
    #|- { multi
    #|  line, a: b}
    #|
  let in_json : Json = [
    { "single line": null, "a": "b" },
    { "multi line": null, "a": "b" },
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "8MK2" {
  let in_yaml =
    #|! a
    #|
  let in_json : Json = "a"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "8QBE" {
  let in_yaml =
    #|key:
    #| - item1
    #| - item2
    #|
  let in_json : Json = { "key": ["item1", "item2"] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "8UDB" {
  let in_yaml =
    #|[
    #|"double
    #| quoted", 'single
    #|           quoted',
    #|plain
    #| text, [ nested ],
    #|single: pair,
    #|]
    #|
  let in_json : Json = [
    "double quoted",
    "single quoted",
    "plain text",
    ["nested"],
    { "single": "pair" },
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "8XDJ" {
  let in_yaml =
    #|key: word1
    #|#  xxx
    #|  word2
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "8XYN" {
  let in_yaml =
    #|---
    #|- &😁 unicode anchor
    #|
  let in_json : Json = ["unicode anchor"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "93JH" {
  let in_yaml =
    #| - key: value
    #|   key2: value2
    #| -
    #|   key3: value3
    #|
  let in_json : Json = [
    { "key": "value", "key2": "value2" },
    { "key3": "value3" },
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "93WF" {
  let in_yaml =
    #|--- >-
    #|  trimmed
    #|  
    #| 
    #|
    #|  as
    #|  space
    #|
  let in_json : Json = "trimmed\n\n\nas space"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "96L6" {
  let in_yaml =
    #|--- >
    #|  Mark McGwire's
    #|  year was crippled
    #|  by a knee injury.
    #|
  let in_json : Json = "Mark McGwire's year was crippled by a knee injury.\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "9BXH" {
  let in_yaml =
    #|---
    #|- { "single line", a: b}
    #|- { "multi
    #|  line", a: b}
    #|
  let in_json : Json = [
    { "single line": null, "a": "b" },
    { "multi line": null, "a": "b" },
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "9C9N" {
  let in_yaml =
    #|---
    #|flow: [a,
    #|b,
    #|c]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "9CWY" {
  let in_yaml =
    #|key:
    #| - item1
    #| - item2
    #|invalid
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "9DXL" {
  let in_yaml =
    #|Mapping: Document
    #|---
    #|# Empty
    #|...
    #|%YAML 1.2
    #|---
    #|matches %: 20
    #|
  let in_json : Json = { "Mapping": "Document" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "9FMG" {
  let in_yaml =
    #|a:
    #|  b:
    #|    c: d
    #|  e:
    #|    f: g
    #|h: i
    #|
  let in_json : Json = {
    "a": { "b": { "c": "d" }, "e": { "f": "g" } },
    "h": "i",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "9HCY" {
  let in_yaml =
    #|!foo "bar"
    #|%TAG ! tag:example.com,2000:app/
    #|---
    #|!foo "bar"
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "9J7A" {
  let in_yaml =
    #|foo:
    #|  bar: baz
    #|
  let in_json : Json = { "foo": { "bar": "baz" } }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "9JBA" {
  let in_yaml =
    #|---
    #|[ a, b, c, ]#invalid
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "9KAX" {
  let in_yaml =
    #|---
    #|&a1
    #|!!str
    #|scalar1
    #|---
    #|!!str
    #|&a2
    #|scalar2
    #|---
    #|&a3
    #|!!str scalar3
    #|---
    #|&a4 !!map
    #|&a5 !!str key5: value4
    #|---
    #|a6: 1
    #|&anchor6 b6: 2
    #|---
    #|!!map
    #|&a8 !!str key8: value7
    #|---
    #|!!map
    #|!!str &a10 key10: value9
    #|---
    #|!!str &a11
    #|value11
    #|
  let in_json : Json = "scalar1"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "9KBC" {
  let in_yaml =
    #|--- key1: value1
    #|    key2: value2
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "9MAG" {
  let in_yaml =
    #|---
    #|[ , a, b, c ]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "9MMA" {
  let in_yaml =
    #|%YAML 1.2
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "9SA2" {
  let in_yaml =
    #|---
    #|- { "single line": value}
    #|- { "multi
    #|  line": value}
    #|
  let in_json : Json = [{ "single line": "value" }, { "multi line": "value" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "9SHH" {
  let in_yaml =
    #|single: 'text'
    #|double: "text"
    #|
  let in_json : Json = { "single": "text", "double": "text" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "9TFX" {
  let in_yaml =
    #|---
    #|" 1st non-empty
    #|
    #| 2nd non-empty 
    #| 3rd non-empty "
    #|
  let in_json : Json = " 1st non-empty\n2nd non-empty 3rd non-empty "
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "9U5K" {
  let in_yaml =
    #|---
    #|# Products purchased
    #|- item    : Super Hoop
    #|  quantity: 1
    #|- item    : Basketball
    #|  quantity: 4
    #|- item    : Big Shoes
    #|  quantity: 1
    #|
  let in_json : Json = [
    { "item": "Super Hoop", "quantity": 1 },
    { "item": "Basketball", "quantity": 4 },
    { "item": "Big Shoes", "quantity": 1 },
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "9WXW" {
  let in_yaml =
    #|# Private
    #|!foo "bar"
    #|...
    #|# Global
    #|%TAG ! tag:example.com,2000:app/
    #|---
    #|!foo "bar"
    #|
  let in_json : Json = "bar"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "9YRD" {
  let in_yaml =
    #|a
    #|b  
    #|  c
    #|d
    #|
    #|e
    #|
  let in_json : Json = "a b c d\ne"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "A2M4" {
  let in_yaml =
    #|? a
    #|: -	b
    #|  -  -	c
    #|     - d
    #|
  let in_json : Json = { "a": ["b", ["c", "d"]] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "A6F9" {
  let in_yaml =
    #|strip: |-
    #|  text
    #|clip: |
    #|  text
    #|keep: |+
    #|  text
    #|
  let in_json : Json = { "strip": "text", "clip": "text\n", "keep": "text\n" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "A984" {
  let in_yaml =
    #|a: b
    #| c
    #|d:
    #| e
    #|  f
    #|
  let in_json : Json = { "a": "b c", "d": "e f" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "AB8U" {
  let in_yaml =
    #|- single multiline
    #| - sequence entry
    #|
  let in_json : Json = ["single multiline - sequence entry"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "AZ63" {
  let in_yaml =
    #|one:
    #|- 2
    #|- 3
    #|four: 5
    #|
  let in_json : Json = { "one": [2, 3], "four": 5 }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "AZW3" {
  let in_yaml =
    #|- bla"keks: foo
    #|- bla]keks: foo
    #|
  let in_json : Json = [{ "bla\"keks": "foo" }, { "bla]keks": "foo" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "B3HG" {
  let in_yaml =
    #|--- >
    #| folded
    #| text
    #|
    #|
    #|
  let in_json : Json = "folded text\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "B63P" {
  let in_yaml =
    #|%YAML 1.2
    #|...
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "BD7L" {
  let in_yaml =
    #|- item1
    #|- item2
    #|invalid: x
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "BEC7" {
  let in_yaml =
    #|%YAML 1.3 # Attempt parsing
    #|          # with a warning
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
test "BF9H" {
  let in_yaml =
    #|---
    #|plain: a
    #|       b # end of scalar
    #|       c
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "BS4K" {
  let in_yaml =
    #|word1  # comment
    #|word2
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "BU8L" {
  let in_yaml =
    #|key: &anchor
    #| !!map
    #|  a: b
    #|
  let in_json : Json = { "key": { "a": "b" } }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "C2DT" {
  let in_yaml =
    #|{
    #|"adjacent":value,
    #|"readable": value,
    #|"empty":
    #|}
    #|
  let in_json : Json = {
    "adjacent": "value",
    "readable": "value",
    "empty": null,
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "C2SP" {
  let in_yaml =
    #|[23
    #|]: 42
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "C4HZ" {
  let in_yaml =
    #|%TAG ! tag:clarkevans.com,2002:
    #|--- !shape
    #|  # Use the ! handle for presenting
    #|  # tag:clarkevans.com,2002:circle
    #|- !circle
    #|  center: &ORIGIN {x: 73, y: 129}
    #|  radius: 7
    #|- !line
    #|  start: *ORIGIN
    #|  finish: { x: 89, y: 102 }
    #|- !label
    #|  start: *ORIGIN
    #|  color: 0xFFEEBB
    #|  text: Pretty vector drawing.
    #|
  let in_json : Json = [
    { "center": { "x": 73, "y": 129 }, "radius": 7 },
    { "start": { "x": 73, "y": 129 }, "finish": { "x": 89, "y": 102 } },
    {
      "start": { "x": 73, "y": 129 },
      "color": 16772795,
      "text": "Pretty vector drawing.",
    },
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "CC74" {
  let in_yaml =
    #|%TAG !e! tag:example.com,2000:app/
    #|---
    #|!e!foo "bar"
    #|
  let in_json : Json = "bar"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "CML9" {
  let in_yaml =
    #|key: [ word1
    #|#  xxx
    #|  word2 ]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "CN3R" {
  let in_yaml =
    #|&flowseq [
    #| a: b,
    #| &c c: d,
    #| { &e e: f },
    #| &g { g: h }
    #|]
    #|
  let in_json : Json = [{ "a": "b" }, { "c": "d" }, { "e": "f" }, { "g": "h" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "CPZ3" {
  let in_yaml =
    #|---
    #|tab: "\tstring"
    #|
  let in_json : Json = { "tab": "\tstring" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "CQ3W" {
  let in_yaml =
    #|---
    #|key: "missing closing quote
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "CT4Q" {
  let in_yaml =
    #|[
    #|? foo
    #| bar : baz
    #|]
    #|
  let in_json : Json = [{ "foo bar": "baz" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "CTN5" {
  let in_yaml =
    #|---
    #|[ a, b, c, , ]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "CUP7" {
  let in_yaml =
    #|anchored: !local &anchor value
    #|alias: *anchor
    #|
  let in_json : Json = { "anchored": "value", "alias": "value" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "CVW2" {
  let in_yaml =
    #|---
    #|[ a, b, c,#invalid
    #|]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "CXX2" {
  let in_yaml =
    #|--- &anchor a: b
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "D49Q" {
  let in_yaml =
    #|'a\nb': 1
    #|'c
    #| d': 1
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "D83L" {
  let in_yaml =
    #|- |2-
    #|  explicit indent and chomp
    #|- |-2
    #|  chomp and explicit indent
    #|
  let in_json : Json = [
    "explicit indent and chomp", "chomp and explicit indent",
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "D88J" {
  let in_yaml =
    #|a: [b, c]
    #|
  let in_json : Json = { "a": ["b", "c"] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "D9TU" {
  let in_yaml =
    #|foo: bar
    #|
  let in_json : Json = { "foo": "bar" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "DBG4" {
  let in_yaml =
    #|# Outside flow collection:
    #|- ::vector
    #|- ": - ()"
    #|- Up, up, and away!
    #|- -123
    #|- http://example.com/foo#bar
    #|# Inside flow collection:
    #|- [ ::vector,
    #|  ": - ()",
    #|  "Up, up and away!",
    #|  -123,
    #|  http://example.com/foo#bar ]
    #|
  let in_json : Json = [
    "::vector",
    ": - ()",
    "Up, up, and away!",
    -123,
    "http://example.com/foo#bar",
    [
      "::vector", ": - ()", "Up, up and away!", -123, "http://example.com/foo#bar",
    ],
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "DC7X" {
  let in_yaml =
    #|a: b	
    #|seq:	
    #| - a	
    #|c: d	#X
    #|
  let in_json : Json = { "a": "b", "seq": ["a"], "c": "d" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "DHP8" {
  let in_yaml =
    #|[foo, bar, 42]
    #|
  let in_json : Json = ["foo", "bar", 42]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "DK3J" {
  let in_yaml =
    #|--- >
    #|line1
    #|# no comment
    #|line3
    #|
  let in_json : Json = "line1 # no comment line3\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "DK4H" {
  let in_yaml =
    #|---
    #|[ key
    #|  : value ]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "DMG6" {
  let in_yaml =
    #|key:
    #|  ok: 1
    #| wrong: 2
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "DWX9" {
  let in_yaml =
    #||
    #| 
    #|  
    #|  literal
    #|   
    #|  
    #|  text
    #|
    #| # Comment
    #|
  let in_json : Json = "\n\nliteral\n \n\ntext\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "E76Z" {
  let in_yaml =
    #|&a a: &b b
    #|*b : *a
    #|
  let in_json : Json = { "a": "b", "b": "a" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "EB22" {
  let in_yaml =
    #|---
    #|scalar1 # comment
    #|%YAML 1.2
    #|---
    #|scalar2
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "EHF6" {
  let in_yaml =
    #|!!map {
    #|  k: !!seq
    #|  [ a, !!str b]
    #|}
    #|
  let in_json : Json = { "k": ["a", "b"] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "EW3V" {
  let in_yaml =
    #|k1: v1
    #| k2: v2
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "EX5H" {
  let in_yaml =
    #|---
    #|a
    #|b  
    #|  c
    #|d
    #|
    #|e
    #|
  let in_json : Json = "a b c d\ne"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "EXG3" {
  let in_yaml =
    #|---
    #|---word1
    #|word2
    #|
  let in_json : Json = "---word1 word2"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "F2C7" {
  let in_yaml =
    #| - &a !!str a
    #| - !!int 2
    #| - !!int &c 4
    #| - &d d
    #|
  let in_json : Json = ["a", 2, 4, "d"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "F3CP" {
  let in_yaml =
    #|---
    #|{ a: [b, c, { d: [e, f] } ] }
    #|
  let in_json : Json = { "a": ["b", "c", { "d": ["e", "f"] }] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "F6MC" {
  let in_yaml =
    #|---
    #|a: >2
    #|   more indented
    #|  regular
    #|b: >2
    #|
    #|
    #|   more indented
    #|  regular
    #|
  let in_json : Json = {
    "a": " more indented\nregular\n",
    "b": "\n\n more indented\nregular\n",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "F8F9" {
  let in_yaml =
    #| # Strip
    #|  # Comments:
    #|strip: |-
    #|  # text
    #|  
    #| # Clip
    #|  # comments:
    #|
    #|clip: |
    #|  # text
    #| 
    #| # Keep
    #|  # comments:
    #|
    #|keep: |+
    #|  # text
    #|
    #| # Trail
    #|  # comments.
    #|
  let in_json : Json = {
    "strip": "# text",
    "clip": "# text\n",
    "keep": "# text\n\n",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "FBC9" {
  let in_yaml =
    #|safe: a!"#$%&'()*+,-./09:;<=>?@AZ[\]^_`az{|}~
    #|     !"#$%&'()*+,-./09:;<=>?@AZ[\]^_`az{|}~
    #|safe question mark: ?foo
    #|safe colon: :foo
    #|safe dash: -foo
    #|
  let in_json : Json = {
    "safe": "a!\"#$%&'()*+,-./09:;<=>?@AZ[\\]^_`az{|}~ !\"#$%&'()*+,-./09:;<=>?@AZ[\\]^_`az{|}~",
    "safe question mark": "?foo",
    "safe colon": ":foo",
    "safe dash": "-foo",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "FP8R" {
  let in_yaml =
    #|--- >
    #|line1
    #|line2
    #|line3
    #|
  let in_json : Json = "line1 line2 line3\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "FQ7F" {
  let in_yaml =
    #|- Mark McGwire
    #|- Sammy Sosa
    #|- Ken Griffey
    #|
  let in_json : Json = ["Mark McGwire", "Sammy Sosa", "Ken Griffey"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "FTA2" {
  let in_yaml =
    #|--- &sequence
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
test "FUP4" {
  let in_yaml =
    #|[a, [b, c]]
    #|
  let in_json : Json = ["a", ["b", "c"]]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "G4RS" {
  let in_yaml =
    #|unicode: "Sosa did fine.\u263A"
    #|control: "\b1998\t1999\t2000\n"
    #|hex esc: "\x0d\x0a is \r\n"
    #|
    #|single: '"Howdy!" he cried.'
    #|quoted: ' # Not a ''comment''.'
    #|tie-fighter: '|\-*-/|'
    #|
  let in_json : Json = {
    "unicode": "Sosa did fine.☺",
    "control": "\b1998\t1999\t2000\n",
    "hex esc": "\r\n is \r\n",
    "single": "\"Howdy!\" he cried.",
    "quoted": " # Not a 'comment'.",
    "tie-fighter": "|\\-*-/|",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "G5U8" {
  let in_yaml =
    #|---
    #|- [-, -]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "G7JE" {
  let in_yaml =
    #|a\nb: 1
    #|c
    #| d: 1
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "G992" {
  let in_yaml =
    #|>
    #| folded
    #| text
    #|
    #|
    #|
  let in_json : Json = "folded text\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "G9HC" {
  let in_yaml =
    #|---
    #|seq:
    #|&anchor
    #|- a
    #|- b
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "GDY7" {
  let in_yaml =
    #|key: value
    #|this is #not a: key
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "GH63" {
  let in_yaml =
    #|? a
    #|: 1.3
    #|fifteen: d
    #|
  let in_json : Json = { "a": 1.3, "fifteen": "d" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "GT5M" {
  let in_yaml =
    #|- item1
    #|&node
    #|- item2
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "H2RW" {
  let in_yaml =
    #|foo: 1
    #|
    #|bar: 2
    #|    
    #|text: |
    #|  a
    #|    
    #|  b
    #|
    #|  c
    #| 
    #|  d
    #|
  let in_json : Json = { "foo": 1, "bar": 2, "text": "a\n  \nb\n\nc\n\nd\n" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "H3Z8" {
  let in_yaml =
    #|---
    #|wanted: love ♥ and peace ☮
    #|
  let in_json : Json = { "wanted": "love ♥ and peace ☮" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "H7J7" {
  let in_yaml =
    #|key: &x
    #|!!map
    #|  a: b
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "H7TQ" {
  let in_yaml =
    #|%YAML 1.2 foo
    #|---
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "HMK4" {
  let in_yaml =
    #|name: Mark McGwire
    #|accomplishment: >
    #|  Mark set a major league
    #|  home run record in 1998.
    #|stats: |
    #|  65 Home Runs
    #|  0.278 Batting Average
    #|
  let in_json : Json = {
    "name": "Mark McGwire",
    "accomplishment": "Mark set a major league home run record in 1998.\n",
    "stats": "65 Home Runs\n0.278 Batting Average\n",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "HMQ5" {
  let in_yaml =
    #|!!str &a1 "foo":
    #|  !!str bar
    #|&a2 baz : *a1
    #|
  let in_json : Json = { "foo": "bar", "baz": "foo" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "HRE5" {
  let in_yaml =
    #|---
    #|double: "quoted \' scalar"
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "HS5T" {
  let in_yaml =
    #|1st non-empty
    #|
    #| 2nd non-empty 
    #|	3rd non-empty
    #|
  let in_json : Json = "1st non-empty\n2nd non-empty 3rd non-empty"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "HU3P" {
  let in_yaml =
    #|key:
    #|  word1 word2
    #|  no: key
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "J3BT" {
  let in_yaml =
    #|# Tabs and spaces
    #|quoted: "Quoted 	"
    #|block:	|
    #|  void main() {
    #|  	printf("Hello, world!\n");
    #|  }
    #|
  let in_json : Json = {
    "quoted": "Quoted \t",
    "block": "void main() {\n\tprintf(\"Hello, world!\\n\");\n}\n",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "J5UC" {
  let in_yaml =
    #|foo: blue
    #|bar: arrr
    #|baz: jazz
    #|
  let in_json : Json = { "foo": "blue", "bar": "arrr", "baz": "jazz" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "J7PZ" {
  let in_yaml =
    #|# The !!omap tag is one of the optional types
    #|# introduced for YAML 1.1. In 1.2, it is not
    #|# part of the standard tags and should not be
    #|# enabled by default.
    #|# Ordered maps are represented as
    #|# A sequence of mappings, with
    #|# each mapping having one key
    #|--- !!omap
    #|- Mark McGwire: 65
    #|- Sammy Sosa: 63
    #|- Ken Griffy: 58
    #|
  let in_json : Json = [
    { "Mark McGwire": 65 },
    { "Sammy Sosa": 63 },
    { "Ken Griffy": 58 },
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "J7VC" {
  let in_yaml =
    #|one: 2
    #|
    #|
    #|three: 4
    #|
  let in_json : Json = { "one": 2, "three": 4 }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "J9HZ" {
  let in_yaml =
    #|---
    #|hr: # 1998 hr ranking
    #|  - Mark McGwire
    #|  - Sammy Sosa
    #|rbi:
    #|  # 1998 rbi ranking
    #|  - Sammy Sosa
    #|  - Ken Griffey
    #|
  let in_json : Json = {
    "hr": ["Mark McGwire", "Sammy Sosa"],
    "rbi": ["Sammy Sosa", "Ken Griffey"],
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "JHB9" {
  let in_yaml =
    #|# Ranking of 1998 home runs
    #|---
    #|- Mark McGwire
    #|- Sammy Sosa
    #|- Ken Griffey
    #|
    #|# Team ranking
    #|---
    #|- Chicago Cubs
    #|- St Louis Cardinals
    #|
  let in_json : Json = ["Mark McGwire", "Sammy Sosa", "Ken Griffey"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "JKF3" {
  let in_yaml =
    #|- - "bar
    #|bar": x
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "JQ4R" {
  let in_yaml =
    #|block sequence:
    #|  - one
    #|  - two : three
    #|
  let in_json : Json = { "block sequence": ["one", { "two": "three" }] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "JR7V" {
  let in_yaml =
    #|- a?string
    #|- another ? string
    #|- key: value?
    #|- [a?string]
    #|- [another ? string]
    #|- {key: value? }
    #|- {key: value?}
    #|- {key?: value }
    #|
  let in_json : Json = [
    "a?string",
    "another ? string",
    { "key": "value?" },
    ["a?string"],
    ["another ? string"],
    { "key": "value?" },
    { "key": "value?" },
    { "key?": "value" },
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "JS2J" {
  let in_yaml =
    #|First occurrence: &anchor Value
    #|Second occurrence: *anchor
    #|
  let in_json : Json = {
    "First occurrence": "Value",
    "Second occurrence": "Value",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "JTV5" {
  let in_yaml =
    #|? a
    #|  true
    #|: null
    #|  d
    #|? e
    #|  42
    #|
  let in_json : Json = { "a true": "null d", "e 42": null }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "JY7Z" {
  let in_yaml =
    #|key1: "quoted1"
    #|key2: "quoted2" no key: nor value
    #|key3: "quoted3"
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "K3WX" {
  let in_yaml =
    #|---
    #|{ "foo" # comment
    #|  :bar }
    #|
  let in_json : Json = { "foo": "bar" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "K4SU" {
  let in_yaml =
    #|- foo
    #|- bar
    #|- 42
    #|
  let in_json : Json = ["foo", "bar", 42]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "K527" {
  let in_yaml =
    #|>-
    #|  trimmed
    #|  
    #| 
    #|
    #|  as
    #|  space
    #|
  let in_json : Json = "trimmed\n\n\nas space"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "K54U" {
  let in_yaml =
    #|---	scalar
    #|
  let in_json : Json = "scalar"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "K858" {
  let in_yaml =
    #|strip: >-
    #|
    #|clip: >
    #|
    #|keep: |+
    #|
    #|
  let in_json : Json = { "strip": "", "clip": "", "keep": "\n" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "KMK3" {
  let in_yaml =
    #|foo:
    #|  bar: 1
    #|baz: 2
    #|
  let in_json : Json = { "foo": { "bar": 1 }, "baz": 2 }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "KS4U" {
  let in_yaml =
    #|---
    #|[
    #|sequence item
    #|]
    #|invalid item
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "KSS4" {
  let in_yaml =
    #|--- "quoted
    #|string"
    #|--- &node foo
    #|
  let in_json : Json = "quoted string"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "L383" {
  let in_yaml =
    #|--- foo  # comment
    #|--- foo  # comment
    #|
  let in_json : Json = "foo"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "L94M" {
  let in_yaml =
    #|? !!str a
    #|: !!int 47
    #|? c
    #|: !!str d
    #|
  let in_json : Json = { "a": 47, "c": "d" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "L9U5" {
  let in_yaml =
    #|implicit block key : [
    #|  implicit flow key : value,
    #| ]
    #|
  let in_json : Json = {
    "implicit block key": [{ "implicit flow key": "value" }],
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "LE5A" {
  let in_yaml =
    #|- !!str "a"
    #|- 'b'
    #|- &anchor "c"
    #|- *anchor
    #|- !!str
    #|
  let in_json : Json = ["a", "b", "c", "c", ""]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "LHL4" {
  let in_yaml =
    #|---
    #|!invalid{}tag scalar
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "LP6E" {
  let in_yaml =
    #|- [a, b , c ]
    #|- { "a"  : b
    #|   , c : 'd' ,
    #|   e   : "f"
    #|  }
    #|- [      ]
    #|
  let in_json : Json = [["a", "b", "c"], { "a": "b", "c": "d", "e": "f" }, []]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "LQZ7" {
  let in_yaml =
    #|"implicit block key" : [
    #|  "implicit flow key" : value,
    #| ]
    #|
  let in_json : Json = {
    "implicit block key": [{ "implicit flow key": "value" }],
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "M29M" {
  let in_yaml =
    #|a: |
    #| ab
    #| 
    #| cd
    #| ef
    #| 
    #|
    #|...
    #|
  let in_json : Json = { "a": "ab\n\ncd\nef\n" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "M5C3" {
  let in_yaml =
    #|literal: |2
    #|  value
    #|folded:
    #|   !foo
    #|  >1
    #| value
    #|
  let in_json : Json = { "literal": "value\n", "folded": "value\n" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "M6YH" {
  let in_yaml =
    #|- |
    #| x
    #|-
    #| foo: bar
    #|-
    #| - 42
    #|
  let in_json : Json = ["x\n", { "foo": "bar" }, [42]]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "M7A3" {
  let in_yaml =
    #|Bare
    #|document
    #|...
    #|# No document
    #|...
    #||
    #|%!PS-Adobe-2.0 # Not the first line
    #|
  let in_json : Json = "Bare document"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "M7NX" {
  let in_yaml =
    #|---
    #|{
    #| a: [
    #|  b, c, {
    #|   d: [e, f]
    #|  }
    #| ]
    #|}
    #|
  let in_json : Json = { "a": ["b", "c", { "d": ["e", "f"] }] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "M9B4" {
  let in_yaml =
    #||
    #| literal
    #| 	text
    #|
    #|
    #|
  let in_json : Json = "literal\n\ttext\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "MJS9" {
  let in_yaml =
    #|>
    #|  foo 
    #| 
    #|  	 bar
    #|
    #|  baz
    #|
  let in_json : Json = "foo \n\n\t bar\n\nbaz\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "MXS3" {
  let in_yaml =
    #|- {a: b}
    #|
  let in_json : Json = [{ "a": "b" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "MYW6" {
  let in_yaml =
    #||-
    #| ab
    #| 
    #| 
    #|...
    #|
  let in_json : Json = "ab"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "MZX3" {
  let in_yaml =
    #|- plain
    #|- "double quoted"
    #|- 'single quoted'
    #|- >
    #|  block
    #|- plain again
    #|
  let in_json : Json = [
    "plain", "double quoted", "single quoted", "block\n", "plain again",
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "N4JP" {
  let in_yaml =
    #|map:
    #|  key1: "quoted1"
    #| key2: "bad indentation"
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "N782" {
  let in_yaml =
    #|[
    #|--- ,
    #|...
    #|]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "NAT4" {
  let in_yaml =
    #|---
    #|a: '
    #|  '
    #|b: '  
    #|  '
    #|c: "
    #|  "
    #|d: "  
    #|  "
    #|e: '
    #|
    #|  '
    #|f: "
    #|
    #|  "
    #|g: '
    #|
    #|
    #|  '
    #|h: "
    #|
    #|
    #|  "
    #|
  let in_json : Json = {
    "a": " ",
    "b": " ",
    "c": " ",
    "d": " ",
    "e": "\n",
    "f": "\n",
    "g": "\n\n",
    "h": "\n\n",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "NB6Z" {
  let in_yaml =
    #|key:
    #|  value
    #|  with
    #|  	
    #|  tabs
    #|
  let in_json : Json = { "key": "value with\ntabs" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "NJ66" {
  let in_yaml =
    #|---
    #|- { single line: value}
    #|- { multi
    #|  line: value}
    #|
  let in_json : Json = [{ "single line": "value" }, { "multi line": "value" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "NP9H" {
  let in_yaml =
    #|"folded 
    #|to a space,	
    #| 
    #|to a line feed, or 	\
    #| \ 	non-content"
    #|
  let in_json : Json = "folded to a space,\nto a line feed, or \t \tnon-content"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "P2AD" {
  let in_yaml =
    #|- | # Empty header↓
    #| literal
    #|- >1 # Indentation indicator↓
    #|  folded
    #|- |+ # Chomping indicator↓
    #| keep
    #|
    #|- >1- # Both indicators↓
    #|  strip
    #|
  let in_json : Json = ["literal\n", " folded\n", "keep\n\n", " strip"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "P2EQ" {
  let in_yaml =
    #|---
    #|- { y: z }- invalid
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "P76L" {
  let in_yaml =
    #|%TAG !! tag:example.com,2000:app/
    #|---
    #|!!int 1 - 3 # Interval, not integer
    #|
  let in_json : Json = "1 - 3"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "P94K" {
  let in_yaml =
    #|key:    # Comment
    #|        # lines
    #|  value
    #|
    #|
    #|
  let in_json : Json = { "key": "value" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "PBJ2" {
  let in_yaml =
    #|american:
    #|  - Boston Red Sox
    #|  - Detroit Tigers
    #|  - New York Yankees
    #|national:
    #|  - New York Mets
    #|  - Chicago Cubs
    #|  - Atlanta Braves
    #|
  let in_json : Json = {
    "american": ["Boston Red Sox", "Detroit Tigers", "New York Yankees"],
    "national": ["New York Mets", "Chicago Cubs", "Atlanta Braves"],
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "PRH3" {
  let in_yaml =
    #|' 1st non-empty
    #|
    #| 2nd non-empty 
    #|	3rd non-empty '
    #|
  let in_json : Json = " 1st non-empty\n2nd non-empty 3rd non-empty "
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "PUW8" {
  let in_yaml =
    #|---
    #|a: b
    #|---
    #|
  let in_json : Json = { "a": "b" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "Q4CL" {
  let in_yaml =
    #|key1: "quoted1"
    #|key2: "quoted2" trailing content
    #|key3: "quoted3"
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "Q5MG" {
  let in_yaml =
    #|	{}
    #|
  let in_json : Json = Json::empty_object()
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "Q88A" {
  let in_yaml =
    #|- [ a, b ]
    #|- { a: b }
    #|- "a"
    #|- 'b'
    #|- c
    #|
  let in_json : Json = [["a", "b"], { "a": "b" }, "a", "b", "c"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "Q8AD" {
  let in_yaml =
    #|---
    #|"folded 
    #|to a space,
    #| 
    #|to a line feed, or 	\
    #| \ 	non-content"
    #|
  let in_json : Json = "folded to a space,\nto a line feed, or \t \tnon-content"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "QB6E" {
  let in_yaml =
    #|---
    #|quoted: "a
    #|b
    #|c"
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "QF4Y" {
  let in_yaml =
    #|[
    #|foo: bar
    #|]
    #|
  let in_json : Json = [{ "foo": "bar" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "QLJ7" {
  let in_yaml =
    #|%TAG !prefix! tag:example.com,2011:
    #|--- !prefix!A
    #|a: b
    #|--- !prefix!B
    #|c: d
    #|--- !prefix!C
    #|e: f
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "R4YG" {
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
    #| 	
    #| detected
    #|
  let in_json : Json = [
    "detected\n", "\n\n# detected\n", " explicit\n", "\t\ndetected\n",
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "R52L" {
  let in_yaml =
    #|---
    #|{ top1: [item1, {key2: value2}, item3], top2: value2 }
    #|
  let in_json : Json = {
    "top1": ["item1", { "key2": "value2" }, "item3"],
    "top2": "value2",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "RHX7" {
  let in_yaml =
    #|---
    #|key: value
    #|%YAML 1.2
    #|---
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "RLU9" {
  let in_yaml =
    #|foo:
    #|- 42
    #|bar:
    #|  - 44
    #|
  let in_json : Json = { "foo": [42], "bar": [44] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "RR7F" {
  let in_yaml =
    #|a: 4.2
    #|? d
    #|: 23
    #|
  let in_json : Json = { "d": 23, "a": 4.2 }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "RTP8" {
  let in_yaml =
    #|%YAML 1.2
    #|---
    #|Document
    #|... # Suffix
    #|
  let in_json : Json = "Document"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "RXY3" {
  let in_yaml =
    #|---
    #|'
    #|...
    #|'
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "RZT7" {
  let in_yaml =
    #|---
    #|Time: 2001-11-23 15:01:42 -5
    #|User: ed
    #|Warning:
    #|  This is an error message
    #|  for the log file
    #|---
    #|Time: 2001-11-23 15:02:31 -5
    #|User: ed
    #|Warning:
    #|  A slightly different error
    #|  message.
    #|---
    #|Date: 2001-11-23 15:03:17 -5
    #|User: ed
    #|Fatal:
    #|  Unknown variable "bar"
    #|Stack:
    #|  - file: TopClass.py
    #|    line: 23
    #|    code: |
    #|      x = MoreObject("345\n")
    #|  - file: MoreClass.py
    #|    line: 58
    #|    code: |-
    #|      foo = bar
    #|
  let in_json : Json = {
    "Time": "2001-11-23 15:01:42 -5",
    "User": "ed",
    "Warning": "This is an error message for the log file",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "S4GJ" {
  let in_yaml =
    #|---
    #|folded: > first line
    #|  second line
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "S4JQ" {
  let in_yaml =
    #|# Assuming conventional resolution:
    #|- "12"
    #|- 12
    #|- ! 12
    #|
  let in_json : Json = ["12", 12, "12"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "S4T7" {
  let in_yaml =
    #|aaa: bbb
    #|...
    #|
  let in_json : Json = { "aaa": "bbb" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "S7BG" {
  let in_yaml =
    #|---
    #|- :,
    #|
  let in_json : Json = [":,"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "S98Z" {
  let in_yaml =
    #|empty block scalar: >
    #| 
    #|  
    #|   
    #| # comment
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "S9E8" {
  let in_yaml =
    #|sequence:
    #|- one
    #|- two
    #|mapping:
    #|  ? sky
    #|  : blue
    #|  sea : green
    #|
  let in_json : Json = {
    "sequence": ["one", "two"],
    "mapping": { "sky": "blue", "sea": "green" },
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "SF5V" {
  let in_yaml =
    #|%YAML 1.2
    #|%YAML 1.2
    #|---
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "SKE5" {
  let in_yaml =
    #|---
    #|seq:
    #| &anchor
    #|- a
    #|- b
    #|
  let in_json : Json = { "seq": ["a", "b"] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "SR86" {
  let in_yaml =
    #|key1: &a value
    #|key2: &b *a
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "SSW6" {
  let in_yaml =
    #|---
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
test "SU5Z" {
  let in_yaml =
    #|key: "value"# invalid comment
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "SU74" {
  let in_yaml =
    #|key1: &alias value1
    #|&b *alias : value2
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "SY6V" {
  let in_yaml =
    #|&anchor - sequence entry
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "SYW4" {
  let in_yaml =
    #|hr:  65    # Home runs
    #|avg: 0.278 # Batting average
    #|rbi: 147   # Runs Batted In
    #|
  let in_json : Json = { "hr": 65, "avg": 0.278, "rbi": 147 }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "T26H" {
  let in_yaml =
    #|--- |
    #| 
    #|  
    #|  literal
    #|   
    #|  
    #|  text
    #|
    #| # Comment
    #|
  let in_json : Json = "\n\nliteral\n \n\ntext\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "T4YY" {
  let in_yaml =
    #|---
    #|' 1st non-empty
    #|
    #| 2nd non-empty 
    #| 3rd non-empty '
    #|
  let in_json : Json = " 1st non-empty\n2nd non-empty 3rd non-empty "
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "T5N4" {
  let in_yaml =
    #|--- |
    #| literal
    #| 	text
    #|
    #|
    #|
  let in_json : Json = "literal\n\ttext\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "T833" {
  let in_yaml =
    #|---
    #|{
    #| foo: 1
    #| bar: 2 }
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "TD5N" {
  let in_yaml =
    #|- item1
    #|- item2
    #|invalid
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "TE2A" {
  let in_yaml =
    #|block mapping:
    #| key: value
    #|
  let in_json : Json = { "block mapping": { "key": "value" } }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "TL85" {
  let in_yaml =
    #|"
    #|  foo 
    #| 
    #|  	 bar
    #|
    #|  baz
    #|"
    #|
  let in_json : Json = " foo\nbar\nbaz "
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "TS54" {
  let in_yaml =
    #|>
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
test "U3C3" {
  let in_yaml =
    #|%TAG !yaml! tag:yaml.org,2002:
    #|---
    #|!yaml!str "foo"
    #|
  let in_json : Json = "foo"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "U3XV" {
  let in_yaml =
    #|---
    #|top1: &node1
    #|  &k1 key1: one
    #|top2: &node2 # comment
    #|  key2: two
    #|top3:
    #|  &k3 key3: three
    #|top4:
    #|  &node4
    #|  &k4 key4: four
    #|top5:
    #|  &node5
    #|  key5: five
    #|top6: &val6
    #|  six
    #|top7:
    #|  &val7 seven
    #|
  let in_json : Json = {
    "top1": { "key1": "one" },
    "top2": { "key2": "two" },
    "top3": { "key3": "three" },
    "top4": { "key4": "four" },
    "top5": { "key5": "five" },
    "top6": "six",
    "top7": "seven",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "U44R" {
  let in_yaml =
    #|map:
    #|  key1: "quoted1"
    #|   key2: "bad indentation"
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "U99R" {
  let in_yaml =
    #|- !!str, xxx
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "U9NS" {
  let in_yaml =
    #|---
    #|time: 20:03:20
    #|player: Sammy Sosa
    #|action: strike (miss)
    #|...
    #|---
    #|time: 20:03:47
    #|player: Sammy Sosa
    #|action: grand slam
    #|...
    #|
  let in_json : Json = {
    "time": "20:03:20",
    "player": "Sammy Sosa",
    "action": "strike (miss)",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "UDM2" {
  let in_yaml =
    #|- { url: http://example.org }
    #|
  let in_json : Json = [{ "url": "http://example.org" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "UDR7" {
  let in_yaml =
    #|sequence: [ one, two, ]
    #|mapping: { sky: blue, sea: green }
    #|
  let in_json : Json = {
    "sequence": ["one", "two"],
    "mapping": { "sky": "blue", "sea": "green" },
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "UGM3" {
  let in_yaml =
    #|--- !<tag:clarkevans.com,2002:invoice>
    #|invoice: 34843
    #|date   : 2001-01-23
    #|bill-to: &id001
    #|    given  : Chris
    #|    family : Dumars
    #|    address:
    #|        lines: |
    #|            458 Walkman Dr.
    #|            Suite #292
    #|        city    : Royal Oak
    #|        state   : MI
    #|        postal  : 48046
    #|ship-to: *id001
    #|product:
    #|    - sku         : BL394D
    #|      quantity    : 4
    #|      description : Basketball
    #|      price       : 450.00
    #|    - sku         : BL4438H
    #|      quantity    : 1
    #|      description : Super Hoop
    #|      price       : 2392.00
    #|tax  : 251.42
    #|total: 4443.52
    #|comments:
    #|    Late afternoon is best.
    #|    Backup contact is Nancy
    #|    Billsmer @ 338-4338.
    #|
  let in_json : Json = {
    "invoice": 34843,
    "date": "2001-01-23",
    "bill-to": {
      "given": "Chris",
      "family": "Dumars",
      "address": {
        "lines": "458 Walkman Dr.\nSuite #292\n",
        "city": "Royal Oak",
        "state": "MI",
        "postal": 48046,
      },
    },
    "ship-to": {
      "given": "Chris",
      "family": "Dumars",
      "address": {
        "lines": "458 Walkman Dr.\nSuite #292\n",
        "city": "Royal Oak",
        "state": "MI",
        "postal": 48046,
      },
    },
    "product": [
      {
        "sku": "BL394D",
        "quantity": 4,
        "description": "Basketball",
        "price": 450,
      },
      {
        "sku": "BL4438H",
        "quantity": 1,
        "description": "Super Hoop",
        "price": 2392,
      },
    ],
    "tax": 251.42,
    "total": 4443.52,
    "comments": "Late afternoon is best. Backup contact is Nancy Billsmer @ 338-4338.",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "UT92" {
  let in_yaml =
    #|---
    #|{ matches
    #|% : 20 }
    #|...
    #|---
    #|# Empty
    #|...
    #|
  let in_json : Json = { "matches %": 20 }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "UV7Q" {
  let in_yaml =
    #|x:
    #| - x
    #|  	x
    #|
  let in_json : Json = { "x": ["x x"] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "V55R" {
  let in_yaml =
    #|- &a a
    #|- &b b
    #|- *a
    #|- *b
    #|
  let in_json : Json = ["a", "b", "a", "b"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "W42U" {
  let in_yaml =
    #|- # Empty
    #|- |
    #| block node
    #|- - one # Compact
    #|  - two # sequence
    #|- one: two # Compact mapping
    #|
  let in_json : Json = [null, "block node\n", ["one", "two"], { "one": "two" }]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "W4TN" {
  let in_yaml =
    #|%YAML 1.2
    #|--- |
    #|%!PS-Adobe-2.0
    #|...
    #|%YAML 1.2
    #|---
    #|# Empty
    #|...
    #|
  let in_json : Json = "%!PS-Adobe-2.0\n"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "W5VH" {
  let in_yaml =
    #|a: &:@*!$"<foo>: scalar a
    #|b: *:@*!$"<foo>:
    #|
  let in_json : Json = { "a": "scalar a", "b": "scalar a" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "W9L4" {
  let in_yaml =
    #|---
    #|block scalar: |
    #|     
    #|  more spaces at the beginning
    #|  are invalid
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "WZ62" {
  let in_yaml =
    #|{
    #|  foo : !!str,
    #|  !!str : bar,
    #|}
    #|
  let in_json : Json = { "foo": "", "": "bar" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "X4QW" {
  let in_yaml =
    #|block: ># comment
    #|  scalar
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "X8DW" {
  let in_yaml =
    #|---
    #|? key
    #|# comment
    #|: value
    #|
  let in_json : Json = { "key": "value" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "XLQ9" {
  let in_yaml =
    #|---
    #|scalar
    #|%YAML 1.2
    #|
  let in_json : Json = "scalar %YAML 1.2"
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "XV9V" {
  let in_yaml =
    #|Folding:
    #|  "Empty line
    #|
    #|  as a line feed"
    #|Chomping: |
    #|  Clipped empty lines
    #| 
    #|
    #|
  let in_json : Json = {
    "Folding": "Empty line\nas a line feed",
    "Chomping": "Clipped empty lines\n",
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "Y2GN" {
  let in_yaml =
    #|---
    #|key: &an:chor value
    #|
  let in_json : Json = { "key": "value" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "YD5X" {
  let in_yaml =
    #|- [name        , hr, avg  ]
    #|- [Mark McGwire, 65, 0.278]
    #|- [Sammy Sosa  , 63, 0.288]
    #|
  let in_json : Json = [
    ["name", "hr", "avg"],
    ["Mark McGwire", 65, 0.278],
    ["Sammy Sosa", 63, 0.288],
  ]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "YJV2" {
  let in_yaml =
    #|[-]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "Z67P" {
  let in_yaml =
    #|literal: |2
    #|  value
    #|folded: !foo >1
    #| value
    #|
  let in_json : Json = { "literal": "value\n", "folded": "value\n" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "Z9M4" {
  let in_yaml =
    #|%TAG !e! tag:example.com,2000:app/
    #|---
    #|- !e!foo "bar"
    #|
  let in_json : Json = ["bar"]
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "ZCZ6" {
  let in_yaml =
    #|a: b: c: d
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "ZF4X" {
  let in_yaml =
    #|Mark McGwire: {hr: 65, avg: 0.278}
    #|Sammy Sosa: {
    #|    hr: 63,
    #|    avg: 0.288
    #|  }
    #|
  let in_json : Json = {
    "Mark McGwire": { "hr": 65, "avg": 0.278 },
    "Sammy Sosa": { "hr": 63, "avg": 0.288 },
  }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "ZH7C" {
  let in_yaml =
    #|&a a: b
    #|c: &d d
    #|
  let in_json : Json = { "a": "b", "c": "d" }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "ZK9H" {
  let in_yaml =
    #|{ key: [[[
    #|  value
    #| ]]]
    #|}
    #|
  let in_json : Json = { "key": [[["value"]]] }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "ZL4Z" {
  let in_yaml =
    #|---
    #|a: 'b': c
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "ZVH3" {
  let in_yaml =
    #|- key: value
    #| - item1
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "ZWK4" {
  let in_yaml =
    #|---
    #|a: 1
    #|? b
    #|&anchor c: 3
    #|
  let in_json : Json = { "a": 1, "b": null, "c": 3 }
  let yaml = @yaml.parse(in_yaml)
  match yaml {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "ZXT5" {
  let in_yaml =
    #|[ "key"
    #|  :value ]
    #|
  let yaml = parse(in_yaml)
  match yaml {
    Ok(_) => fail("Expected parse error")
    Err(_) => ()
  }
}

///|
test "parse booleans and numbers" {
  let in_yaml =
    #|t: true
    #|f: false
    #|i: 42
    #|x: 0.25
    #|
  let in_json : Json = { "t": true, "f": false, "i": 42, "x": 0.25 }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "parse quoted string with escapes" {
  let in_yaml =
    #|a: "line1\nline2\tend"
    #|
  let in_json : Json = { "a": "line1\nline2\tend" }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "parse quoted scalar containing colon" {
  let in_yaml =
    #|a: "b: c"
    #|
  let in_json : Json = { "a": "b: c" }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 basic example" {
  let in_yaml =
    #|# comment
    #|a0 bb: val
    #|a1:
    #|    b1: 4
    #|    b2: d
    #|a2: 4 # i'm comment
    #|a3: [1, 2, 3]
    #|a4:
    #|    - - a1
    #|      - a2
    #|    - 2
    #|a5: 'single_quoted'
    #|a6: "double_quoted"
    #|a7: 你好
    #|
  let in_json : Json = {
    "a0 bb": "val",
    "a1": { "b1": 4, "b2": "d" },
    "a2": 4,
    "a3": [1, 2, 3],
    "a4": [["a1", "a2"], 2],
    "a5": "single_quoted",
    "a6": "double_quoted",
    "a7": "你好",
  }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 openapi quoting example" {
  let in_yaml =
    #|example: '[''This is a test.'']'
    #|
  let in_json : Json = { "example": "['This is a test.']" }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "parse sequence" {
  let in_yaml =
    #|- one
    #|- two
    #|- 3
    #|
  let in_json : Json = ["one", "two", 3]
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "to_string roundtrip preserves json" {
  let in_yaml =
    #|a: 1
    #|b:
    #|  - x
    #|  - y
    #|
  match @yaml.parse(in_yaml) {
    Ok(yaml1) => {
      let json1 = yaml1.to_json()
      let text1 = yaml1.to_string()
      match @yaml.parse(text1) {
        Ok(yaml2) => assert_eq(yaml2.to_json(), json1)
        Err(error) =>
          fail("Unexpected parse error after to_string: " + error.to_string())
      }
    }
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "flow collections" {
  let in_yaml =
    #|{a: 1, b: [2, 3]}
    #|
  let in_json : Json = { "a": 1, "b": [2, 3] }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "nested structures" {
  let in_yaml =
    #|a:
    #|  b:
    #|    - 1
    #|    - 2
    #|
  let in_json : Json = { "a": { "b": [1, 2] } }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "literal block scalar" {
  let in_yaml =
    #|a: |
    #|  line1
    #|  line2
    #|
  let in_json : Json = { "a": "line1\nline2\n" }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "flow scalar inside block sequence" {
  let in_yaml =
    #|-
    #|  "flow in block"
    #|- >
    #| Block scalar
    #|
  let in_json : Json = ["flow in block", "Block scalar\n"]
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "multiple documents returns first document" {
  let in_yaml =
    #|Document
    #|---
    #|# Empty
    #|...
    #|%YAML 1.2
    #|---
    #|matches %: 20
    #|
  let in_json : Json = "Document"
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "explicit empty document is null" {
  let in_yaml =
    #|---
    #|---
    #|
  let in_json : Json = null
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 comment after tag + docstart" {
  let in_yaml =
    #|%YAML 1.2
    #|# This is a comment
    #|--- #-------
    #|foobar
    #|
  let in_json : Json = "foobar"
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 large block scalar indent" {
  let in_yaml =
    #|a: |-
    #|                  a
    #|                      b
    #|
  let in_json : Json = { "a": "a\n    b" }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 three dashes as content" {
  let in_yaml =
    #|---
    #|---word1
    #|word2
    #|
  let in_json : Json = "---word1 word2"
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 multiline flow mapping keys" {
  let in_yaml =
    #|---
    #|- { "single line", a: b}
    #|- { "multi
    #|  line", a: b}
    #|
  let in_json : Json = [
    { "single line": null, "a": "b" },
    { "multi line": null, "a": "b" },
  ]
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 flow sequence entries" {
  let in_yaml =
    #|[
    #|"double
    #| quoted", 'single
    #|           quoted',
    #|plain
    #| text, [ nested ],
    #|single: pair,
    #|]
    #|
  let in_json : Json = [
    "double quoted",
    "single quoted",
    "plain text",
    ["nested"],
    { "single": "pair" },
  ]
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "explicit tags for seq/map" {
  let in_yaml =
    #|foo: !!seq
    #|  - !!str a
    #|  - !!map
    #|    key: !!str value
    #|
  let in_json : Json = { "foo": ["a", { "key": "value" }] }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "missing values become null" {
  let in_yaml =
    #|---
    #|a: &anchor
    #|b: *anchor
    #|
  let in_json : Json = { "a": null, "b": null }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "to_string roundtrip with nesting" {
  let in_yaml =
    #|a:
    #|  b: [1, 2, 3]
    #|  c: {d: 4}
    #|
  match @yaml.parse(in_yaml) {
    Ok(yaml1) => {
      let json1 = yaml1.to_json()
      match @yaml.parse(yaml1.to_string()) {
        Ok(yaml2) => assert_eq(yaml2.to_json(), json1)
        Err(error) =>
          fail("Unexpected parse error after to_string: " + error.to_string())
      }
    }
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "anchors and aliases as keys" {
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
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "sets become null-valued mapping" {
  let in_yaml =
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
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "explicit and block keys" {
  let in_yaml =
    #|? explicit key # Empty value
    #|? |
    #|  block key
    #|: - one # Explicit compact
    #|  - two # block value
    #|
  let in_json : Json = { "explicit key": null, "block key\n": ["one", "two"] }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "question-mark prefixed key in flow mapping" {
  let in_yaml =
    #|{ ?foo: bar,
    #|bar: 42
    #|}
    #|
  let in_json : Json = { "?foo": "bar", "bar": 42 }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "tabs are treated as whitespace" {
  let in_yaml =
    #|- foo:	 bar
    #|- - baz
    #|  -	baz
    #|
  let in_json : Json = [{ "foo": "bar" }, ["baz", "baz"]]
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 keep tags across multiple documents returns first doc" {
  let in_yaml =
    #|%YAML 1.1
    #|%TAG !t! tag:test,2024:
    #|--- !t!1 &1
    #|foo: "bar"
    #|--- !t!2 &2
    #|baz: "qux"
    #|
  let in_json : Json = { "foo": "bar" }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 anchors in mapping" {
  let in_yaml =
    #|&a a: b
    #|c: &d d
    #|
  let in_json : Json = { "a": "b", "c": "d" }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 implicit flow keys under implicit block key" {
  let in_yaml =
    #|"implicit block key" : [
    #|  "implicit flow key" : value,
    #| ]
    #|
  let in_json : Json = {
    "implicit block key": [{ "implicit flow key": "value" }],
  }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 node properties with anchors" {
  let in_yaml =
    #|!!str &a1 "foo":
    #|  !!str bar
    #|&a2 baz : *a1
    #|
  let in_json : Json = { "foo": "bar", "baz": "foo" }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "impl01 quoted scalars and escapes" {
  let in_yaml =
    #|unicode: "Sosa did fine.\u263A"
    #|control: "\b1998\t1999\t2000\n"
    #|hex esc: "\x0d\x0a is \r\n"
    #|
    #|single: '"Howdy!" he cried.'
    #|quoted: ' # Not a ''comment''.'
    #|tie-fighter: '|\-*-/|'
    #|
  let in_json : Json = {
    "unicode": "Sosa did fine.☺",
    "control": "\b1998\t1999\t2000\n",
    "hex esc": "\r\n is \u0013\n",
    "single": "\"Howdy!\" he cried.",
    "quoted": " # Not a 'comment'.",
    "tie-fighter": "|\\-*-/|",
  }
  match @yaml.parse(in_yaml) {
    Ok(yaml) => assert_eq(yaml.to_json(), in_json)
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}

///|
test "to_string roundtrip with anchors" {
  let in_yaml =
    #|a: &anchor
    #|  b: 1
    #|c: *anchor
    #|
  match @yaml.parse(in_yaml) {
    Ok(yaml1) => {
      let json1 = yaml1.to_json()
      match @yaml.parse(yaml1.to_string()) {
        Ok(yaml2) => assert_eq(yaml2.to_json(), json1)
        Err(error) =>
          fail("Unexpected parse error after to_string: " + error.to_string())
      }
    }
    Err(error) => fail("Unexpected parse error: " + error.to_string())
  }
}
