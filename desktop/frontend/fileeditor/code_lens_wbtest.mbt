///|
fn codelens_test_context() -> NavigationContext {
  {
    owner: { channel: @interop.ChannelId::Local, session: "test-session", },
    root: try! @common.Uri::parse("openseek://local/ws"),
  }
}

///|
fn codelens_test_model() -> @model.TextModel {
  @model.TextModel(
    try! @common.Uri::parse("openseek://local/ws/src/main.mbt"),
    "main.mbt",
    "moonbit",
    1,
    "test-revision",
    "pub fn first() -> Int { 1 }\npub fn second() -> Int { 2 }\n",
  )
}

///|
test "Moon IDE CodeLens projection shifts source coordinates and mints app resources" {
  let model = codelens_test_model()
  defer model.dispose()
  let same_resource_diff_model = codelens_test_model()
  defer same_resource_diff_model.dispose()
  assert_true(moon_ide_codelens_source_model_matches(model, Some(model)))
  assert_false(
    moon_ide_codelens_source_model_matches(
      same_resource_diff_model,
      Some(model),
    ),
  )
  assert_false(moon_ide_codelens_source_model_matches(model, None))
  let projection : MoonIdeModelProjection = {
    context: codelens_test_context(),
    path: Relative("src/main.mbt"),
    line_offset: 5,
  }
  let lenses = project_moonide_codelenses(
    {
      lenses: [
        {
          range: {
            start: { line: 5, character: 7, },
            end: { line: 5, character: 12, },
          },
          title: "Local: 1 reference",
          action: @protocol.MoonIdeCodeLensAction::Local(
            position={ line: 5, character: 7, },
            locations=[
              {
                path: "/ws/src/lib.mbt",
                start_line: 3,
                start_column: 4,
                end_line: 3,
                end_column: 9,
              },
            ],
          ),
        },
        {
          range: {
            start: { line: 6, character: 7, },
            end: { line: 6, character: 13, },
          },
          title: "Outside",
          action: @protocol.MoonIdeCodeLensAction::Outside(position={
            line: 6,
            character: 7,
          }),
        },
        {
          range: {
            start: { line: 4, character: 0, },
            end: { line: 4, character: 1, },
          },
          title: "Before fragment",
          action: @protocol.MoonIdeCodeLensAction::Outside(position={
            line: 4,
            character: 0,
          }),
        },
      ],
    },
    model,
    projection,
  )
  assert_eq(lenses.length(), 2)
  assert_eq(lenses[0].range, @common.Range(1, 8, 1, 13))
  guard lenses[0].command is Some(local_command) else {
    fail("local CodeLens had no command")
  }
  assert_eq(local_command.id, MoonIdeLocalReferencesCommand)
  assert_eq(local_command.title, "Local: 1 reference")
  assert_eq(Json(local_command.arguments), [
    "openseek://local/ws/src/main.mbt",
    { "line": 0, "character": 7 },
    [
      {
        "uri": "openseek://local/ws/src/lib.mbt",
        "range": {
          "start": { "line": 2, "character": 3 },
          "end": { "line": 2, "character": 8 },
        },
      },
    ],
  ])
  assert_eq(lenses[1].range, @common.Range(2, 8, 2, 14))
  guard lenses[1].command is Some(outside) else {
    fail("outside CodeLens had no command")
  }
  assert_eq(outside.id, MoonIdeOutsideReferencesCommand)
  assert_eq(Json(outside.arguments), [
    "openseek://local/ws/src/main.mbt",
    { "line": 1, "character": 7 },
  ])
}

///|
test "Moon IDE CodeLens command decoding accepts only normalized Local and Outside actions" {
  let model = codelens_test_model()
  defer model.dispose()
  let context = codelens_test_context()
  let local_request : @code_lens_api.CodeLensCommandRequest = {
    source_viewer_id: "viewer-1",
    resource: model.uri,
    range: @common.Range(1, 1, 1, 10),
    command: {
      id: MoonIdeLocalReferencesCommand,
      title: "Local",
      tooltip: None,
      arguments: [
        Json(model.uri.to_string()),
        { "line": 0, "character": 7 },
        [
          {
            "uri": "openseek://local/ws/src/lib.mbt",
            "range": {
              "start": { "line": 2, "character": 3 },
              "end": { "line": 2, "character": 8 },
            },
          },
        ],
      ],
    },
  }
  guard decode_moonide_codelens_command(local_request, model, context)
    is Some(LocalReferences(position~, locations~)) else {
    fail("local command was not decoded")
  }
  assert_eq(position, @common.Position(1, 8))
  assert_eq(locations.length(), 1)
  assert_eq(locations[0].uri.to_string(), "openseek://local/ws/src/lib.mbt")
  assert_eq(locations[0].range, @common.Range(3, 4, 3, 9))
  let outside : @code_lens_api.CodeLensCommandRequest = {
    ..local_request,
    command: {
      id: MoonIdeOutsideReferencesCommand,
      title: "Outside",
      tooltip: None,
      arguments: [Json(model.uri.to_string()), { "line": 1, "character": 7 }],
    },
  }
  guard decode_moonide_codelens_command(outside, model, context)
    is Some(OutsideReferences(position~)) else {
    fail("outside command was not decoded")
  }
  assert_eq(position, @common.Position(2, 8))
  let forged_source = {
    ..outside,
    command: {
      ..outside.command,
      arguments: [
        "openseek://local/other/main.mbt",
        { "line": 1, "character": 7 },
      ],
    },
  }
  let escaping_target = {
    ..local_request,
    command: {
      ..local_request.command,
      arguments: [
        Json(model.uri.to_string()),
        { "line": 0, "character": 7 },
        [
          {
            "uri": "openseek://local/outside/leak.mbt",
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 1 },
            },
          },
        ],
      ],
    },
  }
  assert_true(
    decode_moonide_codelens_command(forged_source, model, context) is None,
  )
  assert_true(
    decode_moonide_codelens_command(escaping_target, model, context) is None,
  )
}

///|
test "Moon IDE CodeLens stale fence binds viewer model version resource and navigation" {
  let model = codelens_test_model()
  defer model.dispose()
  let replacement = codelens_test_model()
  defer replacement.dispose()
  let context = codelens_test_context()
  let fence : MoonIdeCodeLensFence = {
    viewer_id: "viewer-1",
    model,
    version_id: model.get_version_id(),
    resource: model.uri.to_string(),
    context,
  }
  assert_true(fence.matches("viewer-1", Some(model), Some(context)))
  assert_false(fence.matches("viewer-2", Some(model), Some(context)))
  assert_false(fence.matches("viewer-1", Some(replacement), Some(context)))
  assert_false(fence.matches("viewer-1", Some(model), None))
  model.set_value("pub fn changed() -> Int { 3 }\n")
  assert_false(fence.matches("viewer-1", Some(model), Some(context)))
}
