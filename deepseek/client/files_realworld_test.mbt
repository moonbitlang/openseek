///|
/// Exercise the real Files API and image interpretation together. The fixture
/// is a complete 256x128 RGB PNG (blue left half, yellow right half) in
/// testdata/two-colors.png. Neither the prompt nor the upload filename
/// discloses the expected colors. The upload expires after one hour so running
/// this smoke test does not create permanent files.
async test "realworld DeepSeek image upload and recognition" {
  // Moon tests resolve fixture paths from the module root. Load before the
  // credential check so offline runs also verify that the fixture is present.
  let image = @fs.read_file("deepseek/client/testdata/two-colors.png").binary()
  guard @env.get_env_var("DEEPSEEK") is Some(api_key) && api_key != "" else {
    println(
      "DEEPSEEK is not set; skipping realworld image upload and recognition",
    )
    return
  }
  // The Vision API documents deepseek-flash, represented by V4Flash.
  let client = @client.Client(
    api_key~,
    model=Deepseek(V4Flash),
    retry_attempts=1,
  )
  @async.with_timeout(120_000, () => {
    let uploaded = client.upload_image(
      image,
      filename="fixture.png",
      expires_after_seconds=3600,
      timeout_ms=60_000,
    )
    assert_false(uploaded.id.is_blank())
    assert_eq(uploaded.bytes, image.length().to_int64())
    assert_true(uploaded.expires_at is Some(_))
    let response = client.chat(
      [
        ChatMessage(User, content=[
          Text(
            "Identify the solid color of each half of this image. Reply only with a JSON object with keys left and right, using one lowercase English color name for each.",
          ),
          File(file_id=uploaded.id),
        ]),
      ],
      response_format=JsonObject,
    )
    let answer = @json.parse(response.content)
    guard answer is { "left": "blue", "right": "yellow", .. } else {
      fail("unexpected image recognition response: \{response.content}")
    }
    assert_true(response.usage.total_tokens > 0)
  })
}
