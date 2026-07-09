///|
test "skills catalog replies decode and skip odd entries" {
  let reply : Json = {
    "skills": [
      {
        "name": "acme/widget",
        "module_name": "acme/widget",
        "package_path": "",
        "version": "1.0.0",
        "description": "Build widgets fast.",
        "author": "acme",
        "repository": "https://example.com/acme/widget",
      },
      // Unusable: no module name.
      { "version": "1.0.0" },
      "nonsense",
    ],
  }
  guard decode_skills_catalog_reply(reply.stringify()) is Some([item]) else {
    fail("expected exactly one catalog item")
  }
  assert_eq(item.name, "acme/widget")
  assert_eq(item.module_name, "acme/widget")
  assert_eq(item.version, "1.0.0")
  assert_eq(item.description, "Build widgets fast.")
  assert_eq(market_source_label(item), "acme/widget@1.0.0")
  assert_true(decode_skills_catalog_reply("[]") is None)
  assert_true(decode_skills_catalog_reply("not json") is None)
}

///|
test "subpackage skills carry their package path in the source label" {
  let reply : Json = {
    "skills": [
      {
        "name": "alice/alpha/cmd/run",
        "module_name": "alice/alpha",
        "package_path": "cmd/run",
        "version": "0.2.0",
        "description": "Run alpha commands",
        "author": "",
        "repository": "",
      },
    ],
  }
  guard decode_skills_catalog_reply(reply.stringify()) is Some([item]) else {
    fail("expected one catalog item")
  }
  assert_eq(market_source_label(item), "alice/alpha@0.2.0/cmd/run")
  assert_eq(item.author, "")
}

///|
test "installed skill replies decode, with name falling back to id" {
  let reply : Json = {
    "skills": [
      {
        "id": "acme-widget",
        "name": "widget",
        "description": "Build widgets fast.",
        "source": "acme/widget@1.0.0",
      },
      { "id": "handmade", "name": "", "description": "", "source": "" },
      { "name": "no-id" },
    ],
  }
  guard decode_installed_skills_reply(reply.stringify())
    is Some([widget, handmade]) else {
    fail("expected two installed items")
  }
  assert_eq(widget.id, "acme-widget")
  assert_eq(widget.name, "widget")
  assert_eq(widget.source, "acme/widget@1.0.0")
  assert_eq(handmade.name, "handmade")
  assert_eq(handmade.source, "")
  assert_true(decode_installed_skills_reply("{}") is None)
}
