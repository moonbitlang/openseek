///|
test "w3c/not-wf/not_wf_sa_029" {
  // Text may not contain a literal ']]&gt;' sequence.
  let xml = "<doc>abc]]]>def</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_030" {
  // A form feed is not a legal XML character.
  let xml = "<doc>A form feed () is not legal in data</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_031" {
  // A form feed is not a legal XML character.
  let xml = "<doc><?pi a form feed () is not allowed in a pi?></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_032" {
  // A form feed is not a legal XML character.
  let xml = "<doc><!-- a form feed () is not allowed in a comment --></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_033" {
  // An ESC (octal 033) is not a legal XML character.
  let xml = "<doc>abcdef</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_034" {
  // A form feed is not a legal XML character.
  let xml = "<doc>A form-feed is not white space or a name character</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_035" {
  // The '&lt;' character is a markup delimiter and must start...
  let xml = "<doc>1 < 2 but not in XML</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_036" {
  // Text may not appear after the root element.
  let xml = "<doc></doc>\nIllegal data\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_037" {
  // Character references may not appear after the root element.
  let xml = "<doc></doc>\n&#32;\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_038" {
  // Tests the "Unique Att Spec" WF constraint by providing mu...
  let xml = "<doc x=\"foo\" y=\"bar\" x=\"baz\"></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_039" {
  // Tests the Element Type Match WFC - end tag name must matc...
  let xml = "<doc><a></aa></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_040" {
  // Provides two document elements.
  let xml = "<doc></doc>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_041" {
  // Provides two document elements.
  let xml = "<doc/>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_042" {
  // Invalid End Tag
  let xml = "<doc/></doc/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_043" {
  // Provides #PCDATA text after the document element.
  let xml = "<doc/>\nIllegal data\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_044" {
  // Provides two document elements.
  let xml = "<doc/><doc/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_045" {
  // Invalid Empty Element Tag
  let xml = "<doc>\n<a/\n</doc>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_046" {
  // This start (or empty element) tag was not terminated corr...
  let xml = "<doc>\n<a/</a>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_047" {
  // Invalid empty element tag invalid whitespace
  let xml = "<doc>\n<a / >\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_048" {
  // Provides a CDATA section after the root element.
  let xml = "<doc>\n</doc>\n<![CDATA[]]>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_049" {
  // Missing start tag
  let xml = "<doc>\n<a><![CDATA[xyz]]]></a>\n<![CDATA[]]></a>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_050" {
  // Empty document, with no root element.
  let xml = ""
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_051" {
  // CDATA is invalid at top level of document.
  let xml = "<!-- a comment -->\n<![CDATA[]]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_052" {
  // Invalid character reference.
  let xml = "<!-- a comment -->\n&#32;\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_053" {
  // End tag does not match start tag.
  let xml = "<doc></DOC>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_055" {
  // Invalid Document Type Definition format.
  let xml = "<!DOCTYPE doc [\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_056" {
  // Invalid Document Type Definition format - misplaced comment.
  let xml = "<!DOCTYPE doc -- a comment -- []>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_057" {
  // This isn't SGML; comments can't exist in declarations.
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"whatever\" -- a comment -->\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_058" {
  // Invalid character , in ATTLIST enumeration
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 (foo,bar) #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_059" {
  // String literal must be in quotes.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 NMTOKEN v1>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_060" {
  // Invalid type NAME defined in ATTLIST.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 NAME #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_062" {
  // Entity declarations need space after the entity name.
  let xml = "<!DOCTYPE doc [\n<!ENTITY foo\"some text\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_063" {
  // Conditional sections may only appear in the external DTD ...
  let xml = "<!DOCTYPE doc [\n<![INCLUDE[ ]]>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_064" {
  // Space is required between attribute type and default valu...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST e a1 CDATA\"foo\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_065" {
  // Space is required between attribute name and type in &lt;...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1(foo|bar) #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_066" {
  // Required whitespace is missing.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 (foo|bar)#IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_067" {
  // Space is required between attribute type and default valu...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 (foo)\"foo\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_068" {
  // Space is required between NOTATION keyword and list of en...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 NOTATION(foo) #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_070" {
  // XML comments may not contain "-"
  let xml = "<!-- a comment ending with three dashes --->\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_071" {
  // ENTITY can't reference itself directly or indirectly.
  let xml = "<!DOCTYPE doc [\n<!ENTITY e1 \"&e2;\">\n<!ENTITY e2 \"&e3;\">\n<!ENTITY e3 \"&e1;\">\n]>\n<doc>&e1;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_072" {
  // Undefined ENTITY foo.
  let xml = "<doc>&foo;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_073" {
  // Undefined ENTITY f.
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"whatever\">\n]>\n<doc>&f;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_074" {
  // Internal general parsed entities are only well formed if ...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"</foo><foo>\">\n]>\n<doc>\n<foo>&e;</foo>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_075" {
  // ENTITY can't reference itself directly or indirectly.
  let xml = "<!DOCTYPE doc [\n<!ENTITY e1 \"&e2;\">\n<!ENTITY e2 \"&e3;\">\n<!ENTITY e3 \"&e1;\">\n]>\n<doc a=\"&e1;\"></doc>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_076" {
  // Undefined ENTITY foo.
  let xml = "<doc a=\"&foo;\"></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_077" {
  // Undefined ENTITY bar.
  let xml = "<!DOCTYPE doc [\n<!ENTITY foo \"&bar;\">\n]>\n<doc a=\"&foo;\"></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_078" {
  // Undefined ENTITY foo.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA \"&foo;\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_079" {
  // ENTITY can't reference itself directly or indirectly.
  let xml = "<!DOCTYPE doc [\n<!ENTITY e1 \"&e2;\">\n<!ENTITY e2 \"&e3;\">\n<!ENTITY e3 \"&e1;\">\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA \"&e1;\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_080" {
  // ENTITY can't reference itself directly or indirectly.
  let xml = "<!DOCTYPE doc [\n<!ENTITY e1 \"&e2;\">\n<!ENTITY e2 \"&e3;\">\n<!ENTITY e3 \"&e1;\">\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #FIXED \"&e1;\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_085" {
  // Public IDs may not contain "[".
  let xml = "<!DOCTYPE doc PUBLIC \"[\" \"null.ent\">\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_087" {
  // Public IDs may not contain "[".
  let xml = "<!DOCTYPE doc [\n<!NOTATION foo PUBLIC \"[\" \"null.ent\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_088" {
  // Attribute values are terminated by literal quote characte...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #IMPLIED>\n<!ENTITY e '\"'>\n]>\n<doc a=\"&e;></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_090" {
  // Attributes may not contain a literal "&lt;" character; th...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"<foo a='&#60;'></foo>\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_092" {
  // The replacement text of this entity has an illegal refere...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"<foo a='&#38;'></foo>\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_093" {
  // Hexadecimal character references may not use the uppercas...
  let xml = "<doc>&#X58;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_094" {
  // Prolog VERSION must be lowercase.
  let xml = "<?xml VERSION=\"1.0\"?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_095" {
  // VersionInfo must come before EncodingDecl.
  let xml = "<?xml encoding=\"UTF-8\" version=\"1.0\"?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_096" {
  // Space is required before the standalone declaration.
  let xml = "<?xml version=\"1.0\"encoding=\"UTF-8\" ?>\n<doc></doc>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_097" {
  // Both quotes surrounding VersionNum must be the same.
  let xml = "<?xml version=\"1.0' encoding=\"UTF-8\" ?>\n<doc></doc>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_098" {
  // Only one "version=..." string may appear in an XML declar...
  let xml = "<?xml version=\"1.0\" version=\"1.0\"?>\n<doc></doc>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_099" {
  // Only three pseudo-attributes are in the XML declaration, ...
  let xml = "<?xml version=\"1.0\" valid=\"no\" ?>\n<doc></doc>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_100" {
  // Only "yes" and "no" are permitted as values of "standalone".
  let xml = "<?xml version=\"1.0\" standalone=\"YES\" ?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_101" {
  // Space is not permitted in an encoding name.
  let xml = "<?xml version=\"1.0\" encoding=\" UTF-8\"?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_102" {
  // Provides an illegal XML version number; spaces are illegal.
  let xml = "<?xml version=\"1.0 \" ?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_103" {
  // End-tag required for element foo.
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"&#60;foo>\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_104" {
  // Internal general parsed entities are only well formed if ...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"<foo>\">\n]>\n<doc>&e;</foo></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_105" {
  // Invalid placement of CDATA section.
  let xml = "<?pi stuff?>\n<![CDATA[]]>\n<doc>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_106" {
  // Invalid placement of entity declaration.
  let xml = "<?pi data?>\n&#32;<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_107" {
  // Invalid document type declaration. CDATA alone is invalid.
  let xml = "<!DOCTYPE doc [\n<![CDATA[]]>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_108" {
  // No space in '&lt;![CDATA['.
  let xml = "<doc>\n<![CDATA [  ]]>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_109" {
  // Tags invalid within EntityDecl.
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"<doc></doc>\">\n]>\n&e;\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_110" {
  // Entity reference must be in content of element.
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"\">\n]>\n<doc></doc>\n&e;\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_111" {
  // Entiry reference must be in content of element not Start-...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"foo='bar'\">\n]>\n<doc &e;></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_112" {
  // CDATA sections start '&lt;![CDATA[', not '&lt;!cdata['.
  let xml = "<doc>\n<![cdata[data]]>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_113" {
  // Parameter entity values must use valid reference syntax; ...
  let xml = "<!DOCTYPE doc [\n<!ENTITY % foo \"&\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_114" {
  // General entity values must use valid reference syntax; th...
  let xml = "<!DOCTYPE doc [\n<!ENTITY foo \"&\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_115" {
  // The replacement text of this entity is an illegal charact...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"&#38;\">\n]>\n<doc a=\"&e;\"></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_116" {
  // Internal general parsed entities are only well formed if ...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"&#38;#9\">\n]>\n<doc>&e;7;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_117" {
  // Internal general parsed entities are only well formed if ...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"&#38;\">\n]>\n<doc>&e;#97;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_118" {
  // Entity reference expansion is not recursive.
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"#\">\n]>\n<doc>&&e;97;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_119" {
  // Internal general parsed entities are only well formed if ...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"&#38;\">\n]>\n<doc>\n&e;#38;\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_120" {
  // Character references are expanded in the replacement text...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"&#38;\">\n]>\n<doc>\n&e;\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_121" {
  // A name of an ENTITY was started with an invalid character.
  let xml = "<!DOCTYPE doc [\n<!ENTITY #DEFAULT \"default\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_122" {
  // Invalid syntax mixed connectors are used.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (a, (b) | c)?>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_123" {
  // Invalid syntax mismatched parenthesis.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc ((doc?)))>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_124" {
  // Invalid format of Mixed-content declaration.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (doc|#PCDATA)*>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_125" {
  // Invalid syntax extra set of parenthesis not necessary.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc ((#PCDATA))>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_126" {
  // Invalid syntax Mixed-content must be defined as zero or m...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)+>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_127" {
  // Invalid syntax Mixed-content must be defined as zero or m...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)?>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_128" {
  // Invalid CDATA syntax.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc CDATA>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_129" {
  // Invalid syntax for Element Type Declaration.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc - - (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_130" {
  // Invalid syntax for Element Type Declaration.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (doc?) +(foo)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_131" {
  // Invalid syntax for Element Type Declaration.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (doc?) -(foo)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_132" {
  // Invalid syntax mixed connectors used.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (a, (b, c), (d, (e, f) | g))?>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_133" {
  // Illegal whitespace before optional character causes synta...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (a *)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_134" {
  // Illegal whitespace before optional character causes synta...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (a) *>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_135" {
  // Invalid character used as connector.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (a & b)?>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_136" {
  // Tag omission is invalid in XML.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc O O (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_137" {
  // Space is required before a content model.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc(#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_138" {
  // Invalid syntax for content particle.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (doc*?)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_139" {
  // The element-content model should not be empty.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc ()>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_142" {
  // Character #x0000 is not legal anywhere in an XML document.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#0;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_143" {
  // Character #x001F is not legal anywhere in an XML document.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#31;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_144" {
  // Character #xFFFF is not legal anywhere in an XML document.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#xFFFF;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_145" {
  // Character #xD800 is not legal anywhere in an XML document...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#xD800;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_146" {
  // Character references must also refer to legal XML charact...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#x110000;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_147" {
  // XML Declaration may not be preceded by whitespace.
  let xml = "\n<?xml version=\"1.0\"?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_148" {
  // XML Declaration may not be preceded by comments or whites...
  let xml = "<!-- -->\n<?xml version=\"1.0\"?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_149" {
  // XML Declaration may not be within a DTD.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<?xml version=\"1.0\"?>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_150" {
  // XML declarations may not be within element content.
  let xml = "<doc>\n<?xml version=\"1.0\"?>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_151" {
  // XML declarations may not follow document content.
  let xml = "<doc>\n</doc>\n<?xml version=\"1.0\"?>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_152" {
  // XML declarations must include the "version=..." string.
  let xml = "<?xml encoding=\"UTF-8\"?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_153" {
  // Text declarations may not begin internal parsed entities;...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY e \"<?xml encoding='UTF-8'?>\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_154" {
  // '&lt;?XML ...?&gt;' is neither an XML declaration nor a l...
  let xml = "<?XML version=\"1.0\"?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_155" {
  // '&lt;?xmL ...?&gt;' is neither an XML declaration nor a l...
  let xml = "<?xmL version=\"1.0\"?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_156" {
  // '&lt;?xMl ...?&gt;' is neither an XML declaration nor a l...
  let xml = "<doc>\n<?xMl version=\"1.0\"?>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_157" {
  // '&lt;?xmL ...?&gt;' is not a legal processing instruction...
  let xml = "<doc>\n<?xmL?>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_158" {
  // SGML-ism: "#NOTATION gif" can't have attributes.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!NOTATION gif PUBLIC \"image/gif\" \"\">\n<!ATTLIST #NOTATION gif a1 CDATA #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_159" {
  // Uses '&amp;' unquoted in an entity declaration, which is ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY e \"<![CDATA[Tim & Michael]]>\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_160" {
  // Violates the <EM>PEs in Internal Subset</EM> WFC by using...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY % e \"\">\n<!ENTITY foo \"%e;\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_161" {
  // Violates the <EM>PEs in Internal Subset</EM> WFC by using...
  let xml = "<!DOCTYPE doc [\n<!ENTITY % e \"#PCDATA\">\n<!ELEMENT doc (%e;)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_162" {
  // Violates the <EM>PEs in Internal Subset</EM> WFC by using...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY % e1 \"\">\n<!ENTITY % e2 \"%e1;\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_163" {
  // Invalid placement of Parameter entity reference.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY % e \"\">\n]>\n%e;\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_164" {
  // Invalid placement of Parameter entity reference.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY % e \"\">\n] %e; >\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_165" {
  // Parameter entity declarations must have a space before th...
  let xml = "<!DOCTYPE doc [\n<!ENTITY% e \"\">\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_166" {
  // Character FFFF is not legal anywhere in an XML document.
  let xml = "<doc>￿</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_167" {
  // Character FFFE is not legal anywhere in an XML document.
  let xml = "<doc>￾</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_171" {
  // Character FFFF is not legal anywhere in an XML document.
  let xml = "<!-- ￿ -->\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_172" {
  // Character FFFF is not legal anywhere in an XML document.
  let xml = "<?pi ￿?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_173" {
  // Character FFFF is not legal anywhere in an XML document.
  let xml = "<doc a=\"￿\"></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_174" {
  // Character FFFF is not legal anywhere in an XML document.
  let xml = "<doc><![CDATA[￿]]></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_175" {
  // Character FFFF is not legal anywhere in an XML document.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY % e \"￿\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_176" {
  // Start tags must have matching end tags.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_177" {
  // Character FFFF is not legal anywhere in an XML document.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>A￿</doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_178" {
  // Invalid syntax matching double quote is missing.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #IMPLIED>\n]>\n<doc a=\"&#34;></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_179" {
  // Invalid syntax matching double quote is missing.
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"&#34;>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_180" {
  // The <EM>Entity Declared</EM> WFC requires entities to be ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA \"&e;\">\n<!ENTITY e \"v\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_181" {
  // Internal parsed entities must match the <EM>content</EM> ...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"&#60;![CDATA[\">\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&e;]]></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_182" {
  // Internal parsed entities must match the <EM>content</EM> ...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"&#60;!--\">\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&e;--></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_183" {
  // Mixed content declarations may not include content partic...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA | foo*)* >\n<!ELEMENT foo EMPTY>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_184" {
  // In mixed content models, element names must not be parent...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA | (foo))* >\n<!ELEMENT foo EMPTY>\n]>\n<doc></doc>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/not_wf_sa_186" {
  // Whitespace is required between attribute/value pairs.
  let xml = "<!DOCTYPE a [\n<!ELEMENT a EMPTY>\n<!ATTLIST a b CDATA #IMPLIED d CDATA #IMPLIED>\n]>\n<a b=\"c\"d=\"e\"/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/rmt_ns10_035" {
  // Attribute uniqueness: repeated identical attribute
  let xml = "<?xml version=\"1.0\"?>\n<!-- Attribute uniqueness: repeated identical attribute -->\n<foo xmlns:a=\"http://example.org/~wilbur\"\n     xmlns:b=\"http://example.org/~wilbur\">\n\n<bar a:attr=\"1\" a:attr=\"2\"/>\n\n</foo>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/attlist01" {
  // SGML's NUTOKEN is not allowed.
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n\n    <!-- SGML-ism:  illegal attribute types -->\n\n    <!ATTLIST root\n\tnumber\tNUTOKEN\t\"1\"\n\t>\n\n]>\n\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/attlist02" {
  // SGML's NUTOKENS attribute type is not allowed.
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n\n    <!-- SGML-ism:  illegal attribute types -->\n\n    <!ATTLIST root\n\tnumber\tNUTOKENS\t\"1 2 3\"\n\t>\n\n]>\n\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/attlist03" {
  // Comma doesn't separate enumerations, unlike in SGML.
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n\n    <!-- SGML-ism:  illegal attribute types -->\n\n    <!ATTLIST root\n\tchoice\t(a,b,c)\t\"a\"\n\t>\n\n]>\n\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/attlist04" {
  // SGML's NUMBER attribute type is not allowed.
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n\n    <!-- SGML-ism:  illegal attribute types -->\n\n    <!ATTLIST root\n\tnumber\tNUMBER\t\"1\"\n\t>\n\n]>\n\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/attlist05" {
  // SGML's NUMBERS attribute type is not allowed.
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n\n    <!-- SGML-ism:  illegal attribute types -->\n\n    <!ATTLIST root\n\tnumbers\tNUMBERS\t\"1 2 3 4\"\n\t>\n\n]>\n\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/attlist06" {
  // SGML's NAME attribute type is not allowed.
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n\n    <!-- SGML-ism:  illegal attribute types -->\n\n    <!ATTLIST root\n\tnumber\tNAME\t\"Elvis\"\n\t>\n\n]>\n\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/attlist07" {
  // SGML's NAMES attribute type is not allowed.
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n\n    <!-- SGML-ism:  illegal attribute types -->\n\n    <!ATTLIST root\n\tnumber\tNAMES\t\"The King\"\n\t>\n\n]>\n\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/attlist08" {
  // SGML's #CURRENT is not allowed.
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n\n    <!-- SGML-ism:  illegal attribute default -->\n\n    <!ATTLIST root\n\tlanguage\tCDATA\t#CURRENT\n\t>\n\n]>\n\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/attlist09" {
  // SGML's #CONREF is not allowed.
  let xml = "<!DOCTYPE root [\n    <!-- SGML-ism:  illegal attribute default -->\n\n    <!ATTLIST root\n\tlanguage\tCDATA\t#CONREF\n\t>\n\n]>\n\n<root language=\"Dutch\"/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/attlist10" {
  // Whitespace required between attributes
  let xml = "<!DOCTYPE root [\n<!ELEMENT root ANY>\n<!ATTLIST root att1 CDATA #IMPLIED>\n<!ATTLIST root att2 CDATA #IMPLIED>\n]>\n<root att1=\"value1\"att2=\"value2\">\n    <!-- whitespace required between attributes -->\n</root>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/attlist11" {
  // Whitespace required between attributes
  let xml = "<!DOCTYPE root [\n<!ELEMENT root ANY>\n<!ATTLIST root att1 CDATA #IMPLIED>\n<!ATTLIST root att2 CDATA #IMPLIED>\n]>\n<root att1=\"value1\"att2=\"value2\"/>\n    <!-- whitespace required between attributes -->\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/content01" {
  // No whitespace before "?" in content model
  let xml = "<!DOCTYPE root [\n    <!-- no whitespace before '?', '*', '+' -->\n    <!ELEMENT root ((root) ?)>\n]>\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/content02" {
  // No whitespace before "*" in content model
  let xml = "<!DOCTYPE root [\n    <!-- no whitespace before '?', '*', '+' -->\n    <!ELEMENT root ((root) *)>\n]>\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/content03" {
  // No whitespace before "+" in content model
  let xml = "<!DOCTYPE root [\n    <!-- no whitespace before '?', '*', '+' -->\n    <!ELEMENT root (root +)>\n]>\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/nwf_dtd00" {
  // Comma mandatory in content model
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root (foo, bar? foo)>\n\t<!-- comma omitted -->\n    <!ELEMENT foo EMPTY>\n    <!ELEMENT bar EMPTY>\n]>\n\n<root> <foo/> <foo/> </root>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/nwf_dtd01" {
  // Can't mix comma and vertical bar in content models
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root (foo, bar? | foo)>\n\t<!-- comma swapped for vertical bar -->\n    <!ELEMENT foo EMPTY>\n    <!ELEMENT bar EMPTY>\n]>\n\n<root> <foo/> <foo/> </root>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/dtd02" {
  // PE name immediately after "%"
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n    <!-- correct PE ref syntax -->\n    <!ENTITY % foo \"<!ATTLIST root>\">\n    % foo;\n]>\n\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/dtd03" {
  // PE name immediately followed by ";"
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n    <!-- correct PE ref syntax -->\n    <!ENTITY % foo \"<!ATTLIST root>\">\n    %foo\n    ;\n]>\n\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/element00" {
  // EOF in middle of incomplete ETAG
  let xml = "<root>\n    Incomplete end tag.\n</ro"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/element01" {
  // EOF in middle of incomplete ETAG
  let xml = "<root>\n    Incomplete end tag.\n</root"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/element02" {
  // Illegal markup (&lt;%@ ... %&gt;)
  let xml = "<!DOCTYPE html [ <!ELEMENT html ANY> ]>\n<html>\n    <% @ LANGUAGE=\"VBSCRIPT\" %>\n</html>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/element03" {
  // Illegal markup (&lt;% ... %&gt;)
  let xml = "<!DOCTYPE html [ <!ELEMENT html ANY> ]>\n<html>\n    <% document.println (\"hello, world\"); %>\n</html>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/element04" {
  // Illegal markup (&lt;!ELEMENT ... &gt;)
  let xml = "<!DOCTYPE root [ <!ELEMENT root ANY> ]>\n<root>\n    <!ELEMENT foo EMPTY>\n</root>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/encoding01" {
  // Illegal character " " in encoding name
  let xml = "<?xml version=\"1.0\" encoding=\" utf-8\"?>\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/encoding02" {
  // Illegal character "/" in encoding name
  let xml = "<?xml version=\"1.0\" encoding=\"a/b\"?>\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/encoding03" {
  // Illegal character reference in encoding name
  let xml = "<?xml version=\"1.0\" encoding=\"just&#41;word\"?>\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/encoding04" {
  // Illegal character ":" in encoding name
  let xml = "<?xml version=\"1.0\" encoding=\"utf:8\"?>\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/encoding05" {
  // Illegal character "@" in encoding name
  let xml = "<?xml version=\"1.0\" encoding=\"@import(sys-encoding)\"?>\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/encoding06" {
  // Illegal character "+" in encoding name
  let xml = "<?xml version=\"1.0\" encoding=\"XYZ+999\"?>\n\n<!-- WF ... but illegal encoding name, also a fatal error --> \n\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/pi" {
  // No space between PI target name and data
  let xml = "<!DOCTYPE root [\n<!ELEMENT root EMPTY>\n<!-- space before PI data and ?> -->\n<?bad-pi+?>\n]>\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml01" {
  // SGML-ism: omitted end tag for EMPTY content
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n\n    <!-- SGML-ism:  omitted end tag -->\n]>\n\n<root>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml02" {
  // XML declaration must be at the very beginning of a docume...
  let xml = " <?xml version=\"1.0\"?>\n    <!-- SGML-ism:  XML PI not at beginning -->\n<!DOCTYPE root [ <!ELEMENT root EMPTY> ]>\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml03" {
  // Comments may not contain "-"
  let xml = "<!DOCTYPE root [ <!ELEMENT root EMPTY> ]>\n\n    <!-- SGML-ism:  -- inside comment -->\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml04" {
  // ATTLIST declarations apply to only one element, unlike SGML
  let xml = "<!DOCTYPE root [\n    <!-- SGML-ism:  multiple attlist types -->\n\n    <!ELEMENT root EMPTY>\n    <!ELEMENT branch EMPTY>\n\n    <!ATTLIST (root|branch)\n\tTreeType CDATA #REQUIRED\n\t>\n]>\n\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml05" {
  // ELEMENT declarations apply to only one element, unlike SGML
  let xml = "<!DOCTYPE root [\n    <!-- SGML-ism:  multiple element types -->\n\n    <!ELEMENT root EMPTY>\n    <!ELEMENT leaves EMPTY>\n    <!ELEMENT branch EMPTY>\n\n    <!ELEMENT (bush|tree) (root,leaves,branch)>\n]>\n\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml06" {
  // ATTLIST declarations are never global, unlike in SGML
  let xml = "<!DOCTYPE root [\n    <!-- Web-SGML-ism:  global attlist types -->\n\n    <!ELEMENT root EMPTY>\n\n    <!ATTLIST #ALL\n\tTreeType CDATA #REQUIRED\n\t>\n]>\n\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml07" {
  // SGML Tag minimization specifications are not allowed
  let xml = "<!DOCTYPE root [\n    <!-- SGML-ism:  omitted tag minimzation spec -->\n    <!ELEMENT root - o EMPTY>\n]>\n\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml08" {
  // SGML Tag minimization specifications are not allowed
  let xml = "<!DOCTYPE root [\n    <!-- SGML-ism:  omitted tag minimzation spec -->\n    <!ELEMENT root - - EMPTY>\n]>\n\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml09" {
  // SGML Content model exception specifications are not allowed
  let xml = "<!DOCTYPE root [\n    <!-- SGML-ism:  exception spec -->\n\n    <!ELEMENT footnote (para*) -footnote>\n]>\n\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml10" {
  // SGML Content model exception specifications are not allowed
  let xml = "<!DOCTYPE root [\n    <!-- SGML-ism:  exception spec -->\n    <!ELEMENT section (header,(para|section))* +(annotation|todo)>\n]>\n\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml11" {
  // CDATA is not a valid content model spec
  let xml = "<!DOCTYPE root [\n    <!-- SGML-ism:  CDATA content type -->\n    <!ELEMENT ROOT CDATA>\n]>\n\n<root/>\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml12" {
  // RCDATA is not a valid content model spec
  let xml = "<!DOCTYPE root [\n    <!-- SGML-ism:  RCDATA content type -->\n    <!ELEMENT ROOT RCDATA>\n]>\n\n<root/>\n\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/sgml13" {
  // SGML Unordered content models not allowed
  let xml = "<!DOCTYPE root [\n    <!-- SGML-ism:  unordered content type -->\n    <!ELEMENT ROOT (a & b & c)>\n    <!ELEMENT a EMPTY>\n    <!ELEMENT b EMPTY>\n    <!ELEMENT c EMPTY>\n]>\n\n<root><b/><c/><a/></root>\n\n\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/rmt_e2e_61" {
  // (From John Cowan) An encoding declaration in ASCII specif...
  let xml = "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\n<root/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n02_xml" {
  // Tests an element with an illegal NameStartChar: #0x333
  let xml = "<!DOCTYPE ̳IllegalNameStartChar [\n<!ELEMENT ̳IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar P4: #0x333 -->\n<̳IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n03_xml" {
  // Tests an element with an illegal NameStartChar: #0x369
  let xml = "<!DOCTYPE ͩIllegalNameStartChar [\n<!ELEMENT ͩIllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0x369  -->\n<ͩIllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n04_xml" {
  // Tests an element with an illegal NameStartChar: #0x37E
  let xml = "<!DOCTYPE ;IllegalNameStartChar [\n<!ELEMENT ;IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar  #0x37E  -->\n<;IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n05_xml" {
  // Tests an element with an illegal NameStartChar: #0x2000
  let xml = "<!DOCTYPE  IllegalNameStartChar [\n<!ELEMENT  IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #x2000  -->\n< IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n06_xml" {
  // Tests an element with an illegal NameStartChar: #0x2001
  let xml = "<!DOCTYPE  IllegalNameStartChar [\n<!ELEMENT  IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #x2001 -->\n< IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n07_xml" {
  // Tests an element with an illegal NameStartChar: #0x2002
  let xml = "<!DOCTYPE  IllegalNameStartChar [\n<!ELEMENT  IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #x2002 -->\n< IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n08_xml" {
  // Tests an element with an illegal NameStartChar: #0x2005
  let xml = "<!DOCTYPE  IllegalNameStartChar [\n<!ELEMENT  IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #x2005 -->\n< IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n09_xml" {
  // Tests an element with an illegal NameStartChar: #0x200B
  let xml = "<!DOCTYPE ​IllegalNameStartChar [\n<!ELEMENT ​IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0x200B -->\n<​IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n10_xml" {
  // Tests an element with an illegal NameStartChar: #0x200E
  let xml = "<!DOCTYPE ‎IllegalNameStartChar [\n<!ELEMENT ‎IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0x200E -->\n<‎IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n11_xml" {
  // Tests an element with an illegal NameStartChar: #0x200F
  let xml = "<!DOCTYPE ‏IllegalNameStartChar [\n<!ELEMENT ‏IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0x200F  -->\n<‏IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n12_xml" {
  // Tests an element with an illegal NameStartChar: #0x2069
  let xml = "<!DOCTYPE ⁩IllegalNameStartChar [\n<!ELEMENT ⁩IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0x2069 -->\n<⁩IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n13_xml" {
  // Tests an element with an illegal NameStartChar: #0x2190
  let xml = "<!DOCTYPE ←IllegalNameStartChar [\n<!ELEMENT ←IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0x2190 -->\n<←IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n14_xml" {
  // Tests an element with an illegal NameStartChar: #0x23FF
  let xml = "<!DOCTYPE ⏿IllegalNameStartChar [\n<!ELEMENT ⏿IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #x23FF -->\n<⏿IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n15_xml" {
  // Tests an element with an illegal NameStartChar: #0x280F
  let xml = "<!DOCTYPE ⠏IllegalNameStartChar [\n<!ELEMENT ⠏IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0x280F  -->\n<⠏IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n16_xml" {
  // Tests an element with an illegal NameStartChar: #0x2A00
  let xml = "<!DOCTYPE ⨀IllegalNameStartChar [\n<!ELEMENT ⨀IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0x2A00 -->\n<⨀IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n17_xml" {
  // Tests an element with an illegal NameStartChar: #0x2EDC
  let xml = "<!DOCTYPE ⬀IllegalNameStartChar [\n<!ELEMENT ⬀IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0x2B00  -->\n<⬀IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n18_xml" {
  // Tests an element with an illegal NameStartChar: #0x2B00
  let xml = "<!DOCTYPE ⯿IllegalNameStartChar [\n<!ELEMENT ⯿IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar x2BFF \nin p02:   -->\n<⯿IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n19_xml" {
  // Tests an element with an illegal NameStartChar: #0x2BFF
  let xml = "<!DOCTYPE ⿿IllegalNameStartChar [\n<!ELEMENT ⿿IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0x2FFF -->\n<⿿IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n20_xml" {
  // Tests an element with an illegal NameStartChar: #0x3000
  let xml = "<!DOCTYPE 　IllegalNameStartChar [\n<!ELEMENT 　IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0x3000 -->\n<　IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n21_xml" {
  // Tests an element with an illegal NameStartChar: #0xD800
  let xml = "<!DOCTYPE í IllegalNameStartChar [\n<!ELEMENT í IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0xD800 -->\n<í IllegalNameStartChar/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n22_xml" {
  // Tests an element with an illegal NameStartChar: #0xD801
  let xml = "<!DOCTYPE í IllegalNameStartChar [\n<!ELEMENT í IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0xD801 -->\n<í IllegalNameStartChar/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n23_xml" {
  // Tests an element with an illegal NameStartChar: #0xDAFF
  let xml = "<!DOCTYPE í«¿IllegalNameStartChar [\n<!ELEMENT í«¿IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0xDAFF -->\n<í«¿IllegalNameStartChar/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n24_xml" {
  // Tests an element with an illegal NameStartChar: #0xDFFF
  let xml = "<!DOCTYPE í¿¿IllegalNameStartChar [\n<!ELEMENT í¿¿IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0xDFFF -->\n<í¿¿IllegalNameStartChar/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n25_xml" {
  // Tests an element with an illegal NameStartChar: #0xEFFF
  let xml = "<!DOCTYPE IllegalNameStartChar [\n<!ELEMENT IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0xEFFF -->\n<IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n26_xml" {
  // Tests an element with an illegal NameStartChar: #0xF1FF
  let xml = "<!DOCTYPE IllegalNameStartChar [\n<!ELEMENT IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0xF1FF -->\n<IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n27_xml" {
  // Tests an element with an illegal NameStartChar: #0xF8FF
  let xml = "<!DOCTYPE IllegalNameStartChar [\n<!ELEMENT IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0xF8FF -->\n<IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04_ibm04n28_xml" {
  // Tests an element with an illegal NameStartChar: #0xFFFFF
  let xml = "<!DOCTYPE ￿IllegalNameStartChar [\n<!ELEMENT ￿IllegalNameStartChar ANY>\n]>\n<!-- IllegalNameStartChar #0xFFFFF -->\n<￿IllegalNameStartChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an01_xml" {
  // Tests an element with an illegal NameChar: #xB8
  let xml = "<!DOCTYPE IllegalNameChar¸ [\n<!ELEMENT IllegalNameChar¸ ANY>\n]>\n<!-- IllegalNameChar #xB8 -->\n<IllegalNameChar¸/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an02_xml" {
  // Tests an element with an illegal NameChar: #0xA1
  let xml = "<!DOCTYPE IllegalNameChar¡ [\n<!ELEMENT IllegalNameChar¡ ANY>\n]>\n<!-- IllegalNameChar #0xA1 -->\n<IllegalNameChar¡/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an03_xml" {
  // Tests an element with an illegal NameChar: #0xAF
  let xml = "<!DOCTYPE IllegalNameChar¯ [\n<!ELEMENT IllegalNameChar¯ ANY>\n]>\n<!-- IllegalNameChar #0xAF   -->\n<IllegalNameChar¯/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an04_xml" {
  // Tests an element with an illegal NameChar: #0x37E
  let xml = "<!DOCTYPE IllegalNameChar; [\n<!ELEMENT IllegalNameChar; ANY>\n]>\n<!-- IllegalNameChar #0x37E -->\n<IllegalNameChar;/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an05_xml" {
  // Tests an element with an illegal NameChar: #0x2000
  let xml = "<!DOCTYPE IllegalNameChar  [\n<!ELEMENT IllegalNameChar  ANY>\n]>\n<!-- IllegalNameChar #0x2000 -->\n<IllegalNameChar />"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an06_xml" {
  // Tests an element with an illegal NameChar: #0x2001
  let xml = "<!DOCTYPE IllegalNameChar  [\n<!ELEMENT IllegalNameChar  ANY>\n]>\n<!-- IllegalNameChar #0x2001 -->\n<IllegalNameChar />"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an07_xml" {
  // Tests an element with an illegal NameChar: #0x2002
  let xml = "<!DOCTYPE IllegalNameChar  [\n<!ELEMENT IllegalNameChar  ANY>\n]>\n<!-- IllegalNameChar #0x2002 -->\n<IllegalNameChar />"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an08_xml" {
  // Tests an element with an illegal NameChar: #0x2005
  let xml = "<!DOCTYPE IllegalNameChar  [\n<!ELEMENT IllegalNameChar  ANY>\n]>\n<!-- IllegalNameChar #0x2005 -->\n<IllegalNameChar />"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an09_xml" {
  // Tests an element with an illegal NameChar: #0x200B
  let xml = "<!DOCTYPE IllegalNameChar​ [\n<!ELEMENT IllegalNameChar​ ANY>\n]>\n<!-- IllegalNameChar #0x200B -->\n<IllegalNameChar​/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an10_xml" {
  // Tests an element with an illegal NameChar: #0x200E
  let xml = "<!DOCTYPE IllegalNameChar‎ [\n<!ELEMENT IllegalNameChar‎ ANY>\n]>\n<!-- IllegalNameChar #0x200E -->\n<IllegalNameChar‎/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an11_xml" {
  // Tests an element with an illegal NameChar: #0x2038
  let xml = "<!DOCTYPE IllegalNameChar‽ [\n<!ELEMENT IllegalNameChar‽ ANY>\n]>\n<!-- IllegalNameChar #0x2038 -->\n<IllegalNameChar‽/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an12_xml" {
  // Tests an element with an illegal NameChar: #0x2041
  let xml = "<!DOCTYPE IllegalNameChar⁁ [\n<!ELEMENT IllegalNameChar⁁ ANY>\n]>\n<!-- IllegalNameChar #0x2041 -->\n<IllegalNameChar⁁/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an13_xml" {
  // Tests an element with an illegal NameChar: #0x2190
  let xml = "<!DOCTYPE IllegalNameChar← [\n<!ELEMENT IllegalNameChar← ANY>\n]>\n<!-- IllegalNameChar #0x2190 -->\n<IllegalNameChar←/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an14_xml" {
  // Tests an element with an illegal NameChar: #0x23FF
  let xml = "<!DOCTYPE IllegalNameChar⏿ [\n<!ELEMENT IllegalNameChar⏿ ANY>\n]>\n<!-- IllegalNameChar #0x23FF -->\n<IllegalNameChar⏿/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an15_xml" {
  // Tests an element with an illegal NameChar: #0x280F
  let xml = "<!DOCTYPE IllegalNameChar⠏ [\n<!ELEMENT IllegalNameChar⠏ ANY>\n]>\n<!-- IllegalNameChar #0x280F -->\n<IllegalNameChar⠏/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an16_xml" {
  // Tests an element with an illegal NameChar: #0x2A00
  let xml = "<!DOCTYPE IllegalNameChar⨀ [\n<!ELEMENT IllegalNameChar⨀ ANY>\n]>\n<!-- IllegalNameChar #0x2A00 -->\n<IllegalNameChar⨀/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an17_xml" {
  // Tests an element with an illegal NameChar: #0xFDD0
  let xml = "<!DOCTYPE IllegalNameChar﷐ [\n<!ELEMENT IllegalNameChar﷐ ANY>\n]>\n<!-- IllegalNameChar #0xFDD0 -->\n<IllegalNameChar﷐/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an18_xml" {
  // Tests an element with an illegal NameChar: #0xFDEF
  let xml = "<!DOCTYPE IllegalNameChar﷯ [\n<!ELEMENT IllegalNameChar﷯ ANY>\n]>\n<!-- IllegalNameChar #0xFDEF -->\n<IllegalNameChar﷯/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an19_xml" {
  // Tests an element with an illegal NameChar: #0x2FFF
  let xml = "<!DOCTYPE IllegalNameChar⿿ [\n<!ELEMENT IllegalNameChar⿿ ANY>\n]>\n<!-- IllegalNameChar #0x2FFF -->\n<IllegalNameChar⿿/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an20_xml" {
  // Tests an element with an illegal NameChar: #0x3000
  let xml = "<!DOCTYPE IllegalNameChar　 [\n<!ELEMENT IllegalNameChar　 ANY>\n]>\n<!-- IllegalNameChar  #0x3000 -->\n<IllegalNameChar　/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an21_xml" {
  // Tests an element with an illegal NameChar: #0xD800
  let xml = "<!DOCTYPE IllegalNameCharí  [\n<!ELEMENT IllegalNameCharí  ANY>\n]>\n<!-- IllegalNameChar #0xD800 -->\n<IllegalNameCharí />\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an22_xml" {
  // Tests an element with an illegal NameChar: #0xD801
  let xml = "<!DOCTYPE IllegalNameCharí  [\n<!ELEMENT IllegalNameCharí  ANY>\n]>\n<!-- IllegalNameChar #0xD801 -->\n<IllegalNameCharí />\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an23_xml" {
  // Tests an element with an illegal NameChar: #0xDAFF
  let xml = "<!DOCTYPE IllegalNameCharí«¿ [\n<!ELEMENT IllegalNameCharí«¿ ANY>\n]>\n<!-- IllegalNameChar #0xDAFF -->\n<IllegalNameCharí«¿/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an24_xml" {
  // Tests an element with an illegal NameChar: #0xDFFF
  let xml = "<!DOCTYPE IllegalNameCharí¿¿ [\n<!ELEMENT IllegalNameCharí¿¿ ANY>\n]>\n<!-- IllegalNameChar #0xDFFF -->\n<IllegalNameCharí¿¿/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an25_xml" {
  // Tests an element with an illegal NameChar: #0xEFFF
  let xml = "<!DOCTYPE IllegalNameChar [\n<!ELEMENT IllegalNameChar ANY>\n]>\n<!-- IllegalNameChar #0xEFFF -->\n<IllegalNameChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an26_xml" {
  // Tests an element with an illegal NameChar: #0xF1FF
  let xml = "<!DOCTYPE IllegalNameChar [\n<!ELEMENT IllegalNameChar ANY>\n]>\n<!-- IllegalNameChar #0xF1FF -->\n<IllegalNameChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an27_xml" {
  // Tests an element with an illegal NameChar: #0xF8FF
  let xml = "<!DOCTYPE IllegalNameChar [\n<!ELEMENT IllegalNameChar ANY>\n]>\n<!-- IllegalNameChar #0xF8FF -->\n<IllegalNameChar/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P04a_ibm04an28_xml" {
  // Tests an element with an illegal NameChar: #0xFFFFF
  let xml = "<!DOCTYPE IllegalNameChar￿ [\n<!ELEMENT IllegalNameChar￿ ANY>\n]>\n<!-- IllegalNameChar #0xFFFFF -->\n<IllegalNameChar￿/>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P05_ibm05n01_xml" {
  // Tests an element with an illegal Name containing #0x0B
  let xml = "<!DOCTYPE root [\n<!ELEMENT root ANY>\n<!ELEMENT BadName EMPTY>\n]>\n<!-- BadName containing char 0x0B; -->\n<root>\n\t<BadName/>\t\n</root>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P05_ibm05n02_xml" {
  // Tests an element with an illegal Name containing #0x300
  let xml = "<!DOCTYPE root [\n<!ELEMENT root ANY>\n<!ELEMENT ̀BadName EMPTY>\n]>\n<!-- BadName containing char 0x300; -->\n<root>\n\t<̀BadName/>\t\n</root>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P05_ibm05n03_xml" {
  // Tests an element with an illegal Name containing #0x36F
  let xml = "<!DOCTYPE root [\n<!ELEMENT root ANY>\n<!ELEMENT ͯBadName EMPTY>\n]>\n<!-- BadName containing char 0x36F; -->\n<root>\n\t<ͯBadName/>\t\n</root>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P05_ibm05n04_xml" {
  // Tests an element with an illegal Name containing #0x203F
  let xml = "<!DOCTYPE root [\n<!ELEMENT root ANY>\n<!ELEMENT ‿BadName EMPTY>\n]>\n<!-- BadName containing char 0x203F; -->\n<root>\n\t<‿BadName/>\t\n</root>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P05_ibm05n05_xml" {
  // Tests an element with an illegal Name containing #x2040
  let xml = "<!DOCTYPE root [\n<!ELEMENT root ANY>\n<!ELEMENT ⁀BadName EMPTY>\n]>\n<!-- BadName containing char #x2040; -->\n<root>\n\t<⁀BadName/>\t\n</root>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/x_ibm_1_0_5_not_wf_P05_ibm05n06_xml" {
  // Tests an element with an illegal Name containing #0xB7
  let xml = "<!DOCTYPE root [\n<!ELEMENT root ANY>\n<!ELEMENT ·BadName EMPTY>\n]>\n<!-- BadName containing char 0xB7; -->\n<root>\n\t<·BadName/>\t\n</root>"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/hst_bh_001" {
  // decimal charref > 10FFFF, indeed > max 32 bit integer, ch...
  let xml = "<!DOCTYPE p [\n<!ELEMENT p (#PCDATA)>\n]>\n<p>Fa&#xFF000000F6;il</p>          <!-- 32 bit integer overflow -->\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/hst_bh_002" {
  // hex charref > 10FFFF, indeed > max 32 bit integer, checki...
  let xml = "<!DOCTYPE p [\n<!ELEMENT p (#PCDATA)>\n]>\n<p>Fa&#4294967542;il</p>           <!-- 32 bit integer overflow -->\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/hst_bh_003" {
  // decimal charref > 10FFFF, indeed > max 64 bit integer, ch...
  let xml = "<!DOCTYPE p [\n<!ELEMENT p (#PCDATA)>\n]>\n<p>Fa&#xFFFFFFFF000000F6;il</p>    <!-- 64 bit integer overflow -->\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/hst_bh_004" {
  // hex charref > 10FFFF, indeed > max 64 bit integer, checki...
  let xml = "<!DOCTYPE p [\n<!ELEMENT p (#PCDATA)>\n]>\n<p>Fa&#18446744073709551862;il</p> <!-- 64 bit integer overflow -->\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/not-wf/hst_lhs_009" {
  // UTF-16 BOM plus xml decl of utf-8 (using UTF-8 coding) in...
  let xml = "þÿ<?xml encoding='utf-8'?><x/>\n"
  let reader = Reader::from_string(xml)
  let has_error = (try? reader.read_events_until_eof()) is Err(_)
  assert_true(has_error)
}

///|
test "w3c/valid/valid_sa_045" {
  // Tests whether more than one definition can be provided fo...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 CDATA \"v1\">\n<!ATTLIST doc a1 CDATA \"z1\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_046" {
  // Test demonstrates that when more than one AttlistDecl is ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 CDATA \"v1\">\n<!ATTLIST doc a2 CDATA \"v2\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_047" {
  // Test demonstrates that extra whitespace is normalized int...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>X\nY</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"X\\nY\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_048" {
  // Test demonstrates that character data is valid element co...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>]</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"]\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_052" {
  // The document is encoded in UTF-8 and the text inside the ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>𐀀􏿽</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"𐀀􏿽\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_053" {
  // Tests inclusion of a well-formed internal entity, which h...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"<e/>\">\n<!ELEMENT doc (e)>\n<!ELEMENT e EMPTY>\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Empty({name: \"e\", attributes: []}), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_054" {
  // Test demonstrates that extra whitespace within Start-tags...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n\n\n<doc\n></doc\n>\n\n\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_055" {
  // Test demonstrates that extra whitespace within a processi...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<?pi  data?>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), PI(target=\"pi\", data=\"data\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_056" {
  // Test demonstrates an Attribute List declaration that uses...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#x0000000000000000000000000000000000000041;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"A\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_057" {
  // Test demonstrates an element content model whose element ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (a*)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_058" {
  // Test demonstrates that extra whitespace be normalized int...
  let xml = "<!DOCTYPE doc [\n<!ATTLIST doc a1 NMTOKENS #IMPLIED>\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc a1=\" 1  \t2 \t\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a1\", \"1 2\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_059" {
  // Test demonstrates an Element Type Declaration that uses t...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (e*)>\n<!ELEMENT e EMPTY>\n<!ATTLIST e a1 CDATA #IMPLIED a2 CDATA #IMPLIED a3 CDATA #IMPLIED>\n]>\n<doc>\n<e a1=\"v1\" a2=\"v2\" a3=\"v3\"/>\n<e a1=\"w1\" a2=\"v2\"/>\n<e a1=\"v1\" a2=\"w2\" a3=\"v3\"/>\n</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"\\n\"), Empty({name: \"e\", attributes: [(\"a1\", \"v1\"), (\"a2\", \"v2\"), (\"a3\", \"v3\")]}), Text(\"\\n\"), Empty({name: \"e\", attributes: [(\"a1\", \"w1\"), (\"a2\", \"v2\")]}), Text(\"\\n\"), Empty({name: \"e\", attributes: [(\"a1\", \"v1\"), (\"a2\", \"w2\"), (\"a3\", \"v3\")]}), Text(\"\\n\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_060" {
  // Test demonstrates the use of decimal Character References...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>X&#10;Y</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"X\\nY\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_061" {
  // Test demonstrates the use of decimal Character References...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#163;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"£\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_062" {
  // Test demonstrates the use of hexadecimal Character Refere...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#xe40;&#xe08;&#xe21;ส์</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"เจมส์\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_063" {
  // The document is encoded in UTF-8 and the name of the root...
  let xml = "<!DOCTYPE เจมส์ [\n<!ELEMENT เจมส์ (#PCDATA)>\n]>\n<เจมส์></เจมส์>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"เจมส์\"), Empty({name: \"เจมส์\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_064" {
  // Tests in-line handling of two legal character references,...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#x10000;&#x10FFFD;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"𐀀􏿽\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_065" {
  // Tests ability to define an internal entity which can't le...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"&#60;\">\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_066" {
  // Expands a CDATA attribute with a character reference.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 CDATA #IMPLIED>\n<!-- 34 is double quote -->\n<!ENTITY e1 \"&#34;\">\n]>\n<doc a1=\"&e1;\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Comment(\" 34 is double quote \"), Empty({name: \"doc\", attributes: [(\"a1\", \"\\\"\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_067" {
  // Test demonstrates the use of decimal character references...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#13;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"\\r\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_068" {
  // Tests definition of an internal entity holding a carriage...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY e \"&#13;\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"\\n\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_069" {
  // Verifies that an XML parser will parse a NOTATION declara...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!NOTATION n PUBLIC \"whatever\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_071" {
  // Test demonstrates that an AttlistDecl can use ID as the T...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a ID #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_072" {
  // Test demonstrates that an AttlistDecl can use IDREF as th...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a IDREF #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_073" {
  // Test demonstrates that an AttlistDecl can use IDREFS as t...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a IDREFS #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_074" {
  // Test demonstrates that an AttlistDecl can use ENTITY as t...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a ENTITY #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_075" {
  // Test demonstrates that an AttlistDecl can use ENTITIES as...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a ENTITIES #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_076" {
  // Verifies that an XML parser will parse a NOTATION attribu...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a NOTATION (n1|n2) #IMPLIED>\n<!NOTATION n1 SYSTEM \"http://www.w3.org/\">\n<!NOTATION n2 SYSTEM \"http://www.w3.org/\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_077" {
  // Test demonstrates that an AttlistDecl can use an Enumerat...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a (1|2) #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_078" {
  // Test demonstrates that an AttlistDecl can use an StringTy...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #REQUIRED>\n]>\n<doc a=\"v\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a\", \"v\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_079" {
  // Test demonstrates that an AttlistDecl can use an StringTy...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #FIXED \"v\">\n]>\n<doc a=\"v\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a\", \"v\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_080" {
  // Test demonstrates that an AttlistDecl can use an StringTy...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #FIXED \"v\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_081" {
  // Test demonstrates the use of the optional character follo...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (a, b, c)>\n<!ELEMENT a (a?)>\n<!ELEMENT b (b*)>\n<!ELEMENT c (a | b)+>\n]>\n<doc><a/><b/><c><a/></c></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Empty({name: \"a\", attributes: []}), Empty({name: \"b\", attributes: []}), Start({name: \"c\", attributes: []}), Empty({name: \"a\", attributes: []}), End(\"c\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_084" {
  // Test demonstrates that although whitespace can be used to...
  let xml = "<!DOCTYPE doc [<!ELEMENT doc (#PCDATA)>]><doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_085" {
  // Parameter and General entities use different namespaces, ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY % e \"<foo>\">\n<!ENTITY e \"\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_086" {
  // Tests whether entities may be declared more than once, wi...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY e \"\">\n<!ENTITY e \"<foo>\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_087" {
  // Tests whether character references in internal entities a...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"<foo/&#62;\">\n<!ELEMENT doc (foo)>\n<!ELEMENT foo EMPTY>\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Empty({name: \"foo\", attributes: []}), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_088" {
  // Tests whether entity references in internal entities are ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY e \"&lt;foo>\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"<foo>\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_089" {
  // Tests entity expansion of three legal character reference...
  let xml = "<!DOCTYPE doc [\n<!ENTITY e \"&#x10000;&#x10FFFD;&#x10FFFF;\">\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"𐀀􏿽􏿿\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_090" {
  // Verifies that an XML parser will parse a NOTATION attribu...
  let xml = "<!DOCTYPE doc [\n<!ATTLIST e a NOTATION (n) #IMPLIED>\n<!ELEMENT doc (e)*>\n<!ELEMENT e (#PCDATA)>\n<!NOTATION n PUBLIC \"whatever\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_092" {
  // Test demostrates that extra whitespace is normalized into...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (a)*>\n<!ELEMENT a EMPTY>\n]>\n<doc>\n<a/>\n    <a/>\t<a/>\n\n\n</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"\\n\"), Empty({name: \"a\", attributes: []}), Text(\"\\n    \"), Empty({name: \"a\", attributes: []}), Text(\"\\t\"), Empty({name: \"a\", attributes: []}), Text(\"\\n\\n\\n\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_093" {
  // Test demonstrates that extra whitespace is not intended f...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>\n\n\n</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"\\n\\n\\n\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_094" {
  // Attribute defaults with a DTD have special parsing rules,...
  let xml = "<!DOCTYPE doc [\n<!ENTITY % e \"foo\">\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a1 CDATA \"%e;\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_095" {
  // Basically an output test, this requires extra whitespace ...
  let xml = "<!DOCTYPE doc [\n<!ATTLIST doc a1 CDATA #IMPLIED>\n<!ATTLIST doc a1 NMTOKENS #IMPLIED>\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc a1=\"1  2\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a1\", \"1  2\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_096" {
  // Test demonstrates that extra whitespace is normalized int...
  let xml = "<!DOCTYPE doc [\n<!ATTLIST doc a1 NMTOKENS \" 1  \t2 \t\">\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_098" {
  // Test demonstrates that extra whitespace within a processi...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc><?pi x\ny?></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), PI(target=\"pi\", data=\"x\\ny\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_099" {
  // Test demonstrates the name of the encoding can be compose...
  let xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"utf-8\"), standalone=Some(\"no\")), DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_101" {
  // This tests whether entity expansion is (incorrectly) done...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY e \"&#34;\">\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_102" {
  // Test demonstrates that a CDATA attribute can pass a doubl...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #IMPLIED>\n]>\n<doc a=\"&#34;\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a\", \"\\\"\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_103" {
  // Test demonstrates that an attribute can pass a less than ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc>&#60;doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"<doc>\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_104" {
  // Test demonstrates that extra whitespace within an Attribu...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #IMPLIED>\n]>\n<doc a=\"x\ty\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a\", \"x y\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_105" {
  // Basically an output test, this requires a CDATA attribute...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #IMPLIED>\n]>\n<doc a=\"x&#9;y\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a\", \"x\\ty\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_106" {
  // Basically an output test, this requires a CDATA attribute...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #IMPLIED>\n]>\n<doc a=\"x&#10;y\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a\", \"x\\ny\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_107" {
  // Basically an output test, this requires a CDATA attribute...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #IMPLIED>\n]>\n<doc a=\"x&#13;y\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a\", \"x\\ry\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_108" {
  // This tests normalization of end-of-line characters (CRLF)...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY e \"\n\">\n<!ATTLIST doc a CDATA #IMPLIED>\n]>\n<doc a=\"x&e;y\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a\", \"x y\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_109" {
  // Test demonstrates that an attribute can have a null value.
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a CDATA #IMPLIED>\n]>\n<doc a=\"\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a\", \"\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_110" {
  // Basically an output test, this requires that a CDATA attr...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY e \"&#13;&#10;\">\n<!ATTLIST doc a CDATA #IMPLIED>\n]>\n<doc a=\"x&e;y\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a\", \"x  y\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_111" {
  // Character references expanding to spaces doesn't affect t...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST doc a NMTOKENS #IMPLIED>\n]>\n<doc a=\"&#32;x&#32;&#32;y&#32;\"></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: [(\"a\", \"x y\")]}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_112" {
  // Test demonstrates shows the use of content particles with...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (a | b)>\n<!ELEMENT a (#PCDATA)>\n]>\n<doc><a></a></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Empty({name: \"a\", attributes: []}), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_113" {
  // Test demonstrates that it is not an error to have attribu...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ATTLIST e a CDATA #IMPLIED>\n]>\n<doc></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Empty({name: \"doc\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_114" {
  // Test demonstrates that all text within a valid CDATA sect...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY e \"<![CDATA[&foo;]]>\">\n]>\n<doc>&e;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"&foo;\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_115" {
  // Test demonstrates that an entity reference is processed b...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY e1 \"&e2;\">\n<!ENTITY e2 \"v\">\n]>\n<doc>&e1;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"v\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_116" {
  // Test demonstrates that a line break within CDATA will be ...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n]>\n<doc><![CDATA[\n]]></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"\\n\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_117" {
  // Test demonstrates that entity expansion is done while pro...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY rsqb \"]\">\n]>\n<doc>&rsqb;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"]\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_118" {
  // Test demonstrates that entity expansion is done while pro...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc (#PCDATA)>\n<!ENTITY rsqb \"]]\">\n]>\n<doc>&rsqb;</doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Text(\"]]\"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/valid_sa_119" {
  // Comments may contain any legal XML characters; only the s...
  let xml = "<!DOCTYPE doc [\n<!ELEMENT doc ANY>\n]>\n<doc><!-- -á --></doc>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"doc\"), Start({name: \"doc\", attributes: []}), Comment(\" -á \"), End(\"doc\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_ns10_001" {
  // Namespace name test: a perfectly good http URI
  let xml = "<?xml version=\"1.0\"?>\n<!-- Namespace name test: a perfectly good http URI -->\n<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n<!ATTLIST foo xmlns CDATA #IMPLIED>\n]>\n<foo xmlns=\"http://example.org/namespace\"/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"no\")), DocType(\"foo\"), Comment(\" Namespace name test: a perfectly good http URI \"), Empty({name: \"foo\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/rmt_ns10_002" {
  // Namespace name test: a syntactically plausible URI with a...
  let xml = "<?xml version=\"1.0\"?>\n<!-- Namespace name test: a syntactically plausible URI with a \n     fictitious scheme -->\n<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n<!ATTLIST foo xmlns CDATA #IMPLIED>\n]>\n<foo xmlns=\"zarquon://example.org/namespace\"/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"no\")), DocType(\"foo\"), Comment(\" Namespace name test: a syntactically plausible URI with a \\n     fictitious scheme \"), Empty({name: \"foo\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/rmt_ns10_003" {
  // Namespace name test: a perfectly good http URI with a fra...
  let xml = "<?xml version=\"1.0\"?>\n<!-- Namespace name test: a perfectly good http URI with a fragment -->\n<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n<!ATTLIST foo xmlns CDATA #IMPLIED>\n]>\n<foo xmlns=\"http://example.org/namespace#apples\"/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"no\")), DocType(\"foo\"), Comment(\" Namespace name test: a perfectly good http URI with a fragment \"), Empty({name: \"foo\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/rmt_ns10_007" {
  // Namespace inequality test: different capitalization
  let xml = "<?xml version=\"1.0\"?>\n<!-- Namespace inequality test: different capitalization -->\n<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n<!ATTLIST foo xmlns:a CDATA #IMPLIED\n              xmlns:b CDATA #IMPLIED\n              xmlns:c CDATA #IMPLIED>\n<!ELEMENT bar ANY>\n<!ATTLIST bar a:attr CDATA #IMPLIED\n              b:attr CDATA #IMPLIED\n              c:attr CDATA #IMPLIED>\n]>\n<foo xmlns:a=\"http://example.org/wine\"\n     xmlns:b=\"http://Example.org/wine\"\n     xmlns:c=\"http://example.org/Wine\">\n\n<bar a:attr=\"1\" b:attr=\"2\" c:attr=\"3\"/>\n\n</foo>\n\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"no\")), DocType(\"foo\"), Comment(\" Namespace inequality test: different capitalization \"), Start({name: \"foo\", attributes: []}), Text(\"\\n\\n\"), Empty({name: \"bar\", attributes: [(\"attr\", \"1\"), (\"attr\", \"2\"), (\"attr\", \"3\")]}), Text(\"\\n\\n\"), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_ns10_008" {
  // Namespace inequality test: different escaping
  let xml = "<?xml version=\"1.0\"?>\n<!-- Namespace inequality test: different escaping -->\n<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n<!ATTLIST foo xmlns:a CDATA #IMPLIED\n              xmlns:b CDATA #IMPLIED\n              xmlns:c CDATA #IMPLIED>\n<!ELEMENT bar ANY>\n<!ATTLIST bar a:attr CDATA #IMPLIED\n              b:attr CDATA #IMPLIED\n              c:attr CDATA #IMPLIED>\n]>\n<foo xmlns:a=\"http://example.org/~wilbur\"\n     xmlns:b=\"http://example.org/%7ewilbur\"\n     xmlns:c=\"http://example.org/%7Ewilbur\">\n\n<bar a:attr=\"1\" b:attr=\"2\" c:attr=\"3\"/>\n\n</foo>\n\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"no\")), DocType(\"foo\"), Comment(\" Namespace inequality test: different escaping \"), Start({name: \"foo\", attributes: []}), Text(\"\\n\\n\"), Empty({name: \"bar\", attributes: [(\"attr\", \"1\"), (\"attr\", \"2\"), (\"attr\", \"3\")]}), Text(\"\\n\\n\"), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/ht_ns10_047" {
  // Reserved name: _not_ an error
  let xml = "<!DOCTYPE xml:foo [\n<!ELEMENT xml:foo EMPTY>\n]>\n<xml:foo/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Empty({name: \"foo\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ht_ns10_048" {
  // Reserved name: _not_ an error
  let xml = "<!DOCTYPE x [\n<!ELEMENT x EMPTY>\n<!ATTLIST x xml:foo CDATA #IMPLIED>\n]>\n<x xml:foo=\"\"/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"x\"), Empty({name: \"x\", attributes: [(\"foo\", \"\")]}), Eof]",
  )
}

///|
test "w3c/valid/dtd00" {
  // Tests parsing of alternative forms of text-only mixed con...
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n    <!ELEMENT x (#PCDATA)>\n    <!ELEMENT y (#PCDATA)*>\n]>\n\n<root/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Empty({name: \"root\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/dtd01" {
  // Comments don't get parameter entity expansion
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n    <!ENTITY % PE \"this is a PE\">\n    <!-- %these; %are; %not; %PEs; -->\n]>\n<root/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Comment(\" %these; %are; %not; %PEs; \"), Empty({name: \"root\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/element" {
  // Tests clauses 1, 3, and 4 of the Element Valid validity c...
  let xml = "<!DOCTYPE root [\n<!ELEMENT root ANY>\n<!ELEMENT empty EMPTY>\n<!ELEMENT mixed1 (#PCDATA)>\n<!ELEMENT mixed2 (#PCDATA)*>\n<!ELEMENT mixed3 (#PCDATA|empty)*>\n]>\n\n<root>\n    <empty/>\n\n    <mixed1/>\n    <mixed1></mixed1>\n\n    <mixed2/>\n    <mixed2></mixed2>\n\n    <mixed3/>\n    <mixed3></mixed3>\n\n    <mixed1>allowed</mixed1>\n    <mixed1><![CDATA[<allowed>]]></mixed1>\n\n    <mixed2>also</mixed2>\n    <mixed2><![CDATA[<% illegal otherwise %>]]></mixed2>\n\n    <mixed3>moreover</mixed3>\n\n    <mixed1>allowed &amp; stuff</mixed1>\n\n    <mixed2>also</mixed2>\n\n    <mixed3>moreover <empty></empty> </mixed3>\n    <mixed3>moreover <empty/> </mixed3>\n    <mixed3><empty/> </mixed3>\n    <mixed3><empty/> too</mixed3>\n\n</root>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Start({name: \"root\", attributes: []}), Text(\"\\n    \"), Empty({name: \"empty\", attributes: []}), Text(\"\\n\\n    \"), Empty({name: \"mixed1\", attributes: []}), Text(\"\\n    \"), Empty({name: \"mixed1\", attributes: []}), Text(\"\\n\\n    \"), Empty({name: \"mixed2\", attributes: []}), Text(\"\\n    \"), Empty({name: \"mixed2\", attributes: []}), Text(\"\\n\\n    \"), Empty({name: \"mixed3\", attributes: []}), Text(\"\\n    \"), Empty({name: \"mixed3\", attributes: []}), Text(\"\\n\\n    \"), Start({name: \"mixed1\", attributes: []}), Text(\"allowed\"), End(\"mixed1\"), Text(\"\\n    \"), Start({name: \"mixed1\", attributes: []}), Text(\"<allowed>\"), End(\"mixed1\"), Text(\"\\n\\n    \"), Start({name: \"mixed2\", attributes: []}), Text(\"also\"), End(\"mixed2\"), Text(\"\\n    \"), Start({name: \"mixed2\", attributes: []}), Text(\"<% illegal otherwise %>\"), End(\"mixed2\"), Text(\"\\n\\n    \"), Start({name: \"mixed3\", attributes: []}), Text(\"moreover\"), End(\"mixed3\"), Text(\"\\n\\n    \"), Start({name: \"mixed1\", attributes: []}), Text(\"allowed & stuff\"), End(\"mixed1\"), Text(\"\\n\\n    \"), Start({name: \"mixed2\", attributes: []}), Text(\"also\"), End(\"mixed2\"), Text(\"\\n\\n    \"), Start({name: \"mixed3\", attributes: []}), Text(\"moreover \"), Empty({name: \"empty\", attributes: []}), Text(\" \"), End(\"mixed3\"), Text(\"\\n    \"), Start({name: \"mixed3\", attributes: []}), Text(\"moreover \"), Empty({name: \"empty\", attributes: []}), Text(\" \"), End(\"mixed3\"), Text(\"\\n    \"), Start({name: \"mixed3\", attributes: []}), Empty({name: \"empty\", attributes: []}), Text(\" \"), End(\"mixed3\"), Text(\"\\n    \"), Start({name: \"mixed3\", attributes: []}), Empty({name: \"empty\", attributes: []}), Text(\" too\"), End(\"mixed3\"), Text(\"\\n\\n\"), End(\"root\"), Eof]",
  )
}

///|
test "w3c/valid/required00" {
  // Tests the #REQUIRED attribute declaration syntax, and the...
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n    <!ATTLIST root\n\treq CDATA #REQUIRED\n\t>\n]>\n\n<root req=\"foo\"/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Empty({name: \"root\", attributes: [(\"req\", \"foo\")]}), Eof]",
  )
}

///|
test "w3c/valid/sa01" {
  // A document may be marked 'standalone' if any optional whi...
  let xml = "<?xml version='1.0' standalone='yes'?>\n\n<!DOCTYPE root [\n    <!ELEMENT root (child)*>\n    <!ELEMENT child (#PCDATA)>\n]>\n\n<root>\n    <child>\n    The whitespace around this element would be\n    invalid as standalone were the DTD external.\n    </child>\n</root>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.0\", encoding=Some(\"UTF-8\"), standalone=Some(\"yes\")), DocType(\"root\"), Start({name: \"root\", attributes: []}), Text(\"\\n    \"), Start({name: \"child\", attributes: []}), Text(\"\\n    The whitespace around this element would be\\n    invalid as standalone were the DTD external.\\n    \"), End(\"child\"), Text(\"\\n\"), End(\"root\"), Eof]",
  )
}

///|
test "w3c/valid/v_sgml01" {
  // XML permits token reuse, while SGML does not.
  let xml = "<!DOCTYPE root [\n    <!ELEMENT root EMPTY>\n    <!--\n\tSGML dislikes token reuse.  It's legal XML, so any\n\tXML parser must accept it, though it's discouraged\n\tin documents \"for interoperability\"\n    -->\n    <!ATTLIST root\n\tstatus\t\t(initial-draft|revision|final) \"initial-draft\"\n\tposition\t(first|intermediate|final) \"first\"\n\t>\n]>\n\n<root/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Comment(\"\\n\\tSGML dislikes token reuse.  It's legal XML, so any\\n\\tXML parser must accept it, though it's discouraged\\n\\tin documents \\\"for interoperability\\\"\\n    \"), Empty({name: \"root\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/v_lang01" {
  // Tests a lowercase ISO language code.
  let xml = "<!DOCTYPE root [\n<!ELEMENT root EMPTY>\n<!ATTLIST root xml:lang CDATA #IMPLIED>\n]>\n<root xml:lang=\"en\"/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Empty({name: \"root\", attributes: [(\"lang\", \"en\")]}), Eof]",
  )
}

///|
test "w3c/valid/v_lang02" {
  // Tests a ISO language code with a subcode.
  let xml = "<!DOCTYPE root [\n<!ELEMENT root EMPTY>\n<!ATTLIST root xml:lang CDATA #IMPLIED>\n]>\n<root xml:lang=\"en-IN\"/>\n\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Empty({name: \"root\", attributes: [(\"lang\", \"en-IN\")]}), Eof]",
  )
}

///|
test "w3c/valid/v_lang03" {
  // Tests a IANA language code with a subcode.
  let xml = "<!DOCTYPE root [\n<!ELEMENT root EMPTY>\n<!ATTLIST root xml:lang CDATA #IMPLIED>\n]>\n<root xml:lang=\"i-klingon-whorf\"/>\n\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Empty({name: \"root\", attributes: [(\"lang\", \"i-klingon-whorf\")]}), Eof]",
  )
}

///|
test "w3c/valid/v_lang04" {
  // Tests a user language code with a subcode.
  let xml = "<!DOCTYPE root [\n<!ELEMENT root EMPTY>\n<!ATTLIST root xml:lang CDATA #IMPLIED>\n]>\n<root xml:lang=\"x-dialect-valleygirl\"/>\n\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Empty({name: \"root\", attributes: [(\"lang\", \"x-dialect-valleygirl\")]}), Eof]",
  )
}

///|
test "w3c/valid/v_lang05" {
  // Tests an uppercase ISO language code.
  let xml = "<!DOCTYPE root [\n<!ELEMENT root EMPTY>\n<!ATTLIST root xml:lang CDATA #IMPLIED>\n]>\n<root xml:lang=\"DE\"/>\n\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Empty({name: \"root\", attributes: [(\"lang\", \"DE\")]}), Eof]",
  )
}

///|
test "w3c/valid/v_lang06" {
  // Tests a user language code.
  let xml = "<!DOCTYPE root [\n<!ELEMENT root EMPTY>\n<!ATTLIST root xml:lang CDATA #IMPLIED>\n]>\n<root xml:lang=\"X-Java\"/>\n\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Empty({name: \"root\", attributes: [(\"lang\", \"X-Java\")]}), Eof]",
  )
}

///|
test "w3c/valid/v_pe03" {
  // Tests construction of internal entity replacement text, u...
  let xml = "<!DOCTYPE root [\n<!ELEMENT root (p)>\n<!ELEMENT p (#PCDATA)>\n<!-- Example 1 from XML spec 1.0 Appendix D -->\n<!ENTITY example \"<p>An ampersand (&#38;#38;) may be escaped\nnumerically (&#38;#38;#38) or with a general entity (&amp;amp;).</p>\" >\n]>\n<root>&example;</root>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"root\"), Comment(\" Example 1 from XML spec 1.0 Appendix D \"), Start({name: \"root\", attributes: []}), Start({name: \"p\", attributes: []}), Text(\"An ampersand (&) may be escaped\\nnumerically (&#38) or with a general entity (&amp;).\"), End(\"p\"), End(\"root\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_e2e_15e" {
  // Element content can contain entity reference if replaceme...
  let xml = "<!DOCTYPE foo [\n<!ELEMENT foo (foo*)>\n<!ENTITY space \" \">\n]>\n<foo><foo/>&space;<foo/></foo>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Start({name: \"foo\", attributes: []}), Empty({name: \"foo\", attributes: []}), Text(\" \"), Empty({name: \"foo\", attributes: []}), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_e2e_15f" {
  // Element content can contain entity reference if replaceme...
  let xml = "<!DOCTYPE foo [\n<!ELEMENT foo (foo*)>\n<!ENTITY space \"&#32;\">\n]>\n<foo><foo/>&space;<foo/></foo>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Start({name: \"foo\", attributes: []}), Empty({name: \"foo\", attributes: []}), Text(\" \"), Empty({name: \"foo\", attributes: []}), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_e2e_15i" {
  // Element content can contain a comment
  let xml = "<!DOCTYPE foo [\n<!ELEMENT foo (foo*)>\n]>\n<foo><foo/><!-- comment --><foo/></foo>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Start({name: \"foo\", attributes: []}), Empty({name: \"foo\", attributes: []}), Comment(\" comment \"), Empty({name: \"foo\", attributes: []}), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_e2e_15j" {
  // Element content can contain a PI
  let xml = "<!DOCTYPE foo [\n<!ELEMENT foo (foo*)>\n]>\n<foo><foo/><?pi xxx?><foo/></foo>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Start({name: \"foo\", attributes: []}), Empty({name: \"foo\", attributes: []}), PI(target=\"pi\", data=\"xxx\"), Empty({name: \"foo\", attributes: []}), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_e2e_15k" {
  // Mixed content can contain a comment
  let xml = "<!DOCTYPE foo [\n<!ELEMENT foo (PCDATA|foo)*>\n]>\n<foo><foo/><!-- comment --><foo/></foo>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Start({name: \"foo\", attributes: []}), Empty({name: \"foo\", attributes: []}), Comment(\" comment \"), Empty({name: \"foo\", attributes: []}), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_e2e_15l" {
  // Mixed content can contain a PI
  let xml = "<!DOCTYPE foo [\n<!ELEMENT foo (PCDATA|foo)*>\n]>\n<foo><foo/><?pi xxx?><foo/></foo>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Start({name: \"foo\", attributes: []}), Empty({name: \"foo\", attributes: []}), PI(target=\"pi\", data=\"xxx\"), Empty({name: \"foo\", attributes: []}), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_e2e_22" {
  // UTF-8 entities may start with a BOM
  let xml = "﻿<?xml version=\"1.0\"?>\n<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n]>\n<foo/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Empty({name: \"foo\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/rmt_e2e_24" {
  // Either the built-in entity or a character reference can b...
  let xml = "<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n<!ENTITY gt \">\">\n]>\n<foo>You can use ]]&gt; or ]]&#62;</foo>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Start({name: \"foo\", attributes: []}), Text(\"You can use ]]> or ]]>\"), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_e2e_29" {
  // Three-letter language codes are allowed
  let xml = "<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n<!ATTLIST foo xml:lang NMTOKEN #IMPLIED>\n]>\n<foo xml:lang=\"nds\">\n <foo xml:lang=\"art-lojban\"/>\n</foo>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Start({name: \"foo\", attributes: [(\"lang\", \"nds\")]}), Text(\"\\n \"), Empty({name: \"foo\", attributes: [(\"lang\", \"art-lojban\")]}), Text(\"\\n\"), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_e2e_41" {
  // An xml:lang attribute may be empty
  let xml = "<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n<!ATTLIST foo xml:lang CDATA #IMPLIED>\n]>\n<foo xml:lang=\"\"/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Empty({name: \"foo\", attributes: [(\"lang\", \"\")]}), Eof]",
  )
}

///|
test "w3c/valid/rmt_e2e_48" {
  // ANY content allows character data
  let xml = "<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n]>\n<foo>hello</foo>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Start({name: \"foo\", attributes: []}), Text(\"hello\"), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_e3e_05a" {
  // CDATA sections may occur in Mixed content.
  let xml = "<!-- CDATA sections may occur in Mixed content. -->\n<!DOCTYPE foo [\n<!ELEMENT foo (#PCDATA|foo)*>\n]>\n<foo>a <![CDATA[cdata section]]> in mixed content</foo>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Comment(\" CDATA sections may occur in Mixed content. \"), Start({name: \"foo\", attributes: []}), Text(\"a cdata section in mixed content\"), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/rmt_e3e_05b" {
  // CDATA sections, comments and PIs may occur in ANY content.
  let xml = "<!-- CDATA sections, comments and PIs may occur in ANY content. -->\n<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n]>\n<foo>\na <![CDATA[cdata section]]> in mixed content.\na <!-- comment --> in mixed content.\na <?processing instruction?> in mixed content.\n</foo>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"foo\"), Comment(\" CDATA sections, comments and PIs may occur in ANY content. \"), Start({name: \"foo\", attributes: []}), Text(\"\\na cdata section in mixed content.\\na \"), Comment(\" comment \"), Text(\" in mixed content.\\na \"), PI(target=\"processing\", data=\"instruction\"), Text(\" in mixed content.\\n\"), End(\"foo\"), Eof]",
  )
}

///|
test "w3c/valid/x_rmt_008b" {
  // a document with version=1.7, legal in XML 1.0 from 5th ed...
  let xml = "<?xml version=\"1.7\"?>\n<!-- an implausibly-versioned document -->\n<!DOCTYPE foo [\n<!ELEMENT foo ANY>\n]>\n<foo/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[Decl(version=\"1.7\", encoding=Some(\"UTF-8\"), standalone=Some(\"no\")), DocType(\"foo\"), Comment(\" an implausibly-versioned document \"), Empty({name: \"foo\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/x_rmt5_014a" {
  // Has a "long s" in a name, legal in XML 1.1, legal in XML ...
  let xml = "<!-- Has a \"long s\" in an ID, legal in XML 1.1, illegal in XML 1.0 -->\n<!DOCTYPE egg [\n<!ELEMENT egg EMPTY>\n<!ATTLIST egg id ID #REQUIRED>\n]>\n<egg id=\"eggſ\"/>\n\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"egg\"), Comment(\" Has a \\\"long s\\\" in an ID, legal in XML 1.1, illegal in XML 1.0 \"), Empty({name: \"egg\", attributes: [(\"id\", \"eggſ\")]}), Eof]",
  )
}

///|
test "w3c/valid/x_ibm_1_0_5_valid_P04_ibm04v01_xml" {
  // This test case covers legal NameStartChars character rang...
  let xml = "<!DOCTYPE LegalNameStartChar [\n<!ELEMENT LegalNameStartChar ANY>\n<!ELEMENT :LegalNameStartChar ANY>\n<!ELEMENT ÀLegalNameStartChar ANY>\n<!ELEMENT ÁLegalNameStartChar ANY>\n<!ELEMENT ˾LegalNameStartChar ANY>\n<!ELEMENT ˿LegalNameStartChar ANY>\n<!ELEMENT ͰLegalNameStartChar ANY>\n<!ELEMENT ͱLegalNameStartChar ANY>\n<!ELEMENT ͼLegalNameStartChar ANY>\n<!ELEMENT ͽLegalNameStartChar ANY>\n<!ELEMENT ͿLegalNameStartChar ANY>\n<!ELEMENT ΀LegalNameStartChar ANY>\n<!ELEMENT ῾LegalNameStartChar ANY>\n<!ELEMENT ῿LegalNameStartChar ANY>\n<!ELEMENT ‌LegalNameStartChar ANY>\n<!ELEMENT ‍LegalNameStartChar ANY>\n<!ELEMENT ⁰LegalNameStartChar ANY>\n<!ELEMENT ⁱLegalNameStartChar ANY>\n<!ELEMENT ↎LegalNameStartChar ANY>\n<!ELEMENT ↏LegalNameStartChar ANY>\n<!ELEMENT ⰀLegalNameStartChar ANY>\n<!ELEMENT ⰁLegalNameStartChar ANY>\n<!ELEMENT ⿮LegalNameStartChar ANY>\n<!ELEMENT ⿯LegalNameStartChar ANY>\n<!ELEMENT 、LegalNameStartChar ANY>\n<!ELEMENT 。LegalNameStartChar ANY>\n<!ELEMENT ퟾LegalNameStartChar ANY>\n<!ELEMENT ퟿LegalNameStartChar ANY>\n<!ELEMENT 豈LegalNameStartChar ANY>\n<!ELEMENT 更LegalNameStartChar ANY>\n]>\n<!-- LegalNameChar  0x3A,0xC0,,0xC1,0x2FE,0xC0,,0xC1,0x2FE,0x2FF,0x370,0x371,0x37C,0x37D,0x37F,0x380,0x1FFE,0x1FFF,0x200C,0x200D,0x2070,0x2071,0x218E,0x218F,0x2C00,0x2C01,0x2FEE,0x2FEF,0x3001,0x3002,0xD7FE,0xD7FF,0xF900,0xF901,0xEFFFF,0xFFFFF\nin p02:   -->\n<LegalNameStartChar>\t<:LegalNameStartChar/>\n\t<ÀLegalNameStartChar/>\n\t<ÁLegalNameStartChar/>\n\t<˾LegalNameStartChar/>\n\t<˿LegalNameStartChar/>\n\t<ͰLegalNameStartChar/>\n\t<ͱLegalNameStartChar/>\n\t<ͼLegalNameStartChar/>\n\t<ͽLegalNameStartChar/>\n\t<ͿLegalNameStartChar/>\n\t<΀LegalNameStartChar/>\n\t<῾LegalNameStartChar/>\n\t<῿LegalNameStartChar/>\n\t<‌LegalNameStartChar/>\n\t<‍LegalNameStartChar/>\n\t<⁰LegalNameStartChar/>\n\t<ⁱLegalNameStartChar/>\n\t<↎LegalNameStartChar/>\n\t<↏LegalNameStartChar/>\n\t<ⰀLegalNameStartChar/>\n\t<ⰁLegalNameStartChar/>\n\t<⿮LegalNameStartChar/>\n\t<⿯LegalNameStartChar/>\n\t<、LegalNameStartChar/>\n\t<。LegalNameStartChar/>\n\t<퟾LegalNameStartChar/>\n\t<퟿LegalNameStartChar/>\n\t<豈LegalNameStartChar/>\n\t<更LegalNameStartChar/>\n\n</LegalNameStartChar>"
  let reader = Reader::from_string(xml)
  // Verify parsing succeeds
  let events = reader.read_events_until_eof()
  assert_true(events.length() > 0)
}

///|
test "w3c/valid/x_ibm_1_0_5_valid_P04_ibm04av01_xml" {
  // This test case covers legal NameChars character ranges pl...
  let xml = "<!DOCTYPE LegalNameChar [\n<!ELEMENT LegalNameChar ANY>\n<!ELEMENT LegalNameCharÀ ANY>\n<!ELEMENT LegalNameCharÁ ANY>\n<!ELEMENT LegalNameChar˾ ANY>\n<!ELEMENT LegalNameCharÂ ANY>\n<!ELEMENT LegalNameCharÃ ANY>\n<!ELEMENT LegalNameChar˽ ANY>\n<!ELEMENT LegalNameChar˿ ANY>\n<!ELEMENT LegalNameCharͰ ANY>\n<!ELEMENT LegalNameCharͱ ANY>\n<!ELEMENT LegalNameCharͼ ANY>\n<!ELEMENT LegalNameCharͽ ANY>\n<!ELEMENT LegalNameCharͿ ANY>\n<!ELEMENT LegalNameChar΀ ANY>\n<!ELEMENT LegalNameChar῾ ANY>\n<!ELEMENT LegalNameChar῿ ANY>\n<!ELEMENT LegalNameChar‌ ANY>\n<!ELEMENT LegalNameChar‍ ANY>\n<!ELEMENT LegalNameChar⁰ ANY>\n<!ELEMENT LegalNameCharⁱ ANY>\n<!ELEMENT LegalNameChar↎ ANY>\n<!ELEMENT LegalNameChar↏ ANY>\n<!ELEMENT LegalNameCharⰀ ANY>\n<!ELEMENT LegalNameCharⰁ ANY>\n<!ELEMENT LegalNameChar⿮ ANY>\n<!ELEMENT LegalNameChar⿯ ANY>\n<!ELEMENT LegalNameChar、 ANY>\n<!ELEMENT LegalNameChar。 ANY>\n<!ELEMENT LegalNameChar퟾ ANY>\n<!ELEMENT LegalNameChar퟿ ANY>\n<!ELEMENT LegalNameChar豈 ANY>\n<!ELEMENT LegalNameChar更 ANY>\n<!ELEMENT LegalNameChar� ANY>\n<!ELEMENT LegalNameChar- ANY>\n<!ELEMENT LegalNameChar. ANY>\n<!ELEMENT LegalNameCharA ANY>\n<!ELEMENT LegalNameCharz ANY>\n<!ELEMENT LegalNameChar0 ANY>\n<!ELEMENT LegalNameChar· ANY>\n<!ELEMENT LegalNameChar̀ ANY>\n<!ELEMENT LegalNameChaŕ ANY>\n<!ELEMENT LegalNameCharͮ ANY>\n<!ELEMENT LegalNameCharͯ ANY>\n<!ELEMENT LegalNameChar‿ ANY>\n<!ELEMENT LegalNameChar⁀ ANY>\n]>\n<!-- LegalNameChars ending with\n0x003A, 0x00C0, 0x00C1, 0x02FE, 0x00C2, 0x00C3, 0x02FD, 0x02FF, 0x0370, 0x0371, 0x037C, 0x037D, 0x037F, 0x0380, 0x1FFE, 0x1FFF, 0x200C, 0x200D, 0x2070, 0x2071, 0x218E, 0x218F, 0x2C00, 0x2C01, 0x2FEE, 0x2FEF, 0x3001, 0x3002, 0xD7FE, 0xD7FF, 0xF900, 0xF901, 0xFFFD, 0x002D, 0x002E, 0x0041, 0x007A, 0x0030, 0x00B7, 0x0300, 0x0301, 0x036E, 0x036F, 0x203F, 0x2040\n-->\n<LegalNameChar>\t\n\t<LegalNameCharÀ/>\n\t<LegalNameCharÁ/>\n\t<LegalNameChar˾/>\n\t<LegalNameCharÂ/>\n\t<LegalNameCharÃ/>\n\t<LegalNameChar˽/>\n\t<LegalNameChar˿/>\n\t<LegalNameCharͰ/>\n\t<LegalNameCharͱ/>\n\t<LegalNameCharͼ/>\n\t<LegalNameCharͽ/>\n\t<LegalNameCharͿ/>\n\t<LegalNameChar΀/>\n\t<LegalNameChar῾/>\n\t<LegalNameChar῿/>\n\t<LegalNameChar‌/>\n\t<LegalNameChar‍/>\n\t<LegalNameChar⁰/>\n\t<LegalNameCharⁱ/>\n\t<LegalNameChar↎/>\n\t<LegalNameChar↏/>\n\t<LegalNameCharⰀ/>\n\t<LegalNameCharⰁ/>\n\t<LegalNameChar⿮/>\n\t<LegalNameChar⿯/>\n\t<LegalNameChar、/>\n\t<LegalNameChar。/>\n\t<LegalNameChar퟾/>\n\t<LegalNameChar퟿/>\n\t<LegalNameChar豈/>\n\t<LegalNameChar更/>\n\t<LegalNameChar�/>\n\t<LegalNameChar-/>\n\t<LegalNameChar./>\n\t<LegalNameCharA/>\n\t<LegalNameCharz/>\n\t<LegalNameChar0/>\n\t<LegalNameChar·/>\n\t<LegalNameChar̀/>\n\t<LegalNameChaŕ/>\n\t<LegalNameCharͮ/>\n\t<LegalNameCharͯ/>\n\t<LegalNameChar‿/>\n\t<LegalNameChar⁀/>\n</LegalNameChar>"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"LegalNameChar\"), Comment(\" LegalNameChars ending with\\n0x003A, 0x00C0, 0x00C1, 0x02FE, 0x00C2, 0x00C3, 0x02FD, 0x02FF, 0x0370, 0x0371, 0x037C, 0x037D, 0x037F, 0x0380, 0x1FFE, 0x1FFF, 0x200C, 0x200D, 0x2070, 0x2071, 0x218E, 0x218F, 0x2C00, 0x2C01, 0x2FEE, 0x2FEF, 0x3001, 0x3002, 0xD7FE, 0xD7FF, 0xF900, 0xF901, 0xFFFD, 0x002D, 0x002E, 0x0041, 0x007A, 0x0030, 0x00B7, 0x0300, 0x0301, 0x036E, 0x036F, 0x203F, 0x2040\\n\"), Start({name: \"LegalNameChar\", attributes: []}), Text(\"\\t\\n\\t\"), Empty({name: \"LegalNameCharÀ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharÁ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar˾\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharÂ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharÃ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar˽\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar˿\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharͰ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharͱ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharͼ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharͽ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharͿ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar΀\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar῾\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar῿\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar‌\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar‍\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar⁰\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharⁱ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar↎\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar↏\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharⰀ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharⰁ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar⿮\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar⿯\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar、\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar。\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar퟾\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar퟿\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar豈\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar更\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar�\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar-\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar.\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharA\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharz\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar0\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar·\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar̀\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChaŕ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharͮ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameCharͯ\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar‿\", attributes: []}), Text(\"\\n\\t\"), Empty({name: \"LegalNameChar⁀\", attributes: []}), Text(\"\\n\"), End(\"LegalNameChar\"), Eof]",
  )
}

///|
test "w3c/valid/x_ibm_1_0_5_valid_P05_ibm05v01_xml" {
  // This test case covers legal Element Names as per producti...
  let xml = "<!DOCTYPE LegalName [\n<!ELEMENT LegalName ANY>\n<!ELEMENT LegalName: ANY>\n<!ELEMENT LegalNameÀ ANY>\n<!ELEMENT LegalNameÁ ANY>\n<!ELEMENT LegalName˾ ANY>\n<!ELEMENT LegalNameÂ ANY>\n<!ELEMENT LegalNameÃ ANY>\n<!ELEMENT LegalName˽ ANY>\n<!ELEMENT LegalName˿ ANY>\n<!ELEMENT LegalNameͰ ANY>\n<!ELEMENT LegalNameͱ ANY>\n<!ELEMENT LegalNameͼͽ ANY>\n<!ELEMENT LegalNameͽͿ ANY>\n<!ELEMENT LegalNameͿ΀ ANY>\n<!ELEMENT LegalName΀῾ ANY>\n<!ELEMENT LegalName῾῿ ANY>\n<!ELEMENT LegalName῿‌ ANY>\n<!ELEMENT LegalName‌‍ ANY>\n<!ELEMENT LegalName‍⁰ ANY>\n<!ELEMENT LegalName⁰ⁱ ANY>\n<!ELEMENT LegalNameⁱ↎ ANY>\n<!ELEMENT LegalName↎↏Ⰰ ANY>\n<!ELEMENT LegalName↏ⰀⰁ ANY>\n<!ELEMENT LegalNameⰀⰁ⿮ ANY>\n<!ELEMENT LegalNameⰁ⿮⿯ ANY>\n<!ELEMENT LegalName⿮⿯、 ANY>\n<!ELEMENT LegalName⿯、。 ANY>\n<!ELEMENT LegalName、。퟾ ANY>\n<!ELEMENT LegalName。퟾퟿ ANY>\n<!ELEMENT LegalName퟾퟿豈 ANY>\n<!ELEMENT LegalName퟿豈更 ANY>\n<!ELEMENT LegalName豈퟿퟾。 ANY>\n<!ELEMENT LegalName更豈퟿퟾ ANY>\n<!ELEMENT LegalName�更豈퟿ ANY>\n<!ELEMENT LegalName-�更豈 ANY>\n<!ELEMENT LegalName.-�更 ANY>\n<!ELEMENT LegalNameA.-� ANY>\n<!ELEMENT LegalNamezA.- ANY>\n<!ELEMENT LegalName0zA. ANY>\n<!ELEMENT LegalName·0zA ANY>\n<!ELEMENT LegalNamè·0z ANY>\n<!ELEMENT LegalNamé̀·0 ANY>\n<!ELEMENT LegalNameͮ́̀· ANY>\n<!ELEMENT LegalNameͯͮ́̀ ANY>\n<!ELEMENT LegalName‿ͯͮ́ ANY>\n<!ELEMENT LegalName⁀‿ͯͮ ANY>\n<!ELEMENT LegalNamenull⁀‿ͯ ANY>\n<!ELEMENT LegalNamenullnull⁀‿ ANY>\n<!ELEMENT LegalNamenullnullnull⁀ ANY>\n]>\n<!-- LegalName  0x300,0x333,0x369,0x37E,0x2000,0x2001,0x2002,0x2005,0x200B,0x200E,x200F,0x2069,0x2190,0x23FF,0x280F,0x2A00,0x2EDC,0x2FED,0x2FFF,0x3000,0xD800,0xD801,0xDAFF,0xDFFF,0xEFFF,0xF1FF,0xF8FF,0xFFFFF,0x2D,0x2E, 0x41,0x7A ,0x30, 0xB7, 0x0300, 0x0301, 0xx036E, 0x036F, 0x203F, 0x203E, 0x2039, 0x2040; \nin p02:   -->\n<LegalName>\t<LegalName:/>\n\t<LegalNameÀ/>\n\t<LegalNameÁ/>\n\t<LegalName˾/>\n\t<LegalNameÂ/>\n\t<LegalNameÃ/>\n\t<LegalName˽/>\n\t<LegalName˿/>\n\t<LegalNameͰ/>\n\t<LegalNameͱ/>\n\t<LegalNameͼͽ/>\n\t<LegalNameͽͿ/>\n\t<LegalNameͿ΀/>\n\t<LegalName΀῾/>\n\t<LegalName῾῿/>\n\t<LegalName῿‌/>\n\t<LegalName‌‍/>\n\t<LegalName‍⁰/>\n\t<LegalName⁰ⁱ/>\n\t<LegalNameⁱ↎/>\n\t<LegalName↎↏Ⰰ/>\n\t<LegalName↏ⰀⰁ/>\n\t<LegalNameⰀⰁ⿮/>\n\t<LegalNameⰁ⿮⿯/>\n\t<LegalName⿮⿯、/>\n\t<LegalName⿯、。/>\n\t<LegalName、。퟾/>\n\t<LegalName。퟾퟿/>\n\t<LegalName퟾퟿豈/>\n\t<LegalName퟿豈更/>\n\t<LegalName豈퟿퟾。/>\n\t<LegalName更豈퟿퟾/>\n\t<LegalName�更豈퟿/>\n\t<LegalName-�更豈/>\n\t<LegalName.-�更/>\n\t<LegalNameA.-�/>\n\t<LegalNamezA.-/>\n\t<LegalName0zA./>\n\t<LegalName·0zA/>\n\t<LegalNamè·0z/>\n\t<LegalNamé̀·0/>\n\t<LegalNameͮ́̀·/>\n\t<LegalNameͯͮ́̀/>\n\t<LegalName‿ͯͮ́/>\n\t<LegalName⁀‿ͯͮ/>\n\t<LegalNamenull⁀‿ͯ/>\n\t<LegalNamenullnull⁀‿/>\n\t<LegalNamenullnullnull⁀/>\n</LegalName>"
  let reader = Reader::from_string(xml)
  // Verify parsing succeeds
  let events = reader.read_events_until_eof()
  assert_true(events.length() > 0)
}

///|
test "w3c/valid/x_ibm_1_0_5_valid_P05_ibm05v02_xml" {
  // This test case covers legal PITarget (Names) as per produ...
  let xml = "<!DOCTYPE LegalName [\n<!ELEMENT LegalName ANY>\n]>\n<!-- Legal Names containing one to four characters in order from the list below  used in PI Target Names.  x003A, 0x00C0, 0x00C1, 0x02FE, 0x00C2, 0x00C3, 0x02FD, 0x02FF, 0x0370, 0x0371, 0x037C, 0x037D, 0x037F, 0x0380, 0x1FFE, 0x1FFF, 0x200C, 0x200D, 0x2070, 0x2071, 0x218E, 0x218F, 0x2C00, 0x2C01, 0x2FEE, 0x2FEF, 0x3001, 0x3002, 0xD7FE, 0xD7FF, 0xF900, 0xF901, 0xFFFD, 0x002D, 0x002E, 0x0041, 0x007A, 0x0030, 0x00B7, 0x0300, 0x0301, 0x036E, 0x036F, 0x203F, 0x2040 -->\n<LegalName>\n\t<?PITarget: \tTest\t PIData?>\n\t<?PITargetÀ \tTest\t PIData?>\n\t<?PITargetÁ \tTest\t PIData?>\n\t<?PITarget˾ \tTest\t PIData?>\n\t<?PITargetÂ \tTest\t PIData?>\n\t<?PITargetÃ \tTest\t PIData?>\n\t<?PITarget˽ \tTest\t PIData?>\n\t<?PITarget˿ \tTest\t PIData?>\n\t<?PITargetͰ \tTest\t PIData?>\n\t<?PITargetͱ \tTest\t PIData?>\n\t<?PITargetͼͽ \tTest\t PIData?>\n\t<?PITargetͽͿ \tTest\t PIData?>\n\t<?PITargetͿ΀ \tTest\t PIData?>\n\t<?PITarget΀῾ \tTest\t PIData?>\n\t<?PITarget῾῿ \tTest\t PIData?>\n\t<?PITarget῿‌ \tTest\t PIData?>\n\t<?PITarget‌‍ \tTest\t PIData?>\n\t<?PITarget‍⁰ \tTest\t PIData?>\n\t<?PITarget⁰ⁱ \tTest\t PIData?>\n\t<?PITargetⁱ↎ \tTest\t PIData?>\n\t<?PITarget↎↏Ⰰ \tTest\t PIData?>\n\t<?PITarget↏ⰀⰁ \tTest\t PIData?>\n\t<?PITargetⰀⰁ⿮ \tTest\t PIData?>\n\t<?PITargetⰁ⿮⿯ \tTest\t PIData?>\n\t<?PITarget⿮⿯、 \tTest\t PIData?>\n\t<?PITarget⿯、。 \tTest\t PIData?>\n\t<?PITarget、。퟾ \tTest\t PIData?>\n\t<?PITarget。퟾퟿ \tTest\t PIData?>\n\t<?PITarget퟾퟿豈 \tTest\t PIData?>\n\t<?PITarget퟿豈更 \tTest\t PIData?>\n\t<?PITarget豈퟿퟾。 \tTest\t PIData?>\n\t<?PITarget更豈퟿퟾ \tTest\t PIData?>\n\t<?PITarget�更豈퟿ \tTest\t PIData?>\n\t<?PITarget-�更豈 \tTest\t PIData?>\n\t<?PITarget.-�更 \tTest\t PIData?>\n\t<?PITargetA.-� \tTest\t PIData?>\n\t<?PITargetzA.- \tTest\t PIData?>\n\t<?PITarget0zA. \tTest\t PIData?>\n\t<?PITarget·0zA \tTest\t PIData?>\n\t<?PITarget̀·0z \tTest\t PIData?>\n\t<?PITarget́̀·0 \tTest\t PIData?>\n\t<?PITargetͮ́̀· \tTest\t PIData?>\n\t<?PITargetͯͮ́̀ \tTest\t PIData?>\n\t<?PITarget‿ͯͮ́ \tTest\t PIData?>\n\t<?PITarget⁀‿ͯͮ \tTest\t PIData?>\n\t<?PITargetnull⁀‿ͯ \tTest\t PIData?>\n\t<?PITargetnullnull⁀‿ \tTest\t PIData?>\n\t<?PITargetnullnullnull⁀ \tTest\t PIData?>\n</LegalName>"
  let reader = Reader::from_string(xml)
  // Verify parsing succeeds
  let events = reader.read_events_until_eof()
  assert_true(events.length() > 0)
}

///|
test "w3c/valid/x_ibm_1_0_5_valid_P05_ibm05v03_xml" {
  // This test case covers legal Attribute (Names) as per prod...
  let xml = "<!DOCTYPE LegalName [\n<!ELEMENT LegalName ANY>\n<!ATTLIST LegalName :attr CDATA #IMPLIED>\n<!ATTLIST LegalName Àattr CDATA #IMPLIED>\n<!ATTLIST LegalName Áattr CDATA #IMPLIED>\n<!ATTLIST LegalName ˾attr CDATA #IMPLIED>\n<!ATTLIST LegalName Âattr CDATA #IMPLIED>\n<!ATTLIST LegalName Ãattr CDATA #IMPLIED>\n<!ATTLIST LegalName ˽attr CDATA #IMPLIED>\n<!ATTLIST LegalName ˿attr CDATA #IMPLIED>\n<!ATTLIST LegalName Ͱattr CDATA #IMPLIED>\n<!ATTLIST LegalName ͱattr CDATA #IMPLIED>\n<!ATTLIST LegalName ͼͽattr CDATA #IMPLIED>\n<!ATTLIST LegalName ͽͿattr CDATA #IMPLIED>\n<!ATTLIST LegalName Ϳ΀attr CDATA #IMPLIED>\n<!ATTLIST LegalName ΀῾attr CDATA #IMPLIED>\n<!ATTLIST LegalName ῾῿attr CDATA #IMPLIED>\n<!ATTLIST LegalName ῿‌attr CDATA #IMPLIED>\n<!ATTLIST LegalName ‌‍attr CDATA #IMPLIED>\n<!ATTLIST LegalName ‍⁰attr CDATA #IMPLIED>\n<!ATTLIST LegalName ⁰ⁱattr CDATA #IMPLIED>\n<!ATTLIST LegalName ⁱ↎attr CDATA #IMPLIED>\n<!ATTLIST LegalName ↎↏Ⰰattr CDATA #IMPLIED>\n<!ATTLIST LegalName ↏ⰀⰁattr CDATA #IMPLIED>\n<!ATTLIST LegalName ⰀⰁ⿮attr CDATA #IMPLIED>\n<!ATTLIST LegalName Ⰱ⿮⿯attr CDATA #IMPLIED>\n<!ATTLIST LegalName ⿮⿯、attr CDATA #IMPLIED>\n<!ATTLIST LegalName ⿯、。attr CDATA #IMPLIED>\n<!ATTLIST LegalName 、。퟾attr CDATA #IMPLIED>\n<!ATTLIST LegalName 。퟾퟿attr CDATA #IMPLIED>\n<!ATTLIST LegalName ퟾퟿豈attr CDATA #IMPLIED>\n<!ATTLIST LegalName ퟿豈更attr CDATA #IMPLIED>\n<!ATTLIST LegalName 豈퟿퟾。attr CDATA #IMPLIED>\n<!ATTLIST LegalName 更豈퟿퟾attr CDATA #IMPLIED>\n<!ATTLIST LegalName �更豈퟿attr CDATA #IMPLIED>\n<!ATTLIST LegalName attr-�更豈 CDATA #IMPLIED>\n<!ATTLIST LegalName attr.-�更 CDATA #IMPLIED>\n<!ATTLIST LegalName A.-�attr CDATA #IMPLIED>\n<!ATTLIST LegalName zA.-attr CDATA #IMPLIED>\n<!ATTLIST LegalName attr0zA. CDATA #IMPLIED>\n<!ATTLIST LegalName attr·0zA CDATA #IMPLIED>\n<!ATTLIST LegalName attr̀·0z CDATA #IMPLIED>\n<!ATTLIST LegalName attŕ̀·0 CDATA #IMPLIED>\n<!ATTLIST LegalName attrͮ́̀· CDATA #IMPLIED>\n<!ATTLIST LegalName attrͯͮ́̀ CDATA #IMPLIED>\n<!ATTLIST LegalName attr‿ͯͮ́ CDATA #IMPLIED>\n<!ATTLIST LegalName attr⁀‿ͯͮ CDATA #IMPLIED>\n<!ATTLIST LegalName null⁀‿ͯattr CDATA #IMPLIED>\n<!ATTLIST LegalName nullnull⁀‿attr CDATA #IMPLIED>\n<!ATTLIST LegalName nullnullnull⁀attr CDATA #IMPLIED>\n]>\n<!-- Legal Names containing one to four characters in order from the list below  used in Attr delcs and attributes.  x003A, 0x00C0, 0x00C1, 0x02FE, 0x00C2, 0x00C3, 0x02FD, 0x02FF, 0x0370, 0x0371, 0x037C, 0x037D, 0x037F, 0x0380, 0x1FFE, 0x1FFF, 0x200C, 0x200D, 0x2070, 0x2071, 0x218E, 0x218F, 0x2C00, 0x2C01, 0x2FEE, 0x2FEF, 0x3001, 0x3002, 0xD7FE, 0xD7FF, 0xF900, 0xF901, 0xFFFD, 0x002D, 0x002E, 0x0041, 0x007A, 0x0030, 0x00B7, 0x0300, 0x0301, 0x036E, 0x036F, 0x203F, 0x2040 -->\n<LegalName \n \t:attr=\"attrValue\"\n \tÀattr=\"attrValue\"\n \tÁattr=\"attrValue\"\n \t˾attr=\"attrValue\"\n \tÂattr=\"attrValue\"\n \tÃattr=\"attrValue\"\n \t˽attr=\"attrValue\"\n \t˿attr=\"attrValue\"\n \tͰattr=\"attrValue\"\n \tͱattr=\"attrValue\"\n \tͼͽattr=\"attrValue\"\n \tͽͿattr=\"attrValue\"\n \tͿ΀attr=\"attrValue\"\n \t΀῾attr=\"attrValue\"\n \t῾῿attr=\"attrValue\"\n \t῿‌attr=\"attrValue\"\n \t‌‍attr=\"attrValue\"\n \t‍⁰attr=\"attrValue\"\n \t⁰ⁱattr=\"attrValue\"\n \tⁱ↎attr=\"attrValue\"\n \t↎↏Ⰰattr=\"attrValue\"\n \t↏ⰀⰁattr=\"attrValue\"\n \tⰀⰁ⿮attr=\"attrValue\"\n \tⰁ⿮⿯attr=\"attrValue\"\n \t⿮⿯、attr=\"attrValue\"\n \t⿯、。attr=\"attrValue\"\n \t、。퟾attr=\"attrValue\"\n \t。퟾퟿attr=\"attrValue\"\n \t퟾퟿豈attr=\"attrValue\"\n \t퟿豈更attr=\"attrValue\"\n \t豈퟿퟾。attr=\"attrValue\"\n \t更豈퟿퟾attr=\"attrValue\"\n \t�更豈퟿attr=\"attrValue\"\n \tattr-�更豈=\"attrValue\"\n \tattr.-�更=\"attrValue\"\n \tA.-�attr=\"attrValue\"\n \tzA.-attr=\"attrValue\"\n \tattr0zA.=\"attrValue\"\n \tattr·0zA=\"attrValue\"\n \tattr̀·0z=\"attrValue\"\n \tattŕ̀·0=\"attrValue\"\n \tattrͮ́̀·=\"attrValue\"\n \tattrͯͮ́̀=\"attrValue\"\n \tattr‿ͯͮ́=\"attrValue\"\n \tattr⁀‿ͯͮ=\"attrValue\"\n \tnull⁀‿ͯattr=\"attrValue\"\n \tnullnull⁀‿attr=\"attrValue\"\n \tnullnullnull⁀attr=\"attrValue\"\n />"
  let reader = Reader::from_string(xml)
  // Verify parsing succeeds
  let events = reader.read_events_until_eof()
  assert_true(events.length() > 0)
}

///|
test "w3c/valid/x_ibm_1_0_5_valid_P05_ibm05v04_xml" {
  // This test case covers legal ID/IDREF (Names) as per produ...
  let xml = "<!DOCTYPE LegalName [\n<!ELEMENT LegalName ANY>\n<!ELEMENT LegalName0 ANY>\n<!ATTLIST LegalName0 attr0 ID #IMPLIED>\n<!ATTLIST LegalName0 attr00 IDREF #IMPLIED>\n<!ELEMENT LegalName1 ANY>\n<!ATTLIST LegalName1 attr1 ID #IMPLIED>\n<!ATTLIST LegalName1 attr10 IDREF #IMPLIED>\n<!ELEMENT LegalName2 ANY>\n<!ATTLIST LegalName2 attr2 ID #IMPLIED>\n<!ATTLIST LegalName2 attr20 IDREF #IMPLIED>\n<!ELEMENT LegalName3 ANY>\n<!ATTLIST LegalName3 attr3 ID #IMPLIED>\n<!ATTLIST LegalName3 attr30 IDREF #IMPLIED>\n<!ELEMENT LegalName4 ANY>\n<!ATTLIST LegalName4 attr4 ID #IMPLIED>\n<!ATTLIST LegalName4 attr40 IDREF #IMPLIED>\n<!ELEMENT LegalName5 ANY>\n<!ATTLIST LegalName5 attr5 ID #IMPLIED>\n<!ATTLIST LegalName5 attr50 IDREF #IMPLIED>\n<!ELEMENT LegalName6 ANY>\n<!ATTLIST LegalName6 attr6 ID #IMPLIED>\n<!ATTLIST LegalName6 attr60 IDREF #IMPLIED>\n<!ELEMENT LegalName7 ANY>\n<!ATTLIST LegalName7 attr7 ID #IMPLIED>\n<!ATTLIST LegalName7 attr70 IDREF #IMPLIED>\n<!ELEMENT LegalName8 ANY>\n<!ATTLIST LegalName8 attr8 ID #IMPLIED>\n<!ATTLIST LegalName8 attr80 IDREF #IMPLIED>\n<!ELEMENT LegalName9 ANY>\n<!ATTLIST LegalName9 attr9 ID #IMPLIED>\n<!ATTLIST LegalName9 attr90 IDREF #IMPLIED>\n<!ELEMENT LegalName10 ANY>\n<!ATTLIST LegalName10 attr10 ID #IMPLIED>\n<!ATTLIST LegalName10 attr100 IDREF #IMPLIED>\n<!ELEMENT LegalName11 ANY>\n<!ATTLIST LegalName11 attr11 ID #IMPLIED>\n<!ATTLIST LegalName11 attr110 IDREF #IMPLIED>\n<!ELEMENT LegalName12 ANY>\n<!ATTLIST LegalName12 attr12 ID #IMPLIED>\n<!ATTLIST LegalName12 attr120 IDREF #IMPLIED>\n<!ELEMENT LegalName13 ANY>\n<!ATTLIST LegalName13 attr13 ID #IMPLIED>\n<!ATTLIST LegalName13 attr130 IDREF #IMPLIED>\n<!ELEMENT LegalName14 ANY>\n<!ATTLIST LegalName14 attr14 ID #IMPLIED>\n<!ATTLIST LegalName14 attr140 IDREF #IMPLIED>\n<!ELEMENT LegalName15 ANY>\n<!ATTLIST LegalName15 attr15 ID #IMPLIED>\n<!ATTLIST LegalName15 attr150 IDREF #IMPLIED>\n<!ELEMENT LegalName16 ANY>\n<!ATTLIST LegalName16 attr16 ID #IMPLIED>\n<!ATTLIST LegalName16 attr160 IDREF #IMPLIED>\n<!ELEMENT LegalName17 ANY>\n<!ATTLIST LegalName17 attr17 ID #IMPLIED>\n<!ATTLIST LegalName17 attr170 IDREF #IMPLIED>\n<!ELEMENT LegalName18 ANY>\n<!ATTLIST LegalName18 attr18 ID #IMPLIED>\n<!ATTLIST LegalName18 attr180 IDREF #IMPLIED>\n<!ELEMENT LegalName19 ANY>\n<!ATTLIST LegalName19 attr19 ID #IMPLIED>\n<!ATTLIST LegalName19 attr190 IDREF #IMPLIED>\n<!ELEMENT LegalName20 ANY>\n<!ATTLIST LegalName20 attr20 ID #IMPLIED>\n<!ATTLIST LegalName20 attr200 IDREF #IMPLIED>\n<!ELEMENT LegalName21 ANY>\n<!ATTLIST LegalName21 attr21 ID #IMPLIED>\n<!ATTLIST LegalName21 attr210 IDREF #IMPLIED>\n<!ELEMENT LegalName22 ANY>\n<!ATTLIST LegalName22 attr22 ID #IMPLIED>\n<!ATTLIST LegalName22 attr220 IDREF #IMPLIED>\n<!ELEMENT LegalName23 ANY>\n<!ATTLIST LegalName23 attr23 ID #IMPLIED>\n<!ATTLIST LegalName23 attr230 IDREF #IMPLIED>\n<!ELEMENT LegalName24 ANY>\n<!ATTLIST LegalName24 attr24 ID #IMPLIED>\n<!ATTLIST LegalName24 attr240 IDREF #IMPLIED>\n<!ELEMENT LegalName25 ANY>\n<!ATTLIST LegalName25 attr25 ID #IMPLIED>\n<!ATTLIST LegalName25 attr250 IDREF #IMPLIED>\n<!ELEMENT LegalName26 ANY>\n<!ATTLIST LegalName26 attr26 ID #IMPLIED>\n<!ATTLIST LegalName26 attr260 IDREF #IMPLIED>\n<!ELEMENT LegalName27 ANY>\n<!ATTLIST LegalName27 attr27 ID #IMPLIED>\n<!ATTLIST LegalName27 attr270 IDREF #IMPLIED>\n<!ELEMENT LegalName28 ANY>\n<!ATTLIST LegalName28 attr28 ID #IMPLIED>\n<!ATTLIST LegalName28 attr280 IDREF #IMPLIED>\n<!ELEMENT LegalName29 ANY>\n<!ATTLIST LegalName29 attr29 ID #IMPLIED>\n<!ATTLIST LegalName29 attr290 IDREF #IMPLIED>\n<!ELEMENT LegalName30 ANY>\n<!ATTLIST LegalName30 attr30 ID #IMPLIED>\n<!ATTLIST LegalName30 attr300 IDREF #IMPLIED>\n<!ELEMENT LegalName31 ANY>\n<!ATTLIST LegalName31 attr31 ID #IMPLIED>\n<!ATTLIST LegalName31 attr310 IDREF #IMPLIED>\n<!ELEMENT LegalName32 ANY>\n<!ATTLIST LegalName32 attr32 ID #IMPLIED>\n<!ATTLIST LegalName32 attr320 IDREF #IMPLIED>\n<!ELEMENT LegalName33 ANY>\n<!ATTLIST LegalName33 attr33 ID #IMPLIED>\n<!ATTLIST LegalName33 attr330 IDREF #IMPLIED>\n<!ELEMENT LegalName34 ANY>\n<!ATTLIST LegalName34 attr34 ID #IMPLIED>\n<!ATTLIST LegalName34 attr340 IDREF #IMPLIED>\n<!ELEMENT LegalName35 ANY>\n<!ATTLIST LegalName35 attr35 ID #IMPLIED>\n<!ATTLIST LegalName35 attr350 IDREF #IMPLIED>\n<!ELEMENT LegalName36 ANY>\n<!ATTLIST LegalName36 attr36 ID #IMPLIED>\n<!ATTLIST LegalName36 attr360 IDREF #IMPLIED>\n<!ELEMENT LegalName37 ANY>\n<!ATTLIST LegalName37 attr37 ID #IMPLIED>\n<!ATTLIST LegalName37 attr370 IDREF #IMPLIED>\n<!ELEMENT LegalName38 ANY>\n<!ATTLIST LegalName38 attr38 ID #IMPLIED>\n<!ATTLIST LegalName38 attr380 IDREF #IMPLIED>\n<!ELEMENT LegalName39 ANY>\n<!ATTLIST LegalName39 attr39 ID #IMPLIED>\n<!ATTLIST LegalName39 attr390 IDREF #IMPLIED>\n<!ELEMENT LegalName40 ANY>\n<!ATTLIST LegalName40 attr40 ID #IMPLIED>\n<!ATTLIST LegalName40 attr400 IDREF #IMPLIED>\n<!ELEMENT LegalName41 ANY>\n<!ATTLIST LegalName41 attr41 ID #IMPLIED>\n<!ATTLIST LegalName41 attr410 IDREF #IMPLIED>\n<!ELEMENT LegalName42 ANY>\n<!ATTLIST LegalName42 attr42 ID #IMPLIED>\n<!ATTLIST LegalName42 attr420 IDREF #IMPLIED>\n<!ELEMENT LegalName43 ANY>\n<!ATTLIST LegalName43 attr43 ID #IMPLIED>\n<!ATTLIST LegalName43 attr430 IDREF #IMPLIED>\n<!ELEMENT LegalName44 ANY>\n<!ATTLIST LegalName44 attr44 ID #IMPLIED>\n<!ATTLIST LegalName44 attr440 IDREF #IMPLIED>\n<!ELEMENT LegalName45 ANY>\n<!ATTLIST LegalName45 attr45 ID #IMPLIED>\n<!ATTLIST LegalName45 attr450 IDREF #IMPLIED>\n<!ELEMENT LegalName46 ANY>\n<!ATTLIST LegalName46 attr46 ID #IMPLIED>\n<!ATTLIST LegalName46 attr460 IDREF #IMPLIED>\n<!ELEMENT LegalName47 ANY>\n<!ATTLIST LegalName47 attr47 ID #IMPLIED>\n<!ATTLIST LegalName47 attr470 IDREF #IMPLIED>\n]>\n<!-- Legal Names containing one to four characters in order from the list below  used in Attr delcs and attributes.  x003A, 0x00C0, 0x00C1, 0x02FE, 0x00C2, 0x00C3, 0x02FD, 0x02FF, 0x0370, 0x0371, 0x037C, 0x037D, 0x037F, 0x0380, 0x1FFE, 0x1FFF, 0x200C, 0x200D, 0x2070, 0x2071, 0x218E, 0x218F, 0x2C00, 0x2C01, 0x2FEE, 0x2FEF, 0x3001, 0x3002, 0xD7FE, 0xD7FF, 0xF900, 0xF901, 0xFFFD, 0x002D, 0x002E, 0x0041, 0x007A, 0x0030, 0x00B7, 0x0300, 0x0301, 0x036E, 0x036F, 0x203F, 0x2040 -->\n<LegalName>\n \tattr0=\":\" attr00=\":\"\n \tattr1=\"À\" attr10=\"À\"\n \tattr2=\"Á\" attr20=\"Á\"\n \tattr3=\"˾\" attr30=\"˾\"\n \tattr4=\"Â\" attr40=\"Â\"\n \tattr5=\"Ã\" attr50=\"Ã\"\n \tattr6=\"˽\" attr60=\"˽\"\n \tattr7=\"˿\" attr70=\"˿\"\n \tattr8=\"Ͱ\" attr80=\"Ͱ\"\n \tattr9=\"ͱ\" attr90=\"ͱ\"\n \tattr10=\"ͼͽ\" attr100=\"ͼͽ\"\n \tattr11=\"ͽͿ\" attr110=\"ͽͿ\"\n \tattr12=\"Ϳ΀\" attr120=\"Ϳ΀\"\n \tattr13=\"΀῾\" attr130=\"΀῾\"\n \tattr14=\"῾῿\" attr140=\"῾῿\"\n \tattr15=\"῿‌\" attr150=\"῿‌\"\n \tattr16=\"‌‍\" attr160=\"‌‍\"\n \tattr17=\"‍⁰\" attr170=\"‍⁰\"\n \tattr18=\"⁰ⁱ\" attr180=\"⁰ⁱ\"\n \tattr19=\"ⁱ↎\" attr190=\"ⁱ↎\"\n \tattr20=\"↎↏Ⰰ\" attr200=\"↎↏Ⰰ\"\n \tattr21=\"↏ⰀⰁ\" attr210=\"↏ⰀⰁ\"\n \tattr22=\"ⰀⰁ⿮\" attr220=\"ⰀⰁ⿮\"\n \tattr23=\"Ⰱ⿮⿯\" attr230=\"Ⰱ⿮⿯\"\n \tattr24=\"⿮⿯、\" attr240=\"⿮⿯、\"\n \tattr25=\"⿯、。\" attr250=\"⿯、。\"\n \tattr26=\"、。퟾\" attr260=\"、。퟾\"\n \tattr27=\"。퟾퟿\" attr270=\"。퟾퟿\"\n \tattr28=\"퟾퟿豈\" attr280=\"퟾퟿豈\"\n \tattr29=\"퟿豈更\" attr290=\"퟿豈更\"\n \tattr30=\"豈퟿퟾。\" attr300=\"豈퟿퟾。\"\n \tattr31=\"更豈퟿퟾\" attr310=\"更豈퟿퟾\"\n \tattr32=\"�更豈퟿\" attr320=\"�更豈퟿\"\n \tattr33=\"-�更豈\" attr330=\"-�更豈\"\n \tattr34=\".-�更\" attr340=\".-�更\"\n \tattr35=\"A.-�\" attr350=\"A.-�\"\n \tattr36=\"zA.-\" attr360=\"zA.-\"\n \tattr37=\"0zA.\" attr370=\"0zA.\"\n \tattr38=\"·0zA\" attr380=\"·0zA\"\n \tattr39=\"̀·0z\" attr390=\"̀·0z\"\n \tattr40=\"́̀·0\" attr400=\"́̀·0\"\n \tattr41=\"ͮ́̀·\" attr410=\"ͮ́̀·\"\n \tattr42=\"ͯͮ́̀\" attr420=\"ͯͮ́̀\"\n \tattr43=\"‿ͯͮ́\" attr430=\"‿ͯͮ́\"\n \tattr44=\"⁀‿ͯͮ\" attr440=\"⁀‿ͯͮ\"\n \tattr45=\"null⁀‿ͯ\" attr450=\"null⁀‿ͯ\"\n \tattr46=\"nullnull⁀‿\" attr460=\"nullnull⁀‿\"\n \tattr47=\"nullnullnull⁀\" attr470=\"nullnullnull⁀\"\n</LegalName>"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"LegalName\"), Comment(\" Legal Names containing one to four characters in order from the list below  used in Attr delcs and attributes.  x003A, 0x00C0, 0x00C1, 0x02FE, 0x00C2, 0x00C3, 0x02FD, 0x02FF, 0x0370, 0x0371, 0x037C, 0x037D, 0x037F, 0x0380, 0x1FFE, 0x1FFF, 0x200C, 0x200D, 0x2070, 0x2071, 0x218E, 0x218F, 0x2C00, 0x2C01, 0x2FEE, 0x2FEF, 0x3001, 0x3002, 0xD7FE, 0xD7FF, 0xF900, 0xF901, 0xFFFD, 0x002D, 0x002E, 0x0041, 0x007A, 0x0030, 0x00B7, 0x0300, 0x0301, 0x036E, 0x036F, 0x203F, 0x2040 \"), Start({name: \"LegalName\", attributes: []}), Text(\"\\n \\tattr0=\\\":\\\" attr00=\\\":\\\"\\n \\tattr1=\\\"À\\\" attr10=\\\"À\\\"\\n \\tattr2=\\\"Á\\\" attr20=\\\"Á\\\"\\n \\tattr3=\\\"˾\\\" attr30=\\\"˾\\\"\\n \\tattr4=\\\"Â\\\" attr40=\\\"Â\\\"\\n \\tattr5=\\\"Ã\\\" attr50=\\\"Ã\\\"\\n \\tattr6=\\\"˽\\\" attr60=\\\"˽\\\"\\n \\tattr7=\\\"˿\\\" attr70=\\\"˿\\\"\\n \\tattr8=\\\"Ͱ\\\" attr80=\\\"Ͱ\\\"\\n \\tattr9=\\\"ͱ\\\" attr90=\\\"ͱ\\\"\\n \\tattr10=\\\"ͼͽ\\\" attr100=\\\"ͼͽ\\\"\\n \\tattr11=\\\"ͽͿ\\\" attr110=\\\"ͽͿ\\\"\\n \\tattr12=\\\"Ϳ΀\\\" attr120=\\\"Ϳ΀\\\"\\n \\tattr13=\\\"΀῾\\\" attr130=\\\"΀῾\\\"\\n \\tattr14=\\\"῾῿\\\" attr140=\\\"῾῿\\\"\\n \\tattr15=\\\"῿‌\\\" attr150=\\\"῿‌\\\"\\n \\tattr16=\\\"‌‍\\\" attr160=\\\"‌‍\\\"\\n \\tattr17=\\\"‍⁰\\\" attr170=\\\"‍⁰\\\"\\n \\tattr18=\\\"⁰ⁱ\\\" attr180=\\\"⁰ⁱ\\\"\\n \\tattr19=\\\"ⁱ↎\\\" attr190=\\\"ⁱ↎\\\"\\n \\tattr20=\\\"↎↏Ⰰ\\\" attr200=\\\"↎↏Ⰰ\\\"\\n \\tattr21=\\\"↏ⰀⰁ\\\" attr210=\\\"↏ⰀⰁ\\\"\\n \\tattr22=\\\"ⰀⰁ⿮\\\" attr220=\\\"ⰀⰁ⿮\\\"\\n \\tattr23=\\\"Ⰱ⿮⿯\\\" attr230=\\\"Ⰱ⿮⿯\\\"\\n \\tattr24=\\\"⿮⿯、\\\" attr240=\\\"⿮⿯、\\\"\\n \\tattr25=\\\"⿯、。\\\" attr250=\\\"⿯、。\\\"\\n \\tattr26=\\\"、。퟾\\\" attr260=\\\"、。퟾\\\"\\n \\tattr27=\\\"。퟾퟿\\\" attr270=\\\"。퟾퟿\\\"\\n \\tattr28=\\\"퟾퟿豈\\\" attr280=\\\"퟾퟿豈\\\"\\n \\tattr29=\\\"퟿豈更\\\" attr290=\\\"퟿豈更\\\"\\n \\tattr30=\\\"豈퟿퟾。\\\" attr300=\\\"豈퟿퟾。\\\"\\n \\tattr31=\\\"更豈퟿퟾\\\" attr310=\\\"更豈퟿퟾\\\"\\n \\tattr32=\\\"�更豈퟿\\\" attr320=\\\"�更豈퟿\\\"\\n \\tattr33=\\\"-�更豈\\\" attr330=\\\"-�更豈\\\"\\n \\tattr34=\\\".-�更\\\" attr340=\\\".-�更\\\"\\n \\tattr35=\\\"A.-�\\\" attr350=\\\"A.-�\\\"\\n \\tattr36=\\\"zA.-\\\" attr360=\\\"zA.-\\\"\\n \\tattr37=\\\"0zA.\\\" attr370=\\\"0zA.\\\"\\n \\tattr38=\\\"·0zA\\\" attr380=\\\"·0zA\\\"\\n \\tattr39=\\\"̀·0z\\\" attr390=\\\"̀·0z\\\"\\n \\tattr40=\\\"́̀·0\\\" attr400=\\\"́̀·0\\\"\\n \\tattr41=\\\"ͮ́̀·\\\" attr410=\\\"ͮ́̀·\\\"\\n \\tattr42=\\\"ͯͮ́̀\\\" attr420=\\\"ͯͮ́̀\\\"\\n \\tattr43=\\\"‿ͯͮ́\\\" attr430=\\\"‿ͯͮ́\\\"\\n \\tattr44=\\\"⁀‿ͯͮ\\\" attr440=\\\"⁀‿ͯͮ\\\"\\n \\tattr45=\\\"null⁀‿ͯ\\\" attr450=\\\"null⁀‿ͯ\\\"\\n \\tattr46=\\\"nullnull⁀‿\\\" attr460=\\\"nullnull⁀‿\\\"\\n \\tattr47=\\\"nullnullnull⁀\\\" attr470=\\\"nullnullnull⁀\\\"\\n\"), End(\"LegalName\"), Eof]",
  )
}

///|
test "w3c/valid/x_ibm_1_0_5_valid_P05_ibm05v05_xml" {
  // This test case covers legal ENTITY (Names) as per product...
  let xml = "<!DOCTYPE LegalName [\n<!ELEMENT LegalName ANY>\n<!ELEMENT LegalName0 ANY>\n<!ATTLIST LegalName0 attr0 CDATA #IMPLIED>\n<!ELEMENT LegalName1 ANY>\n<!ATTLIST LegalName1 attr1 CDATA #IMPLIED>\n<!ELEMENT LegalName2 ANY>\n<!ATTLIST LegalName2 attr2 CDATA #IMPLIED>\n<!ELEMENT LegalName3 ANY>\n<!ATTLIST LegalName3 attr3 CDATA #IMPLIED>\n<!ELEMENT LegalName4 ANY>\n<!ATTLIST LegalName4 attr4 CDATA #IMPLIED>\n<!ELEMENT LegalName5 ANY>\n<!ATTLIST LegalName5 attr5 CDATA #IMPLIED>\n<!ELEMENT LegalName6 ANY>\n<!ATTLIST LegalName6 attr6 CDATA #IMPLIED>\n<!ELEMENT LegalName7 ANY>\n<!ATTLIST LegalName7 attr7 CDATA #IMPLIED>\n<!ELEMENT LegalName8 ANY>\n<!ATTLIST LegalName8 attr8 CDATA #IMPLIED>\n<!ELEMENT LegalName9 ANY>\n<!ATTLIST LegalName9 attr9 CDATA #IMPLIED>\n<!ELEMENT LegalName10 ANY>\n<!ATTLIST LegalName10 attr10 CDATA #IMPLIED>\n<!ELEMENT LegalName11 ANY>\n<!ATTLIST LegalName11 attr11 CDATA #IMPLIED>\n<!ELEMENT LegalName12 ANY>\n<!ATTLIST LegalName12 attr12 CDATA #IMPLIED>\n<!ELEMENT LegalName13 ANY>\n<!ATTLIST LegalName13 attr13 CDATA #IMPLIED>\n<!ELEMENT LegalName14 ANY>\n<!ATTLIST LegalName14 attr14 CDATA #IMPLIED>\n<!ELEMENT LegalName15 ANY>\n<!ATTLIST LegalName15 attr15 CDATA #IMPLIED>\n<!ELEMENT LegalName16 ANY>\n<!ATTLIST LegalName16 attr16 CDATA #IMPLIED>\n<!ELEMENT LegalName17 ANY>\n<!ATTLIST LegalName17 attr17 CDATA #IMPLIED>\n<!ELEMENT LegalName18 ANY>\n<!ATTLIST LegalName18 attr18 CDATA #IMPLIED>\n<!ELEMENT LegalName19 ANY>\n<!ATTLIST LegalName19 attr19 CDATA #IMPLIED>\n<!ELEMENT LegalName20 ANY>\n<!ATTLIST LegalName20 attr20 CDATA #IMPLIED>\n<!ELEMENT LegalName21 ANY>\n<!ATTLIST LegalName21 attr21 CDATA #IMPLIED>\n<!ELEMENT LegalName22 ANY>\n<!ATTLIST LegalName22 attr22 CDATA #IMPLIED>\n<!ELEMENT LegalName23 ANY>\n<!ATTLIST LegalName23 attr23 CDATA #IMPLIED>\n<!ELEMENT LegalName24 ANY>\n<!ATTLIST LegalName24 attr24 CDATA #IMPLIED>\n<!ELEMENT LegalName25 ANY>\n<!ATTLIST LegalName25 attr25 CDATA #IMPLIED>\n<!ELEMENT LegalName26 ANY>\n<!ATTLIST LegalName26 attr26 CDATA #IMPLIED>\n<!ELEMENT LegalName27 ANY>\n<!ATTLIST LegalName27 attr27 CDATA #IMPLIED>\n<!ELEMENT LegalName28 ANY>\n<!ATTLIST LegalName28 attr28 CDATA #IMPLIED>\n<!ELEMENT LegalName29 ANY>\n<!ATTLIST LegalName29 attr29 CDATA #IMPLIED>\n<!ELEMENT LegalName30 ANY>\n<!ATTLIST LegalName30 attr30 CDATA #IMPLIED>\n<!ELEMENT LegalName31 ANY>\n<!ATTLIST LegalName31 attr31 CDATA #IMPLIED>\n<!ELEMENT LegalName32 ANY>\n<!ATTLIST LegalName32 attr32 CDATA #IMPLIED>\n<!ELEMENT LegalName33 ANY>\n<!ATTLIST LegalName33 attr33 CDATA #IMPLIED>\n<!ELEMENT LegalName34 ANY>\n<!ATTLIST LegalName34 attr34 CDATA #IMPLIED>\n<!ELEMENT LegalName35 ANY>\n<!ATTLIST LegalName35 attr35 CDATA #IMPLIED>\n<!ELEMENT LegalName36 ANY>\n<!ATTLIST LegalName36 attr36 CDATA #IMPLIED>\n<!ELEMENT LegalName37 ANY>\n<!ATTLIST LegalName37 attr37 CDATA #IMPLIED>\n<!ELEMENT LegalName38 ANY>\n<!ATTLIST LegalName38 attr38 CDATA #IMPLIED>\n<!ELEMENT LegalName39 ANY>\n<!ATTLIST LegalName39 attr39 CDATA #IMPLIED>\n<!ELEMENT LegalName40 ANY>\n<!ATTLIST LegalName40 attr40 CDATA #IMPLIED>\n<!ELEMENT LegalName41 ANY>\n<!ATTLIST LegalName41 attr41 CDATA #IMPLIED>\n<!ELEMENT LegalName42 ANY>\n<!ATTLIST LegalName42 attr42 CDATA #IMPLIED>\n<!ELEMENT LegalName43 ANY>\n<!ATTLIST LegalName43 attr43 CDATA #IMPLIED>\n<!ENTITY Name: \"Test\">\n<!ENTITY NameÀ \"Test\">\n<!ENTITY NameÁ \"Test\">\n<!ENTITY Name˾ \"Test\">\n<!ENTITY NameÂ \"Test\">\n<!ENTITY NameÃ \"Test\">\n<!ENTITY Name˽ \"Test\">\n<!ENTITY Name˿ \"Test\">\n<!ENTITY NameͰ \"Test\">\n<!ENTITY Nameͱ \"Test\">\n<!ENTITY Nameͼ \"Test\">\n<!ENTITY Nameͽ \"Test\">\n<!ENTITY NameͿ \"Test\">\n<!ENTITY Name΀ \"Test\">\n<!ENTITY Name῾ \"Test\">\n<!ENTITY Name῿ \"Test\">\n<!ENTITY Name‌ \"Test\">\n<!ENTITY Name‍ \"Test\">\n<!ENTITY Name⁰ \"Test\">\n<!ENTITY Nameⁱ \"Test\">\n<!ENTITY Name↎ \"Test\">\n<!ENTITY Name↏ \"Test\">\n<!ENTITY NameⰀ \"Test\">\n<!ENTITY NameⰁ \"Test\">\n<!ENTITY Name⿮ \"Test\">\n<!ENTITY Name⿯ \"Test\">\n<!ENTITY Name、 \"Test\">\n<!ENTITY Name。 \"Test\">\n<!ENTITY Name퟾ \"Test\">\n<!ENTITY Name퟿ \"Test\">\n<!ENTITY Name豈 \"Test\">\n<!ENTITY Name更 \"Test\">\n<!ENTITY Name� \"Test\">\n<!ENTITY Name- \"Test\">\n<!ENTITY Name. \"Test\">\n<!ENTITY NameA \"Test\">\n<!ENTITY Namez \"Test\">\n<!ENTITY Name0 \"Test\">\n<!ENTITY Name· \"Test\">\n<!ENTITY Namè \"Test\">\n<!ENTITY Namé \"Test\">\n<!ENTITY Nameͮ \"Test\">\n<!ENTITY Nameͯ \"Test\">\n<!ENTITY Name‿ \"Test\">\n]>\n<!-- Legal Names containing one to four characters in order from the list below  used in Attr delcs and attributes.  x003A, 0x00C0, 0x00C1, 0x02FE, 0x00C2, 0x00C3, 0x02FD, 0x02FF, 0x0370, 0x0371, 0x037C, 0x037D, 0x037F, 0x0380, 0x1FFE, 0x1FFF, 0x200C, 0x200D, 0x2070, 0x2071, 0x218E, 0x218F, 0x2C00, 0x2C01, 0x2FEE, 0x2FEF, 0x3001, 0x3002, 0xD7FE, 0xD7FF, 0xF900, 0xF901, 0xFFFD, 0x002D, 0x002E, 0x0041, 0x007A, 0x0030, 0x00B7, 0x0300, 0x0301, 0x036E, 0x036F, 0x203F, 0x2040 -->\n<LegalName>\n<LegalName0 attr0=\"Name:\"\t/>\n<LegalName1 attr1=\"NameÀ\"\t/>\n<LegalName2 attr2=\"NameÁ\"\t/>\n<LegalName3 attr3=\"Name˾\"\t/>\n<LegalName4 attr4=\"NameÂ\"\t/>\n<LegalName5 attr5=\"NameÃ\"\t/>\n<LegalName6 attr6=\"Name˽\"\t/>\n<LegalName7 attr7=\"Name˿\"\t/>\n<LegalName8 attr8=\"NameͰ\"\t/>\n<LegalName9 attr9=\"Nameͱ\"\t/>\n<LegalName10 attr10=\"Nameͼ\"\t/>\n<LegalName11 attr11=\"Nameͽ\"\t/>\n<LegalName12 attr12=\"NameͿ\"\t/>\n<LegalName13 attr13=\"Name΀\"\t/>\n<LegalName14 attr14=\"Name῾\"\t/>\n<LegalName15 attr15=\"Name῿\"\t/>\n<LegalName16 attr16=\"Name‌\"\t/>\n<LegalName17 attr17=\"Name‍\"\t/>\n<LegalName18 attr18=\"Name⁰\"\t/>\n<LegalName19 attr19=\"Nameⁱ\"\t/>\n<LegalName20 attr20=\"Name↎\"\t/>\n<LegalName21 attr21=\"Name↏\"\t/>\n<LegalName22 attr22=\"NameⰀ\"\t/>\n<LegalName23 attr23=\"NameⰁ\"\t/>\n<LegalName24 attr24=\"Name⿮\"\t/>\n<LegalName25 attr25=\"Name⿯\"\t/>\n<LegalName26 attr26=\"Name、\"\t/>\n<LegalName27 attr27=\"Name。\"\t/>\n<LegalName28 attr28=\"Name퟾\"\t/>\n<LegalName29 attr29=\"Name퟿\"\t/>\n<LegalName30 attr30=\"Name豈\"\t/>\n<LegalName31 attr31=\"Name更\"\t/>\n<LegalName32 attr32=\"Name�\"\t/>\n<LegalName33 attr33=\"Name-\"\t/>\n<LegalName34 attr34=\"Name.\"\t/>\n<LegalName35 attr35=\"NameA\"\t/>\n<LegalName36 attr36=\"Namez\"\t/>\n<LegalName37 attr37=\"Name0\"\t/>\n<LegalName38 attr38=\"Name·\"\t/>\n<LegalName39 attr39=\"Namè\"\t/>\n<LegalName40 attr40=\"Namé\"\t/>\n<LegalName41 attr41=\"Nameͮ\"\t/>\n<LegalName42 attr42=\"Nameͯ\"\t/>\n<LegalName43 attr43=\"Name‿\"\t/>\n</LegalName>"
  let reader = Reader::from_string(xml)
  // Verify parsing succeeds
  let events = reader.read_events_until_eof()
  assert_true(events.length() > 0)
}

///|
test "w3c/valid/x_ibm_1_0_5_valid_P047_ibm07v01_xml" {
  // This test case covers legal NMTOKEN Name character ranges...
  let xml = "<!DOCTYPE NMtokenName [\n<!ELEMENT NMtokenName ANY>\n<!ATTLIST NMtokenName thistoken0 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken1 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken2 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken3 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken4 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken5 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken6 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken7 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken8 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken9 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken10 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken11 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken12 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken13 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken14 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken15 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken16 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken17 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken18 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken19 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken20 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken21 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken22 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken23 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken24 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken25 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken26 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken27 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken28 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken29 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken30 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken31 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken32 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken33 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken34 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken35 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken36 NMTOKEN #IMPLIED>\n<!ATTLIST NMtokenName thistoken37 NMTOKEN #IMPLIED>\n]>\n<!-- LegalNameChar  0x300,0x333,0x369,0x37E,0x2000,0x2001,0x2002,0x2005,0x200B,0x200E,x200F,0x2069,0x2190,0x23FF,0x280F,0x2A00,0x2EDC,0x2FED,0x2FFF,0x3000,0xD800,0xD801,0xDAFF,0xDFFF,0xEFFF,0xF1FF,0xF8FF,0xFFFFF; _, ., 0, B7, C0, 2FFF in P07 -->\n<NMtokenName  thistoken0=\":\"\n thistoken1=\"À\"\n thistoken2=\"Á\"\n thistoken3=\"˾\"\n thistoken4=\"À\"\n thistoken5=\"Á\"\n thistoken6=\"˾\"\n thistoken7=\"˿\"\n thistoken8=\"Ͱ\"\n thistoken9=\"ͱ\"\n thistoken10=\"ͼ\"\n thistoken11=\"ͽ\"\n thistoken12=\"Ϳ\"\n thistoken13=\"΀\"\n thistoken14=\"῾\"\n thistoken15=\"῿\"\n thistoken16=\"‌\"\n thistoken17=\"‍\"\n thistoken18=\"⁰\"\n thistoken19=\"ⁱ\"\n thistoken20=\"↎\"\n thistoken21=\"↏\"\n thistoken22=\"Ⰰ\"\n thistoken23=\"Ⰱ\"\n thistoken24=\"⿮\"\n thistoken25=\"⿯\"\n thistoken26=\"、\"\n thistoken27=\"。\"\n thistoken28=\"퟾\"\n thistoken29=\"퟿\"\n thistoken30=\"豈\"\n thistoken31=\"更\"\n thistoken32=\"_\"\n thistoken33=\".\"\n thistoken34=\"0\"\n thistoken35=\"·\"\n thistoken36=\"À\"\n thistoken37=\"ͼ\"\n />"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"NMtokenName\"), Comment(\" LegalNameChar  0x300,0x333,0x369,0x37E,0x2000,0x2001,0x2002,0x2005,0x200B,0x200E,x200F,0x2069,0x2190,0x23FF,0x280F,0x2A00,0x2EDC,0x2FED,0x2FFF,0x3000,0xD800,0xD801,0xDAFF,0xDFFF,0xEFFF,0xF1FF,0xF8FF,0xFFFFF; _, ., 0, B7, C0, 2FFF in P07 \"), Empty({name: \"NMtokenName\", attributes: [(\"thistoken0\", \":\"), (\"thistoken1\", \"À\"), (\"thistoken2\", \"Á\"), (\"thistoken3\", \"˾\"), (\"thistoken4\", \"À\"), (\"thistoken5\", \"Á\"), (\"thistoken6\", \"˾\"), (\"thistoken7\", \"˿\"), (\"thistoken8\", \"Ͱ\"), (\"thistoken9\", \"ͱ\"), (\"thistoken10\", \"ͼ\"), (\"thistoken11\", \"ͽ\"), (\"thistoken12\", \"Ϳ\"), (\"thistoken13\", \"΀\"), (\"thistoken14\", \"῾\"), (\"thistoken15\", \"῿\"), (\"thistoken16\", \"‌\"), (\"thistoken17\", \"‍\"), (\"thistoken18\", \"⁰\"), (\"thistoken19\", \"ⁱ\"), (\"thistoken20\", \"↎\"), (\"thistoken21\", \"↏\"), (\"thistoken22\", \"Ⰰ\"), (\"thistoken23\", \"Ⰱ\"), (\"thistoken24\", \"⿮\"), (\"thistoken25\", \"⿯\"), (\"thistoken26\", \"、\"), (\"thistoken27\", \"。\"), (\"thistoken28\", \"퟾\"), (\"thistoken29\", \"퟿\"), (\"thistoken30\", \"豈\"), (\"thistoken31\", \"更\"), (\"thistoken32\", \"_\"), (\"thistoken33\", \".\"), (\"thistoken34\", \"0\"), (\"thistoken35\", \"·\"), (\"thistoken36\", \"À\"), (\"thistoken37\", \"ͼ\")]}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n03_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ĳ an only legal per 5th edition char #x132\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ĳ\", data=\"an only legal per 5th edition char #x132\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n04_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ĳ an only legal per 5th edition char #x133\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ĳ\", data=\"an only legal per 5th edition char #x133\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n05_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ŀ an only legal per 5th edition char #x13f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ŀ\", data=\"an only legal per 5th edition char #x13f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n06_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ŀ an only legal per 5th edition char #x140\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ŀ\", data=\"an only legal per 5th edition char #x140\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n07_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ŉ an only legal per 5th edition char #x149\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ŉ\", data=\"an only legal per 5th edition char #x149\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n08_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ſ an only legal per 5th edition char #x17f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ſ\", data=\"an only legal per 5th edition char #x17f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n09_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ǆ an only legal per 5th edition char #x1c4\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ǆ\", data=\"an only legal per 5th edition char #x1c4\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n10_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ǌ an only legal per 5th edition char #x1cc\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ǌ\", data=\"an only legal per 5th edition char #x1cc\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n100_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ஶ an only legal per 5th edition char #x0bb6\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ஶ\", data=\"an only legal per 5th edition char #x0bb6\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n101_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?஺ an only legal per 5th edition char #x0bba\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"஺\", data=\"an only legal per 5th edition char #x0bba\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n102_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?఍ an only legal per 5th edition char #x0c0d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"఍\", data=\"an only legal per 5th edition char #x0c0d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n103_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?఑ an only legal per 5th edition char #x0c11\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"఑\", data=\"an only legal per 5th edition char #x0c11\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n104_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?఩ an only legal per 5th edition char #x0c29\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"఩\", data=\"an only legal per 5th edition char #x0c29\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n105_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ఴ an only legal per 5th edition char #x0c34\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ఴ\", data=\"an only legal per 5th edition char #x0c34\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n106_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?౟ an only legal per 5th edition char #x0c5f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"౟\", data=\"an only legal per 5th edition char #x0c5f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n107_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ౢ an only legal per 5th edition char #x0c62\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ౢ\", data=\"an only legal per 5th edition char #x0c62\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n108_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?಍ an only legal per 5th edition char #x0c8d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"಍\", data=\"an only legal per 5th edition char #x0c8d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n109_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?಑ an only legal per 5th edition char #x0c91\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"಑\", data=\"an only legal per 5th edition char #x0c91\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n11_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ǳ an only legal per 5th edition char #x1f1\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ǳ\", data=\"an only legal per 5th edition char #x1f1\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n110_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?಩ an only legal per 5th edition char #x0ca9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"಩\", data=\"an only legal per 5th edition char #x0ca9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n111_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?಴ an only legal per 5th edition char #x0cb4\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"಴\", data=\"an only legal per 5th edition char #x0cb4\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n112_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?಺ an only legal per 5th edition char #x0cba\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"಺\", data=\"an only legal per 5th edition char #x0cba\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n113_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?೟ an only legal per 5th edition char #x0cdf\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"೟\", data=\"an only legal per 5th edition char #x0cdf\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n114_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ೢ an only legal per 5th edition char #x0ce2\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ೢ\", data=\"an only legal per 5th edition char #x0ce2\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n115_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?഍ an only legal per 5th edition char #x0d0d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"഍\", data=\"an only legal per 5th edition char #x0d0d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n116_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?഑ an only legal per 5th edition char #x0d11\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"഑\", data=\"an only legal per 5th edition char #x0d11\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n117_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ഩ an only legal per 5th edition char #x0d29\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ഩ\", data=\"an only legal per 5th edition char #x0d29\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n118_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ഺ an only legal per 5th edition char #x0d3a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ഺ\", data=\"an only legal per 5th edition char #x0d3a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n119_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ൢ an only legal per 5th edition char #x0d62\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ൢ\", data=\"an only legal per 5th edition char #x0d62\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n12_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ǳ an only legal per 5th edition char #x1f3\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ǳ\", data=\"an only legal per 5th edition char #x1f3\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n120_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ฯ an only legal per 5th edition char #x0e2f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ฯ\", data=\"an only legal per 5th edition char #x0e2f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n121_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ั an only legal per 5th edition char #x0e31\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ั\", data=\"an only legal per 5th edition char #x0e31\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n122_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ิ an only legal per 5th edition char #x0e34\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ิ\", data=\"an only legal per 5th edition char #x0e34\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n123_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ๆ an only legal per 5th edition char #x0e46\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ๆ\", data=\"an only legal per 5th edition char #x0e46\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n124_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?຃ an only legal per 5th edition char #x0e83\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"຃\", data=\"an only legal per 5th edition char #x0e83\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n125_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?຅ an only legal per 5th edition char #x0e85\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"຅\", data=\"an only legal per 5th edition char #x0e85\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n126_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ຉ an only legal per 5th edition char #x0e89\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ຉ\", data=\"an only legal per 5th edition char #x0e89\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n127_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?຋ an only legal per 5th edition char #x0e8b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"຋\", data=\"an only legal per 5th edition char #x0e8b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n128_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ຎ an only legal per 5th edition char #x0e8e\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ຎ\", data=\"an only legal per 5th edition char #x0e8e\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n129_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ຘ an only legal per 5th edition char #x0e98\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ຘ\", data=\"an only legal per 5th edition char #x0e98\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n13_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ƕ an only legal per 5th edition char #x1f6\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ƕ\", data=\"an only legal per 5th edition char #x1f6\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n130_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ຠ an only legal per 5th edition char #x0ea0\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ຠ\", data=\"an only legal per 5th edition char #x0ea0\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n131_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?຤ an only legal per 5th edition char #x0ea4\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"຤\", data=\"an only legal per 5th edition char #x0ea4\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n132_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?຦ an only legal per 5th edition char #x0ea6\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"຦\", data=\"an only legal per 5th edition char #x0ea6\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n133_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ຨ an only legal per 5th edition char #x0ea8\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ຨ\", data=\"an only legal per 5th edition char #x0ea8\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n134_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ຬ an only legal per 5th edition char #x0eac\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ຬ\", data=\"an only legal per 5th edition char #x0eac\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n135_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ຯ an only legal per 5th edition char #x0eaf\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ຯ\", data=\"an only legal per 5th edition char #x0eaf\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n136_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ັ an only legal per 5th edition char #x0eb1\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ັ\", data=\"an only legal per 5th edition char #x0eb1\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n137_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ິ an only legal per 5th edition char #x0eb4\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ິ\", data=\"an only legal per 5th edition char #x0eb4\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n138_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?຾ an only legal per 5th edition char #x0ebe\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"຾\", data=\"an only legal per 5th edition char #x0ebe\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n139_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?໅ an only legal per 5th edition char #x0ec5\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"໅\", data=\"an only legal per 5th edition char #x0ec5\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n14_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ǹ an only legal per 5th edition char #x1f9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ǹ\", data=\"an only legal per 5th edition char #x1f9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n140_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?཈ an only legal per 5th edition char #x0f48\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"཈\", data=\"an only legal per 5th edition char #x0f48\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n141_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ཪ an only legal per 5th edition char #x0f6a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ཪ\", data=\"an only legal per 5th edition char #x0f6a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n142_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?჆ an only legal per 5th edition char #x10c6\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"჆\", data=\"an only legal per 5th edition char #x10c6\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n143_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ჷ an only legal per 5th edition char #x10f7\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ჷ\", data=\"an only legal per 5th edition char #x10f7\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n144_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᄁ an only legal per 5th edition char #x1101\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᄁ\", data=\"an only legal per 5th edition char #x1101\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n145_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᄄ an only legal per 5th edition char #x1104\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᄄ\", data=\"an only legal per 5th edition char #x1104\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n146_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᄈ an only legal per 5th edition char #x1108\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᄈ\", data=\"an only legal per 5th edition char #x1108\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n147_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᄊ an only legal per 5th edition char #x110a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᄊ\", data=\"an only legal per 5th edition char #x110a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n148_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᄍ an only legal per 5th edition char #x110d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᄍ\", data=\"an only legal per 5th edition char #x110d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n149_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᄻ an only legal per 5th edition char #x113b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᄻ\", data=\"an only legal per 5th edition char #x113b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n15_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ǹ an only legal per 5th edition char #x1f9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ǹ\", data=\"an only legal per 5th edition char #x1f9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n150_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᄿ an only legal per 5th edition char #x113f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᄿ\", data=\"an only legal per 5th edition char #x113f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n151_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅁ an only legal per 5th edition char #x1141\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅁ\", data=\"an only legal per 5th edition char #x1141\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n152_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅍ an only legal per 5th edition char #x114d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅍ\", data=\"an only legal per 5th edition char #x114d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n153_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅏ an only legal per 5th edition char #x114f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅏ\", data=\"an only legal per 5th edition char #x114f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n154_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅑ an only legal per 5th edition char #x1151\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅑ\", data=\"an only legal per 5th edition char #x1151\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n155_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅖ an only legal per 5th edition char #x1156\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅖ\", data=\"an only legal per 5th edition char #x1156\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n156_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅚ an only legal per 5th edition char #x115a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅚ\", data=\"an only legal per 5th edition char #x115a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n157_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅢ an only legal per 5th edition char #x1162\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅢ\", data=\"an only legal per 5th edition char #x1162\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n158_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅤ an only legal per 5th edition char #x1164\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅤ\", data=\"an only legal per 5th edition char #x1164\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n159_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅦ an only legal per 5th edition char #x1166\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅦ\", data=\"an only legal per 5th edition char #x1166\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n16_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ȱ an only legal per 5th edition char #x230\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ȱ\", data=\"an only legal per 5th edition char #x230\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n160_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅫ an only legal per 5th edition char #x116b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅫ\", data=\"an only legal per 5th edition char #x116b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n161_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅯ an only legal per 5th edition char #x116f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅯ\", data=\"an only legal per 5th edition char #x116f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n162_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᅴ an only legal per 5th edition char #x1174\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᅴ\", data=\"an only legal per 5th edition char #x1174\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n163_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᆟ an only legal per 5th edition char #x119f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᆟ\", data=\"an only legal per 5th edition char #x119f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n164_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᆬ an only legal per 5th edition char #x11ac\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᆬ\", data=\"an only legal per 5th edition char #x11ac\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n165_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᆶ an only legal per 5th edition char #x11b6\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᆶ\", data=\"an only legal per 5th edition char #x11b6\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n166_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᆹ an only legal per 5th edition char #x11b9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᆹ\", data=\"an only legal per 5th edition char #x11b9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n167_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᆻ an only legal per 5th edition char #x11bb\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᆻ\", data=\"an only legal per 5th edition char #x11bb\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n168_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᇃ an only legal per 5th edition char #x11c3\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᇃ\", data=\"an only legal per 5th edition char #x11c3\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n169_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᇱ an only legal per 5th edition char #x11f1\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᇱ\", data=\"an only legal per 5th edition char #x11f1\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n17_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ʯ an only legal per 5th edition char #x2af\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ʯ\", data=\"an only legal per 5th edition char #x2af\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n170_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ᇺ an only legal per 5th edition char #x11fa\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ᇺ\", data=\"an only legal per 5th edition char #x11fa\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n171_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ẜ an only legal per 5th edition char #x1e9c\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ẜ\", data=\"an only legal per 5th edition char #x1e9c\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n172_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ỻ an only legal per 5th edition char #x1efa\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ỻ\", data=\"an only legal per 5th edition char #x1efa\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n173_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?἖ an only legal per 5th edition char #x1f16\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"἖\", data=\"an only legal per 5th edition char #x1f16\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n174_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?἞ an only legal per 5th edition char #x1f1e\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"἞\", data=\"an only legal per 5th edition char #x1f1e\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n175_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?὆ an only legal per 5th edition char #x1f46\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"὆\", data=\"an only legal per 5th edition char #x1f46\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n176_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?὏ an only legal per 5th edition char #x1f4f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"὏\", data=\"an only legal per 5th edition char #x1f4f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n177_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?὘ an only legal per 5th edition char #x1f58\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"὘\", data=\"an only legal per 5th edition char #x1f58\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n178_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?὚ an only legal per 5th edition char #x1f5a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"὚\", data=\"an only legal per 5th edition char #x1f5a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n179_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?὜ an only legal per 5th edition char #x1f5c\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"὜\", data=\"an only legal per 5th edition char #x1f5c\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n18_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ˏ an only legal per 5th edition char #x2cf\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ˏ\", data=\"an only legal per 5th edition char #x2cf\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n180_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?὞ an only legal per 5th edition char #x1f5e\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"὞\", data=\"an only legal per 5th edition char #x1f5e\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n181_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?὾ an only legal per 5th edition char #x1f7e\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"὾\", data=\"an only legal per 5th edition char #x1f7e\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n182_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?᾵ an only legal per 5th edition char #x1fb5\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"᾵\", data=\"an only legal per 5th edition char #x1fb5\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n183_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?᾽ an only legal per 5th edition char #x1fbd\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"᾽\", data=\"an only legal per 5th edition char #x1fbd\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n184_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?᾿ an only legal per 5th edition char #x1fbf\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"᾿\", data=\"an only legal per 5th edition char #x1fbf\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n185_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?῅ an only legal per 5th edition char #x1fc5\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"῅\", data=\"an only legal per 5th edition char #x1fc5\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n186_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?῍ an only legal per 5th edition char #x1fcd\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"῍\", data=\"an only legal per 5th edition char #x1fcd\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n187_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?῕ an only legal per 5th edition char #x1fd5\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"῕\", data=\"an only legal per 5th edition char #x1fd5\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n188_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?῜ an only legal per 5th edition char #x1fdc\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"῜\", data=\"an only legal per 5th edition char #x1fdc\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n189_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?῭ an only legal per 5th edition char #x1fed\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"῭\", data=\"an only legal per 5th edition char #x1fed\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n19_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?· an only legal per 5th edition char #x387\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"·\", data=\"an only legal per 5th edition char #x387\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n190_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?῵ an only legal per 5th edition char #x1ff5\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"῵\", data=\"an only legal per 5th edition char #x1ff5\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n191_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?´ an only legal per 5th edition char #x1ffd\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"´\", data=\"an only legal per 5th edition char #x1ffd\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n192_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?℧ an only legal per 5th edition char #x2127\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"℧\", data=\"an only legal per 5th edition char #x2127\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n193_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ℯ an only legal per 5th edition char #x212f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ℯ\", data=\"an only legal per 5th edition char #x212f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n194_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ↄ an only legal per 5th edition char #x2183\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ↄ\", data=\"an only legal per 5th edition char #x2183\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n195_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ゕ an only legal per 5th edition char #x3095\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ゕ\", data=\"an only legal per 5th edition char #x3095\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n196_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?・ an only legal per 5th edition char #x30fb\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"・\", data=\"an only legal per 5th edition char #x30fb\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n197_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ㄭ an only legal per 5th edition char #x312d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ㄭ\", data=\"an only legal per 5th edition char #x312d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n198_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?힤 an only legal per 5th edition char #xd7a4\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"힤\", data=\"an only legal per 5th edition char #xd7a4\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n20_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?΋ an only legal per 5th edition char #x38b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"΋\", data=\"an only legal per 5th edition char #x38b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n21_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?΢ an only legal per 5th edition char #x3a2\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"΢\", data=\"an only legal per 5th edition char #x3a2\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n22_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ϗ an only legal per 5th edition char #x3cf\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ϗ\", data=\"an only legal per 5th edition char #x3cf\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n23_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ϗ an only legal per 5th edition char #x3d7\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ϗ\", data=\"an only legal per 5th edition char #x3d7\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n24_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ϝ an only legal per 5th edition char #x3dd\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ϝ\", data=\"an only legal per 5th edition char #x3dd\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n25_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ϡ an only legal per 5th edition char #x3e1\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ϡ\", data=\"an only legal per 5th edition char #x3e1\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n26_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ϴ an only legal per 5th edition char #x3f4\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ϴ\", data=\"an only legal per 5th edition char #x3f4\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n27_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ѝ an only legal per 5th edition char #x40d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ѝ\", data=\"an only legal per 5th edition char #x40d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n28_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ѐ an only legal per 5th edition char #x450\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ѐ\", data=\"an only legal per 5th edition char #x450\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n29_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ѝ an only legal per 5th edition char #x45d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ѝ\", data=\"an only legal per 5th edition char #x45d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n30_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?҂ an only legal per 5th edition char #x482\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"҂\", data=\"an only legal per 5th edition char #x482\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n31_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ӆ an only legal per 5th edition char #x4c5\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ӆ\", data=\"an only legal per 5th edition char #x4c5\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n32_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ӆ an only legal per 5th edition char #x4c6\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ӆ\", data=\"an only legal per 5th edition char #x4c6\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n33_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ӊ an only legal per 5th edition char #x4c9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ӊ\", data=\"an only legal per 5th edition char #x4c9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n34_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ӭ an only legal per 5th edition char #x4ec\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ӭ\", data=\"an only legal per 5th edition char #x4ec\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n35_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ӭ an only legal per 5th edition char #x4ed\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ӭ\", data=\"an only legal per 5th edition char #x4ed\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n36_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ӷ an only legal per 5th edition char #x4f6\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ӷ\", data=\"an only legal per 5th edition char #x4f6\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n37_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?Ӻ an only legal per 5th edition char #x4fa\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"Ӻ\", data=\"an only legal per 5th edition char #x4fa\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n38_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?՗ an only legal per 5th edition char #x557\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"՗\", data=\"an only legal per 5th edition char #x557\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n39_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?՘ an only legal per 5th edition char #x558\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"՘\", data=\"an only legal per 5th edition char #x558\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n40_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?և an only legal per 5th edition char #x587\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"և\", data=\"an only legal per 5th edition char #x587\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n41_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?׫ an only legal per 5th edition char #x5eb\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"׫\", data=\"an only legal per 5th edition char #x5eb\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n42_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?׳ an only legal per 5th edition char #x5f3\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"׳\", data=\"an only legal per 5th edition char #x5f3\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n43_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ؠ an only legal per 5th edition char #x620\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ؠ\", data=\"an only legal per 5th edition char #x620\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n44_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ػ an only legal per 5th edition char #x63b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ػ\", data=\"an only legal per 5th edition char #x63b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n45_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ً an only legal per 5th edition char #x64b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ً\", data=\"an only legal per 5th edition char #x64b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n46_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ڸ an only legal per 5th edition char #x6b8\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ڸ\", data=\"an only legal per 5th edition char #x6b8\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n47_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ڿ an only legal per 5th edition char #x6bf\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ڿ\", data=\"an only legal per 5th edition char #x6bf\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n48_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ۏ an only legal per 5th edition char #x6cf\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ۏ\", data=\"an only legal per 5th edition char #x6cf\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n49_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?۔ an only legal per 5th edition char #x6d4\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"۔\", data=\"an only legal per 5th edition char #x6d4\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n50_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ۖ an only legal per 5th edition char #x6d6\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ۖ\", data=\"an only legal per 5th edition char #x6d6\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n51_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ۧ an only legal per 5th edition char #x6e7\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ۧ\", data=\"an only legal per 5th edition char #x6e7\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n52_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ऺ an only legal per 5th edition char #x093a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ऺ\", data=\"an only legal per 5th edition char #x093a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n53_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ा an only legal per 5th edition char #x093e\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ा\", data=\"an only legal per 5th edition char #x093e\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n54_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ॢ an only legal per 5th edition char #x0962\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ॢ\", data=\"an only legal per 5th edition char #x0962\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n55_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?঍ an only legal per 5th edition char #x098d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"঍\", data=\"an only legal per 5th edition char #x098d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n56_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?঑ an only legal per 5th edition char #x0991\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"঑\", data=\"an only legal per 5th edition char #x0991\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n57_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?঒ an only legal per 5th edition char #x0992\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"঒\", data=\"an only legal per 5th edition char #x0992\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n58_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?঩ an only legal per 5th edition char #x09a9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"঩\", data=\"an only legal per 5th edition char #x09a9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n59_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?঱ an only legal per 5th edition char #x09b1\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"঱\", data=\"an only legal per 5th edition char #x09b1\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n60_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?঵ an only legal per 5th edition char #x09b5\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"঵\", data=\"an only legal per 5th edition char #x09b5\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n61_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?঺ an only legal per 5th edition char #x09ba\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"঺\", data=\"an only legal per 5th edition char #x09ba\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n62_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?৞ an only legal per 5th edition char #x09de\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"৞\", data=\"an only legal per 5th edition char #x09de\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n63_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ৢ an only legal per 5th edition char #x09e2\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ৢ\", data=\"an only legal per 5th edition char #x09e2\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n64_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?৲ an only legal per 5th edition char #x09f2\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"৲\", data=\"an only legal per 5th edition char #x09f2\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n65_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?਋ an only legal per 5th edition char #x0a0b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"਋\", data=\"an only legal per 5th edition char #x0a0b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n66_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?਑ an only legal per 5th edition char #x0a11\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"਑\", data=\"an only legal per 5th edition char #x0a11\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n67_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?਩ an only legal per 5th edition char #x0a29\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"਩\", data=\"an only legal per 5th edition char #x0a29\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n68_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?਱ an only legal per 5th edition char #x0a31\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"਱\", data=\"an only legal per 5th edition char #x0a31\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n69_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?਴ an only legal per 5th edition char #x0a34\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"਴\", data=\"an only legal per 5th edition char #x0a34\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n70_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?਷ an only legal per 5th edition char #x0a37\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"਷\", data=\"an only legal per 5th edition char #x0a37\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n71_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?਺ an only legal per 5th edition char #x0a3a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"਺\", data=\"an only legal per 5th edition char #x0a3a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n72_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?੝ an only legal per 5th edition char #x0a5d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"੝\", data=\"an only legal per 5th edition char #x0a5d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n73_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ੰ an only legal per 5th edition char #x0a70\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ੰ\", data=\"an only legal per 5th edition char #x0a70\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n74_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ੵ an only legal per 5th edition char #x0a75\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ੵ\", data=\"an only legal per 5th edition char #x0a75\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n75_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?઄ an only legal per 5th edition char #x0a84\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"઄\", data=\"an only legal per 5th edition char #x0a84\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n76_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?઼ an only legal per 5th edition char #x0abc\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"઼\", data=\"an only legal per 5th edition char #x0abc\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n77_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?઒ an only legal per 5th edition char #x0a92\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"઒\", data=\"an only legal per 5th edition char #x0a92\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n78_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?઩ an only legal per 5th edition char #x0aa9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"઩\", data=\"an only legal per 5th edition char #x0aa9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n79_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?઱ an only legal per 5th edition char #x0ab1\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"઱\", data=\"an only legal per 5th edition char #x0ab1\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n80_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?઴ an only legal per 5th edition char #x0ab4\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"઴\", data=\"an only legal per 5th edition char #x0ab4\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n81_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?઺ an only legal per 5th edition char #x0aba\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"઺\", data=\"an only legal per 5th edition char #x0aba\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n82_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?଄ an only legal per 5th edition char #x0b04\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"଄\", data=\"an only legal per 5th edition char #x0b04\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n83_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?଍ an only legal per 5th edition char #x0b0d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"଍\", data=\"an only legal per 5th edition char #x0b0d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n84_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?଑ an only legal per 5th edition char #x0b11\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"଑\", data=\"an only legal per 5th edition char #x0b11\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n85_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?଩ an only legal per 5th edition char #x0b29\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"଩\", data=\"an only legal per 5th edition char #x0b29\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n86_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?଱ an only legal per 5th edition char #x0b31\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"଱\", data=\"an only legal per 5th edition char #x0b31\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n87_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?଴ an only legal per 5th edition char #x0b34\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"଴\", data=\"an only legal per 5th edition char #x0b34\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n88_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?଺ an only legal per 5th edition char #x0b3a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"଺\", data=\"an only legal per 5th edition char #x0b3a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n89_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ା an only legal per 5th edition char #x0b3e\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ା\", data=\"an only legal per 5th edition char #x0b3e\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n90_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?୞ an only legal per 5th edition char #x0b5e\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"୞\", data=\"an only legal per 5th edition char #x0b5e\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n91_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?ୢ an only legal per 5th edition char #x0b62\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"ୢ\", data=\"an only legal per 5th edition char #x0b62\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n92_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?஋ an only legal per 5th edition char #x0b8b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"஋\", data=\"an only legal per 5th edition char #x0b8b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n93_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?஑ an only legal per 5th edition char #x0b91\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"஑\", data=\"an only legal per 5th edition char #x0b91\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n94_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?஘ an only legal per 5th edition char #x0b98\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"஘\", data=\"an only legal per 5th edition char #x0b98\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n95_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?஛ an only legal per 5th edition char #x0b9b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"஛\", data=\"an only legal per 5th edition char #x0b9b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n96_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?஝ an only legal per 5th edition char #x0b9d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"஝\", data=\"an only legal per 5th edition char #x0b9d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n97_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?஠ an only legal per 5th edition char #x0ba0\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"஠\", data=\"an only legal per 5th edition char #x0ba0\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n98_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?஧ an only legal per 5th edition char #x0ba7\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"஧\", data=\"an only legal per 5th edition char #x0ba7\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P85_ibm85n99_xml" {
  // Tests BaseChar with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?஫ an only legal per 5th edition char #x0bab\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"஫\", data=\"an only legal per 5th edition char #x0bab\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P86_ibm86n01_xml" {
  // Tests Ideographic with an only legal per 5th edition char...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?䳿 an only legal per 5th edition char #x4cff\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"䳿\", data=\"an only legal per 5th edition char #x4cff\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P86_ibm86n02_xml" {
  // Tests Ideographic with an only legal per 5th edition char...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?龦 an only legal per 5th edition char #x9fa6\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"龦\", data=\"an only legal per 5th edition char #x9fa6\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P86_ibm86n03_xml" {
  // Tests Ideographic with an only legal per 5th edition char...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?〈 an only legal per 5th edition char #x3008\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"〈\", data=\"an only legal per 5th edition char #x3008\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P86_ibm86n04_xml" {
  // Tests Ideographic with an only legal per 5th edition char...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?〪 an only legal per 5th edition char #x302a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"〪\", data=\"an only legal per 5th edition char #x302a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n01_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_˿ an only legal per 5th edition char #x2ff\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_˿\", data=\"an only legal per 5th edition char #x2ff\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n02_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_͆ an only legal per 5th edition char #x346\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_͆\", data=\"an only legal per 5th edition char #x346\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n03_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_͢ an only legal per 5th edition char #x362\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_͢\", data=\"an only legal per 5th edition char #x362\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n04_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_҇ an only legal per 5th edition char #x487\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_҇\", data=\"an only legal per 5th edition char #x487\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n05_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_֢ an only legal per 5th edition char #x5a2\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_֢\", data=\"an only legal per 5th edition char #x5a2\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n06_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ֺ an only legal per 5th edition char #x5ba\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ֺ\", data=\"an only legal per 5th edition char #x5ba\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n07_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_־ an only legal per 5th edition char #x5be\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_־\", data=\"an only legal per 5th edition char #x5be\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n08_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_׀ an only legal per 5th edition char #x5c0\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_׀\", data=\"an only legal per 5th edition char #x5c0\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n09_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_׃ an only legal per 5th edition char #x5c3\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_׃\", data=\"an only legal per 5th edition char #x5c3\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n10_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ٓ an only legal per 5th edition char #x653\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ٓ\", data=\"an only legal per 5th edition char #x653\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n11_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ڸ an only legal per 5th edition char #x6b8\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ڸ\", data=\"an only legal per 5th edition char #x6b8\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n12_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ڹ an only legal per 5th edition char #x6b9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ڹ\", data=\"an only legal per 5th edition char #x6b9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n13_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_۩ an only legal per 5th edition char #x6e9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_۩\", data=\"an only legal per 5th edition char #x6e9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n14_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ۮ an only legal per 5th edition char #x6ee\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ۮ\", data=\"an only legal per 5th edition char #x6ee\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n15_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ऄ an only legal per 5th edition char #x0904\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ऄ\", data=\"an only legal per 5th edition char #x0904\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n16_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ऻ an only legal per 5th edition char #x093b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ऻ\", data=\"an only legal per 5th edition char #x093b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n17_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ॎ an only legal per 5th edition char #x094e\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ॎ\", data=\"an only legal per 5th edition char #x094e\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n18_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ॕ an only legal per 5th edition char #x0955\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ॕ\", data=\"an only legal per 5th edition char #x0955\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n19_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_। an only legal per 5th edition char #x0964\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_।\", data=\"an only legal per 5th edition char #x0964\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n20_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_঄ an only legal per 5th edition char #x0984\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_঄\", data=\"an only legal per 5th edition char #x0984\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n21_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_৅ an only legal per 5th edition char #x09c5\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_৅\", data=\"an only legal per 5th edition char #x09c5\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n22_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_৉ an only legal per 5th edition char #x09c9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_৉\", data=\"an only legal per 5th edition char #x09c9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n23_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ৎ an only legal per 5th edition char #x09ce\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ৎ\", data=\"an only legal per 5th edition char #x09ce\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n24_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_৘ an only legal per 5th edition char #x09d8\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_৘\", data=\"an only legal per 5th edition char #x09d8\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n25_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_৤ an only legal per 5th edition char #x09e4\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_৤\", data=\"an only legal per 5th edition char #x09e4\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n26_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ਃ an only legal per 5th edition char #x0a03\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ਃ\", data=\"an only legal per 5th edition char #x0a03\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n27_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_਽ an only legal per 5th edition char #x0a3d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_਽\", data=\"an only legal per 5th edition char #x0a3d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n28_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_੆ an only legal per 5th edition char #x0a46\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_੆\", data=\"an only legal per 5th edition char #x0a46\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n29_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_੉ an only legal per 5th edition char #x0a49\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_੉\", data=\"an only legal per 5th edition char #x0a49\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n30_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_੎ an only legal per 5th edition char #x0a4e\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_੎\", data=\"an only legal per 5th edition char #x0a4e\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n31_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_઀ an only legal per 5th edition char #x0a80\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_઀\", data=\"an only legal per 5th edition char #x0a80\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n32_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_઄ an only legal per 5th edition char #x0a84\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_઄\", data=\"an only legal per 5th edition char #x0a84\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n33_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_઻ an only legal per 5th edition char #x0abb\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_઻\", data=\"an only legal per 5th edition char #x0abb\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n34_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_૆ an only legal per 5th edition char #x0ac6\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_૆\", data=\"an only legal per 5th edition char #x0ac6\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n35_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_૊ an only legal per 5th edition char #x0aca\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_૊\", data=\"an only legal per 5th edition char #x0aca\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n36_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_૎ an only legal per 5th edition char #x0ace\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_૎\", data=\"an only legal per 5th edition char #x0ace\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n37_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_଄ an only legal per 5th edition char #x0b04\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_଄\", data=\"an only legal per 5th edition char #x0b04\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n38_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_଻ an only legal per 5th edition char #x0b3b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_଻\", data=\"an only legal per 5th edition char #x0b3b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n39_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ୄ an only legal per 5th edition char #x0b44\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ୄ\", data=\"an only legal per 5th edition char #x0b44\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n40_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_୊ an only legal per 5th edition char #x0b4a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_୊\", data=\"an only legal per 5th edition char #x0b4a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n41_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_୎ an only legal per 5th edition char #x0b4e\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_୎\", data=\"an only legal per 5th edition char #x0b4e\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n42_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_୘ an only legal per 5th edition char #x0b58\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_୘\", data=\"an only legal per 5th edition char #x0b58\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n43_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_஄ an only legal per 5th edition char #x0b84\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_஄\", data=\"an only legal per 5th edition char #x0b84\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n44_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_௃ an only legal per 5th edition char #x0bc3\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_௃\", data=\"an only legal per 5th edition char #x0bc3\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n45_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_௉ an only legal per 5th edition char #x0bc9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_௉\", data=\"an only legal per 5th edition char #x0bc9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n46_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_௖ an only legal per 5th edition char #x0bd6\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_௖\", data=\"an only legal per 5th edition char #x0bd6\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n47_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_఍ an only legal per 5th edition char #x0c0d\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_఍\", data=\"an only legal per 5th edition char #x0c0d\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n48_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_౅ an only legal per 5th edition char #x0c45\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_౅\", data=\"an only legal per 5th edition char #x0c45\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n49_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_౉ an only legal per 5th edition char #x0c49\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_౉\", data=\"an only legal per 5th edition char #x0c49\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n50_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_౔ an only legal per 5th edition char #x0c54\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_౔\", data=\"an only legal per 5th edition char #x0c54\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n51_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ಁ an only legal per 5th edition char #x0c81\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ಁ\", data=\"an only legal per 5th edition char #x0c81\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n52_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_಄ an only legal per 5th edition char #x0c84\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_಄\", data=\"an only legal per 5th edition char #x0c84\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n53_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_೅ an only legal per 5th edition char #x0cc5\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_೅\", data=\"an only legal per 5th edition char #x0cc5\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n54_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_೉ an only legal per 5th edition char #x0cc9\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_೉\", data=\"an only legal per 5th edition char #x0cc9\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n55_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_೔ an only legal per 5th edition char #x0cd4\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_೔\", data=\"an only legal per 5th edition char #x0cd4\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n56_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_೗ an only legal per 5th edition char #x0cd7\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_೗\", data=\"an only legal per 5th edition char #x0cd7\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n57_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ഄ an only legal per 5th edition char #x0d04\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ഄ\", data=\"an only legal per 5th edition char #x0d04\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n58_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_൅ an only legal per 5th edition char #x0d45\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_൅\", data=\"an only legal per 5th edition char #x0d45\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n59_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_൉ an only legal per 5th edition char #x0d49\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_൉\", data=\"an only legal per 5th edition char #x0d49\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n60_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ൎ an only legal per 5th edition char #x0d4e\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ൎ\", data=\"an only legal per 5th edition char #x0d4e\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n61_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_൘ an only legal per 5th edition char #x0d58\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_൘\", data=\"an only legal per 5th edition char #x0d58\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n62_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_฿ an only legal per 5th edition char #x0e3f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_฿\", data=\"an only legal per 5th edition char #x0e3f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n63_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_฻ an only legal per 5th edition char #x0e3b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_฻\", data=\"an only legal per 5th edition char #x0e3b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n64_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_๏ an only legal per 5th edition char #x0e4f\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_๏\", data=\"an only legal per 5th edition char #x0e4f\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n66_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_຺ an only legal per 5th edition char #x0eba\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_຺\", data=\"an only legal per 5th edition char #x0eba\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n67_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_຾ an only legal per 5th edition char #x0ebe\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_຾\", data=\"an only legal per 5th edition char #x0ebe\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n68_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_໎ an only legal per 5th edition char #x0ece\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_໎\", data=\"an only legal per 5th edition char #x0ece\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n69_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_༚ an only legal per 5th edition char #x0f1a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_༚\", data=\"an only legal per 5th edition char #x0f1a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n70_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_༶ an only legal per 5th edition char #x0f36\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_༶\", data=\"an only legal per 5th edition char #x0f36\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n71_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_༸ an only legal per 5th edition char #x0f38\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_༸\", data=\"an only legal per 5th edition char #x0f38\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n72_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_༻ an only legal per 5th edition char #x0f3b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_༻\", data=\"an only legal per 5th edition char #x0f3b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n73_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_༺ an only legal per 5th edition char #x0f3a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_༺\", data=\"an only legal per 5th edition char #x0f3a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n74_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_཰ an only legal per 5th edition char #x0f70\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_཰\", data=\"an only legal per 5th edition char #x0f70\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n75_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_྅ an only legal per 5th edition char #x0f85\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_྅\", data=\"an only legal per 5th edition char #x0f85\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n76_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ྌ an only legal per 5th edition char #x0f8c\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ྌ\", data=\"an only legal per 5th edition char #x0f8c\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n77_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ྖ an only legal per 5th edition char #x0f96\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ྖ\", data=\"an only legal per 5th edition char #x0f96\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n78_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_྘ an only legal per 5th edition char #x0f98\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_྘\", data=\"an only legal per 5th edition char #x0f98\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n79_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ྰ an only legal per 5th edition char #x0fb0\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ྰ\", data=\"an only legal per 5th edition char #x0fb0\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n80_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ྸ an only legal per 5th edition char #x0fb8\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ྸ\", data=\"an only legal per 5th edition char #x0fb8\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n81_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ྺ an only legal per 5th edition char #x0fba\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ྺ\", data=\"an only legal per 5th edition char #x0fba\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n82_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_⃝ an only legal per 5th edition char #x20dd\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_⃝\", data=\"an only legal per 5th edition char #x20dd\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n83_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_⃢ an only legal per 5th edition char #x20e2\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_⃢\", data=\"an only legal per 5th edition char #x20e2\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n84_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_〰 an only legal per 5th edition char #x3030\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_〰\", data=\"an only legal per 5th edition char #x3030\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P87_ibm87n85_xml" {
  // Tests CombiningChar with an only legal per 5th edition ch...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_゛ an only legal per 5th edition char #x309b\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_゛\", data=\"an only legal per 5th edition char #x309b\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n03_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_٪ an only legal per 5th edition char #x66a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_٪\", data=\"an only legal per 5th edition char #x66a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n04_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ۺ an only legal per 5th edition char #x6fa\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ۺ\", data=\"an only legal per 5th edition char #x6fa\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n05_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_॰ an only legal per 5th edition char #x0970\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_॰\", data=\"an only legal per 5th edition char #x0970\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n06_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_৲ an only legal per 5th edition char #x09f2\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_৲\", data=\"an only legal per 5th edition char #x09f2\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n08_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_૰ an only legal per 5th edition char #x0af0\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_૰\", data=\"an only legal per 5th edition char #x0af0\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n09_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_୰ an only legal per 5th edition char #x0b70\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_୰\", data=\"an only legal per 5th edition char #x0b70\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n10_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_౥ an only legal per 5th edition char #x0c65\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_౥\", data=\"an only legal per 5th edition char #x0c65\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n11_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_೥ an only legal per 5th edition char #x0ce5\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_೥\", data=\"an only legal per 5th edition char #x0ce5\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n12_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_೰ an only legal per 5th edition char #x0cf0\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_೰\", data=\"an only legal per 5th edition char #x0cf0\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n13_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_൰ an only legal per 5th edition char #x0d70\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_൰\", data=\"an only legal per 5th edition char #x0d70\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n14_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_๚ an only legal per 5th edition char #x0e5a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_๚\", data=\"an only legal per 5th edition char #x0e5a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n15_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_໚ an only legal per 5th edition char #x0eda\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_໚\", data=\"an only legal per 5th edition char #x0eda\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P88_ibm88n16_xml" {
  // Tests Digit with an only legal per 5th edition character....
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_༪ an only legal per 5th edition char #x0f2a\n in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_༪\", data=\"an only legal per 5th edition char #x0f2a\\n in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P89_ibm89n03_xml" {
  // Tests Extender with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_˒ an only legal per 5th edition extender #x2d2 in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_˒\", data=\"an only legal per 5th edition extender #x2d2 in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P89_ibm89n04_xml" {
  // Tests Extender with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_Ͼ an only legal per 5th edition extender #x3fe in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_Ͼ\", data=\"an only legal per 5th edition extender #x3fe in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}

///|
test "w3c/valid/ibm_valid_P89_ibm89n05_xml" {
  // Tests Extender with an only legal per 5th edition charact...
  let xml = "<!DOCTYPE animal [\n<!ELEMENT animal ANY>\n<?_ٟ an only legal per 5th edition extender #x65f in PITarget ?>\n]>\n<animal/>\n"
  let reader = Reader::from_string(xml)
  let events = reader.read_events_until_eof()
  inspect(
    to_libxml_format(events),
    content="[DocType(\"animal\"), PI(target=\"_ٟ\", data=\"an only legal per 5th edition extender #x65f in PITarget \"), Empty({name: \"animal\", attributes: []}), Eof]",
  )
}
