///|
/// Mutable result accumulator for MoonBit-authored browser tests.
pub struct BrowserTestContext {
  suite : String
  failures : Array[String]
  metrics : Map[String, Json]
}

///|
/// Creates a browser test context for one suite.
pub fn BrowserTestContext::BrowserTestContext(
  suite : String,
) -> BrowserTestContext {
  { suite, failures: [], metrics: Map([]), }
}

///|
/// Records a failed assertion message.
pub fn BrowserTestContext::fail(
  self : BrowserTestContext,
  message : String,
) -> Unit {
  self.failures.push(message)
}

///|
/// Records `message` when `condition` is false.
pub fn BrowserTestContext::assert_true(
  self : BrowserTestContext,
  condition : Bool,
  message : String,
) -> Unit {
  if !condition {
    self.fail(message)
  }
}

///|
/// Stores a JSON metric on the test report.
pub fn BrowserTestContext::metric(
  self : BrowserTestContext,
  name : String,
  value : Json,
) -> Unit {
  self.metrics[name] = value
}

///|
/// Stores an integer metric.
pub fn BrowserTestContext::metric_int(
  self : BrowserTestContext,
  name : String,
  value : Int32,
) -> Unit {
  self.metric(name, Json(value))
}

///|
/// Stores a numeric metric.
pub fn BrowserTestContext::metric_number(
  self : BrowserTestContext,
  name : String,
  value : Double,
) -> Unit {
  self.metric(name, Json::number(value))
}

///|
/// Stores a string metric.
pub fn BrowserTestContext::metric_string(
  self : BrowserTestContext,
  name : String,
  value : String,
) -> Unit {
  self.metric(name, Json(value))
}

///|
/// Serializes the suite result for the Playwright bridge.
pub fn BrowserTestContext::to_json(self : BrowserTestContext) -> Json {
  {
    "suite": Json(self.suite),
    "status": Json(
      if self.failures.length() == 0 {
        "passed"
      } else {
        "failed"
      },
    ),
    "failures": Json(self.failures.map(failure => Json(failure))),
    "metrics": Json(self.metrics),
  }
}

///|
/// Emits the final suite result to the browser test reporter.
pub fn BrowserTestContext::finish(self : BrowserTestContext) -> Unit {
  report_json(self.to_json().stringify())
}
