///|
fn run_render_perf_test() -> Unit {
  @languages.languages.set_tokens_provider(
    "moonbit",
    @lang_moonbit.MoonBitTokenizer(),
  )
  |> ignore
  let ctx = @support.BrowserTestContext("viewer_render_perf")
  let done = Ref(false)
  let sample_index = Ref(-1)
  let sample_start = Ref(0.0)
  let samples : Array[Double] = []
  let large_text = large_source_text(2000)
  let viewer_ref : Ref[@viewer.Viewer?] = Ref(None)
  match mount_host() {
    Some(host) => {
      let viewer = @viewer.Viewer::create(
        host,
        options=ViewerOptions(placeholder="Loading performance fixture..."),
      )
      @viewer_testing.on_did_render_model(viewer.get_id(), event => {
        if event.fresh && event.model.uri.to_string().contains("large") {
          record_sample(
            ctx, viewer_ref, large_text, done, sample_index, sample_start, samples,
          )
        }
      })
      |> ignore
      viewer_ref.val = Some(viewer)
      @support.set_timeout(
        () => run_next_sample(viewer, large_text, sample_index, sample_start),
        50,
      )
      @support.set_timeout(
        () => {
          if !done.val {
            ctx.fail("timed out waiting for perf samples")
            done.val = true
            ctx.finish()
          }
        },
        15000,
      )
    }
    None => {
      ctx.fail("missing #app mount point")
      ctx.finish()
    }
  }
}

///|
fn mount_host() -> @rdom.Element? {
  let document = @rdom.document()
  match document.query_selector("#app").to_option() {
    Some(app) => {
      let shell = document.create_element("main")
      shell.set_attribute("class", "editor-shell")
      shell.set_attribute("data-theme", "dark")
      shell.set_attribute("style", "height:100vh;display:block;")
      let host = document.create_element("div")
      host.set_attribute("class", "viewer-host")
      host.set_attribute("style", "height:100vh;")
      shell.append_child(host.as_node())
      app.append_child(shell.as_node())
      Some(host)
    }
    None => None
  }
}

///|
fn run_next_sample(
  viewer : @viewer.Viewer,
  large_text : String,
  sample_index : Ref[Int],
  sample_start : Ref[Double],
) -> Unit {
  sample_start.val = @support.now_ms()
  let name = if sample_index.val < 0 {
    "warmup"
  } else {
    "sample_\{sample_index.val.to_string()}"
  }
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/perf/large_\{name}.mbt",
  )
  viewer.set_model(
    Some(
      TextModel(
        uri,
        @base_common.basename_or_authority(uri),
        "moonbit",
        sample_index.val + 2,
        "perf-\{name}",
        large_text,
      ),
    ),
  )
  viewer.handle_initialized()
}

///|
fn record_sample(
  ctx : @support.BrowserTestContext,
  viewer_ref : Ref[@viewer.Viewer?],
  large_text : String,
  done : Ref[Bool],
  sample_index : Ref[Int],
  sample_start : Ref[Double],
  samples : Array[Double],
) -> Unit {
  if done.val {
    return
  }
  let elapsed = @support.now_ms() - sample_start.val
  if sample_index.val >= 0 {
    samples.push(elapsed)
  }
  sample_index.val = sample_index.val + 1
  if sample_index.val >= 3 {
    finish_perf_report(ctx, done, samples)
  } else {
    match viewer_ref.val {
      Some(viewer) =>
        @support.set_timeout(
          () => run_next_sample(viewer, large_text, sample_index, sample_start),
          50,
        )
      None => {
        ctx.fail("viewer reference was not initialized")
        done.val = true
        ctx.finish()
      }
    }
  }
}

///|
fn finish_perf_report(
  ctx : @support.BrowserTestContext,
  done : Ref[Bool],
  samples : Array[Double],
) -> Unit {
  if samples.length() != 3 {
    ctx.fail("expected 3 measured samples, got \{samples.length().to_string()}")
  }
  let (best, median, worst) = sample_summary(samples)
  ctx.metric_int("warmupCount", 1)
  ctx.metric_int("sampleCount", samples.length())
  ctx.metric(
    "samples",
    Json::array(samples.map(sample => Json::number(sample))),
  )
  ctx.metric_number("bestMs", best)
  ctx.metric_number("medianMs", median)
  ctx.metric_number("p95Ms", worst)
  ctx.metric_number("worstMs", worst)
  done.val = true
  ctx.finish()
}

///|
fn sample_summary(samples : Array[Double]) -> (Double, Double, Double) {
  if samples.length() == 0 {
    return (0.0, 0.0, 0.0)
  }
  let (best, worst) = for sample in samples; bounds = (samples[0], samples[0]) {
    let (best, worst) = bounds
    let best = if sample < best { sample } else { best }
    let worst = if sample > worst { sample } else { worst }
    continue (best, worst)
  } nobreak {
    bounds
  }
  let median = if samples.length() == 3 {
    samples[0] + samples[1] + samples[2] - best - worst
  } else {
    samples[samples.length() / 2]
  }
  (best, median, worst)
}

///|
fn large_source_text(count : Int) -> String {
  let builder = StringBuilder()
  for index in 0..<count {
    builder <+ "///|\npub fn perf_value_\{index}() -> Int {\n  \{index}"
    builder.write_string(
      (
        #|
        #|}
        #|
        #|
      ),
    )
  }
  builder.to_string()
}
