///|
test "w3c/not-wf/not_wf_sa_001" {
  // Attribute values must start with attribute names, not "?".
  let xml = "<doc>\n<doc\n?\n<a</a>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_002" {
  // Names may not start with "."; it's not a Letter.
  let xml = "<doc>\n<.doc></.doc>\n</doc>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_003" {
  // Processing Instruction target name is required.
  let xml = "<doc><? ?></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_004" {
  // SGML-ism: processing instructions end in '?&gt;' not '&gt;'.
  let xml = "<doc><?target some data></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_005" {
  // Processing instructions end in '?&gt;' not '?'.
  let xml = "<doc><?target some data?</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_006" {
  // XML comments may not contain "-"
  let xml = "<doc><!-- a comment -- another --></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_007" {
  // General entity references have no whitespace after the en...
  let xml = "<doc>&amp no refc</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_008" {
  // Entity references must include names, which don't begin w...
  let xml = "<doc>&.entity;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_009" {
  // Character references may have only decimal or numeric str...
  let xml = "<doc>&#RE;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_010" {
  // Ampersand may only appear as part of a general entity ref...
  let xml = "<doc>A & B</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_011" {
  // SGML-ism: attribute values must be explicitly assigned a ...
  let xml = "<doc a1></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_012" {
  // SGML-ism: attribute values must be quoted in all cases.
  let xml = "<doc a1=v1></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_013" {
  // The quotes on both ends of an attribute value must match.
  let xml = "<doc a1=\"v1'></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_014" {
  // Attribute values may not contain literal '&lt;' characters.
  let xml = "<doc a1=\"<foo>\"></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_015" {
  // Attribute values need a value, not just an equals sign.
  let xml = "<doc a1=></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_016" {
  // Attribute values need an associated name.
  let xml = "<doc a1=\"v1\" \"v2\"></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_017" {
  // CDATA sections need a terminating ']]&gt;'.
  let xml = "<doc><![CDATA[</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_018" {
  // CDATA sections begin with a literal '&lt;![CDATA[', no sp...
  let xml = "<doc><![CDATA [ stuff]]></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_019" {
  // End tags may not be abbreviated as '&lt;/&gt;'.
  let xml = "<doc></>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_020" {
  // Attribute values may not contain literal '&amp;' characte...
  let xml = "<doc a1=\"A & B\"></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_021" {
  // Attribute values may not contain literal '&amp;' characte...
  let xml = "<doc a1=\"a&b\"></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_022" {
  // Character references end with semicolons, always!
  let xml = "<doc a1=\"&#123:\"></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_023" {
  // Digits are not valid name start characters.
  let xml = "<doc 12=\"34\"></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_024" {
  // Digits are not valid name start characters.
  let xml = "<doc>\n<123></123>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_025" {
  // Text may not contain a literal ']]&gt;' sequence.
  let xml = "<doc>]]></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_026" {
  // Text may not contain a literal ']]&gt;' sequence.
  let xml = "<doc>]]]></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_027" {
  // Comments must be terminated with "-&gt;".
  let xml = "<doc>\n<!-- abc\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_028" {
  // Processing instructions must end with '?&gt;'.
  let xml = "<doc>\n<?a pi that is not closed\n</doc>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/valid/valid_sa_001" {
  // Test demonstrates an Element Type Declaration with Mixed ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_002" {
  // Test demonstrates that whitespace is permitted after the ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc ></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_003" {
  // Test demonstrates that whitespace is permitted after the ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc >\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_004" {
  // Test demonstrates a valid attribute specification within ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 CDATA #IMPLIED>\n]>\n<doc a1=\"v1\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a1\", \"v1\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_005" {
  // Test demonstrates a valid attribute specification within ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 CDATA #IMPLIED>\n]>\n<doc a1 = \"v1\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a1\", \"v1\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_006" {
  // Test demonstrates that the AttValue within a Start-tag ca...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 CDATA #IMPLIED>\n]>\n<doc a1='v1'></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a1\", \"v1\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_007" {
  // Test demonstrates numeric character references can be use...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#32;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\" \"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_008" {
  // Test demonstrates character references can be used for el...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&amp;&lt;&gt;&quot;&apos;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"&<>\\\"'\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_009" {
  // Test demonstrates that PubidChar can be used for element ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#x20;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\" \"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_010" {
  // Test demonstrates that whitespace is valid after the Attr...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 CDATA #IMPLIED>\n]>\n<doc a1=\"v1\" ></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a1\", \"v1\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_011" {
  // Test demonstrates mutliple Attibutes within the Start-tag.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 CDATA #IMPLIED a2 CDATA #IMPLIED>\n]>\n<doc a1=\"v1\" a2=\"v2\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a1\", \"v1\"), (\"a2\", \"v2\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_012" {
  // Uses a legal XML 1.0 name consisting of a single colon ch...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc : CDATA #IMPLIED>\n]>\n<doc :=\"v1\"></doc>\n"
  let reader = Reader::from_string(xml)
  // Verify parsing succeeds
  let events = reader.read_events_until_eof()
  assert_true(events.length() > 0)
}

///|
test "w3c/valid/valid_sa_013" {
  // Test demonstrates that the Attribute in a Start-tag can c...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc _.-0123456789 CDATA #IMPLIED>\n]>\n<doc _.-0123456789=\"v1\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"_.-0123456789\", \"v1\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_014" {
  // Test demonstrates that all lower case letters are valid f...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc abcdefghijklmnopqrstuvwxyz CDATA #IMPLIED>\n]>\n<doc abcdefghijklmnopqrstuvwxyz=\"v1\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"abcdefghijklmnopqrstuvwxyz\", \"v1\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_015" {
  // Test demonstrates that all upper case letters are valid f...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc ABCDEFGHIJKLMNOPQRSTUVWXYZ CDATA #IMPLIED>\n]>\n<doc ABCDEFGHIJKLMNOPQRSTUVWXYZ=\"v1\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"ABCDEFGHIJKLMNOPQRSTUVWXYZ\", \"v1\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_016" {
  // Test demonstrates that Processing Instructions are valid ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc><?pi?></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), PI(target=\"pi\", data=\"\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_017" {
  // Test demonstrates that Processing Instructions are valid ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc><?pi some data ?><?x?></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), PI(target=\"pi\", data=\"some data \"), PI(target=\"x\", data=\"\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_018" {
  // Test demonstrates that CDATA sections are valid element c...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc><![CDATA[<foo>]]></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"<foo>\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_019" {
  // Test demonstrates that CDATA sections are valid element c...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc><![CDATA[<&]]></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"<&\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_020" {
  // Test demonstractes that CDATA sections are valid element ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc><![CDATA[<&]>]]]></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"<&]>]\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_021" {
  // Test demonstrates that comments are valid element content.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc><!-- a comment --></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Comment(\" a comment \"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_022" {
  // Test demonstrates that comments are valid element content...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc><!-- a comment ->--></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Comment(\" a comment ->\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_023" {
  // Test demonstrates that Entity References are valid elemen...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY e \"\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_024" {
  // Test demonstrates that Entity References are valid elemen...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (foo)>\n<!ELEMENT foo (#PCDATA)>\n<!ENTITY e \"&#60;foo></foo>\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Empty({name: \"foo\", attributes: []}), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_025" {
  // Test demonstrates an Element Type Declaration and that th...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (foo*)>\n<!ELEMENT foo (#PCDATA)>\n]>\n<doc><foo/><foo></foo></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Empty({name: \"foo\", attributes: []}), Empty({name: \"foo\", attributes: []}), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_026" {
  // Test demonstrates an Element Type Declaration and that EM...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (foo*)>\n<!ELEMENT foo EMPTY>\n]>\n<doc><foo/><foo></foo></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Empty({name: \"foo\", attributes: []}), Empty({name: \"foo\", attributes: []}), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_027" {
  // Test demonstrates an Element Type Declaration and that AN...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (foo*)>\n<!ELEMENT foo ANY>\n]>\n<doc><foo/><foo></foo></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Empty({name: \"foo\", attributes: []}), Empty({name: \"foo\", attributes: []}), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_028" {
  // Test demonstrates a valid prolog that uses double quotes ...
  let xml = "<?xml version=\"1.0\"?>\n<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"no\")), DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_029" {
  // Test demonstrates a valid prolog that uses single quotes ...
  let xml = "<?xml version='1.0'?>\n<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"no\")), DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_030" {
  // Test demonstrates a valid prolog that contains whitespace...
  let xml = "<?xml version = \"1.0\"?>\n<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"no\")), DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_031" {
  // Test demonstrates a valid EncodingDecl within the prolog.
  let xml = "<?xml version='1.0' encoding=\"UTF-8\"?>\n<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"no\")), DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_032" {
  // Test demonstrates a valid SDDecl within the prolog.
  let xml = "<?xml version='1.0' standalone='yes'?>\n<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"yes\")), DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_033" {
  // Test demonstrates that both a EncodingDecl and SDDecl are...
  let xml = "<?xml version='1.0' encoding=\"UTF-8\" standalone='yes'?>\n<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"yes\")), DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_034" {
  // Test demonstrates the correct syntax for an Empty element...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_035" {
  // Test demonstrates that whitespace is permissible after th...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc />\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_036" {
  // Test demonstrates a valid processing instruction.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n<?pi data?>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), PI(target=\"pi\", data=\"data\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_017a" {
  // Test demonstrates that two apparently wrong Processing In...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc><?pi some data ? > <??></doc>"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), PI(target=\"pi\", data=\"some data ? > <?\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_037" {
  // Test demonstrates a valid comment and that it may appear ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n<!-- comment -->\n\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Comment(\" comment \"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_038" {
  // Test demonstrates a valid comment and that it may appear ...
  let xml = "<!-- comment -->\n<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Comment(\" comment \"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_039" {
  // Test demonstrates a valid processing instruction and that...
  let xml = "<?pi data?>\n<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), PI(target=\"pi\", data=\"data\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_040" {
  // Test demonstrates an Attribute List declaration that uses...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 CDATA #IMPLIED>\n]>\n<doc a1=\"&quot;&lt;&amp;&gt;&apos;\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a1\", \"\\\"<&>'\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_041" {
  // Test demonstrates an Attribute List declaration that uses...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 CDATA #IMPLIED>\n]>\n<doc a1=\"&#65;\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a1\", \"A\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_042" {
  // Test demonstrates an Attribute List declaration that uses...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#00000000000000000000000000000000065;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"A\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_043" {
  // An element's attributes may be declared before its conten...
  let xml = "<!DOCTYPE doc [\n<!ATTLIST doc a1 CDATA #IMPLIED>\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc a1=\"foo\nbar\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a1\", \"foo bar\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_044" {
  // Test demonstrates that the empty-element tag must be use ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (e*)>\n<!ELEMENT e EMPTY>\n<!ATTLIST e a1 CDATA \"v1\" a2 CDATA \"v2\" a3 CDATA #IMPLIED>\n]>\n<doc>\n<e a3=\"v3\"/>\n<e a1=\"w1\"/>\n<e a2=\"w2\" a3=\"v3\"/>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"\\n\"), Empty({name: \"e\", attributes: [(\"a3\", \"v3\")]}), Text(\"\\n\"), Empty({name: \"e\", attributes: [(\"a1\", \"w1\")]}), Text(\"\\n\"), Empty({name: \"e\", attributes: [(\"a2\", \"w2\"), (\"a3\", \"v3\")]}), Text(\"\\n\"), End(\"doc\"), Eof]",
  )
}
