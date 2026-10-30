///|
priv struct Series {
  kind : String
  label : String
  color : String
  x : Array[Double]
  y : Array[Double]
  labels : Array[String]
  bins : Int32
}

///|
priv struct Spec {
  title : String
  x_label : String
  y_label : String
  width : Int32
  height : Int32
  grid : Bool
  series : Array[Series]
}

///|
fn[T : @json.FromJson] optional_field(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
  fallback : T,
) -> T raise @json.JsonDecodeError {
  match fields.get(key) {
    None => fallback
    Some(value) => @json.FromJson::from_json(value, path.add_key(key))
  }
}

///|
fn[T] invalid(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise @json.JsonDecodeError((path, message))
}

///|
impl @json.FromJson for Series with fn from_json(value, path) {
  guard value is Object(fields) else {
    return invalid(path, "Expected a chart series object")
  }
  let kind : String = optional_field(fields, "kind", path, "line")
  guard ["line", "scatter", "bar", "barh", "hist", "pie", "area"].contains(kind) else {
    return invalid(
      path.add_key("kind"),
      "Supported kinds: line, scatter, bar, barh, hist, pie, area",
    )
  }
  let y : Array[Double] = optional_field(fields, "y", path, [])
  let x : Array[Double] = optional_field(
    fields,
    "x",
    path,
    Array::makei(y.length(), i => i.to_double()),
  )
  let labels : Array[String] = optional_field(fields, "labels", path, [])
  let bins : Int32 = optional_field(fields, "bins", path, 10)
  if y.is_empty() ||
    y.any(v => v.is_nan() || v.is_inf()) ||
    x.any(v => v.is_nan() || v.is_inf()) {
    invalid(path, "y must be nonempty; x and y must contain finite numbers")
  }
  if x.length() != y.length() {
    invalid(path, "x and y must have equal lengths")
  }
  if !labels.is_empty() && labels.length() != y.length() {
    invalid(path, "labels and y must have equal lengths")
  }
  if bins < 1 || bins > 1000 {
    invalid(path.add_key("bins"), "bins must be between 1 and 1000")
  }
  {
    kind,
    x,
    y,
    labels,
    bins,
    label: optional_field(fields, "label", path, ""),
    color: optional_field(fields, "color", path, ""),
  }
}

///|
impl @json.FromJson for Spec with fn from_json(value, path) {
  guard value is Object(fields) else {
    return invalid(path, "Expected a chart object")
  }
  let version : Int32 = optional_field(fields, "version", path, 1)
  if version != 1 {
    invalid(path.add_key("version"), "Unsupported chart version")
  }
  let series : Array[Series] = optional_field(fields, "series", path, [])
  if series.is_empty() {
    invalid(path.add_key("series"), "At least one series is required")
  }
  let width : Int32 = optional_field(fields, "width", path, 720)
  let height : Int32 = optional_field(fields, "height", path, 420)
  if width < 240 || width > 2400 || height < 180 || height > 1600 {
    invalid(path, "width must be 240..2400; height must be 180..1600")
  }
  {
    title: optional_field(fields, "title", path, ""),
    x_label: optional_field(fields, "x_label", path, ""),
    y_label: optional_field(fields, "y_label", path, ""),
    grid: optional_field(fields, "grid", path, false),
    series,
    width,
    height,
  }
}
