///|
async test "PTC attaches unprinted images even when the outer script fails and bounds cumulative images" {
  let picture = @protocol.Image::from_bytes(b"\x89PNG\r\n\x1a\n")
  let parts : Array[@protocol.ContentPart] = [
    Text("before picture"),
    Image(picture),
    Text("after picture"),
  ]
  let tool = leaf(
    name="picture",
    concurrent_safe=true,
    execute=Sync(_ => @agent_tool.respond_content(Content(parts))),
  )
  @async.with_task_group(group => {
    let service = Service::start(group, Tools([tool]))
    let program = service.register()
    for _ in 0..<4 {
      let result = request(program.env(), "picture", {})
      assert_true(
        result
        is { "is_error": false, "content": "before pictureafter picture", .. },
      )
      assert_false(result.stringify().contains("base64"))
    }
    assert_true(
      request(program.env(), "picture", {}) is { "is_error": true, .. },
    )
    program.close()
    let action = program.result(
      @agent_tool.respond("later script failure", is_error=true),
    )
    guard action is Respond(output) else { fail("expected response") }
    assert_true(output.is_error)
    assert_eq(
      output.content.0,
      [Text("later script failure"), ..parts, ..parts, ..parts, ..parts],
    )
    assert_true(
      program.trace()
      is {
        "ptc_calls": [
          _,
          _,
          _,
          _,
          { "status": "done", "result": { "is_error": true, .. }, .. },
        ],
        ..
      },
    )
  })
}

///|
async test "PTC background images have durable snapshots separate from trace and stable repeat reads" {
  let root = @fs.tmpdir(prefix="openseek-ptc-images-")
  defer @fs.rmdir(root, recursive=true)
  let picture = @protocol.Image::from_bytes(b"\x89PNG\r\n\x1a\n")
  let tool = leaf(
    name="picture",
    execute=Sync(_ => {
      @agent_tool.respond_content(Content([Text("picture"), Image(picture)]))
    }),
  )
  let metadata = @async.with_task_group(group => {
    let service = Service::start(group, Tools([tool]), image_directory=() => {
      Some(root)
    })
    let program = service.register()
    assert_true(
      request(program.env(), "picture", {}) is { "is_error": false, .. },
    )
    program.handoff("job-test", _ => ())
    assert_true(
      request(program.env(), "picture", {}) is { "is_error": false, .. },
    )
    program.close()
    assert_eq(program.image_content(), [
      Text("picture"),
      Image(picture),
      Text("picture"),
      Image(picture),
    ])
    assert_eq(program.image_content(), [
      Text("picture"),
      Image(picture),
      Text("picture"),
      Image(picture),
    ])
    guard program.result(@agent_tool.respond("background")) is Respond(output) else {
      fail("expected handoff")
    }
    assert_true(output.content.is_text_only())
    program.trace()
  })
  guard metadata is { "ptc_images": Array(images), .. } else {
    fail("missing snapshots")
  }
  assert_eq(images.length(), 2)
  for image in images {
    guard image is { "path": String(path), .. } else {
      fail("missing retained path")
    }
    assert_eq(@fs.read_file(path).binary(), picture.bytes)
  }
  assert_false(metadata.stringify().contains("base64"))
}

///|
async test "image persistence errors settle the call without attaching a picture or consuming its budget" {
  let root = @fs.tmpdir(prefix="openseek-ptc-image-failure-")
  defer @fs.rmdir(root, recursive=true)
  let picture = @protocol.Image::from_bytes(b"\x89PNG\r\n\x1a\n")
  let tool = leaf(
    name="picture",
    execute=Sync(_ => {
      @agent_tool.respond_content(Content([Text("picture"), Image(picture)]))
    }),
  )
  @async.with_task_group(group => {
    let directory = Ref("\{root}/missing")
    let service = Service::start(group, Tools([tool]), image_directory=() => {
      Some(directory.val)
    })
    let program = service.register()
    for _ in 0..<5 {
      let result = request(program.env(), "picture", {})
      assert_true(result is { "is_error": true, .. })
      assert_true(program.image_content().is_empty())
    }
    directory.val = root
    assert_true(
      request(program.env(), "picture", {}) is { "is_error": false, .. },
    )
    program.close()
    assert_eq(program.image_content(), [Text("picture"), Image(picture)])
  })
}
